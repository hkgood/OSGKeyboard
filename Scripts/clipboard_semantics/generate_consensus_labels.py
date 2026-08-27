#!/usr/bin/env python3
"""Prepare public-text labeling queues and build deterministic consensus silver data."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import re
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path


SEED = 20260827
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
)
SPECIAL_FLAGS = ("ambiguous", "quotedOrMeta")
ACTION_LABELS = (
    "taskOnly",
    "complaintOnly",
    "both",
    "questionRequest",
    "neither",
)
COORDINATION_LABELS = (
    "invitation",
    "scheduleNegotiation",
    "confirmationDecision",
    "followUpReminder",
    "neither",
)
PROMPT_VERSION = "clipboard-consensus-v1"
DEFAULT_DIRECTORY = Path("ModelTraining/ClipboardSemantics/Consensus")
DEFAULT_INPUT = Path("ModelTraining/ClipboardSemantics/open-training-corpus.jsonl")


def normalized_text(value: str) -> str:
    return " ".join(
        unicodedata.normalize("NFKC", value)
        .replace("\u0000", " ")
        .split()
    ).strip()


def stable_hash(value: str) -> int:
    return int.from_bytes(hashlib.sha256(value.encode()).digest()[:8], "big")


def read_json_lines(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def write_json_lines(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    serialized = "\n".join(
        json.dumps(record, ensure_ascii=False, sort_keys=True)
        for record in records
    )
    path.write_text(serialized + ("\n" if serialized else ""), encoding="utf-8")


def queue_priority(
    record: dict,
    hard_negative_texts: set[str],
) -> tuple[int, int]:
    known_labels = set(record.get("knownLabels") or [])
    positive_count = sum(bool(record.get(label)) for label in INTENT_LABELS)
    confusion_priority = int(
        bool(
            known_labels
            & {
                "task",
                "question",
                "complaint",
                "invitation",
                "scheduleNegotiation",
                "confirmationDecision",
                "followUpReminder",
            }
        )
    )
    hard_negative_priority = int(
        normalized_text(record["text"]).casefold() in hard_negative_texts
    )
    return (
        hard_negative_priority * 10 + confusion_priority + positive_count,
        stable_hash(record["id"]),
    )


def stratified_queue(
    records: list[dict],
    count: int,
    seed: int,
    hard_negative_texts: set[str],
) -> list[dict]:
    grouped: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for record in records:
        grouped[
            (
                record.get("sourceDataset", "unknown"),
                record.get("language", "unknown"),
            )
        ].append(record)
    for key in grouped:
        grouped[key].sort(
            key=lambda record: queue_priority(record, hard_negative_texts),
            reverse=True,
        )

    keys = sorted(grouped)
    rng = random.Random(seed)
    rng.shuffle(keys)
    offsets = {key: 0 for key in keys}
    selected: list[dict] = []
    while len(selected) < count:
        added = False
        for key in keys:
            offset = offsets[key]
            values = grouped[key]
            if offset >= len(values):
                continue
            selected.append(values[offset])
            offsets[key] += 1
            added = True
            if len(selected) == count:
                break
        if not added:
            break
    return sorted(selected, key=lambda record: record["id"])


def labeling_instructions() -> str:
    return """# Clipboard semantic consensus labeling

Prompt version: clipboard-consensus-v1

Label every JSONL queue record independently. Use only the text itself; do not
infer missing conversational context. Return one JSON object per input record:

{"id":"same id","labels":["task"],"ambiguous":false,"quotedOrMeta":false,"confidence":0.98}

Allowed labels:
- task: another person is explicitly asked/assigned to perform an action.
- question: a genuine information question, including request-shaped questions.
- invitation: invitation to join an event or social activity.
- complaint: present dissatisfaction, malfunction, bad service, or unresolved problem.
- scheduleNegotiation: proposing, changing, or choosing between times; a fixed time is not enough.
- confirmationDecision: explicit approval, rejection, or selection of an option.
- followUpReminder: request to remind, check back, or follow up later/after a trigger.
- blessing: a genuine birthday, holiday, congratulations, or good-wish message.
- replyableMessage: a direct conversational message that naturally invites a response.

Rules:
- Multi-label is allowed. "Could you send it?" is task + question + replyableMessage.
- Set quotedOrMeta when intent-like words are quoted, documented, searched, or discussed.
- Set ambiguous when the text cannot be labeled without missing context.
- Empty labels mean none of the product intents.
- Negative sentiment alone is not complaint. Fixed appointments are not schedule negotiation.
- Do not expose reasoning or add fields. Confidence must be between 0 and 1.
"""


def prepare(arguments: argparse.Namespace) -> None:
    records = read_json_lines(arguments.input)
    requested_hard_negatives: set[str] = set()
    for path in arguments.hard_negative_report:
        report = json.loads(path.read_text(encoding="utf-8"))
        for classifier in report.get("classifiers") or []:
            for example in classifier.get("falsePositiveExamples") or []:
                requested_hard_negatives.add(
                    normalized_text(example["text"]).casefold()
                )
    license_safe_texts = {
        normalized_text(record["text"]).casefold() for record in records
    }
    matched_hard_negatives = requested_hard_negatives & license_safe_texts
    queue = stratified_queue(
        records,
        arguments.count,
        arguments.seed,
        matched_hard_negatives,
    )
    queue_records = [
        {
            "id": record["id"],
            "text": record["text"],
            "language": record["language"],
            "sourceDataset": record.get("sourceDataset"),
            "sourceLicense": record.get("sourceLicense"),
            "sourceURL": record.get("sourceURL"),
            "sourceRevision": record.get("sourceRevision"),
            "knownLabels": record.get("knownLabels", []),
            "sourceLabels": {
                label: bool(record.get(label))
                for label in INTENT_LABELS
                if label in set(record.get("knownLabels") or [])
            },
        }
        for record in queue
    ]
    write_json_lines(arguments.queue, queue_records)
    arguments.instructions.parent.mkdir(parents=True, exist_ok=True)
    instructions = labeling_instructions()
    arguments.instructions.write_text(instructions, encoding="utf-8")
    manifest = {
        "schemaVersion": 1,
        "promptVersion": PROMPT_VERSION,
        "promptSHA256": hashlib.sha256(instructions.encode()).hexdigest(),
        "seed": arguments.seed,
        "input": str(arguments.input),
        "queue": str(arguments.queue),
        "recordCount": len(queue_records),
        "requestedHardNegativeCount": len(requested_hard_negatives),
        "licenseSafeMatchedHardNegativeCount": len(matched_hard_negatives),
        "sourceCounts": dict(
            sorted(
                Counter(
                    record.get("sourceDataset") or "unknown"
                    for record in queue_records
                ).items()
            )
        ),
        "languageCounts": dict(
            sorted(Counter(record["language"] for record in queue_records).items())
        ),
    }
    arguments.prepare_report.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        f"CONSENSUS_QUEUE records={len(queue_records)} "
        f"promptSHA256={manifest['promptSHA256']}"
    )


def parse_labeler_argument(value: str) -> tuple[str, Path]:
    name, separator, raw_path = value.partition("=")
    if not separator or not name or not raw_path:
        raise argparse.ArgumentTypeError("Expected LABELER=PATH")
    return name, Path(raw_path)


def validate_labeler_record(record: dict, expected_ids: set[str]) -> dict:
    record_id = record.get("id")
    if record_id not in expected_ids:
        raise ValueError(f"Unexpected labeler record id: {record_id}")
    labels = record.get("labels")
    if not isinstance(labels, list) or any(label not in INTENT_LABELS for label in labels):
        raise ValueError(f"Unsupported labels for {record_id}: {labels}")
    confidence = record.get("confidence")
    if not isinstance(confidence, (int, float)) or not 0 <= confidence <= 1:
        raise ValueError(f"Invalid confidence for {record_id}: {confidence}")
    for flag in SPECIAL_FLAGS:
        if not isinstance(record.get(flag), bool):
            raise ValueError(f"Missing boolean {flag} for {record_id}")
    return {
        "id": record_id,
        "labels": sorted(set(labels)),
        "ambiguous": record["ambiguous"],
        "quotedOrMeta": record["quotedOrMeta"],
        "confidence": round(float(confidence), 4),
    }


def action_label(labels: set[str]) -> str:
    if "task" in labels and "complaint" in labels:
        return "both"
    if "task" in labels:
        return "taskOnly"
    if "complaint" in labels:
        return "complaintOnly"
    if "question" in labels:
        return "questionRequest"
    return "neither"


def coordination_label(labels: set[str]) -> str | None:
    matches = [
        label
        for label in COORDINATION_LABELS
        if label != "neither" and label in labels
    ]
    if len(matches) > 1:
        return None
    return matches[0] if matches else "neither"


def cluster_signature(text: str) -> str:
    normalized = unicodedata.normalize("NFKC", text).casefold()
    normalized = re.sub(r"\d+", "<n>", normalized)
    normalized = re.sub(r"[^\w\u4e00-\u9fff<>]+", " ", normalized)
    tokens = normalized.split()
    # Prefix and suffix retain intent-bearing wording while grouping slot variants.
    skeleton = tokens[:10] + (["|"] + tokens[-6:] if len(tokens) > 16 else [])
    return " ".join(skeleton)


def split_for(record: dict) -> str:
    bucket = stable_hash(cluster_signature(record["text"])) % 100
    if bucket < 70:
        return "silverTrain"
    if bucket < 85:
        return "silverCalibration"
    return "silverAcceptance"


def fleiss_kappa(
    labeler_records: list[dict[str, dict]],
    queue_ids: list[str],
) -> float:
    if len(labeler_records) < 2 or not queue_ids:
        return 0
    category_counts = [0, 0]
    agreement_total = 0.0
    item_count = 0
    rater_count = len(labeler_records)
    for record_id in queue_ids:
        for label in INTENT_LABELS:
            yes_count = sum(
                label in set(labeler[record_id]["labels"])
                for labeler in labeler_records
            )
            no_count = rater_count - yes_count
            category_counts[0] += no_count
            category_counts[1] += yes_count
            agreement_total += (
                no_count * (no_count - 1) + yes_count * (yes_count - 1)
            ) / (rater_count * (rater_count - 1))
            item_count += 1
    observed = agreement_total / item_count
    total_votes = sum(category_counts)
    expected = sum((count / total_votes) ** 2 for count in category_counts)
    if math.isclose(expected, 1):
        return 1
    return round((observed - expected) / (1 - expected), 4)


def merge(arguments: argparse.Namespace) -> None:
    queue = read_json_lines(arguments.queue)
    queue_by_id = {record["id"]: record for record in queue}
    if len(queue_by_id) != len(queue):
        raise ValueError("Consensus queue contains duplicate ids")
    expected_ids = set(queue_by_id)
    if len(arguments.labeler) < 3:
        raise ValueError("Consensus requires at least three independent labelers")

    labelers: list[tuple[str, dict[str, dict]]] = []
    for name, path in arguments.labeler:
        values = [
            validate_labeler_record(record, expected_ids)
            for record in read_json_lines(path)
        ]
        by_id = {record["id"]: record for record in values}
        missing = expected_ids.difference(by_id)
        if missing:
            raise ValueError(f"Labeler {name} is missing {len(missing)} records")
        if len(by_id) != len(values):
            raise ValueError(f"Labeler {name} contains duplicate ids")
        labelers.append((name, by_id))

    accepted: list[dict] = []
    conflicts: list[dict] = []
    for record_id in sorted(expected_ids):
        queue_record = queue_by_id[record_id]
        votes = Counter(
            label
            for _, records in labelers
            for label in records[record_id]["labels"]
        )
        source_labels = {
            label
            for label, value in (queue_record.get("sourceLabels") or {}).items()
            if value
        }
        consensus_labels = {
            label
            for label, count in votes.items()
            if count == len(labelers) or count >= 2 and label in source_labels
        }
        ambiguous_votes = sum(
            records[record_id]["ambiguous"] for _, records in labelers
        )
        quoted_votes = sum(
            records[record_id]["quotedOrMeta"] for _, records in labelers
        )
        coordination = coordination_label(consensus_labels)
        full_agreement = all(
            set(records[record_id]["labels"]) == set(
                labelers[0][1][record_id]["labels"]
            )
            and records[record_id]["ambiguous"]
            == labelers[0][1][record_id]["ambiguous"]
            and records[record_id]["quotedOrMeta"]
            == labelers[0][1][record_id]["quotedOrMeta"]
            for _, records in labelers[1:]
        )
        rejected_reason = None
        if ambiguous_votes >= 2:
            rejected_reason = "ambiguous-majority"
        elif quoted_votes >= 2 and consensus_labels:
            rejected_reason = "quoted-or-meta-intent"
        elif coordination is None:
            rejected_reason = "multiple-coordination-labels"
        elif not consensus_labels and not full_agreement:
            rejected_reason = "no-supported-consensus"

        audit = {
            "id": record_id,
            "labelerVotes": dict(sorted(votes.items())),
            "labelerConfidences": {
                name: records[record_id]["confidence"]
                for name, records in labelers
            },
            "labelerResponseHashes": {
                name: hashlib.sha256(
                    json.dumps(
                        records[record_id],
                        ensure_ascii=False,
                        sort_keys=True,
                        separators=(",", ":"),
                    ).encode()
                ).hexdigest()
                for name, records in labelers
            },
            "sourceLabels": sorted(source_labels),
            "ambiguousVotes": ambiguous_votes,
            "quotedOrMetaVotes": quoted_votes,
            "fullAgreement": full_agreement,
        }
        if rejected_reason:
            conflicts.append(
                {
                    **queue_record,
                    **audit,
                    "rejectedReason": rejected_reason,
                }
            )
            continue

        split = split_for(queue_record)
        labels = set() if quoted_votes >= 2 else consensus_labels
        silver = {
            "id": f"consensus-{record_id}",
            "sourceRecordID": record_id,
            "text": queue_record["text"],
            "language": queue_record["language"],
            "family": "consensus_public",
            "split": split,
            **{label: label in labels for label in INTENT_LABELS},
            "sentiment": "neutral",
            "replyable": "replyableMessage" in labels,
            "actionVerifierLabel": action_label(labels),
            "coordinationVerifierLabel": coordination_label(labels) or "neither",
            "quotedOrMeta": quoted_votes >= 2,
            "consensusAgreement": round(
                max(
                    [votes.get(label, 0) for label in INTENT_LABELS] + [
                        len(labelers) if not labels and full_agreement else 0
                    ]
                )
                / len(labelers),
                4,
            ),
            "promptVersion": PROMPT_VERSION,
            "sourceDataset": queue_record.get("sourceDataset"),
            "sourceLicense": queue_record.get("sourceLicense"),
            "sourceURL": queue_record.get("sourceURL"),
            "sourceRevision": queue_record.get("sourceRevision"),
            **audit,
        }
        accepted.append(silver)

    write_json_lines(arguments.consensus, accepted)
    write_json_lines(arguments.conflicts, conflicts)
    for split, path in (
        ("silverTrain", arguments.train),
        ("silverCalibration", arguments.calibration),
        ("silverAcceptance", arguments.acceptance),
    ):
        write_json_lines(
            path,
            [record for record in accepted if record["split"] == split],
        )

    labeler_maps = [records for _, records in labelers]
    text_split_map: dict[str, set[str]] = defaultdict(set)
    cluster_split_map: dict[str, set[str]] = defaultdict(set)
    for record in accepted:
        text_split_map[normalized_text(record["text"]).casefold()].add(record["split"])
        cluster_split_map[cluster_signature(record["text"])].add(record["split"])
    exact_overlap_count = sum(len(splits) > 1 for splits in text_split_map.values())
    cluster_overlap_count = sum(
        len(splits) > 1 for splits in cluster_split_map.values()
    )
    if exact_overlap_count or cluster_overlap_count:
        raise ValueError("Silver split overlap validation failed")
    report = {
        "schemaVersion": 1,
        "promptVersion": PROMPT_VERSION,
        "promptSHA256": hashlib.sha256(labeling_instructions().encode()).hexdigest(),
        "queueCount": len(queue),
        "acceptedCount": len(accepted),
        "conflictCount": len(conflicts),
        "conflictRate": round(len(conflicts) / max(len(queue), 1), 4),
        "duplicateTextRate": round(
            (len(accepted) - len(text_split_map)) / max(len(accepted), 1),
            4,
        ),
        "overlapChecks": {
            "exactTextAcrossSplits": exact_overlap_count,
            "nearDuplicateClusterAcrossSplits": cluster_overlap_count,
        },
        "fullAgreementCount": sum(record["fullAgreement"] for record in accepted)
        + sum(record["fullAgreement"] for record in conflicts),
        "fleissKappa": fleiss_kappa(
            labeler_maps,
            sorted(expected_ids),
        ),
        "labelers": [name for name, _ in labelers],
        "splitCounts": dict(sorted(Counter(record["split"] for record in accepted).items())),
        "actionLabelCounts": dict(
            sorted(Counter(record["actionVerifierLabel"] for record in accepted).items())
        ),
        "coordinationLabelCounts": dict(
            sorted(
                Counter(
                    record["coordinationVerifierLabel"] for record in accepted
                ).items()
            )
        ),
        "intentPositiveCounts": {
            label: sum(bool(record[label]) for record in accepted)
            for label in INTENT_LABELS
        },
        "languageCounts": dict(
            sorted(Counter(record["language"] for record in accepted).items())
        ),
        "sourceCounts": dict(
            sorted(
                Counter(
                    record.get("sourceDataset") or "unknown"
                    for record in accepted
                ).items()
            )
        ),
    }
    arguments.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        f"CONSENSUS_DONE accepted={len(accepted)} conflicts={len(conflicts)} "
        f"kappa={report['fleissKappa']}"
    )


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    subparsers = root.add_subparsers(dest="command", required=True)

    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    prepare_parser.add_argument(
        "--queue",
        type=Path,
        default=DEFAULT_DIRECTORY / "labeling-queue.jsonl",
    )
    prepare_parser.add_argument(
        "--instructions",
        type=Path,
        default=DEFAULT_DIRECTORY / "labeling-instructions.md",
    )
    prepare_parser.add_argument(
        "--prepare-report",
        type=Path,
        default=DEFAULT_DIRECTORY / "labeling-queue-report.json",
    )
    prepare_parser.add_argument("--count", type=int, default=360)
    prepare_parser.add_argument("--seed", type=int, default=SEED)
    prepare_parser.add_argument(
        "--hard-negative-report",
        action="append",
        type=Path,
        default=[],
    )
    prepare_parser.set_defaults(handler=prepare)

    merge_parser = subparsers.add_parser("merge")
    merge_parser.add_argument(
        "--queue",
        type=Path,
        default=DEFAULT_DIRECTORY / "labeling-queue.jsonl",
    )
    merge_parser.add_argument(
        "--labeler",
        action="append",
        type=parse_labeler_argument,
        required=True,
    )
    merge_parser.add_argument(
        "--consensus",
        type=Path,
        default=DEFAULT_DIRECTORY / "consensus-silver.jsonl",
    )
    merge_parser.add_argument(
        "--conflicts",
        type=Path,
        default=DEFAULT_DIRECTORY / "consensus-conflicts.jsonl",
    )
    merge_parser.add_argument(
        "--train",
        type=Path,
        default=DEFAULT_DIRECTORY / "silver-train.jsonl",
    )
    merge_parser.add_argument(
        "--calibration",
        type=Path,
        default=DEFAULT_DIRECTORY / "silver-calibration.jsonl",
    )
    merge_parser.add_argument(
        "--acceptance",
        type=Path,
        default=DEFAULT_DIRECTORY / "silver-acceptance.jsonl",
    )
    merge_parser.add_argument(
        "--report",
        type=Path,
        default=DEFAULT_DIRECTORY / "consensus-report.json",
    )
    merge_parser.set_defaults(handler=merge)
    return root


def main() -> None:
    arguments = parser().parse_args()
    arguments.handler(arguments)


if __name__ == "__main__":
    main()
