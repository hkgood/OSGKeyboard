#!/usr/bin/env python3
"""Finalize a double-annotated blessing benchmark with adjudication."""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path


DEFAULT_DIRECTORY = Path(
    "ModelTraining/ClipboardSemantics/BlessingBenchmark"
)
CONFIDENCE_VALUES = {"high", "medium", "low"}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", type=Path, default=DEFAULT_DIRECTORY)
    parser.add_argument("--annotator-a-id", required=True)
    parser.add_argument("--annotator-b-id", required=True)
    parser.add_argument("--adjudicator-id")
    parser.add_argument("--adjudication", type=Path)
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_DIRECTORY / "blessing-benchmark.jsonl",
    )
    return parser.parse_args()


def load_jsonl(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def annotation_map(path: Path, expected_ids: set[str]) -> dict[str, dict]:
    records = load_jsonl(path)
    values = {record_value["id"]: record_value for record_value in records}
    if len(values) != len(records):
        raise ValueError(f"Duplicate annotation IDs in {path}")
    if set(values) != expected_ids:
        missing = sorted(expected_ids.difference(values))
        extra = sorted(set(values).difference(expected_ids))
        raise ValueError(
            f"Annotation ID mismatch in {path}: missing={missing[:5]} "
            f"extra={extra[:5]}"
        )
    for record_id, record_value in values.items():
        if not isinstance(record_value.get("label"), bool):
            raise ValueError(f"Missing boolean label for {record_id} in {path}")
        category = record_value.get("boundaryCategory")
        if not isinstance(category, str) or not category.strip():
            raise ValueError(f"Missing boundary category for {record_id} in {path}")
        if record_value.get("confidence") not in CONFIDENCE_VALUES:
            raise ValueError(f"Invalid confidence for {record_id} in {path}")
    return values


def benchmark_split(record_id: str) -> str:
    value = int.from_bytes(
        hashlib.sha256(f"blessing-benchmark-v1|{record_id}".encode()).digest()[:8],
        "big",
    )
    return "calibration" if value % 10 < 3 else "test"


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def binary_cohen_kappa(
    annotation_a: dict[str, dict],
    annotation_b: dict[str, dict],
) -> tuple[float, float]:
    record_ids = set(annotation_a)
    if not record_ids:
        return 0, 0
    observed = sum(
        annotation_a[record_id]["label"] == annotation_b[record_id]["label"]
        for record_id in record_ids
    ) / len(record_ids)
    positive_a = sum(
        annotation_a[record_id]["label"] for record_id in record_ids
    ) / len(record_ids)
    positive_b = sum(
        annotation_b[record_id]["label"] for record_id in record_ids
    ) / len(record_ids)
    expected = positive_a * positive_b + (1 - positive_a) * (1 - positive_b)
    kappa = (observed - expected) / (1 - expected) if expected < 1 else 1
    return observed, kappa


def main() -> None:
    arguments = parse_arguments()
    if arguments.annotator_a_id == arguments.annotator_b_id:
        raise ValueError("The two annotator IDs must be different")

    directory = arguments.directory
    queue = load_jsonl(directory / "review-queue.jsonl")
    queue_ids = {record_value["id"] for record_value in queue}
    if len(queue_ids) != len(queue):
        raise ValueError("Duplicate review queue IDs")
    annotation_a = annotation_map(directory / "annotator-a.jsonl", queue_ids)
    annotation_b = annotation_map(directory / "annotator-b.jsonl", queue_ids)
    disagreements = {
        record_id
        for record_id in queue_ids
        if annotation_a[record_id]["label"] != annotation_b[record_id]["label"]
        or annotation_a[record_id]["boundaryCategory"]
        != annotation_b[record_id]["boundaryCategory"]
    }

    adjudication: dict[str, dict] = {}
    if disagreements:
        if not arguments.adjudication or not arguments.adjudicator_id:
            disagreement_path = directory / "adjudication-needed.jsonl"
            template = [
                {
                    "id": record_id,
                    "label": None,
                    "boundaryCategory": None,
                    "confidence": None,
                    "notes": "",
                    "annotatorA": annotation_a[record_id],
                    "annotatorB": annotation_b[record_id],
                }
                for record_id in sorted(disagreements)
            ]
            disagreement_path.write_text(
                "\n".join(
                    json.dumps(value, ensure_ascii=False, sort_keys=True)
                    for value in template
                )
                + "\n",
                encoding="utf-8",
            )
            raise ValueError(
                f"{len(disagreements)} disagreements require adjudication; "
                f"template written to {disagreement_path}"
            )
        adjudication = annotation_map(arguments.adjudication, disagreements)

    finalized: list[dict] = []
    agreement_count = 0
    for record_value in queue:
        record_id = record_value["id"]
        if record_id in disagreements:
            final_annotation = adjudication[record_id]
            resolution = "adjudicated"
        else:
            final_annotation = annotation_a[record_id]
            resolution = "agreement"
            agreement_count += 1
        finalized.append(
            {
                "id": record_id,
                "text": record_value["text"],
                "language": record_value["language"],
                "split": benchmark_split(record_id),
                "blessing": final_annotation["label"],
                "boundaryCategory": final_annotation["boundaryCategory"],
                "annotationConfidence": final_annotation["confidence"],
                "annotationResolution": resolution,
            }
        )

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(
        "\n".join(
            json.dumps(value, ensure_ascii=False, sort_keys=True)
            for value in finalized
        )
        + "\n",
        encoding="utf-8",
    )
    exact_agreement = agreement_count / len(finalized) if finalized else 0
    label_agreement, label_kappa = binary_cohen_kappa(
        annotation_a,
        annotation_b,
    )
    manifest = {
        "schemaVersion": 1,
        "status": "human-reviewed",
        "humanReviewComplete": True,
        "records": len(finalized),
        "annotators": [arguments.annotator_a_id, arguments.annotator_b_id],
        "adjudicator": arguments.adjudicator_id,
        "exactLabelAndCategoryAgreement": round(exact_agreement, 6),
        "labelAgreement": round(label_agreement, 6),
        "labelCohenKappa": round(label_kappa, 6),
        "adjudicatedRecords": len(disagreements),
        "languages": dict(Counter(value["language"] for value in finalized)),
        "splits": dict(Counter(value["split"] for value in finalized)),
        "labels": {
            "positive": sum(value["blessing"] for value in finalized),
            "negative": sum(not value["blessing"] for value in finalized),
        },
        "boundaryCategories": dict(
            Counter(value["boundaryCategory"] for value in finalized)
        ),
        "outputSHA256": file_sha256(arguments.output),
    }
    (directory / "final-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
