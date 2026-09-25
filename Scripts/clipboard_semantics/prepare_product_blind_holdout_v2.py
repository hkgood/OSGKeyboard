#!/usr/bin/env python3
"""Prepare the v2 product blind holdout with stratified, IPW-correctable sampling.

The v1 blind holdout has 120 records and as few as two positives per intent, so
it cannot separate a real quality regression from sampling noise. This script
builds a larger queue from real, clipboard-shaped licensed text.

Every eligible pool record is assigned to exactly one stratum by a rarest-first
intent priority, so the design is a clean stratified sample: each emitted record
carries `inclusionProbability` = selected/available for its stratum, and
prevalence-corrected metrics follow from Horvitz-Thompson weighting. Rare
intents are oversampled for statistical power without biasing reported rates.

Weak source labels drive stratification only. They are written to the sealed
provenance file and never to the blind queue.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path


SEED = 20260902
MODEL_TRAINING = Path("ModelTraining/ClipboardSemantics")
OUTPUT_DIRECTORY = MODEL_TRAINING / "ProductBlindHoldoutV2"
DEFAULT_SOURCES = (
    MODEL_TRAINING / "comprehensive-online-holdout-corpus.jsonl",
    MODEL_TRAINING / "online-real-holdout-corpus.jsonl",
)

# Intents in rarest-first order. A record joins the first stratum it matches,
# which is what gives the scarce intents their own guaranteed sampling cells.
INTENT_PRIORITY = (
    "blessing",
    "confirmationDecision",
    "scheduleNegotiation",
    "invitation",
    "followUpReminder",
    "complaint",
    "task",
    "question",
)
REPLYABLE_STRATUM = "replyableOnly"
NEGATIVE_STRATUM = "noWeakIntent"
LANGUAGES = ("en", "zh-Hans")

# Families that are real text but not clipboard-shaped. CPED is television
# dialogue and GoEmotions is short Reddit reaction text; both are dominated by
# sub-15-character conversational turns that no user copies to a clipboard.
EXCLUDED_FAMILY_PREFIXES = ("online_cped_", "online_goemotions_")

PII_PATTERN = re.compile(
    r"(?:[\w.+-]+@[\w.-]+\.\w+)|(?:\+?\d[\d ()-]{8,}\d)|"
    r"(?:\b\d{3}-\d{2}-\d{4}\b)",
    re.IGNORECASE,
)
INTENT_FIELDS = (*INTENT_PRIORITY, "replyable")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", action="append", type=Path, default=[])
    parser.add_argument("--output-directory", type=Path, default=OUTPUT_DIRECTORY)
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument(
        "--minimum-characters",
        type=int,
        default=25,
        help="Clipboard-shape floor. Shorter real text is conversational turns.",
    )
    parser.add_argument("--maximum-characters", type=int, default=1_500)
    parser.add_argument(
        "--rare-stratum-target",
        type=int,
        default=50,
        help="Reviewed records to draw from each scarce intent stratum.",
    )
    parser.add_argument(
        "--common-stratum-target",
        type=int,
        default=120,
        help="Reviewed records to draw from each abundant stratum.",
    )
    parser.add_argument(
        "--common-strata",
        default="question,replyableOnly,noWeakIntent",
        help="Comma-separated strata that use --common-stratum-target.",
    )
    parser.add_argument(
        "--training-corpus",
        action="append",
        default=[],
        type=Path,
        help="Additional JSONL whose text must not appear in the queue.",
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
        for record in load_records(path):
            values.add(fingerprint(record["text"]))
    return values


def is_real_source(record: dict) -> bool:
    """Reject template-generated families, which are not real user text."""

    family = record.get("family") or ""
    return family.startswith("online_") and not family.startswith(
        EXCLUDED_FAMILY_PREFIXES
    )


def stratum_of(record: dict) -> str:
    for intent in INTENT_PRIORITY:
        if record.get(intent) is True:
            return intent
    if record.get("replyable") is True:
        return REPLYABLE_STRATUM
    return NEGATIVE_STRATUM


def stable_priority(record_id: str, seed: int, salt: str) -> bytes:
    return hashlib.sha256(f"{seed}|{salt}|{record_id}".encode()).digest()


def eligible_pool(
    sources: list[Path],
    *,
    minimum_characters: int,
    maximum_characters: int,
    protected: set[str],
) -> tuple[list[dict], Counter]:
    rejected: Counter = Counter()
    seen: set[str] = set()
    pool: list[dict] = []
    for path in sources:
        for record in load_records(path):
            if not is_real_source(record):
                rejected["notRealClipboardShapedSource"] += 1
                continue
            if record.get("language") not in LANGUAGES:
                rejected["unsupportedLanguage"] += 1
                continue
            text = normalized_text(record.get("text") or "")
            if not minimum_characters <= len(text) <= maximum_characters:
                rejected["lengthOutsideClipboardShape"] += 1
                continue
            key = fingerprint(text)
            if key in protected:
                rejected["overlapsProtectedCorpus"] += 1
                continue
            if key in seen:
                rejected["duplicateText"] += 1
                continue
            if PII_PATTERN.search(text):
                rejected["detectedPII"] += 1
                continue
            seen.add(key)
            candidate = dict(record)
            candidate["_text"] = text
            candidate["_stratum"] = stratum_of(record)
            pool.append(candidate)
    return pool, rejected


def select(
    pool: list[dict],
    *,
    seed: int,
    rare_target: int,
    common_target: int,
    common_strata: set[str],
) -> tuple[list[dict], list[dict]]:
    """Draw each stratum independently and report unfilled cells."""

    by_cell: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for record in pool:
        by_cell[(record["language"], record["_stratum"])].append(record)

    all_strata = (*INTENT_PRIORITY, REPLYABLE_STRATUM, NEGATIVE_STRATUM)
    selected: list[dict] = []
    gaps: list[dict] = []
    for language in LANGUAGES:
        for stratum in all_strata:
            target = common_target if stratum in common_strata else rare_target
            available = by_cell.get((language, stratum), [])
            drawn = sorted(
                available,
                key=lambda value: stable_priority(value["id"], seed, stratum),
            )[:target]
            probability = len(drawn) / len(available) if available else 0.0
            for record in drawn:
                record["_inclusionProbability"] = probability
                record["_stratumAvailable"] = len(available)
                record["_stratumSelected"] = len(drawn)
                selected.append(record)
            if len(drawn) < target:
                gaps.append(
                    {
                        "language": language,
                        "stratum": stratum,
                        "target": target,
                        "available": len(available),
                        "selected": len(drawn),
                        "mustAuthor": target - len(drawn),
                    }
                )
    return selected, gaps


def write_jsonl(path: Path, records: list[dict]) -> None:
    path.write_text(
        "\n".join(
            json.dumps(record, ensure_ascii=False, sort_keys=True)
            for record in records
        )
        + "\n",
        encoding="utf-8",
    )


def main() -> None:
    arguments = parse_arguments()
    sources = arguments.source or list(DEFAULT_SOURCES)
    common_strata = {
        value.strip() for value in arguments.common_strata.split(",") if value.strip()
    }

    protected = protected_fingerprints(arguments.training_corpus)
    pool, rejected = eligible_pool(
        sources,
        minimum_characters=arguments.minimum_characters,
        maximum_characters=arguments.maximum_characters,
        protected=protected,
    )
    selected, gaps = select(
        pool,
        seed=arguments.seed,
        rare_target=arguments.rare_stratum_target,
        common_target=arguments.common_stratum_target,
        common_strata=common_strata,
    )

    output_directory = arguments.output_directory
    output_directory.mkdir(parents=True, exist_ok=True)

    queue: list[dict] = []
    provenance: list[dict] = []
    template: list[dict] = []
    for index, source in enumerate(
        sorted(
            selected,
            key=lambda value: stable_priority(value["id"], arguments.seed, "queue"),
        ),
        start=1,
    ):
        review_id = f"product-blind-v2-{index:05d}"
        queue.append(
            {
                "id": review_id,
                "text": source["_text"],
                "language": source["language"],
                "annotationStatus": "unreviewed",
            }
        )
        provenance.append(
            {
                "id": review_id,
                "language": source["language"],
                "sourceRecordID": source["id"],
                "sourceDataset": source.get("sourceDataset"),
                "sourceLicense": source.get("sourceLicense"),
                "sourceURL": source.get("sourceURL"),
                "family": source.get("family"),
                "samplingStratum": source["_stratum"],
                "inclusionProbability": source["_inclusionProbability"],
                "stratumAvailable": source["_stratumAvailable"],
                "stratumSelected": source["_stratumSelected"],
                "weakSourceLabels": {
                    field: source.get(field) for field in INTENT_FIELDS
                },
            }
        )
        template.append(
            {
                "id": review_id,
                **{field: None for field in INTENT_FIELDS},
                "sentiment": None,
                "ambiguous": None,
                "confidence": None,
                "evidence": "",
                "notes": "",
            }
        )

    queue_path = output_directory / "review-queue.jsonl"
    provenance_path = output_directory / "sealed-provenance.jsonl"
    write_jsonl(queue_path, queue)
    write_jsonl(provenance_path, provenance)
    write_jsonl(output_directory / "annotator-a.jsonl", template)
    write_jsonl(output_directory / "annotator-b.jsonl", template)

    cell_counts: Counter = Counter(
        f"{value['language']}:{value['samplingStratum']}" for value in provenance
    )
    manifest = {
        "schemaVersion": 1,
        "seed": arguments.seed,
        "status": "awaiting-double-human-annotation",
        "humanReviewComplete": False,
        "policy": (
            "Evaluation-only stratified queue drawn from real licensed text. "
            "Weak source labels are stratification input only and are never "
            "gold. Never merge these records into training."
        ),
        "design": (
            "Single-stage stratified sample. Each record belongs to exactly one "
            "(language, stratum) cell; divide by inclusionProbability for "
            "prevalence-corrected Horvitz-Thompson metrics."
        ),
        "sources": [str(path) for path in sources],
        "clipboardShapeFilter": {
            "excludedFamilyPrefixes": list(EXCLUDED_FAMILY_PREFIXES),
            "minimumCharacters": arguments.minimum_characters,
            "maximumCharacters": arguments.maximum_characters,
        },
        "poolRecords": len(pool),
        "rejected": dict(rejected),
        "records": len(queue),
        "languages": dict(Counter(value["language"] for value in queue)),
        "cells": dict(sorted(cell_counts.items())),
        "unfilledCells": gaps,
        "authoringRequired": sum(gap["mustAuthor"] for gap in gaps),
        "validation": {
            "duplicateNormalizedTexts": len(queue)
            - len({fingerprint(value["text"]) for value in queue}),
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
