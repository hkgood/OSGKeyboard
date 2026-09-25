#!/usr/bin/env python3
"""Prepare a leakage-free Apple NL corpus with product-scale evaluation splits."""

from __future__ import annotations

import argparse
import hashlib
import json
import unicodedata
from collections import Counter
from pathlib import Path


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


def prepare(
    training_records: list[dict],
    product_records: list[dict],
) -> tuple[list[dict], dict]:
    if any(record.get("split") != "train" for record in training_records):
        raise ValueError("Training source must contain only split=train records")

    evaluation_records = [
        record for record in product_records if record.get("split") in EVALUATION_SPLITS
    ]
    if not evaluation_records:
        raise ValueError("Product corpus has no evaluation records")

    evaluation_fingerprints = {
        fingerprint(record["text"]) for record in evaluation_records
    }
    evaluation_ids = {record["id"] for record in evaluation_records}
    filtered_training = [
        record
        for record in training_records
        if record["id"] not in evaluation_ids
        and fingerprint(record["text"]) not in evaluation_fingerprints
    ]
    records = filtered_training + evaluation_records

    identifiers = [record["id"] for record in records]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("Duplicate record ids remain after filtering")

    training_fingerprints = {
        fingerprint(record["text"]) for record in filtered_training
    }
    if training_fingerprints & evaluation_fingerprints:
        raise ValueError("Training and evaluation text overlap remains after filtering")

    report = {
        "schemaVersion": 1,
        "originalTrainingCount": len(training_records),
        "filteredTrainingCount": len(filtered_training),
        "excludedTrainingOverlapCount": len(training_records)
        - len(filtered_training),
        "evaluationCount": len(evaluation_records),
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
        json.dumps(final_report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return final_report


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    root.add_argument("--train", type=Path, required=True)
    root.add_argument("--product-corpus", type=Path, required=True)
    root.add_argument("--output", type=Path, required=True)
    root.add_argument("--report", type=Path, required=True)
    return root


def main() -> None:
    arguments = parser().parse_args()
    records, report = prepare(
        read_json_lines(arguments.train),
        read_json_lines(arguments.product_corpus),
    )
    final_report = write_outputs(
        records,
        report,
        arguments.output,
        arguments.report,
    )
    print(
        "APPLE_NL_HARDENING_CORPUS "
        f"records={final_report['recordCount']} "
        f"excludedOverlap={final_report['excludedTrainingOverlapCount']} "
        f"sha256={final_report['corpusSHA256']}"
    )


if __name__ == "__main__":
    main()
