#!/usr/bin/env python3
"""Build a provenance-preserving clipboard-semantics corpus registry."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

INTENT_FIELDS = (
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
SPLIT_USE = {
    "train": "train",
    "silverTrain": "train",
    "validation": "calibration-only",
    "silverCalibration": "calibration-only",
    "test": "evaluation-only",
    "golden": "evaluation-only",
    "silverAcceptance": "evaluation-only",
    "calibration": "calibration-only",
}
USE_PRIORITY = {
    "train": 0,
    "calibration-only": 1,
    "evaluation-only": 2,
    "research-only": 3,
}
TRAIN_LICENSES = {
    "Apache-2.0",
    "CC0-1.0 source / Apache-2.0 mirror",
    "CC-BY-3.0",
    "CC-BY-4.0",
    "CDLA-Permissive-1.0",
    "MIT",
    "OSGKeyboard project license",
    "CC0-1.0",
}


@dataclass(frozen=True)
class Source:
    identifier: str
    path: Path
    license: str
    default_use: str
    source_type: str
    all_intents_known: bool
    known_intent_labels: frozenset[str] | None
    sentiment_known: bool
    required: bool
    sensitive: bool
    weight: float


def normalize_text(value: str) -> str:
    return " ".join(
        unicodedata.normalize("NFKC", value)
        .replace("\u0000", " ")
        .casefold()
        .split()
    ).strip()


def text_hash(value: str) -> str:
    return hashlib.sha256(normalize_text(value).encode()).hexdigest()


def cluster_signature(text: str, language: str, family: str) -> str:
    normalized = normalize_text(text)
    normalized = re.sub(r"https?://\S+|www\.\S+", "<url>", normalized)
    normalized = re.sub(r"[\w.+-]+@[\w.-]+\.[a-z]{2,}", "<email>", normalized)
    normalized = re.sub(r"\d+(?:[./:-]\d+)*", "<n>", normalized)
    normalized = re.sub(r"[^\w\u3400-\u9fff<>]+", " ", normalized)
    tokens = normalized.split()
    skeleton = tokens[:12] + (["|"] + tokens[-8:] if len(tokens) > 20 else [])
    value = f"{language}|{family}|{' '.join(skeleton)}"
    return hashlib.sha256(value.encode()).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def iter_records(path: Path) -> Iterator[dict]:
    with path.open(encoding="utf-8") as handle:
        first = ""
        while not first:
            first = handle.readline()
            if not first:
                return
            first = first.strip()
        if first.startswith("["):
            payload = json.loads(first + handle.read())
            if not isinstance(payload, list):
                raise TypeError(f"Expected JSON array in {path}")
            yield from payload
            return
        yield json.loads(first)
        for line in handle:
            if line.strip():
                yield json.loads(line)


def resolve_path(raw_path: str, repository_root: Path) -> Path:
    expanded = raw_path.replace("${REPO_ROOT}", str(repository_root))
    path = Path(expanded).expanduser()
    return path if path.is_absolute() else repository_root / path


def load_sources(manifest_path: Path, repository_root: Path) -> tuple[list[Source], dict]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    sources = []
    for raw in manifest["sources"]:
        if not raw.get("enabled", True):
            continue
        weight = float(raw.get("weight", 1.0))
        if not 0 < weight <= 1:
            raise ValueError(f"Invalid source weight for {raw['id']}: {weight}")
        known_labels = raw.get("knownIntentLabels")
        if known_labels is not None:
            unknown = set(known_labels) - set(INTENT_FIELDS)
            if unknown:
                raise ValueError(
                    f"Unknown intent labels for {raw['id']}: {sorted(unknown)}"
                )
        sources.append(
            Source(
                identifier=raw["id"],
                path=resolve_path(raw["path"], repository_root),
                license=raw["license"],
                default_use=raw["defaultUse"],
                source_type=raw["sourceType"],
                all_intents_known=raw.get("allIntentLabelsKnown", False),
                known_intent_labels=(
                    frozenset(known_labels) if known_labels is not None else None
                ),
                sentiment_known=raw.get("sentimentKnown", False),
                required=raw.get("required", False),
                sensitive=raw.get("sensitive", False),
                weight=weight,
            )
        )
    return sources, manifest


def source_use(source: Source, record: dict) -> str:
    if source.default_use != "by-split":
        return source.default_use
    return SPLIT_USE.get(
        record.get("split") or record.get("sourceSplit") or "",
        "evaluation-only",
    )


def known_intents(source: Source, record: dict) -> set[str]:
    if source.known_intent_labels is not None:
        values = set(source.known_intent_labels)
        record_values = set(record.get("knownLabels") or [])
        if "replyable" in record_values:
            record_values.add("replyableMessage")
        return values | (record_values & set(INTENT_FIELDS))
    if source.all_intents_known:
        return set(INTENT_FIELDS)
    values = set(record.get("knownLabels") or [])
    if "replyable" in values:
        values.add("replyableMessage")
    return values & set(INTENT_FIELDS)


def record_value(record: dict, label: str) -> bool:
    source_field = "replyable" if label == "replyableMessage" else label
    return bool(record.get(source_field))


def effective_license(source: Source, record: dict) -> str:
    return record.get("sourceLicense") or source.license


def effective_weight(source: Source, record: dict) -> float:
    record_weight = float(record.get("sampleWeight", 1.0))
    if not 0 < record_weight <= 1:
        raise ValueError(
            f"Invalid record sampleWeight for {record.get('id')}: {record_weight}"
        )
    return round(source.weight * record_weight, 6)


def add_record(
    registry: dict[str, dict],
    source: Source,
    record: dict,
    source_path: Path,
) -> str:
    text = str(record.get("text") or "").strip()
    language = str(record.get("language") or "").strip()
    if not text or language not in {"en", "zh-Hans"}:
        return "invalid"
    digest = text_hash(text)
    family = str(record.get("family") or "unknown")
    use = source_use(source, record)
    license_name = effective_license(source, record)
    if use == "train" and license_name not in TRAIN_LICENSES:
        return "unsafe-license"
    known_labels = set(record.get("knownLabels") or [])
    if "domain" in known_labels and record.get("domain") not in DOMAINS:
        return "invalid-domain"
    sample_weight = effective_weight(source, record)
    canonical = registry.setdefault(
        digest,
        {
            "id": f"corpus-{digest[:20]}",
            "text": text,
            "normalizedTextSHA256": digest,
            "language": language,
            "clusterSignature": cluster_signature(text, language, family),
            "families": set(),
            "uses": set(),
            "provenance": [],
            "intentEvidence": defaultdict(list),
            "sentimentEvidence": [],
            "domainEvidence": [],
        },
    )
    canonical["families"].add(family)
    canonical["uses"].add(use)
    known = known_intents(source, record)
    for label in known:
        canonical["intentEvidence"][label].append(
            {
                "source": source.identifier,
                "value": record_value(record, label),
            }
        )
    sentiment_is_known = source.sentiment_known or "sentiment" in set(
        record.get("knownLabels") or []
    )
    if sentiment_is_known and record.get("sentiment") in {
        "negative",
        "neutral",
        "positive",
    }:
        canonical["sentimentEvidence"].append(
            {
                "source": source.identifier,
                "value": record["sentiment"],
            }
        )
    if "domain" in known_labels:
        domain = record.get("domain")
        canonical["domainEvidence"].append(
            {
                "source": source.identifier,
                "value": domain,
            }
        )
    canonical["provenance"].append(
        {
            "source": source.identifier,
            "sourcePath": str(source_path),
            "sourceRecordID": record.get("id"),
            "sourceDataset": record.get("sourceDataset") or source.identifier,
            "sourceRevision": record.get("sourceRevision"),
            "sourceURL": record.get("sourceURL"),
            "split": record.get("split") or record.get("sourceSplit"),
            "allowedUse": use,
            "license": license_name,
            "sourceType": source.source_type,
            "sensitive": source.sensitive,
            "sampleWeight": sample_weight,
        }
    )
    return "accepted"


def resolve_state(evidence: list[dict]) -> tuple[str, bool]:
    values = {item["value"] for item in evidence}
    if len(values) != 1:
        return "unknown", len(values) > 1
    return ("true" if values.pop() is True else "false"), False


def finalize_record(raw: dict) -> dict:
    states = {}
    conflicts = []
    evidence = {}
    for label in INTENT_FIELDS:
        values = raw["intentEvidence"].get(label, [])
        state, conflict = resolve_state(values)
        states[label] = state
        if values:
            evidence[label] = values
        if conflict:
            conflicts.append(label)
    sentiment_values = {
        item["value"] for item in raw["sentimentEvidence"]
    }
    sentiment = (
        next(iter(sentiment_values)) if len(sentiment_values) == 1 else "unknown"
    )
    if len(sentiment_values) > 1:
        conflicts.append("sentiment")
    domain_values = {item["value"] for item in raw["domainEvidence"]}
    domain = next(iter(domain_values)) if len(domain_values) == 1 else "unknown"
    if len(domain_values) > 1:
        conflicts.append("domain")
    allowed_use = max(raw["uses"], key=USE_PRIORITY.__getitem__)
    training_weights = [
        value["sampleWeight"]
        for value in raw["provenance"]
        if value["allowedUse"] == "train"
    ]
    training_datasets = sorted(
        {
            value["sourceDataset"]
            for value in raw["provenance"]
            if value["allowedUse"] == "train"
        }
    )
    known_labels = [
        label for label, state in states.items() if state != "unknown"
    ]
    if sentiment != "unknown":
        known_labels.append("sentiment")
    if domain != "unknown":
        known_labels.append("domain")
    flattened_labels = {
        ("replyable" if label == "replyableMessage" else label): state == "true"
        for label, state in states.items()
    }
    return {
        "id": raw["id"],
        "text": raw["text"],
        "normalizedTextSHA256": raw["normalizedTextSHA256"],
        "language": raw["language"],
        "sourceDataset": training_datasets[0] if training_datasets else None,
        "clusterSignature": raw["clusterSignature"],
        "families": sorted(raw["families"]),
        "family": sorted(raw["families"])[0],
        "observedUses": sorted(raw["uses"], key=USE_PRIORITY.__getitem__),
        "allowedUse": allowed_use,
        "split": (
            "train"
            if allowed_use == "train"
            else "validation"
            if allowed_use == "calibration-only"
            else "test"
        ),
        **flattened_labels,
        "labels": states,
        "sentiment": sentiment if sentiment != "unknown" else "neutral",
        "domain": domain if domain != "unknown" else None,
        "knownLabels": sorted(known_labels),
        "sampleWeight": max(training_weights, default=1.0),
        "labelConflicts": sorted(conflicts),
        "sourceEvidence": evidence,
        "sentimentEvidence": raw["sentimentEvidence"],
        "domainEvidence": raw["domainEvidence"],
        "provenance": raw["provenance"],
    }


def write_json_lines(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(
                json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n"
            )


def select_pilot(records: list[dict], count: int) -> list[dict]:
    grouped: dict[tuple[str, str, str], list[dict]] = defaultdict(list)
    for record in records:
        source = sorted(
            {
                value["sourceDataset"]
                for value in record["provenance"]
                if value["allowedUse"] == "train"
            }
        )[0]
        family = record["families"][0]
        grouped[(record["language"], source, family)].append(record)
    for values in grouped.values():
        values.sort(
            key=lambda item: (
                not item["labelConflicts"],
                item["clusterSignature"],
                item["id"],
            )
        )
    keys = sorted(grouped)
    selected = []
    seen_clusters = set()
    offsets = defaultdict(int)
    while len(selected) < count:
        added = False
        for key in keys:
            values = grouped[key]
            while offsets[key] < len(values):
                candidate = values[offsets[key]]
                offsets[key] += 1
                if candidate["clusterSignature"] in seen_clusters:
                    continue
                selected.append(
                    {
                        "id": candidate["id"],
                        "text": candidate["text"],
                        "language": candidate["language"],
                    }
                )
                seen_clusters.add(candidate["clusterSignature"])
                added = True
                break
            if len(selected) >= count:
                break
        if not added:
            break
    return sorted(selected, key=lambda item: item["id"])


def build(arguments: argparse.Namespace) -> dict:
    repository_root = arguments.repository_root.resolve()
    sources, manifest = load_sources(arguments.source_manifest, repository_root)
    raw_registry: dict[str, dict] = {}
    source_reports = []
    missing_sources = []
    excluded_counts = Counter()
    for source in sources:
        if not source.path.exists():
            if source.required:
                raise FileNotFoundError(f"Required corpus is missing: {source.path}")
            missing_sources.append(source.identifier)
            continue
        statuses = Counter()
        for record in iter_records(source.path):
            statuses[add_record(raw_registry, source, record, source.path)] += 1
        source_reports.append(
            {
                "id": source.identifier,
                "path": str(source.path),
                "sha256": sha256_file(source.path),
                "records": sum(statuses.values()),
                "statuses": dict(sorted(statuses.items())),
            }
        )
        excluded_counts.update(
            {
                key: value
                for key, value in statuses.items()
                if key != "accepted"
            }
        )
    records = sorted(
        (finalize_record(value) for value in raw_registry.values()),
        key=lambda item: item["id"],
    )
    train_candidates = [
        record
        for record in records
        if record["allowedUse"] == "train"
        and not record["labelConflicts"]
        and (
            any(value != "unknown" for value in record["labels"].values())
            or record["sentiment"] != "unknown"
            or record["domain"] != "unknown"
        )
    ]
    conflicts = [
        {
            "id": record["id"],
            "text": record["text"],
            "language": record["language"],
            "conflicts": record["labelConflicts"],
            "sourceEvidence": record["sourceEvidence"],
            "sentimentEvidence": record["sentimentEvidence"],
            "domainEvidence": record["domainEvidence"],
            "resolution": None,
            "reviewer": None,
        }
        for record in records
        if record["labelConflicts"]
    ]
    pilot_was_preserved = (
        getattr(arguments, "preserve_pilot", False) and arguments.pilot.exists()
    )
    if pilot_was_preserved:
        pilot = list(iter_records(arguments.pilot))
        if len(pilot) != arguments.pilot_count:
            raise ValueError(
                f"Preserved pilot has {len(pilot)} records; "
                f"expected {arguments.pilot_count}"
            )
    else:
        pilot = select_pilot(train_candidates, arguments.pilot_count)
    write_json_lines(arguments.registry, records)
    write_json_lines(arguments.train_candidates, train_candidates)
    if not pilot_was_preserved:
        write_json_lines(arguments.pilot, pilot)
    write_json_lines(arguments.human_review, conflicts)
    usage_counts = Counter(record["allowedUse"] for record in records)
    language_counts = Counter(record["language"] for record in records)
    train_barred_by_evaluation = sum(
        "train" in record["observedUses"]
        and "evaluation-only" in record["observedUses"]
        for record in records
    )
    train_barred_by_calibration = sum(
        "train" in record["observedUses"]
        and "calibration-only" in record["observedUses"]
        for record in records
    )
    report = {
        "schemaVersion": 1,
        "sourceManifest": str(arguments.source_manifest),
        "sourceManifestSHA256": sha256_file(arguments.source_manifest),
        "sourceReports": source_reports,
        "excludedSources": manifest.get("excludedSources", []),
        "missingOptionalSources": missing_sources,
        "inputRecordCount": sum(
            item["records"] for item in source_reports
        ),
        "canonicalRecordCount": len(records),
        "exactDuplicateCount": sum(
            max(len(record["provenance"]) - 1, 0) for record in records
        ),
        "trainCandidateCount": len(train_candidates),
        "trainBarredByEvaluationCount": train_barred_by_evaluation,
        "trainBarredByCalibrationCount": train_barred_by_calibration,
        "labelConflictCount": len(conflicts),
        "pilotCount": len(pilot),
        "pilotPreserved": pilot_was_preserved,
        "pilotSHA256": sha256_file(arguments.pilot),
        "usageCounts": dict(sorted(usage_counts.items())),
        "languageCounts": dict(sorted(language_counts.items())),
        "excludedRecordCounts": dict(sorted(excluded_counts.items())),
        "outputs": {
            "registry": str(arguments.registry),
            "trainCandidates": str(arguments.train_candidates),
            "pilot": str(arguments.pilot),
            "humanReview": str(arguments.human_review),
        },
    }
    arguments.report.parent.mkdir(parents=True, exist_ok=True)
    arguments.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return report


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    root.add_argument("--repository-root", type=Path, default=Path.cwd())
    root.add_argument(
        "--source-manifest",
        type=Path,
        default=Path(
            "ModelTraining/ClipboardSemantics/corpus-registry-sources.json"
        ),
    )
    root.add_argument(
        "--registry",
        type=Path,
        default=Path(
            "ModelTraining/ClipboardSemantics/CorpusRegistry/registry.jsonl"
        ),
    )
    root.add_argument(
        "--train-candidates",
        type=Path,
        default=Path(
            "ModelTraining/ClipboardSemantics/CorpusRegistry/"
            "train-candidates.jsonl"
        ),
    )
    root.add_argument(
        "--pilot",
        type=Path,
        default=Path(
            "ModelTraining/ClipboardSemantics/CorpusRegistry/"
            "labeling-pilot.jsonl"
        ),
    )
    root.add_argument(
        "--human-review",
        type=Path,
        default=Path(
            "ModelTraining/ClipboardSemantics/CorpusRegistry/"
            "source-conflicts-human-review.jsonl"
        ),
    )
    root.add_argument(
        "--report",
        type=Path,
        default=Path(
            "ModelTraining/ClipboardSemantics/CorpusRegistry/registry-report.json"
        ),
    )
    root.add_argument("--pilot-count", type=int, default=1000)
    root.add_argument("--preserve-pilot", action="store_true")
    return root


def main() -> None:
    arguments = parser().parse_args()
    report = build(arguments)
    print(
        "CORPUS_REGISTRY_DONE "
        f"canonical={report['canonicalRecordCount']} "
        f"train={report['trainCandidateCount']} "
        f"pilot={report['pilotCount']} "
        f"conflicts={report['labelConflictCount']}"
    )


if __name__ == "__main__":
    main()
