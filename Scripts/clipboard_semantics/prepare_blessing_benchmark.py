#!/usr/bin/env python3
"""Prepare a blind, double-annotation queue for the blessing benchmark."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import unicodedata
from collections import Counter
from pathlib import Path


SEED = 20260828
OUTPUT_DIRECTORY = Path("ModelTraining/ClipboardSemantics/BlessingBenchmark")
SOURCE_PATH = Path(
    "ModelTraining/ClipboardSemantics/comprehensive-online-holdout-corpus.jsonl"
)
PII_PATTERN = re.compile(
    r"(?:[\w.+-]+@[\w.-]+\.\w+)|(?:\+?\d[\d ()-]{8,}\d)|"
    r"(?:\b\d{3}-\d{2}-\d{4}\b)",
    re.IGNORECASE,
)
EXPLICIT_PATTERN = re.compile(
    r"(?:祝|愿你|愿您|愿他|愿她|愿大家|恭喜|祝贺|生日快乐|"
    r"新年快乐|一路平安|一路顺风|康复|前程|平安|安康|如意|好梦|"
    r"希望.{0,40}(?:快乐|幸福|平安|顺利|康复|成功|健康)|"
    r"wish|hope you|may you|may your|congrat|happy birthday|"
    r"happy new year|good luck|best wishes|get well|safe travel|"
    r"sweet dream|peace and happiness|future success)",
    re.IGNORECASE,
)
BOUNDARY_PATTERN = re.compile(
    r"(?:祝福语|祝福模板|祝福文案|谢谢.{0,30}祝福|感谢.{0,30}祝福|"
    r"收到.{0,30}祝福|庆祝|庆功|引用.{0,20}(?:祝|愿|恭喜)|"
    r"怎么.{0,20}(?:祝|生日快乐)|如何.{0,20}(?:祝|生日快乐)|"
    r"template|thanks?.{0,64}(?:wish|wishes|congratulations)|"
    r"celebrat|quotes?.{0,32}(?:wish|congratulat)|"
    r"how to write.{0,32}(?:wish|greeting))",
    re.IGNORECASE,
)
PLAIN_GREETING_PATTERN = re.compile(
    r"^(?:你好|您好|早上好|中午好|下午好|晚上好|晚安|好久不见|"
    r"hello|good morning|good afternoon|good evening|long time no see)"
    r"[！!。,.，~～]*$",
    re.IGNORECASE,
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=SOURCE_PATH)
    parser.add_argument("--output-directory", type=Path, default=OUTPUT_DIRECTORY)
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument("--chinese-records", type=int, default=3_000)
    parser.add_argument("--english-records", type=int, default=1_500)
    parser.add_argument(
        "--training-corpus",
        action="append",
        default=[],
        type=Path,
        help="Additional JSONL whose text must not overlap the review queue.",
    )
    return parser.parse_args()


def normalized_text(value: str) -> str:
    value = unicodedata.normalize("NFKC", value.replace("\u0000", " "))
    return " ".join(value.split()).strip()


def fingerprint(value: str) -> str:
    return normalized_text(value).casefold()


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_records(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def protected_fingerprints(paths: list[Path]) -> set[str]:
    values: set[str] = set()
    for path in paths:
        for record_value in load_records(path):
            values.add(fingerprint(record_value["text"]))
    return values


def selection_stratum(record_value: dict) -> str:
    text = normalized_text(record_value["text"])
    if BOUNDARY_PATTERN.search(text) or PLAIN_GREETING_PATTERN.fullmatch(text):
        return "boundary_candidate"
    if EXPLICIT_PATTERN.search(text):
        return "explicit_candidate"
    if record_value.get("blessing"):
        return "weak_positive_candidate"
    if record_value.get("sentiment") == "positive":
        return "positive_language_boundary"
    return "natural_negative"


def stable_priority(record_value: dict, seed: int, salt: str) -> bytes:
    return hashlib.sha256(
        f"{seed}|{salt}|{record_value['id']}".encode()
    ).digest()


def select_language(
    records: list[dict],
    *,
    language: str,
    target: int,
    seed: int,
    protected: set[str],
) -> list[dict]:
    candidates: list[dict] = []
    seen: set[str] = set()
    for record_value in records:
        if record_value.get("language") != language:
            continue
        text = normalized_text(record_value.get("text") or "")
        text_key = fingerprint(text)
        if (
            not 2 <= len(text) <= 500
            or PII_PATTERN.search(text)
            or text_key in protected
            or text_key in seen
        ):
            continue
        seen.add(text_key)
        candidate = dict(record_value)
        candidate["_normalizedText"] = text
        candidate["_stratum"] = selection_stratum(record_value)
        candidates.append(candidate)

    fractions = {
        "explicit_candidate": 0.30,
        "boundary_candidate": 0.25,
        "weak_positive_candidate": 0.10,
        "positive_language_boundary": 0.15,
        "natural_negative": 0.20,
    }
    selected: list[dict] = []
    selected_ids: set[str] = set()
    remaining = target
    for index, (stratum, fraction) in enumerate(fractions.items()):
        desired = target - len(selected) if index == len(fractions) - 1 else round(
            target * fraction
        )
        values = sorted(
            (
                value
                for value in candidates
                if value["_stratum"] == stratum
            ),
            key=lambda value: stable_priority(value, seed, stratum),
        )
        for value in values[:desired]:
            selected.append(value)
            selected_ids.add(value["id"])
        remaining = target - len(selected)

    if remaining:
        fillers = sorted(
            (value for value in candidates if value["id"] not in selected_ids),
            key=lambda value: stable_priority(value, seed, "fill"),
        )
        selected.extend(fillers[:remaining])
    if len(selected) != target:
        raise RuntimeError(
            f"Only selected {len(selected)}/{target} review records for {language}"
        )
    return selected


def write_jsonl(path: Path, records: list[dict]) -> None:
    path.write_text(
        "\n".join(
            json.dumps(record_value, ensure_ascii=False, sort_keys=True)
            for record_value in records
        )
        + "\n",
        encoding="utf-8",
    )


def main() -> None:
    arguments = parse_arguments()
    if arguments.chinese_records < 100 or arguments.english_records < 100:
        raise ValueError("Each language requires at least 100 review records")

    source_records = load_records(arguments.source)
    protected = protected_fingerprints(arguments.training_corpus)
    selected = select_language(
        source_records,
        language="zh-Hans",
        target=arguments.chinese_records,
        seed=arguments.seed,
        protected=protected,
    ) + select_language(
        source_records,
        language="en",
        target=arguments.english_records,
        seed=arguments.seed,
        protected=protected,
    )

    output_directory = arguments.output_directory
    output_directory.mkdir(parents=True, exist_ok=True)
    queue: list[dict] = []
    provenance: list[dict] = []
    annotation_template: list[dict] = []
    for index, source in enumerate(
        sorted(selected, key=lambda value: stable_priority(value, arguments.seed, "queue")),
        start=1,
    ):
        review_id = f"blessing-review-{index:05d}"
        queue.append(
            {
                "id": review_id,
                "text": source["_normalizedText"],
                "language": source["language"],
                "annotationStatus": "unreviewed",
            }
        )
        provenance.append(
            {
                "id": review_id,
                "sourceRecordID": source["id"],
                "sourceDataset": source.get("sourceDataset"),
                "sourceLicense": source.get("sourceLicense"),
                "sourceURL": source.get("sourceURL"),
                "selectionStratum": source["_stratum"],
                "previousWeakLabel": bool(source.get("blessing")),
            }
        )
        annotation_template.append(
            {
                "id": review_id,
                "label": None,
                "boundaryCategory": None,
                "confidence": None,
                "notes": "",
            }
        )

    queue_path = output_directory / "review-queue.jsonl"
    provenance_path = output_directory / "sealed-provenance.jsonl"
    annotator_a_path = output_directory / "annotator-a.jsonl"
    annotator_b_path = output_directory / "annotator-b.jsonl"
    write_jsonl(queue_path, queue)
    write_jsonl(provenance_path, provenance)
    write_jsonl(annotator_a_path, annotation_template)
    write_jsonl(annotator_b_path, annotation_template)

    manifest = {
        "schemaVersion": 1,
        "seed": arguments.seed,
        "status": "awaiting-double-human-annotation",
        "humanReviewComplete": False,
        "policy": (
            "Evaluation-only queue derived from the frozen comprehensive holdout. "
            "Never merge these records into training."
        ),
        "records": len(queue),
        "languages": dict(Counter(value["language"] for value in queue)),
        "selectionStrata": dict(
            Counter(value["selectionStratum"] for value in provenance)
        ),
        "sourceDatasets": dict(
            Counter(value["sourceDataset"] for value in provenance)
        ),
        "validation": {
            "duplicateNormalizedTexts": (
                len(queue)
                - len({fingerprint(value["text"]) for value in queue})
            ),
            "configuredTrainingOverlap": sum(
                fingerprint(value["text"]) in protected for value in queue
            ),
            "containsDetectedPII": any(
                PII_PATTERN.search(value["text"]) for value in queue
            ),
        },
        "artifacts": {
            "reviewQueueSHA256": file_sha256(queue_path),
            "sealedProvenanceSHA256": file_sha256(provenance_path),
        },
    }
    (output_directory / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
