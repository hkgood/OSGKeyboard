#!/usr/bin/env python3
"""Finalize the frozen v6 blind holdout with field-level consensus."""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Iterable, Sequence


LABEL_DIRECTORY = Path(
    "ModelTraining/ClipboardSemantics/CorpusRegistry/Labels"
)
V6_BLIND_DIRECTORY = LABEL_DIRECTORY / "V6Blind"
DEFAULT_HOLDOUT = LABEL_DIRECTORY / "product-policy-blind-holdout-v1.jsonl"
DEFAULT_HUMAN_LABELS = (
    LABEL_DIRECTORY / "product-policy-blind-labels-v1.jsonl"
)
DEFAULT_OUTPUT = Path(
    "ModelTraining/ClipboardSemantics/v6-blind-evaluation-corpus.jsonl"
)
DEFAULT_REPORT = Path(
    "ModelTraining/ClipboardSemantics/v6-blind-evaluation-report.json"
)
DEFAULT_PRIMARY = (
    ("grok", V6_BLIND_DIRECTORY / "primary-grok.jsonl"),
    ("luna", V6_BLIND_DIRECTORY / "primary-luna.jsonl"),
    ("composer", V6_BLIND_DIRECTORY / "primary-composer.jsonl"),
)
DEFAULT_REVIEWERS = (
    ("sol", V6_BLIND_DIRECTORY / "reviewer-sol.jsonl"),
    ("claude", V6_BLIND_DIRECTORY / "reviewer-claude.jsonl"),
)
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
CONSENSUS_FIELDS = (*INTENT_LABELS, "sentiment", "domain")
RESOLUTION_FIELDS = (*CONSENSUS_FIELDS, "ambiguous")
HUMAN_FIELDS = ("task", "question", "replyableMessage", "ambiguous")
LABEL_STATES = {"true", "false", "unknown"}
SENTIMENT_STATES = {"positive", "neutral", "negative", "unknown"}
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
SOURCE_DATASET = "product-policy-blind-holdout-v1"
SOURCE_LICENSE = "OSGKeyboard project license"
SOURCE_REVISION = "v1"
SPLITS = ("validation", "test", "golden")


def read_json_lines(path: Path) -> list[dict]:
    """Read non-empty JSONL records in file order."""

    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def write_json_lines(path: Path, records: Iterable[dict]) -> None:
    """Write deterministic JSONL without changing text values."""

    path.parent.mkdir(parents=True, exist_ok=True)
    values = list(records)
    path.write_text(
        "".join(
            json.dumps(value, ensure_ascii=False, sort_keys=True) + "\n"
            for value in values
        ),
        encoding="utf-8",
    )


def sha256_file(path: Path) -> str:
    """Return a lowercase SHA-256 digest for one input or output."""

    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_named_path(value: str) -> tuple[str, Path]:
    """Parse a command-line NAME=PATH labeler input."""

    name, separator, raw_path = value.partition("=")
    if not separator or not name.strip() or not raw_path.strip():
        raise argparse.ArgumentTypeError("Expected NAME=PATH")
    return name.strip(), Path(raw_path)


def unique_records(records: Sequence[dict], source: str) -> dict[str, dict]:
    """Index records while rejecting missing and duplicate IDs."""

    by_id: dict[str, dict] = {}
    for record in records:
        identifier = record.get("id")
        if not isinstance(identifier, str) or not identifier:
            raise ValueError(f"{source} contains a missing or invalid id")
        if identifier in by_id:
            raise ValueError(f"{source} contains duplicate id: {identifier}")
        by_id[identifier] = record
    return by_id


def validate_holdout(records: Sequence[dict], expected_count: int | None) -> None:
    """Validate the frozen source records without normalizing their text."""

    unique_records(records, "holdout")
    if expected_count is not None and len(records) != expected_count:
        raise ValueError(
            f"Holdout must contain {expected_count} records, found {len(records)}"
        )
    for record in records:
        identifier = record["id"]
        if not isinstance(record.get("text"), str):
            raise TypeError(f"Holdout text must be a string for {identifier}")
        if record.get("language") not in {"en", "zh-Hans"}:
            raise ValueError(f"Unsupported holdout language for {identifier}")


def validate_model_record(record: dict, identifier: str, source: str) -> dict:
    """Validate and flatten one v6 model annotation."""

    labels = record.get("labels")
    if not isinstance(labels, dict) or set(labels) != set(INTENT_LABELS):
        raise ValueError(f"{source} must label all intents for {identifier}")
    for field in INTENT_LABELS:
        if labels[field] not in LABEL_STATES:
            raise ValueError(f"{source} has invalid {field} for {identifier}")
    if record.get("sentiment") not in SENTIMENT_STATES:
        raise ValueError(f"{source} has invalid sentiment for {identifier}")
    if record.get("domain") not in DOMAIN_STATES:
        raise ValueError(f"{source} has invalid domain for {identifier}")
    if not isinstance(record.get("ambiguous"), bool):
        raise TypeError(f"{source} has invalid ambiguous flag for {identifier}")
    return {
        **{field: labels[field] for field in INTENT_LABELS},
        "sentiment": record["sentiment"],
        "domain": record["domain"],
        "ambiguous": "true" if record["ambiguous"] else "false",
    }


def load_model_outputs(
    inputs: Sequence[tuple[str, Path]],
    expected_ids: set[str],
    source_kind: str,
) -> list[tuple[str, dict[str, dict]]]:
    """Load labelers whose IDs must exactly match their assigned queue."""

    loaded = []
    names: set[str] = set()
    for name, path in inputs:
        if name in names:
            raise ValueError(f"Duplicate {source_kind} labeler name: {name}")
        names.add(name)
        records = read_json_lines(path)
        by_id = unique_records(records, f"{source_kind} {name}")
        if set(by_id) != expected_ids:
            missing = expected_ids - set(by_id)
            extra = set(by_id) - expected_ids
            raise ValueError(
                f"{source_kind} {name} id mismatch: "
                f"missing={len(missing)} extra={len(extra)}"
            )
        loaded.append(
            (
                name,
                {
                    identifier: validate_model_record(
                        record,
                        identifier,
                        f"{source_kind} {name}",
                    )
                    for identifier, record in by_id.items()
                },
            )
        )
    return loaded


def resolve_votes(values: Sequence[str], required_votes: int) -> str:
    """Accept one non-unknown value only when it reaches the vote threshold."""

    votes = Counter(value for value in values if value != "unknown")
    if not votes:
        return "unknown"
    value, count = votes.most_common(1)[0]
    return value if count >= required_votes else "unknown"


def resolve_model_states(
    identifier: str,
    primary: Sequence[tuple[str, dict[str, dict]]],
    reviewers: Sequence[tuple[str, dict[str, dict]]],
    in_review_queue: bool,
) -> dict[str, str]:
    """Resolve every field independently under the 3/3 or 4/5 rule."""

    primary_records = [records[identifier] for _, records in primary]
    if in_review_queue:
        records = primary_records + [
            reviewer_records[identifier]
            for _, reviewer_records in reviewers
        ]
        required_votes = 4
    else:
        records = primary_records
        required_votes = 3
    return {
        field: resolve_votes(
            [record[field] for record in records],
            required_votes,
        )
        for field in RESOLUTION_FIELDS
    }


def validate_human_labels(
    records: Sequence[dict],
    expected_ids: set[str],
) -> dict[str, dict]:
    """Validate sparse product-owner labels without inferring absent fields."""

    by_id = unique_records(records, "human labels")
    if set(by_id) != expected_ids:
        missing = expected_ids - set(by_id)
        extra = set(by_id) - expected_ids
        raise ValueError(
            "Human label ids must match the frozen human prefix: "
            f"missing={len(missing)} extra={len(extra)}"
        )
    for identifier, record in by_id.items():
        disposition = record.get("recordDisposition")
        if disposition not in {None, "keep", "exclude-device-command"}:
            raise ValueError(
                f"Invalid human recordDisposition for {identifier}"
            )
        for field in HUMAN_FIELDS:
            if field in record and record[field] not in LABEL_STATES:
                raise ValueError(f"Invalid human {field} for {identifier}")
    return by_id


def apply_human_overrides(
    states: dict[str, str],
    human_record: dict | None,
) -> list[str]:
    """Override only explicitly supplied human fields."""

    overridden = []
    if human_record is None:
        return overridden
    for field in HUMAN_FIELDS:
        if field in human_record:
            states[field] = human_record[field]
            overridden.append(field)
    return overridden


def assign_splits(
    records: Sequence[dict],
    records_per_split: int | None,
) -> dict[str, str]:
    """Assign equal contiguous validation, test, and golden slices per language."""

    by_language: dict[str, list[str]] = {"en": [], "zh-Hans": []}
    for record in records:
        by_language[record["language"]].append(record["id"])
    assignments = {}
    for language, identifiers in by_language.items():
        per_split = records_per_split
        if per_split is None:
            if len(identifiers) % len(SPLITS):
                raise ValueError(
                    f"{language} count cannot be evenly divided into splits"
                )
            per_split = len(identifiers) // len(SPLITS)
        expected = per_split * len(SPLITS)
        if len(identifiers) != expected:
            raise ValueError(
                f"{language} must contain {expected} records, "
                f"found {len(identifiers)}"
            )
        for index, identifier in enumerate(identifiers):
            assignments[identifier] = SPLITS[index // per_split]
    return assignments


def output_record(
    source: dict,
    states: dict[str, str],
    split: str,
) -> dict:
    """Build one partial-label evaluation record in the training schema."""

    known_labels = [
        field for field in CONSENSUS_FIELDS if states[field] != "unknown"
    ]
    return {
        "id": source["id"],
        "text": source["text"],
        "language": source["language"],
        "split": split,
        "family": "v6_blind_product_holdout",
        **{
            ("replyable" if field == "replyableMessage" else field): (
                states[field] == "true"
            )
            for field in INTENT_LABELS
        },
        "sentiment": (
            states["sentiment"]
            if states["sentiment"] != "unknown"
            else "neutral"
        ),
        "domain": (
            states["domain"] if states["domain"] != "unknown" else None
        ),
        "ambiguous": (
            states["ambiguous"] == "true"
            if states["ambiguous"] != "unknown"
            else None
        ),
        "knownLabels": known_labels,
        "sourceDataset": SOURCE_DATASET,
        "sourceLicense": SOURCE_LICENSE,
        "sourceRevision": SOURCE_REVISION,
    }


def verify_report_hashes(
    holdout_path: Path,
    primary_inputs: Sequence[tuple[str, Path]],
    reviewer_inputs: Sequence[tuple[str, Path]],
    primary_report_path: Path,
    consensus_report_path: Path,
    review_count: int,
) -> None:
    """Cross-check frozen inputs against both existing consensus manifests."""

    primary_report = json.loads(primary_report_path.read_text(encoding="utf-8"))
    consensus_report = json.loads(
        consensus_report_path.read_text(encoding="utf-8")
    )
    holdout_hash = sha256_file(holdout_path)
    for name, report in (
        ("primary report", primary_report),
        ("consensus report", consensus_report),
    ):
        if report.get("queueSHA256") != holdout_hash:
            raise ValueError(f"{name} holdout SHA-256 mismatch")
    if primary_report.get("reviewCount") != review_count:
        raise ValueError("Primary report review count mismatch")
    all_inputs = (*primary_inputs, *reviewer_inputs)
    expected_primary = primary_report.get("primaryOutputSHA256") or {}
    expected_all = consensus_report.get("labelerOutputSHA256") or {}
    for name, path in all_inputs:
        actual_hash = sha256_file(path)
        if name in expected_primary and expected_primary[name] != actual_hash:
            raise ValueError(f"Primary report SHA-256 mismatch for {name}")
        if expected_all.get(name) != actual_hash:
            raise ValueError(f"Consensus report SHA-256 mismatch for {name}")


def build_corpus(
    holdout: Sequence[dict],
    primary: Sequence[tuple[str, dict[str, dict]]],
    reviewers: Sequence[tuple[str, dict[str, dict]]],
    review_ids: set[str],
    human_by_id: dict[str, dict],
    records_per_split: int | None,
) -> tuple[list[dict], dict[str, list[str]], dict[str, dict[str, str]]]:
    """Resolve all records while preserving frozen order and partial labels."""

    split_by_id = assign_splits(holdout, records_per_split)
    output = []
    overrides_by_id: dict[str, list[str]] = {}
    states_by_id: dict[str, dict[str, str]] = {}
    for source in holdout:
        identifier = source["id"]
        states = resolve_model_states(
            identifier,
            primary,
            reviewers,
            identifier in review_ids,
        )
        overrides = apply_human_overrides(states, human_by_id.get(identifier))
        overrides_by_id[identifier] = overrides
        states_by_id[identifier] = states
        output.append(output_record(source, states, split_by_id[identifier]))
    return output, overrides_by_id, states_by_id


def build_report(
    output: Sequence[dict],
    states_by_id: dict[str, dict[str, str]],
    overrides_by_id: dict[str, list[str]],
    human_by_id: dict[str, dict],
    input_hashes: dict[str, str],
    output_hash: str,
) -> dict:
    """Summarize coverage without treating unknown defaults as labels."""

    known_counts = Counter()
    positive_counts = Counter()
    unresolved_counts = Counter()
    for record in output:
        known_counts.update(record["knownLabels"])
        for field in INTENT_LABELS:
            output_field = "replyable" if field == "replyableMessage" else field
            if field in record["knownLabels"] and record[output_field]:
                positive_counts[field] += 1
        for field, state in states_by_id[record["id"]].items():
            if state == "unknown":
                unresolved_counts[field] += 1
    override_counts = Counter(
        field for fields in overrides_by_id.values() for field in fields
    )
    domains = Counter(
        record["domain"] for record in output if record["domain"] is not None
    )
    domains["unknown"] = sum(record["domain"] is None for record in output)
    return {
        "schemaVersion": 1,
        "sourceDataset": SOURCE_DATASET,
        "sourceLicense": SOURCE_LICENSE,
        "sourceRevision": SOURCE_REVISION,
        "recordCount": len(output),
        "inputSHA256": dict(sorted(input_hashes.items())),
        "outputSHA256": output_hash,
        "languages": dict(
            sorted(Counter(record["language"] for record in output).items())
        ),
        "splits": dict(
            sorted(Counter(record["split"] for record in output).items())
        ),
        "knownByField": {
            field: known_counts[field] for field in CONSENSUS_FIELDS
        },
        "positiveByIntent": {
            field: positive_counts[field] for field in INTENT_LABELS
        },
        "domains": dict(sorted(domains.items())),
        "humanCoverage": {
            "records": len(human_by_id),
            "overriddenRecords": sum(bool(value) for value in overrides_by_id.values()),
            "overridesByField": {
                field: override_counts[field] for field in HUMAN_FIELDS
            },
            "excludeDeviceCommandRecords": sum(
                record.get("recordDisposition") == "exclude-device-command"
                for record in human_by_id.values()
            ),
        },
        "unresolvedByField": {
            field: unresolved_counts[field] for field in RESOLUTION_FIELDS
        },
    }


def finalize(arguments: argparse.Namespace) -> dict:
    """Load, validate, resolve, write, and report one frozen holdout."""

    primary_inputs = tuple(arguments.primary or DEFAULT_PRIMARY)
    reviewer_inputs = tuple(arguments.reviewer or DEFAULT_REVIEWERS)
    if len(primary_inputs) != 3 or len(reviewer_inputs) != 2:
        raise ValueError("Exactly three primary and two reviewer inputs are required")
    holdout = read_json_lines(arguments.holdout)
    validate_holdout(holdout, arguments.expected_count)
    holdout_ids = {record["id"] for record in holdout}
    holdout_by_id = {record["id"]: record for record in holdout}
    review_queue = read_json_lines(arguments.review_queue)
    review_by_id = unique_records(review_queue, "review queue")
    review_ids = set(review_by_id)
    if not review_ids <= holdout_ids:
        raise ValueError("Review queue contains IDs outside the holdout")
    if (
        arguments.expected_review_count is not None
        and len(review_queue) != arguments.expected_review_count
    ):
        raise ValueError(
            "Review queue must contain "
            f"{arguments.expected_review_count} records, found {len(review_queue)}"
        )
    for identifier, record in review_by_id.items():
        source = holdout_by_id[identifier]
        if (
            record.get("text") != source["text"]
            or record.get("language") != source["language"]
        ):
            raise ValueError(f"Review queue changed frozen text for {identifier}")
    primary = load_model_outputs(
        primary_inputs,
        holdout_ids,
        "primary",
    )
    reviewers = load_model_outputs(
        reviewer_inputs,
        review_ids,
        "reviewer",
    )
    human_records = read_json_lines(arguments.human_labels)
    human_count = arguments.human_count
    if human_count is None:
        human_count = len(human_records)
    human_prefix_ids = {
        record["id"] for record in holdout[:human_count]
    }
    if len(human_records) != human_count:
        raise ValueError(
            f"Expected {human_count} human labels, found {len(human_records)}"
        )
    human_by_id = validate_human_labels(human_records, human_prefix_ids)
    if arguments.verify_manifests:
        verify_report_hashes(
            arguments.holdout,
            primary_inputs,
            reviewer_inputs,
            arguments.primary_report,
            arguments.consensus_report,
            len(review_queue),
        )
    output, overrides_by_id, states_by_id = build_corpus(
        holdout,
        primary,
        reviewers,
        review_ids,
        human_by_id,
        arguments.records_per_split,
    )
    if [record["id"] for record in output] != [
        record["id"] for record in holdout
    ]:
        raise AssertionError("Output order changed")
    if any(record["split"] == "train" for record in output):
        raise AssertionError("Evaluation output must not contain train records")
    if any(
        output_record_value["text"] != source["text"]
        for output_record_value, source in zip(output, holdout)
    ):
        raise AssertionError("Output text changed")
    write_json_lines(arguments.output, output)
    input_paths = {
        "holdout": arguments.holdout,
        "reviewQueue": arguments.review_queue,
        "humanLabels": arguments.human_labels,
        **{f"primary:{name}": path for name, path in primary_inputs},
        **{f"reviewer:{name}": path for name, path in reviewer_inputs},
    }
    report = build_report(
        output,
        states_by_id,
        overrides_by_id,
        human_by_id,
        {name: sha256_file(path) for name, path in input_paths.items()},
        sha256_file(arguments.output),
    )
    arguments.report.parent.mkdir(parents=True, exist_ok=True)
    arguments.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return report


def parser() -> argparse.ArgumentParser:
    """Build the command-line interface with production-safe defaults."""

    value = argparse.ArgumentParser()
    value.add_argument("--holdout", type=Path, default=DEFAULT_HOLDOUT)
    value.add_argument(
        "--review-queue",
        type=Path,
        default=V6_BLIND_DIRECTORY / "review-queue.jsonl",
    )
    value.add_argument("--primary", action="append", type=parse_named_path)
    value.add_argument("--reviewer", action="append", type=parse_named_path)
    value.add_argument(
        "--human-labels",
        type=Path,
        default=DEFAULT_HUMAN_LABELS,
    )
    value.add_argument(
        "--primary-report",
        type=Path,
        default=V6_BLIND_DIRECTORY / "primary-report.json",
    )
    value.add_argument(
        "--consensus-report",
        type=Path,
        default=V6_BLIND_DIRECTORY / "consensus-report.json",
    )
    value.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    value.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    value.add_argument("--expected-count", type=int, default=120)
    value.add_argument("--expected-review-count", type=int, default=94)
    value.add_argument("--human-count", type=int, default=60)
    value.add_argument("--records-per-split", type=int, default=20)
    value.add_argument(
        "--skip-manifest-verification",
        action="store_false",
        dest="verify_manifests",
    )
    value.set_defaults(verify_manifests=True)
    return value


def main() -> None:
    """Run the finalizer and print its compact completion counts."""

    report = finalize(parser().parse_args())
    print(
        "V6_BLIND_FINALIZED "
        f"records={report['recordCount']} "
        f"unresolved={sum(report['unresolvedByField'].values())}"
    )


if __name__ == "__main__":
    main()
