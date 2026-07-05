#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build the curated AI / tech / brand seed lexicon for OSGKeyboard ASR.

Reads Scripts/lexicon/seeds/ai_tech_brands_seed.tsv and emits:
  OSGKeyboard/Resources/CustomLanguageModel/ai-tech-brands/v1/phrases.tsv
  OSGKeyboard/Resources/CustomLanguageModel/ai-tech-brands/v1/manifest.json

Each seed row may declare pipe-separated aliases; aliases are expanded into
additional phrase rows sharing the same category and weight.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SEED = REPO_ROOT / "Scripts/lexicon/seeds/ai_tech_brands_seed.tsv"
DEFAULT_OUTPUT = REPO_ROOT / "OSGKeyboard/Resources/CustomLanguageModel/ai-tech-brands/v1"


@dataclass(frozen=True)
class SeedRow:
    word: str
    pinyin: str
    aliases: tuple[str, ...]
    category: str
    weight: int


@dataclass(frozen=True)
class PhraseRow:
    word: str
    pinyin: str
    source: str
    category: str
    weight: int
    canonical: str


def parse_seed_file(seed_path: Path) -> list[SeedRow]:
    rows: list[SeedRow] = []
    with seed_path.open(encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 4:
                print(f"Warning: skip malformed line {line_number}: {line}", file=sys.stderr)
                continue
            word = parts[0].strip()
            pinyin = parts[1].strip() if len(parts) > 1 else ""
            aliases_raw = parts[2].strip() if len(parts) > 2 else ""
            category = parts[3].strip() if len(parts) > 3 else "misc"
            weight_raw = parts[4].strip() if len(parts) > 4 else "80"
            if not word:
                continue
            aliases = tuple(
                alias.strip()
                for alias in aliases_raw.split("|")
                if alias.strip() and alias.strip() != word
            )
            try:
                weight = int(weight_raw)
            except ValueError:
                weight = 80
            rows.append(
                SeedRow(
                    word=word,
                    pinyin=pinyin,
                    aliases=aliases,
                    category=category,
                    weight=weight,
                )
            )
    return rows


def expand_rows(seeds: list[SeedRow]) -> list[PhraseRow]:
    """Expand canonical + aliases; dedupe by word keeping highest weight."""
    merged: dict[str, PhraseRow] = {}

    for seed in seeds:
        candidates = [(seed.word, seed.pinyin, seed.category, seed.weight, seed.word)]
        for alias in seed.aliases:
            # Aliases inherit canonical pinyin only when alias is Chinese.
            alias_pinyin = seed.pinyin if _contains_cjk(alias) else ""
            candidates.append((alias, alias_pinyin, seed.category, seed.weight, seed.word))

        for word, pinyin, category, weight, canonical in candidates:
            if not word:
                continue
            row = PhraseRow(
                word=word,
                pinyin=pinyin,
                source="ai_tech_seed",
                category=category,
                weight=weight,
                canonical=canonical,
            )
            current = merged.get(word)
            if current is None or row.weight > current.weight:
                merged[word] = row

    return sorted(merged.values(), key=lambda item: (-item.weight, item.word.lower()))


def _contains_cjk(text: str) -> bool:
    return any("\u4e00" <= char <= "\u9fff" for char in text)


def write_outputs(phrases: list[PhraseRow], output_dir: Path, seed_path: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    phrases_path = output_dir / "phrases.tsv"
    with phrases_path.open("w", encoding="utf-8") as handle:
        handle.write("word\tpinyin\tsource\tcategory\tweight\tcanonical\n")
        for row in phrases:
            handle.write(
                f"{row.word}\t{row.pinyin}\t{row.source}\t{row.category}\t{row.weight}\t{row.canonical}\n"
            )

    category_counts = Counter(row.category for row in phrases)
    manifest = {
        "version": "v1",
        "name": "ai-tech-brands",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "locale": "zh-Hans",
        "entry_count": len(phrases),
        "seed_file": str(seed_path.relative_to(REPO_ROOT)),
        "license": "MIT (curated seed; OSGKeyboard contributors)",
        "categories": dict(sorted(category_counts.items())),
        "notes": [
            "Curated bilingual AI brands, tech companies, terminology, and hot words.",
            "English canonical forms + Chinese aliases for ASR PhraseCount weighting.",
            "Aliases expanded at build time; canonical column tracks the primary form.",
            "English post-processing (casing) remains LLM polish responsibility.",
        ],
        "files": {"phrases": phrases_path.name},
    }
    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def build(seed_path: Path, output_dir: Path) -> int:
    if not seed_path.exists():
        print(f"Missing seed file: {seed_path}", file=sys.stderr)
        return 1

    seeds = parse_seed_file(seed_path)
    phrases = expand_rows(seeds)
    write_outputs(phrases, output_dir, seed_path)

    print(f"Seed rows: {len(seeds)}")
    print(f"Expanded unique phrases: {len(phrases)}")
    print(f"Wrote {output_dir / 'phrases.tsv'}")
    print(f"Wrote {output_dir / 'manifest.json'}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Build AI/tech brand seed lexicon")
    parser.add_argument("--seed", type=Path, default=DEFAULT_SEED)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    return build(args.seed, args.output_dir)


if __name__ == "__main__":
    raise SystemExit(main())
