#!/usr/bin/env python3
"""Prepare and evaluate product-owner clipboard semantic anchor labels."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

from adjudicate_consensus_conflicts import (
    load_adjudicator,
    read_json_lines,
    write_json_lines,
)

ANCHOR_FIELDS = (
    "replyableMessage",
    "task",
    "question",
    "assistantCommand",
    "informationQuery",
    "systemNotification",
    "domain",
    "ambiguous",
)
PROMPT_VERSION = "clipboard-adjudication-v5"


def read_anchors(path: Path) -> list[dict]:
    records = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(records, list) or not records:
        raise ValueError("Anchor file must contain a non-empty JSON array")
    identifiers = [record.get("id") for record in records]
    if len(set(identifiers)) != len(identifiers):
        raise ValueError("Anchor file contains duplicate ids")
    return records


def prepare(arguments: argparse.Namespace) -> dict:
    anchors = read_anchors(arguments.anchors)
    queue = [
        {
            "id": record["id"],
            "text": record["text"],
            "language": record["language"],
            "unresolvedFields": list(ANCHOR_FIELDS),
        }
        for record in anchors
    ]
    write_json_lines(arguments.queue, queue)
    return {
        "promptVersion": PROMPT_VERSION,
        "anchorCount": len(anchors),
        "queueCount": len(queue),
    }


def prepare_holdout(arguments: argparse.Namespace) -> dict:
    records = read_json_lines(arguments.holdout)
    identifiers = [record.get("id") for record in records]
    if len(set(identifiers)) != len(identifiers):
        raise ValueError("Holdout contains duplicate ids")
    queue = [
        {
            "id": record["id"],
            "text": record["text"],
            "language": record["language"],
            "unresolvedFields": list(ANCHOR_FIELDS),
        }
        for record in records
    ]
    write_json_lines(arguments.queue, queue)
    return {
        "promptVersion": PROMPT_VERSION,
        "holdoutCount": len(records),
        "queueCount": len(queue),
    }


def parse_labeler(value: str) -> tuple[str, Path]:
    name, separator, path = value.partition("=")
    if not separator or not name or not path:
        raise argparse.ArgumentTypeError("Labeler must use name=path")
    return name, Path(path)


def actual_value(adjudication: dict, field: str) -> str:
    if field == "recordDisposition":
        return adjudication["recordDisposition"]
    return adjudication["resolutions"][field]


def evaluate_labeler(
    anchors: list[dict],
    adjudications: dict[str, dict],
    gate_fields: set[str],
) -> dict:
    field_totals = Counter()
    field_correct = Counter()
    failures = []
    exact_records = 0
    for anchor in anchors:
        actual = adjudications[anchor["id"]]
        mismatches = {}
        for field, expected in anchor["expected"].items():
            field_totals[field] += 1
            observed = actual_value(actual, field)
            if observed == expected:
                field_correct[field] += 1
            else:
                mismatches[field] = {
                    "expected": expected,
                    "actual": observed,
                }
        if mismatches:
            failures.append(
                {
                    "id": anchor["id"],
                    "text": anchor["text"],
                    "mismatches": mismatches,
                }
            )
        else:
            exact_records += 1
    total = sum(field_totals.values())
    correct = sum(field_correct.values())
    gate_total = sum(field_totals[field] for field in gate_fields)
    gate_correct = sum(field_correct[field] for field in gate_fields)
    return {
        "decisionCount": total,
        "correctDecisionCount": correct,
        "decisionAccuracy": round(correct / total, 4),
        "exactRecordCount": exact_records,
        "exactRecordAccuracy": round(exact_records / len(anchors), 4),
        "gateDecisionCount": gate_total,
        "gateCorrectDecisionCount": gate_correct,
        "gateDecisionAccuracy": round(gate_correct / gate_total, 4),
        "fieldAccuracy": {
            field: round(field_correct[field] / count, 4)
            for field, count in sorted(field_totals.items())
        },
        "failures": failures,
    }


def evaluate(arguments: argparse.Namespace) -> dict:
    anchors = read_anchors(arguments.anchors)
    queue = read_json_lines(arguments.queue)
    queue_by_id = {record["id"]: record for record in queue}
    if {record["id"] for record in anchors} != set(queue_by_id):
        raise ValueError("Anchor and queue ids differ")
    gate_fields = set(
        getattr(arguments, "gate_field", None)
        or ("recordDisposition", *ANCHOR_FIELDS)
    )
    results = {}
    for name, path in arguments.labeler:
        adjudications = load_adjudicator([path], queue_by_id)
        results[name] = evaluate_labeler(
            anchors,
            adjudications,
            gate_fields,
        )
    report = {
        "schemaVersion": 1,
        "promptVersion": PROMPT_VERSION,
        "anchorCount": len(anchors),
        "minimumAccuracy": arguments.minimum_accuracy,
        "gateFields": sorted(gate_fields),
        "eligibleForCorpusReadjudication": all(
            result["gateDecisionAccuracy"] >= arguments.minimum_accuracy
            for result in results.values()
        ),
        "labelers": results,
    }
    arguments.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return report


def evaluate_blind(arguments: argparse.Namespace) -> dict:
    queue = read_json_lines(arguments.queue)
    queue_by_id = {record["id"]: record for record in queue}
    labels = read_json_lines(arguments.labels)
    label_ids = [record.get("id") for record in labels]
    if len(set(label_ids)) != len(label_ids):
        raise ValueError("Blind labels contain duplicate ids")
    if not set(label_ids) <= set(queue_by_id):
        raise ValueError("Blind labels contain ids outside the queue")
    anchors = []
    for label in labels:
        expected = {
            field: value
            for field, value in label.items()
            if field in {"recordDisposition", *ANCHOR_FIELDS}
        }
        queue_record = queue_by_id[label["id"]]
        anchors.append(
            {
                "id": label["id"],
                "text": queue_record["text"],
                "language": queue_record["language"],
                "expected": expected,
            }
        )
    gate_fields = set(
        getattr(arguments, "gate_field", None)
        or ("recordDisposition", *ANCHOR_FIELDS)
    )
    results = {}
    for name, path in arguments.labeler:
        adjudications = load_adjudicator([path], queue_by_id)
        results[name] = evaluate_labeler(
            anchors,
            adjudications,
            gate_fields,
        )
    report = {
        "schemaVersion": 1,
        "promptVersion": PROMPT_VERSION,
        "holdoutCount": len(queue),
        "labeledCount": len(anchors),
        "minimumAccuracy": arguments.minimum_accuracy,
        "gateFields": sorted(gate_fields),
        "eligibleForCorpusReadjudication": all(
            result["gateDecisionAccuracy"] >= arguments.minimum_accuracy
            for result in results.values()
        ),
        "labelers": results,
    }
    arguments.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return report


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)

    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--anchors", type=Path, required=True)
    prepare_parser.add_argument("--queue", type=Path, required=True)
    prepare_parser.set_defaults(handler=prepare)

    holdout_parser = commands.add_parser("prepare-holdout")
    holdout_parser.add_argument("--holdout", type=Path, required=True)
    holdout_parser.add_argument("--queue", type=Path, required=True)
    holdout_parser.set_defaults(handler=prepare_holdout)

    evaluate_parser = commands.add_parser("evaluate")
    evaluate_parser.add_argument("--anchors", type=Path, required=True)
    evaluate_parser.add_argument("--queue", type=Path, required=True)
    evaluate_parser.add_argument(
        "--labeler",
        action="append",
        type=parse_labeler,
        required=True,
    )
    evaluate_parser.add_argument("--minimum-accuracy", type=float, default=0.95)
    evaluate_parser.add_argument(
        "--gate-field",
        action="append",
        choices=("recordDisposition", *ANCHOR_FIELDS),
    )
    evaluate_parser.add_argument("--report", type=Path, required=True)
    evaluate_parser.set_defaults(handler=evaluate)

    blind_parser = commands.add_parser("evaluate-blind")
    blind_parser.add_argument("--labels", type=Path, required=True)
    blind_parser.add_argument("--queue", type=Path, required=True)
    blind_parser.add_argument(
        "--labeler",
        action="append",
        type=parse_labeler,
        required=True,
    )
    blind_parser.add_argument("--minimum-accuracy", type=float, default=0.95)
    blind_parser.add_argument(
        "--gate-field",
        action="append",
        choices=("recordDisposition", *ANCHOR_FIELDS),
    )
    blind_parser.add_argument("--report", type=Path, required=True)
    blind_parser.set_defaults(handler=evaluate_blind)
    return root


def main() -> None:
    arguments = parser().parse_args()
    report = arguments.handler(arguments)
    count = report.get("anchorCount", report.get("holdoutCount"))
    print(
        f"PRODUCT_POLICY_{arguments.command.upper()} "
        f"records={count}"
    )


if __name__ == "__main__":
    main()
