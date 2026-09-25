#!/usr/bin/env python3
"""Assemble registry-approved training data with a frozen v6 evaluation set."""

from __future__ import annotations

import argparse
import hashlib
import json
import unicodedata
from collections import Counter
from pathlib import Path


DEFAULT_TRAIN = Path(
    "ModelTraining/ClipboardSemantics/CorpusRegistry/train-candidates.jsonl"
)
DEFAULT_EVALUATION = Path(
    "ModelTraining/ClipboardSemantics/v6-blind-evaluation-corpus.jsonl"
)
DEFAULT_OUTPUT = Path(
    "ModelTraining/ClipboardSemantics/Generated/v6-model-corpus.jsonl"
)
DEFAULT_REPORT = Path(
    "ModelTraining/ClipboardSemantics/Generated/v6-model-corpus-report.json"
)
EVALUATION_SPLITS = {"validation", "test", "golden"}


def read_json_lines(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def fingerprint(text: str) -> str:
    normalized = unicodedata.normalize("NFKC", text)
    return " ".join(normalized.casefold().split())


def assemble(train_path: Path, evaluation_path: Path) -> tuple[list[dict], dict]:
    training = read_json_lines(train_path)
    evaluation = read_json_lines(evaluation_path)
    if any(record.get("split") != "train" for record in training):
        raise ValueError("Registry train candidates must all use split=train")
    if any(record.get("split") not in EVALUATION_SPLITS for record in evaluation):
        raise ValueError("Evaluation records must use validation, test, or golden")

    training_fingerprints = {fingerprint(record["text"]) for record in training}
    overlap = [
        record["id"]
        for record in evaluation
        if fingerprint(record["text"]) in training_fingerprints
    ]
    if overlap:
        raise ValueError(f"Frozen evaluation overlap detected: {overlap[:5]}")

    identifiers = [record["id"] for record in (*training, *evaluation)]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("Duplicate record ids in assembled corpus")

    records = training + evaluation
    report = {
        "schemaVersion": 1,
        "trainSource": str(train_path),
        "evaluationSource": str(evaluation_path),
        "recordCount": len(records),
        "splitCounts": dict(
            sorted(Counter(record["split"] for record in records).items())
        ),
        "languageCounts": dict(
            sorted(Counter(record["language"] for record in records).items())
        ),
        "evaluationOverlapCount": 0,
    }
    return records, report


def write_outputs(
    records: list[dict],
    report: dict,
    output_path: Path,
    report_path: Path,
) -> dict:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    payload = "".join(
        json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n"
        for record in records
    )
    output_path.write_text(payload, encoding="utf-8")
    final_report = {
        **report,
        "corpusSHA256": hashlib.sha256(payload.encode()).hexdigest(),
    }
    report_path.write_text(
        json.dumps(final_report, ensure_ascii=False, indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )
    return final_report


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    root.add_argument("--train", type=Path, default=DEFAULT_TRAIN)
    root.add_argument("--evaluation", type=Path, default=DEFAULT_EVALUATION)
    root.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    root.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    return root


def main() -> None:
    arguments = parser().parse_args()
    records, report = assemble(arguments.train, arguments.evaluation)
    final_report = write_outputs(
        records,
        report,
        arguments.output,
        arguments.report,
    )
    print(
        "V6_MODEL_CORPUS "
        f"records={final_report['recordCount']} "
        f"sha256={final_report['corpusSHA256']}"
    )


if __name__ == "__main__":
    main()
