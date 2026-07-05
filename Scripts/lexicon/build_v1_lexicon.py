#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build OSGKeyboard domain ASR lexicon v1 from the computer-terms scel source.

Sources:
  Local 计算机词汇大全【官方推荐】.scel (IT / computer vocabulary only)

Casual network slang and Sogou popular-word dumps are intentionally excluded —
they dilute custom LM phrase biasing without improving domain ASR accuracy.

Output:
  OSGKeyboard/Resources/CustomLanguageModel/v1/phrases.tsv
  OSGKeyboard/Resources/CustomLanguageModel/v1/manifest.json

The compiled .bin asset is exported separately to
OSGKeyboardShared/Resources/CustomLanguageModel/v1/ via export_clm.swift.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from scel_parser import get_scel_info, parse_scel_file

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "OSGKeyboard/Resources/CustomLanguageModel/v1"
DEFAULT_COMPUTER_SCEL = Path("/Users/rocky/Downloads/计算机词汇大全【官方推荐】.scel")

SOURCE_KEY = "computer_terms"
SOURCE_LABEL = "计算机词汇大全【官方推荐】"
SOURCE_WEIGHT = 5


@dataclass
class LexiconEntry:
    word: str
    pinyin: str
    source: str
    weight: int


def merge_entries(entries: list[tuple[str, str]]) -> list[LexiconEntry]:
    merged: dict[str, LexiconEntry] = {}

    for word, pinyin in entries:
        current = merged.get(word)
        candidate = LexiconEntry(
            word=word,
            pinyin=pinyin,
            source=SOURCE_KEY,
            weight=SOURCE_WEIGHT,
        )
        if current is None:
            merged[word] = candidate
        elif not current.pinyin and pinyin:
            merged[word] = candidate

    return sorted(merged.values(), key=lambda item: item.word)


def write_outputs(entries: list[LexiconEntry], output_dir: Path, raw_count: int) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    phrases_path = output_dir / "phrases.tsv"
    with phrases_path.open("w", encoding="utf-8") as handle:
        handle.write("word\tpinyin\tsource\tweight\n")
        for entry in entries:
            handle.write(f"{entry.word}\t{entry.pinyin}\t{entry.source}\t{entry.weight}\n")

    manifest = {
        "version": "v1",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "locale": "zh-Hans",
        "entry_count": len(entries),
        "sources": [
            {
                "key": SOURCE_KEY,
                "label": SOURCE_LABEL,
                "weight": SOURCE_WEIGHT,
                "raw_count": raw_count,
            }
        ],
        "notes": [
            "Domain-specific computer/IT vocabulary only; casual network slang removed.",
            "PhraseCount weights map to SFCustomLanguageModelData relative frequencies.",
            "Merged with ai-tech-brands seed at export time for the final .bin asset.",
        ],
        "files": {
            "phrases": phrases_path.name,
        },
    }

    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def build(*, computer_scel: Path, output_dir: Path) -> int:
    if not computer_scel.exists():
        print(f"Missing computer scel: {computer_scel}", file=sys.stderr)
        return 1

    computer_info = get_scel_info(computer_scel)
    print(f"Computer dict: {computer_info.name} ({computer_info.word_count} header count)")

    raw_entries = parse_scel_file(computer_scel)
    merged = merge_entries(raw_entries)
    write_outputs(merged, output_dir, raw_count=len(raw_entries))

    print(f"Raw count: {len(raw_entries)}")
    print(f"Merged unique entries: {len(merged)}")
    print(f"Wrote {output_dir / 'phrases.tsv'}")
    print(f"Wrote {output_dir / 'manifest.json'}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Build OSGKeyboard domain ASR lexicon v1")
    parser.add_argument("--computer-scel", type=Path, default=DEFAULT_COMPUTER_SCEL)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    args = parser.parse_args()
    return build(computer_scel=args.computer_scel, output_dir=args.output_dir)


if __name__ == "__main__":
    raise SystemExit(main())
