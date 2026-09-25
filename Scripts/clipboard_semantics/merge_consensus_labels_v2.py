#!/usr/bin/env python3
"""Merge blind three-state labels from three primary and two review models."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import Counter
from pathlib import Path

INTENT_LABELS = (
    "task",
    "question",
    "invitation",
    "complaint",
    "scheduleNegotiation",
    "confirmationDecision",
    "followUpReminder",
    "blessing",
    "replyableMessage",
    "assistantCommand",
    "informationQuery",
    "systemNotification",
)
DOMAINS = {
    "finance",
    "travel",
    "calendar",
    "communication",
    "media",
    "smartHome",
    "shopping",
    "dining",
    "health",
    "weather",
    "accountService",
    "generalKnowledge",
}
DOMAIN_STATES = {*DOMAINS, "unknown"}
LABEL_STATES = {"true", "false", "unknown"}
SENTIMENT_STATES = {"positive", "neutral", "negative", "unknown"}
PROMPT_VERSION = "clipboard-consensus-v6"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


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


def parse_labeler(value: str) -> tuple[str, Path]:
    name, separator, raw_path = value.partition("=")
    if not separator or not name or not raw_path:
        raise argparse.ArgumentTypeError("Expected LABELER=PATH")
    return name, Path(raw_path)


def validate_record(record: dict, expected_ids: set[str]) -> dict:
    identifier = record.get("id")
    if identifier not in expected_ids:
        raise ValueError(f"Unexpected labeler record id: {identifier}")
    labels = record.get("labels")
    if not isinstance(labels, dict) or set(labels) != set(INTENT_LABELS):
        raise ValueError(f"Every intent label is required for {identifier}")
    if any(value not in LABEL_STATES for value in labels.values()):
        raise ValueError(f"Invalid three-state label for {identifier}")
    sentiment = record.get("sentiment")
    if sentiment not in SENTIMENT_STATES:
        raise ValueError(f"Invalid sentiment for {identifier}: {sentiment}")
    domain = record.get("domain")
    if domain not in DOMAIN_STATES:
        raise ValueError(f"Invalid domain for {identifier}: {domain}")
    if not isinstance(record.get("ambiguous"), bool):
        raise TypeError(f"Missing ambiguous flag for {identifier}")
    if not isinstance(record.get("quotedOrMeta"), bool):
        raise TypeError(f"Missing quotedOrMeta flag for {identifier}")
    confidence = record.get("confidence")
    if not isinstance(confidence, (int, float)) or not 0 <= confidence <= 1:
        raise ValueError(f"Invalid confidence for {identifier}: {confidence}")
    return {
        "id": identifier,
        "labels": {label: labels[label] for label in INTENT_LABELS},
        "sentiment": sentiment,
        "domain": domain,
        "ambiguous": record["ambiguous"],
        "quotedOrMeta": record["quotedOrMeta"],
        "confidence": round(float(confidence), 4),
    }


def load_labelers(
    values: list[tuple[str, Path]],
    expected_ids: set[str],
    require_exact_ids: bool,
) -> list[tuple[str, dict[str, dict]]]:
    labelers = []
    for name, path in values:
        records = [
            validate_record(record, expected_ids)
            for record in read_json_lines(path)
        ]
        by_id = {record["id"]: record for record in records}
        if len(by_id) != len(records):
            raise ValueError(f"Labeler {name} contains duplicate ids")
        if require_exact_ids and set(by_id) != expected_ids:
            missing = expected_ids - set(by_id)
            extra = set(by_id) - expected_ids
            raise ValueError(
                f"Labeler {name} id mismatch: missing={len(missing)} "
                f"extra={len(extra)}"
            )
        labelers.append((name, by_id))
    return labelers


def field_values(record: dict) -> dict[str, str]:
    return {
        **record["labels"],
        "sentiment": record["sentiment"],
        "domain": record["domain"],
    }


def primary_review_ids(
    primary: list[tuple[str, dict[str, dict]]],
    queue_ids: set[str],
) -> set[str]:
    review_ids = set()
    for identifier in queue_ids:
        records = [values[identifier] for _, values in primary]
        fields = [field_values(record) for record in records]
        unanimous = all(
            len({field[name] for field in fields}) == 1
            for name in (*INTENT_LABELS, "sentiment", "domain")
        )
        flags_clear = not any(
            record["ambiguous"] or record["quotedOrMeta"] for record in records
        )
        if not unanimous or not flags_clear:
            review_ids.add(identifier)
    return review_ids


def prepare_review(arguments: argparse.Namespace) -> dict:
    queue = read_json_lines(arguments.queue)
    queue_by_id = {record["id"]: record for record in queue}
    if len(queue_by_id) != len(queue):
        raise ValueError("Queue contains duplicate ids")
    if len(arguments.primary) != 3:
        raise ValueError("Exactly three primary labelers are required")
    primary = load_labelers(arguments.primary, set(queue_by_id), True)
    review_ids = primary_review_ids(primary, set(queue_by_id))
    review_queue = [
        {
            "id": record["id"],
            "text": record["text"],
            "language": record["language"],
        }
        for record in queue
        if record["id"] in review_ids
    ]
    write_json_lines(arguments.output, review_queue)
    report = {
        "schemaVersion": 2,
        "promptVersion": PROMPT_VERSION,
        "queueCount": len(queue),
        "queueSHA256": sha256_file(arguments.queue),
        "primaryUnanimousCount": len(queue) - len(review_queue),
        "reviewCount": len(review_queue),
        "primaryLabelers": [name for name, _ in primary],
        "primaryOutputSHA256": {
            name: sha256_file(path) for name, path in arguments.primary
        },
    }
    arguments.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return report


def split_queue(arguments: argparse.Namespace) -> dict:
    queue = read_json_lines(arguments.queue)
    if arguments.chunk_size <= 0:
        raise ValueError("chunk-size must be positive")
    arguments.output_directory.mkdir(parents=True, exist_ok=True)
    output_paths = []
    for start in range(0, len(queue), arguments.chunk_size):
        index = len(output_paths) + 1
        path = arguments.output_directory / f"chunk-{index:03d}.jsonl"
        write_json_lines(path, queue[start : start + arguments.chunk_size])
        output_paths.append(path)
    report = {
        "schemaVersion": 2,
        "queueCount": len(queue),
        "queueSHA256": sha256_file(arguments.queue),
        "chunkSize": arguments.chunk_size,
        "chunkCount": len(output_paths),
        "chunks": [
            {
                "path": str(path),
                "records": len(read_json_lines(path)),
                "sha256": sha256_file(path),
            }
            for path in output_paths
        ],
    }
    arguments.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return report


def combine_labeler(arguments: argparse.Namespace) -> dict:
    queue = read_json_lines(arguments.queue)
    queue_ids = [record["id"] for record in queue]
    expected_ids = set(queue_ids)
    combined = []
    for path in arguments.input:
        combined.extend(read_json_lines(path))
    validated = [
        validate_record(record, expected_ids) for record in combined
    ]
    by_id = {record["id"]: record for record in validated}
    if len(by_id) != len(validated):
        raise ValueError("Combined labeler outputs contain duplicate ids")
    if set(by_id) != expected_ids:
        raise ValueError(
            "Combined labeler output ids do not match the source queue"
        )
    ordered = [by_id[identifier] for identifier in queue_ids]
    write_json_lines(arguments.output, ordered)
    report = {
        "schemaVersion": 2,
        "queueCount": len(queue),
        "queueSHA256": sha256_file(arguments.queue),
        "inputCount": len(arguments.input),
        "outputCount": len(ordered),
        "outputSHA256": sha256_file(arguments.output),
    }
    arguments.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return report


def stable_split(identifier: str) -> str:
    bucket = int.from_bytes(hashlib.sha256(identifier.encode()).digest()[:8], "big")
    bucket %= 100
    if bucket < 80:
        return "silverTrain"
    if bucket < 90:
        return "silverCalibration"
    return "silverAcceptance"


def field_consensus(
    records: list[dict],
    field: str,
    required_votes: int,
) -> tuple[str, dict[str, int]]:
    values = [
        field_values(record)[field]
        for record in records
        if field_values(record)[field] != "unknown"
    ]
    votes = Counter(values)
    if not votes:
        return "unknown", {}
    value, count = votes.most_common(1)[0]
    if count < required_votes:
        return "unknown", dict(sorted(votes.items()))
    return value, dict(sorted(votes.items()))


def fleiss_kappa_for_field(
    labelers: list[tuple[str, dict[str, dict]]],
    identifiers: list[str],
    field: str,
) -> float:
    categories = (
        sorted(SENTIMENT_STATES)
        if field == "sentiment"
        else sorted(DOMAIN_STATES)
        if field == "domain"
        else sorted(LABEL_STATES)
    )
    category_totals = Counter()
    item_agreements = []
    rater_count = len(labelers)
    for identifier in identifiers:
        votes = Counter(
            field_values(records[identifier])[field]
            for _, records in labelers
        )
        category_totals.update(votes)
        item_agreements.append(
            sum(count * (count - 1) for count in votes.values())
            / (rater_count * (rater_count - 1))
        )
    if not item_agreements:
        return 0
    observed = sum(item_agreements) / len(item_agreements)
    total = sum(category_totals.values())
    expected = sum(
        (category_totals[category] / total) ** 2 for category in categories
    )
    if math.isclose(expected, 1):
        return 1
    return round((observed - expected) / (1 - expected), 4)


def training_record(
    queue_record: dict,
    states: dict[str, str],
    tier: str,
    votes: dict,
    labelers: list[tuple[str, dict[str, dict]]],
) -> dict:
    split = stable_split(queue_record["id"])
    known_labels = [
        label
        for label in (*INTENT_LABELS, "sentiment", "domain")
        if states[label] != "unknown"
    ]
    return {
        "id": f"consensus-v2-{queue_record['id']}",
        "sourceRecordID": queue_record["id"],
        "text": queue_record["text"],
        "language": queue_record["language"],
        "family": "consensus_v2",
        "split": split,
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
        "labelQualityTier": tier,
        "sampleWeight": 1.0 if tier == "A" else 0.65,
        "promptVersion": PROMPT_VERSION,
        "modelVotes": votes,
        "labelers": [name for name, _ in labelers],
    }


def merge(arguments: argparse.Namespace) -> dict:
    queue = read_json_lines(arguments.queue)
    queue_by_id = {record["id"]: record for record in queue}
    queue_ids = set(queue_by_id)
    if len(queue_by_id) != len(queue):
        raise ValueError("Queue contains duplicate ids")
    if len(arguments.primary) != 3 or len(arguments.reviewer) != 2:
        raise ValueError("Three primary and two review labelers are required")
    primary = load_labelers(arguments.primary, queue_ids, True)
    review_ids = primary_review_ids(primary, queue_ids)
    reviewers = load_labelers(arguments.reviewer, review_ids, True)
    tier_a = []
    tier_b = []
    human_review = []
    all_labelers = primary + reviewers
    field_names = (*INTENT_LABELS, "sentiment", "domain")
    for identifier in sorted(queue_ids):
        queue_record = queue_by_id[identifier]
        primary_records = [records[identifier] for _, records in primary]
        if identifier not in review_ids:
            states = {
                field: field_values(primary_records[0])[field]
                for field in field_names
            }
            votes = {
                field: {states[field]: 3}
                for field in field_names
            }
            tier_a.append(
                training_record(
                    queue_record,
                    states,
                    "A",
                    votes,
                    primary,
                )
            )
            continue
        combined_records = primary_records + [
            records[identifier] for _, records in reviewers
        ]
        states = {}
        votes = {}
        for field in field_names:
            states[field], votes[field] = field_consensus(
                combined_records,
                field,
                4,
            )
        ambiguous_votes = sum(
            record["ambiguous"] for record in combined_records
        )
        quoted_votes = sum(
            record["quotedOrMeta"] for record in combined_records
        )
        unresolved = [
            field
            for field, value in states.items()
            if value == "unknown" and votes[field]
        ]
        positive_intents = any(states[label] == "true" for label in INTENT_LABELS)
        if ambiguous_votes >= 2:
            unresolved.append("ambiguous")
        if quoted_votes >= 2 and positive_intents:
            unresolved.append("quotedOrMeta")
        if unresolved:
            human_review.append(
                {
                    "id": identifier,
                    "text": queue_record["text"],
                    "language": queue_record["language"],
                    "unresolvedFields": sorted(set(unresolved)),
                    "modelVotes": votes,
                    "ambiguousVotes": ambiguous_votes,
                    "quotedOrMetaVotes": quoted_votes,
                    "resolution": None,
                    "reviewer": None,
                    "reason": None,
                }
            )
            continue
        tier_b.append(
            training_record(
                queue_record,
                states,
                "B",
                votes,
                all_labelers,
            )
        )
    accepted = tier_a + tier_b
    write_json_lines(arguments.tier_a, tier_a)
    write_json_lines(arguments.tier_b, tier_b)
    write_json_lines(arguments.accepted, accepted)
    write_json_lines(arguments.human_review, human_review)
    identifiers = sorted(queue_ids)
    kappa_by_field = {
        field: fleiss_kappa_for_field(primary, identifiers, field)
        for field in field_names
    }
    languages = sorted({record["language"] for record in queue})
    kappa_by_language = {
        language: {
            field: fleiss_kappa_for_field(
                primary,
                sorted(
                    identifier
                    for identifier, record in queue_by_id.items()
                    if record["language"] == language
                ),
                field,
            )
            for field in field_names
        }
        for language in languages
    }
    kappa_gate_passed = all(
        value >= 0.8
        for values in kappa_by_language.values()
        for value in values.values()
    )
    report = {
        "schemaVersion": 2,
        "promptVersion": PROMPT_VERSION,
        "queueCount": len(queue),
        "queueSHA256": sha256_file(arguments.queue),
        "tierACount": len(tier_a),
        "tierBCount": len(tier_b),
        "humanReviewCount": len(human_review),
        "acceptanceRate": round(len(accepted) / max(len(queue), 1), 4),
        "primaryLabelers": [name for name, _ in primary],
        "reviewLabelers": [name for name, _ in reviewers],
        "labelerOutputSHA256": {
            name: sha256_file(path)
            for name, path in (*arguments.primary, *arguments.reviewer)
        },
        "primaryFleissKappaByField": kappa_by_field,
        "primaryFleissKappaByLanguageAndField": kappa_by_language,
        "scaleUpKappaThreshold": 0.8,
        "eligibleForScaleUp": kappa_gate_passed,
        "acceptedIntentPositiveCounts": {
            label: sum(
                record["replyable" if label == "replyableMessage" else label]
                for record in accepted
            )
            for label in INTENT_LABELS
        },
        "acceptedLanguageCounts": dict(
            sorted(Counter(record["language"] for record in accepted).items())
        ),
        "splitCounts": dict(
            sorted(Counter(record["split"] for record in accepted).items())
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
    review = commands.add_parser("prepare-review")
    review.add_argument("--queue", type=Path, required=True)
    review.add_argument(
        "--primary",
        action="append",
        type=parse_labeler,
        required=True,
    )
    review.add_argument("--output", type=Path, required=True)
    review.add_argument("--report", type=Path, required=True)
    review.set_defaults(handler=prepare_review)

    split = commands.add_parser("split-queue")
    split.add_argument("--queue", type=Path, required=True)
    split.add_argument("--output-directory", type=Path, required=True)
    split.add_argument("--chunk-size", type=int, default=100)
    split.add_argument("--report", type=Path, required=True)
    split.set_defaults(handler=split_queue)

    combine = commands.add_parser("combine-labeler")
    combine.add_argument("--queue", type=Path, required=True)
    combine.add_argument(
        "--input",
        action="append",
        type=Path,
        required=True,
    )
    combine.add_argument("--output", type=Path, required=True)
    combine.add_argument("--report", type=Path, required=True)
    combine.set_defaults(handler=combine_labeler)

    merge_parser = commands.add_parser("merge")
    merge_parser.add_argument("--queue", type=Path, required=True)
    merge_parser.add_argument(
        "--primary",
        action="append",
        type=parse_labeler,
        required=True,
    )
    merge_parser.add_argument(
        "--reviewer",
        action="append",
        type=parse_labeler,
        required=True,
    )
    merge_parser.add_argument("--tier-a", type=Path, required=True)
    merge_parser.add_argument("--tier-b", type=Path, required=True)
    merge_parser.add_argument("--accepted", type=Path, required=True)
    merge_parser.add_argument("--human-review", type=Path, required=True)
    merge_parser.add_argument("--report", type=Path, required=True)
    merge_parser.set_defaults(handler=merge)
    return root


def main() -> None:
    arguments = parser().parse_args()
    report = arguments.handler(arguments)
    print(
        f"CONSENSUS_V2_{arguments.command.upper().replace('-', '_')} "
        + " ".join(f"{key}={value}" for key, value in report.items() if key.endswith("Count"))
    )


if __name__ == "__main__":
    main()
