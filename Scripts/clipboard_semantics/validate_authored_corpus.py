#!/usr/bin/env python3
"""Validate LLM-authored clipboard corpus batches before they enter any split.

Authored records exist because four socially scarce intents (blessing,
invitation, confirmationDecision, scheduleNegotiation) have no commercially
licensed real-text source. Their whole value is that they are not
template-generated, so this script measures template-ness directly instead of
trusting the author.

Checks:
  * schema, label states, and duplicate ids/text
  * PII shapes and frozen-holdout overlap
  * distinct-n diversity and the most repeated 4-gram
  * prefix concentration, which is how slot-filled templates leak a fingerprint
  * per-family label balance, so a family is never a pure label proxy
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path


MODEL_TRAINING = Path("ModelTraining/ClipboardSemantics")
INTENT_FIELDS = (
    "task",
    "question",
    "invitation",
    "complaint",
    "scheduleNegotiation",
    "confirmationDecision",
    "followUpReminder",
    "blessing",
    "replyable",
)
SENTIMENTS = {"positive", "neutral", "negative"}
REQUIRED_FIELDS = ("id", "text", "language", "family", "sentiment", *INTENT_FIELDS)
LANGUAGES = {"en", "zh-Hans"}
PII_PATTERN = re.compile(
    r"(?:[\w.+-]+@[\w.-]+\.\w+)|(?:\+?\d[\d ()-]{8,}\d)|"
    r"(?:\b\d{3}-\d{2}-\d{4}\b)",
    re.IGNORECASE,
)

# Diversity floors. Template corpora sit far below these because slot filling
# reuses one skeleton per family.
MINIMUM_DISTINCT_4GRAM_RATIO = 0.80
MAXIMUM_TOP_4GRAM_SHARE = 0.06
MAXIMUM_PREFIX_SHARE = 0.10


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("batches", nargs="+", type=Path)
    parser.add_argument(
        "--holdout",
        action="append",
        type=Path,
        default=[],
        help="Frozen holdout JSONL whose text must not be reused.",
    )
    parser.add_argument("--report", type=Path)
    parser.add_argument(
        "--compare-corpus",
        type=Path,
        default=MODEL_TRAINING / "clipboard_semantic_corpus.jsonl",
        help="Existing template corpus, scored with the same diversity metrics.",
    )
    return parser.parse_args()


def normalized_text(value: str) -> str:
    value = unicodedata.normalize("NFKC", value)
    return " ".join(value.split()).strip()


def fingerprint(value: str) -> str:
    return normalized_text(value).casefold()


def load_records(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def character_ngrams(value: str, size: int) -> list[str]:
    text = normalized_text(value)
    return [text[index : index + size] for index in range(len(text) - size + 1)]


def diversity_metrics(texts: list[str]) -> dict:
    """Distinct-n and concentration statistics over character 4-grams."""

    grams: Counter = Counter()
    for text in texts:
        grams.update(character_ngrams(text, 4))
    total = sum(grams.values())
    if not total:
        return {"distinct4GramRatio": 0.0, "topGramShare": 1.0, "topGram": ""}
    top_gram, top_count = grams.most_common(1)[0]
    prefixes = Counter(normalized_text(text)[:6] for text in texts)
    top_prefix, prefix_count = prefixes.most_common(1)[0]
    return {
        "distinct4GramRatio": round(len(grams) / total, 4),
        "topGramShare": round(top_count / total, 4),
        "topGram": top_gram,
        "topPrefix": top_prefix,
        "topPrefixShare": round(prefix_count / len(texts), 4),
        "totalGrams": total,
        "distinctGrams": len(grams),
    }


def validate(records: list[dict], protected: set[str]) -> list[str]:
    errors: list[str] = []
    seen_ids: set[str] = set()
    seen_text: set[str] = set()
    for record in records:
        identifier = record.get("id", "<missing>")
        for field in REQUIRED_FIELDS:
            if field not in record:
                errors.append(f"{identifier}: missing field {field}")
        if identifier in seen_ids:
            errors.append(f"{identifier}: duplicate id")
        seen_ids.add(identifier)

        text = normalized_text(record.get("text") or "")
        if not text:
            errors.append(f"{identifier}: empty text")
            continue
        key = fingerprint(text)
        if key in seen_text:
            errors.append(f"{identifier}: duplicate text")
        seen_text.add(key)
        if key in protected:
            errors.append(f"{identifier}: text overlaps a frozen holdout")
        if PII_PATTERN.search(text):
            errors.append(f"{identifier}: detected PII shape")
        if record.get("language") not in LANGUAGES:
            errors.append(f"{identifier}: unsupported language {record.get('language')}")
        if record.get("sentiment") not in SENTIMENTS:
            errors.append(f"{identifier}: bad sentiment {record.get('sentiment')}")
        for field in INTENT_FIELDS:
            if not isinstance(record.get(field), bool):
                errors.append(f"{identifier}: {field} must be a boolean")
    return errors


def family_balance(records: list[dict]) -> dict:
    by_family: dict[str, list[dict]] = defaultdict(list)
    for record in records:
        by_family[record["family"]].append(record)
    return {
        family: {
            "records": len(values),
            "positives": {
                field: sum(1 for value in values if value.get(field) is True)
                for field in INTENT_FIELDS
                if any(value.get(field) is True for value in values)
            },
        }
        for family, values in sorted(by_family.items())
    }


def main() -> int:
    arguments = parse_arguments()
    records: list[dict] = []
    for path in arguments.batches:
        records.extend(load_records(path))

    protected: set[str] = set()
    for path in arguments.holdout:
        for record in load_records(path):
            protected.add(fingerprint(record["text"]))

    errors = validate(records, protected)
    texts = [record["text"] for record in records if record.get("text")]
    metrics = diversity_metrics(texts)

    by_language = {
        language: diversity_metrics(
            [record["text"] for record in records if record.get("language") == language]
        )
        for language in sorted({record.get("language") for record in records} - {None})
    }

    comparison = {}
    if arguments.compare_corpus and arguments.compare_corpus.is_file():
        compare_records = load_records(arguments.compare_corpus)
        for language in sorted(by_language):
            subset = [
                record["text"]
                for record in compare_records
                if record.get("language") == language
            ]
            if subset:
                comparison[language] = diversity_metrics(subset)

    gates: dict[str, dict] = {}
    for language, values in by_language.items():
        gates[language] = {
            "distinct4GramRatio": {
                "actual": values["distinct4GramRatio"],
                "required": MINIMUM_DISTINCT_4GRAM_RATIO,
                "passed": values["distinct4GramRatio"] >= MINIMUM_DISTINCT_4GRAM_RATIO,
            },
            "topGramShare": {
                "actual": values["topGramShare"],
                "maximum": MAXIMUM_TOP_4GRAM_SHARE,
                "passed": values["topGramShare"] <= MAXIMUM_TOP_4GRAM_SHARE,
            },
            "topPrefixShare": {
                "actual": values["topPrefixShare"],
                "maximum": MAXIMUM_PREFIX_SHARE,
                "passed": values["topPrefixShare"] <= MAXIMUM_PREFIX_SHARE,
            },
        }

    all_passed = not errors and all(
        check["passed"] for language in gates.values() for check in language.values()
    )
    report = {
        "schemaVersion": 1,
        "batches": [str(path) for path in arguments.batches],
        "records": len(records),
        "languages": dict(Counter(record.get("language") for record in records)),
        "families": len({record.get("family") for record in records}),
        "positivesByIntent": {
            field: sum(1 for record in records if record.get(field) is True)
            for field in INTENT_FIELDS
        },
        "diversity": metrics,
        "diversityByLanguage": by_language,
        "templateCorpusComparison": comparison,
        "gates": gates,
        "familyBalance": family_balance(records),
        "errors": errors,
        "allChecksPassed": all_passed,
    }
    output = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True)
    if arguments.report:
        arguments.report.write_text(output + "\n", encoding="utf-8")
    print(output)
    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
