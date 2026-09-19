#!/usr/bin/env python3
"""Split authored batches into train and evaluation corpora by scenario family.

Whole families move together. A family is one scenario (for example
"invitation to a meal" or "received thanks for a blessing"), so a family-level
split forces the evaluation set to test scenarios the model never trained on
instead of paraphrases of them. Text overlap between the two sides is therefore
impossible by construction, and the script verifies it anyway.

Positive and negative families are assigned separately so both sides keep a
usable label balance.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path


SEED = 20260903
AUTHORED_DIRECTORY = Path("ModelTraining/ClipboardSemantics/Authored")
INTENT_FIELDS = (
    "task",
    "question",
    "invitation",
    "complaint",
    "scheduleNegotiation",
    "confirmationDecision",
    "followUpReminder",
    "blessing",
    "replyable",
)
SOURCE_DATASET = "authored-v1"
SOURCE_LICENSE = "OSGKeyboard project license"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("batches", nargs="*", type=Path)
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument(
        "--evaluation-family-fraction",
        type=float,
        default=0.30,
        help="Share of families in each polarity group reserved for evaluation.",
    )
    parser.add_argument(
        "--sample-weight",
        type=float,
        default=1.0,
        help="Training sample weight recorded on every authored train record.",
    )
    parser.add_argument(
        "--train-output",
        type=Path,
        default=AUTHORED_DIRECTORY / "authored-train-corpus.jsonl",
    )
    parser.add_argument(
        "--evaluation-output",
        type=Path,
        default=AUTHORED_DIRECTORY / "authored-eval-corpus.jsonl",
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=AUTHORED_DIRECTORY / "authored-split-report.json",
    )
    return parser.parse_args()


def normalized_text(value: str) -> str:
    return " ".join(unicodedata.normalize("NFKC", value).split()).strip()


def fingerprint(value: str) -> str:
    return normalized_text(value).casefold()


def load_records(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def polarity_group(family: str) -> str:
    """Negative families carry a `neg` marker in their leading token."""

    return "negative" if "neg_" in family else "positive"


def intent_group(family: str) -> str:
    return family.split("_", 1)[0].removesuffix("neg")


def family_priority(family: str, seed: int) -> str:
    return hashlib.sha256(f"{seed}|{family}".encode()).hexdigest()


def assign_families(families: set[str], seed: int, fraction: float) -> dict[str, str]:
    """Reserve a deterministic share of each intent/polarity cell for evaluation."""

    cells: dict[tuple[str, str], list[str]] = defaultdict(list)
    for family in families:
        cells[(intent_group(family), polarity_group(family))].append(family)

    assignment: dict[str, str] = {}
    for cell, values in sorted(cells.items()):
        ordered = sorted(values, key=lambda value: family_priority(value, seed))
        reserved = max(1, round(len(ordered) * fraction))
        for index, family in enumerate(ordered):
            assignment[family] = "evaluation" if index < reserved else "train"
    return assignment


def main() -> None:
    arguments = parse_arguments()
    batches = arguments.batches or sorted(
        path
        for path in AUTHORED_DIRECTORY.glob("*.jsonl")
        if not path.name.startswith("authored-")
    )
    records: list[dict] = []
    for path in batches:
        records.extend(load_records(path))

    assignment = assign_families(
        {record["family"] for record in records},
        arguments.seed,
        arguments.evaluation_family_fraction,
    )

    train: list[dict] = []
    evaluation: list[dict] = []
    for record in records:
        target = assignment[record["family"]]
        emitted = {
            "id": record["id"],
            "text": normalized_text(record["text"]),
            "language": record["language"],
            "family": record["family"],
            "sentiment": record["sentiment"],
            **{field: record[field] for field in INTENT_FIELDS},
            "sourceDataset": SOURCE_DATASET,
            "sourceLicense": SOURCE_LICENSE,
            "provenance": "llm-authored",
            "knownLabels": list(INTENT_FIELDS),
        }
        if target == "train":
            emitted["split"] = "train"
            emitted["sampleWeight"] = arguments.sample_weight
            train.append(emitted)
        else:
            emitted["split"] = "authoredEvaluation"
            evaluation.append(emitted)

    train_texts = {fingerprint(record["text"]) for record in train}
    evaluation_texts = {fingerprint(record["text"]) for record in evaluation}
    leaked = sorted(train_texts & evaluation_texts)

    for path, values in (
        (arguments.train_output, train),
        (arguments.evaluation_output, evaluation),
    ):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "\n".join(
                json.dumps(value, ensure_ascii=False, sort_keys=True)
                for value in values
            )
            + "\n",
            encoding="utf-8",
        )

    def positives(values: list[dict]) -> dict:
        return {
            field: sum(1 for value in values if value[field] is True)
            for field in INTENT_FIELDS
        }

    report = {
        "schemaVersion": 1,
        "seed": arguments.seed,
        "batches": [str(path) for path in batches],
        "evaluationFamilyFraction": arguments.evaluation_family_fraction,
        "sampleWeight": arguments.sample_weight,
        "families": len(assignment),
        "familyAssignment": dict(sorted(assignment.items())),
        "train": {
            "records": len(train),
            "families": len({value["family"] for value in train}),
            "languages": dict(Counter(value["language"] for value in train)),
            "positives": positives(train),
        },
        "evaluation": {
            "records": len(evaluation),
            "families": len({value["family"] for value in evaluation}),
            "languages": dict(Counter(value["language"] for value in evaluation)),
            "positives": positives(evaluation),
        },
        "validation": {
            "trainEvaluationTextOverlap": len(leaked),
            "leakedExamples": leaked[:5],
        },
    }
    arguments.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
