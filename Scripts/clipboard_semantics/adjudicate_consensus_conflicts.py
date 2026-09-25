#!/usr/bin/env python3
"""Prepare and merge evidence-backed AI adjudication of consensus conflicts."""

from __future__ import annotations

import argparse
import hashlib
import json
import unicodedata
from collections import Counter
from pathlib import Path

from merge_consensus_labels_v2 import DOMAINS, INTENT_LABELS, stable_split

FLAG_FIELDS = {"ambiguous", "quotedOrMeta"}
LABEL_STATES = {"true", "false", "unknown"}
SENTIMENT_STATES = {"positive", "neutral", "negative", "unknown"}
RECORD_DISPOSITIONS = {"keep", "exclude-device-command"}
PRODUCT_POLICY_FIELDS = (
    "task",
    "question",
    "invitation",
    "complaint",
    "followUpReminder",
    "blessing",
    "replyableMessage",
    "assistantCommand",
    "informationQuery",
    "systemNotification",
    "domain",
)
PROMPT_VERSION = "clipboard-adjudication-v5"


def normalize(value: str) -> str:
    return " ".join(unicodedata.normalize("NFKC", value).casefold().split())


def read_json_lines(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def write_json_lines(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(
                json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n"
            )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def prepare(arguments: argparse.Namespace) -> dict:
    conflicts = read_json_lines(arguments.conflicts)
    include_policy_fields = getattr(
        arguments,
        "include_product_policy_fields",
        False,
    )
    queue = [
        {
            "id": record["id"],
            "text": record["text"],
            "language": record["language"],
            "unresolvedFields": list(
                dict.fromkeys(
                    (
                        *PRODUCT_POLICY_FIELDS,
                        *record["unresolvedFields"],
                    )
                    if include_policy_fields
                    else record["unresolvedFields"]
                )
            ),
        }
        for record in conflicts
    ]
    if len({record["id"] for record in queue}) != len(queue):
        raise ValueError("Conflict queue contains duplicate ids")
    write_json_lines(arguments.queue, queue)
    arguments.chunk_directory.mkdir(parents=True, exist_ok=True)
    chunks = []
    for start in range(0, len(queue), arguments.chunk_size):
        index = len(chunks) + 1
        path = arguments.chunk_directory / f"chunk-{index:03d}.jsonl"
        values = queue[start : start + arguments.chunk_size]
        write_json_lines(path, values)
        chunks.append(
            {
                "path": str(path),
                "records": len(values),
                "sha256": sha256_file(path),
            }
        )
    report = {
        "schemaVersion": 1,
        "promptVersion": PROMPT_VERSION,
        "queueCount": len(queue),
        "queueSHA256": sha256_file(arguments.queue),
        "chunkSize": arguments.chunk_size,
        "chunkCount": len(chunks),
        "includesProductPolicyFields": include_policy_fields,
        "productPolicyFields": (
            list(PRODUCT_POLICY_FIELDS) if include_policy_fields else []
        ),
        "chunks": chunks,
    }
    arguments.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return report


def valid_state(field: str, value: object) -> bool:
    if field == "sentiment":
        return value in SENTIMENT_STATES
    if field == "domain":
        return value in {*DOMAINS, "unknown"}
    return value in LABEL_STATES


def validate_adjudication(record: dict, queue_record: dict) -> dict:
    identifier = queue_record["id"]
    if record.get("id") != identifier:
        raise ValueError(f"Unexpected adjudication id: {record.get('id')}")
    disposition = record.get("recordDisposition")
    if disposition not in RECORD_DISPOSITIONS:
        raise ValueError(f"Invalid record disposition: {identifier}")
    disposition_confidence = record.get("dispositionConfidence")
    if (
        not isinstance(disposition_confidence, (int, float))
        or not 0 <= disposition_confidence <= 1
    ):
        raise ValueError(f"Invalid disposition confidence: {identifier}")
    disposition_evidence = record.get("dispositionEvidence")
    text = normalize(queue_record["text"])
    if (
        not isinstance(disposition_evidence, str)
        or not normalize(disposition_evidence)
        or normalize(disposition_evidence) not in text
    ):
        raise ValueError(f"Invalid disposition evidence: {identifier}")
    expected = set(queue_record["unresolvedFields"])
    for key in ("resolutions", "confidence", "evidence"):
        if not isinstance(record.get(key), dict) or set(record[key]) != expected:
            raise ValueError(f"{key} fields do not match unresolved fields: {identifier}")
    for field in expected:
        if not valid_state(field, record["resolutions"][field]):
            raise ValueError(f"Invalid resolution for {identifier}/{field}")
        confidence = record["confidence"][field]
        if not isinstance(confidence, (int, float)) or not 0 <= confidence <= 1:
            raise ValueError(f"Invalid confidence for {identifier}/{field}")
        evidence = record["evidence"][field]
        if not isinstance(evidence, str) or not normalize(evidence):
            raise ValueError(f"Missing evidence for {identifier}/{field}")
        if normalize(evidence) not in text:
            raise ValueError(f"Evidence is not an exact text quote: {identifier}/{field}")
    return {
        "id": identifier,
        "recordDisposition": disposition,
        "dispositionConfidence": round(float(disposition_confidence), 4),
        "dispositionEvidence": disposition_evidence,
        "resolutions": {
            field: record["resolutions"][field] for field in sorted(expected)
        },
        "confidence": {
            field: round(float(record["confidence"][field]), 4)
            for field in sorted(expected)
        },
        "evidence": {
            field: record["evidence"][field] for field in sorted(expected)
        },
    }


def load_adjudicator(
    paths: list[Path],
    queue_by_id: dict[str, dict],
) -> dict[str, dict]:
    values = []
    for path in paths:
        values.extend(read_json_lines(path))
    by_id = {}
    for value in values:
        identifier = value.get("id")
        if identifier not in queue_by_id:
            raise ValueError(f"Unexpected adjudication id: {identifier}")
        if identifier in by_id:
            raise ValueError(f"Duplicate adjudication id: {identifier}")
        by_id[identifier] = validate_adjudication(
            value,
            queue_by_id[identifier],
        )
    if set(by_id) != set(queue_by_id):
        raise ValueError("Adjudicator outputs do not cover the complete queue")
    return by_id


def resolved_base_field(conflict: dict, field: str) -> str:
    votes = conflict.get("modelVotes", {}).get(field, {})
    if not votes:
        return "unknown"
    value, count = max(votes.items(), key=lambda item: item[1])
    return value if count >= 4 else "unknown"


def tier_c_record(conflict: dict, resolutions: dict, evidence: dict) -> dict:
    states = {}
    for field in (*INTENT_LABELS, "sentiment", "domain"):
        states[field] = resolutions.get(
            field,
            resolved_base_field(conflict, field),
        )
    known_labels = [
        field
        for field in (*INTENT_LABELS, "sentiment", "domain")
        if states[field] != "unknown"
    ]
    return {
        "id": f"adjudicated-v5-{conflict['id']}",
        "sourceRecordID": conflict["id"],
        "text": conflict["text"],
        "language": conflict["language"],
        "family": "ai_adjudicated_v5",
        "split": stable_split(conflict["id"]),
        **{
            ("replyable" if label == "replyableMessage" else label): (
                states[label] == "true"
            )
            for label in INTENT_LABELS
        },
        "sentiment": (
            states["sentiment"]
            if states["sentiment"] != "unknown"
            else "neutral"
        ),
        "domain": (
            states["domain"] if states["domain"] != "unknown" else None
        ),
        "knownLabels": known_labels,
        "labelQualityTier": "C",
        "sampleWeight": 0.35,
        "promptVersion": PROMPT_VERSION,
        "adjudicationEvidence": evidence,
    }


def merge(arguments: argparse.Namespace) -> dict:
    conflicts = read_json_lines(arguments.conflicts)
    conflicts_by_id = {record["id"]: record for record in conflicts}
    queue = read_json_lines(arguments.queue)
    queue_by_id = {record["id"]: record for record in queue}
    if set(conflicts_by_id) != set(queue_by_id):
        raise ValueError("Conflict and adjudication queue ids differ")
    adjudicator_a = load_adjudicator(arguments.adjudicator_a, queue_by_id)
    adjudicator_b = load_adjudicator(arguments.adjudicator_b, queue_by_id)
    accepted = []
    excluded = []
    remaining = []
    rejection_reasons = Counter()
    for identifier in sorted(queue_by_id):
        conflict = conflicts_by_id[identifier]
        first = adjudicator_a[identifier]
        second = adjudicator_b[identifier]
        resolutions = {}
        evidence = {}
        rejected_fields = {}
        first_disposition = first["recordDisposition"]
        second_disposition = second["recordDisposition"]
        disposition_reasons = []
        if first_disposition != second_disposition:
            disposition_reasons.append("adjudicator-disagreement")
        if min(
            first["dispositionConfidence"],
            second["dispositionConfidence"],
        ) < arguments.minimum_confidence:
            disposition_reasons.append("low-confidence")
        if disposition_reasons:
            rejected_fields["recordDisposition"] = sorted(
                set(disposition_reasons)
            )
            rejection_reasons.update(set(disposition_reasons))
        elif first_disposition == "exclude-device-command":
            excluded.append(
                {
                    "id": identifier,
                    "text": conflict["text"],
                    "language": conflict["language"],
                    "disposition": first_disposition,
                    "promptVersion": PROMPT_VERSION,
                    "evidence": {
                        arguments.adjudicator_a_name: first[
                            "dispositionEvidence"
                        ],
                        arguments.adjudicator_b_name: second[
                            "dispositionEvidence"
                        ],
                    },
                }
            )
            continue
        for field in queue_by_id[identifier]["unresolvedFields"]:
            first_value = first["resolutions"][field]
            second_value = second["resolutions"][field]
            reasons = []
            if first_value != second_value:
                reasons.append("adjudicator-disagreement")
            if "unknown" in {first_value, second_value}:
                reasons.append("unknown")
            if min(
                first["confidence"][field],
                second["confidence"][field],
            ) < arguments.minimum_confidence:
                reasons.append("low-confidence")
            if field == "ambiguous" and first_value == "true":
                reasons.append("materially-ambiguous")
            if reasons:
                rejected_fields[field] = sorted(set(reasons))
                rejection_reasons.update(set(reasons))
                continue
            resolutions[field] = first_value
            evidence[field] = {
                arguments.adjudicator_a_name: first["evidence"][field],
                arguments.adjudicator_b_name: second["evidence"][field],
            }
        if rejected_fields:
            remaining.append(
                {
                    **conflict,
                    "aiAdjudication": {
                        "rejectedFields": rejected_fields,
                        "adjudicatorA": first,
                        "adjudicatorB": second,
                    },
                }
            )
            continue
        accepted.append(
            tier_c_record(conflict, resolutions, evidence)
        )
    write_json_lines(arguments.accepted, accepted)
    write_json_lines(arguments.excluded, excluded)
    write_json_lines(arguments.remaining, remaining)
    report = {
        "schemaVersion": 1,
        "promptVersion": PROMPT_VERSION,
        "queueCount": len(queue),
        "queueSHA256": sha256_file(arguments.queue),
        "minimumConfidence": arguments.minimum_confidence,
        "acceptedTierCCount": len(accepted),
        "excludedDeviceCommandCount": len(excluded),
        "remainingHumanReviewCount": len(remaining),
        "resolvedCount": len(accepted) + len(excluded),
        "resolutionRate": round(
            (len(accepted) + len(excluded)) / max(len(queue), 1),
            4,
        ),
        "rejectionReasonCounts": dict(sorted(rejection_reasons.items())),
        "adjudicators": [
            arguments.adjudicator_a_name,
            arguments.adjudicator_b_name,
        ],
        "acceptedLanguageCounts": dict(
            sorted(Counter(record["language"] for record in accepted).items())
        ),
        "remainingLanguageCounts": dict(
            sorted(Counter(record["language"] for record in remaining).items())
        ),
    }
    arguments.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return report


def review_priority(record: dict) -> tuple:
    reasons = {
        reason
        for field_reasons in record["aiAdjudication"]["rejectedFields"].values()
        for reason in field_reasons
    }
    severity = (
        0 if "adjudicator-disagreement" in reasons else 1,
        0 if "unknown" in reasons else 1,
        0 if "materially-ambiguous" in reasons else 1,
    )
    return (*severity, record["id"])


def adjudicator_field_review(adjudication: dict, field: str) -> dict:
    if field == "recordDisposition":
        return {
            "value": adjudication["recordDisposition"],
            "confidence": adjudication["dispositionConfidence"],
            "evidence": adjudication["dispositionEvidence"],
        }
    return {
        "value": adjudication["resolutions"][field],
        "confidence": adjudication["confidence"][field],
        "evidence": adjudication["evidence"][field],
    }


def review_sample(arguments: argparse.Namespace) -> dict:
    records = read_json_lines(arguments.remaining)
    grouped: dict[tuple[str, str], list[dict]] = {}
    for record in records:
        for field in record["aiAdjudication"]["rejectedFields"]:
            grouped.setdefault((record["language"], field), []).append(record)
    for values in grouped.values():
        values.sort(key=review_priority)

    selected = []
    selected_ids = set()
    offsets = {key: 0 for key in grouped}
    keys = sorted(grouped)
    while len(selected) < min(arguments.sample_size, len(records)):
        added = False
        for key in keys:
            values = grouped[key]
            while (
                offsets[key] < len(values)
                and values[offsets[key]]["id"] in selected_ids
            ):
                offsets[key] += 1
            if offsets[key] >= len(values):
                continue
            record = values[offsets[key]]
            offsets[key] += 1
            selected.append(record)
            selected_ids.add(record["id"])
            added = True
            if len(selected) >= arguments.sample_size:
                break
        if not added:
            break

    output = []
    for record in selected:
        first = record["aiAdjudication"]["adjudicatorA"]
        second = record["aiAdjudication"]["adjudicatorB"]
        fields = record["aiAdjudication"]["rejectedFields"]
        output.append(
            {
                "id": record["id"],
                "text": record["text"],
                "language": record["language"],
                "fieldReviews": {
                    field: {
                        "rejectionReasons": fields[field],
                        "adjudicatorA": adjudicator_field_review(first, field),
                        "adjudicatorB": adjudicator_field_review(second, field),
                    }
                    for field in sorted(fields)
                },
                "humanDecision": {field: None for field in sorted(fields)},
                "notes": "",
            }
        )
    write_json_lines(arguments.sample, output)
    report = {
        "schemaVersion": 1,
        "promptVersion": PROMPT_VERSION,
        "remainingCount": len(records),
        "sampleCount": len(output),
        "sampleSHA256": sha256_file(arguments.sample),
        "languageCounts": dict(
            sorted(Counter(record["language"] for record in output).items())
        ),
        "fieldCounts": dict(
            sorted(
                Counter(
                    field
                    for record in output
                    for field in record["fieldReviews"]
                ).items()
            )
        ),
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
    prepare_parser.add_argument("--conflicts", type=Path, required=True)
    prepare_parser.add_argument("--queue", type=Path, required=True)
    prepare_parser.add_argument("--chunk-directory", type=Path, required=True)
    prepare_parser.add_argument("--chunk-size", type=int, default=80)
    prepare_parser.add_argument(
        "--include-product-policy-fields",
        action="store_true",
    )
    prepare_parser.add_argument("--report", type=Path, required=True)
    prepare_parser.set_defaults(handler=prepare)

    merge_parser = commands.add_parser("merge")
    merge_parser.add_argument("--conflicts", type=Path, required=True)
    merge_parser.add_argument("--queue", type=Path, required=True)
    merge_parser.add_argument(
        "--adjudicator-a",
        action="append",
        type=Path,
        required=True,
    )
    merge_parser.add_argument(
        "--adjudicator-b",
        action="append",
        type=Path,
        required=True,
    )
    merge_parser.add_argument("--adjudicator-a-name", required=True)
    merge_parser.add_argument("--adjudicator-b-name", required=True)
    merge_parser.add_argument("--minimum-confidence", type=float, default=0.9)
    merge_parser.add_argument("--accepted", type=Path, required=True)
    merge_parser.add_argument("--excluded", type=Path, required=True)
    merge_parser.add_argument("--remaining", type=Path, required=True)
    merge_parser.add_argument("--report", type=Path, required=True)
    merge_parser.set_defaults(handler=merge)

    sample_parser = commands.add_parser("sample-review")
    sample_parser.add_argument("--remaining", type=Path, required=True)
    sample_parser.add_argument("--sample", type=Path, required=True)
    sample_parser.add_argument("--sample-size", type=int, default=60)
    sample_parser.add_argument("--report", type=Path, required=True)
    sample_parser.set_defaults(handler=review_sample)
    return root


def main() -> None:
    arguments = parser().parse_args()
    report = arguments.handler(arguments)
    print(
        f"AI_ADJUDICATION_{arguments.command.upper()} "
        + " ".join(
            f"{key}={value}"
            for key, value in report.items()
            if key.endswith("Count")
        )
    )


if __name__ == "__main__":
    main()
