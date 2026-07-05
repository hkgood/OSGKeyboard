#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build OSGKeyboard custom ASR lexicon v1 from Sogou-derived sources.

Sources (experimentation only — Sogou data is non-commercial):
  1. ASC8384/SogouPopularDict accumulated pinyin TSV
  2. Local 计算机词汇大全【官方推荐】.scel
  3. Local 网络流行新词.scel

Output:
  OSGKeyboard/Resources/CustomLanguageModel/v1/phrases.tsv
  OSGKeyboard/Resources/CustomLanguageModel/v1/manifest.json
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from scel_parser import get_scel_info, load_pinyin_tsv, parse_scel_file

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "OSGKeyboard/Resources/CustomLanguageModel/v1"
SOGOU_ACCUMULATED_URL = (
    "https://raw.githubusercontent.com/ASC8384/SogouPopularDict/main/"
    "data/sogou_network_words_accumulated_pinyin.tsv"
)

DEFAULT_COMPUTER_SCEL = Path("/Users/rocky/Downloads/计算机词汇大全【官方推荐】.scel")
DEFAULT_NETWORK_SCEL = Path("/Users/rocky/Downloads/网络流行新词.scel")


@dataclass(frozen=True)
class SourceSpec:
    key: str
    label: str
    weight: int


SOURCES = [
    SourceSpec("computer_terms", "计算机词汇大全【官方推荐】", weight=5),
    SourceSpec("network_slang_local", "网络流行新词.scel", weight=3),
    SourceSpec("sogou_popular_accumulated", "SogouPopularDict accumulated", weight=1),
]


def download_accumulated_tsv(destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(SOGOU_ACCUMULATED_URL, timeout=120) as response:
        destination.write_bytes(response.read())


@dataclass
class LexiconEntry:
    word: str
    pinyin: str
    source: str
    weight: int


def merge_entries(sources: list[tuple[SourceSpec, list[tuple[str, str]]]]) -> list[LexiconEntry]:
    merged: dict[str, LexiconEntry] = {}
    source_counts: Counter[str] = Counter()

    for spec, entries in sources:
        for word, pinyin in entries:
            source_counts[spec.key] += 1
            current = merged.get(word)
            candidate = LexiconEntry(word=word, pinyin=pinyin, source=spec.key, weight=spec.weight)
            if current is None or candidate.weight > current.weight:
                merged[word] = candidate
            elif current.weight == candidate.weight and not current.pinyin and pinyin:
                merged[word] = candidate

    return sorted(merged.values(), key=lambda item: (item.weight * -1, item.word))


def write_outputs(entries: list[LexiconEntry], output_dir: Path, source_stats: dict[str, int]) -> None:
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
                "key": spec.key,
                "label": spec.label,
                "weight": spec.weight,
                "raw_count": source_stats.get(spec.key, 0),
            }
            for spec in SOURCES
        ],
        "notes": [
            "Sogou-derived data is for internal ASR experimentation only.",
            "PhraseCount weights map to SFCustomLanguageModelData relative frequencies.",
            "Higher source weight wins on duplicate words.",
        ],
        "files": {
            "phrases": phrases_path.name,
        },
    }

    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def build(
    *,
    computer_scel: Path,
    network_scel: Path,
    output_dir: Path,
    skip_download: bool,
) -> int:
    cache_dir = REPO_ROOT / ".cache/lexicon"
    cache_dir.mkdir(parents=True, exist_ok=True)
    accumulated_tsv = cache_dir / "sogou_network_words_accumulated_pinyin.tsv"

    if not skip_download and not accumulated_tsv.exists():
        print(f"Downloading {SOGOU_ACCUMULATED_URL} …")
        download_accumulated_tsv(accumulated_tsv)
    elif not accumulated_tsv.exists():
        print(f"Missing accumulated TSV: {accumulated_tsv}", file=sys.stderr)
        return 1

    if not computer_scel.exists():
        print(f"Missing computer scel: {computer_scel}", file=sys.stderr)
        return 1
    if not network_scel.exists():
        print(f"Missing network scel: {network_scel}", file=sys.stderr)
        return 1

    computer_info = get_scel_info(computer_scel)
    network_info = get_scel_info(network_scel)
    print(f"Computer dict: {computer_info.name} ({computer_info.word_count} header count)")
    print(f"Network dict: {network_info.name} ({network_info.word_count} header count)")

    loaded_sources: list[tuple[SourceSpec, list[tuple[str, str]]]] = [
        (SOURCES[0], parse_scel_file(computer_scel)),
        (SOURCES[1], parse_scel_file(network_scel)),
        (SOURCES[2], load_pinyin_tsv(accumulated_tsv)),
    ]

    source_stats = {spec.key: len(entries) for spec, entries in loaded_sources}
    merged = merge_entries(loaded_sources)
    write_outputs(merged, output_dir, source_stats)

    print(f"Raw counts: {source_stats}")
    print(f"Merged unique entries: {len(merged)}")
    print(f"Wrote {output_dir / 'phrases.tsv'}")
    print(f"Wrote {output_dir / 'manifest.json'}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Build OSGKeyboard custom ASR lexicon v1")
    parser.add_argument("--computer-scel", type=Path, default=DEFAULT_COMPUTER_SCEL)
    parser.add_argument("--network-scel", type=Path, default=DEFAULT_NETWORK_SCEL)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--skip-download", action="store_true")
    args = parser.parse_args()
    return build(
        computer_scel=args.computer_scel,
        network_scel=args.network_scel,
        output_dir=args.output_dir,
        skip_download=args.skip_download,
    )


if __name__ == "__main__":
    raise SystemExit(main())
