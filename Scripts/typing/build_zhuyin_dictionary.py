#!/usr/bin/env python3
"""Build a traditional-Chinese, tone-aware Rime Zhuyin dictionary offline.

Source: McBopomofo's MIT-licensed, Taiwan-oriented BPMFBase/BPMFMappings
and phrase.occ tables. A *local* checkout is required; this script never
downloads anything or installs a Python package.

    python3 Scripts/typing/build_zhuyin_dictionary.py
    python3 Scripts/typing/build_zhuyin_dictionary.py --check
"""

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESOURCE = ROOT / "OSGKeyboard/Resources/Typing/Rime"
DEFAULT_SOURCE = ROOT / ".cache/mcbopomofo-source/Source/Data"
SOURCE_COMMIT = "be6564acad6c4d3265c34a2e1a872d80f9db6068"
SOURCE_URL = "https://github.com/openvanilla/McBopomofo"

# Must match OSGKeyboardShared/Typing/ZhuyinKeyboardLayout.swift exactly.
DACHEN = dict(zip(
    "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄧㄨㄩㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦˊˇˋ˙",
    "1qaz2wsxedcrfv5tgbyhnujm8ik,9ol.0p;/-6347",
))
TONES = set("ˊˇˋ˙")
DATA_FILES = ("BPMFBase.txt", "BPMFMappings.txt", "phrase.occ")
PINNED_HASHES = {
    "BPMFBase.txt": "46e64a53dc9c6baa2cbe6e0b1af572f8ef6aafb50597178b5fd53df804316ce7",
    "BPMFMappings.txt": "394f3946754ebdd9d5e503f0f94c6977e5e19bd7cab21b4b18a6ea0167e00171",
    "phrase.occ": "dcd11597090b2bef88fb385bdd567e235ccd916728c84b8d0d3f8069ccfc7b8d",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def syllable_code(syllable: str) -> str | None:
    # McBopomofo includes initial neutral-tone readings (˙ㄇㄚ); Dachen
    # users press the neutral-tone key at the end (ㄇㄚ˙).
    syllable = syllable.replace("｜", "ㄧ")
    if not syllable or any(char not in DACHEN for char in syllable):
        return None
    tones = [char for char in syllable if char in TONES]
    if len(tones) > 1:
        return None
    base = "".join(DACHEN[char] for char in syllable if char not in TONES)
    return base + (DACHEN[tones[0]] if tones else "") if base else None


def load_frequencies(source_dir: Path) -> dict[str, int]:
    frequencies: dict[str, int] = {}
    with (source_dir / "phrase.occ").open(encoding="utf-8") as stream:
        for line in stream:
            columns = line.split()
            if len(columns) == 2:
                try:
                    frequencies[columns[0]] = max(0, int(columns[1]))
                except ValueError:
                    continue
    return frequencies


def build_entries(source_dir: Path) -> tuple[dict[tuple[str, str], int], dict[str, int]]:
    frequencies = load_frequencies(source_dir)
    entries: dict[tuple[str, str], int] = {}
    statistics: dict[str, int] = {"base": 0, "phrases": 0, "skipped": 0}

    def add(word: str, readings: list[str], origin: str) -> None:
        if not word or not readings or any(char.isspace() for char in word):
            statistics["skipped"] += 1
            return
        codes = [syllable_code(reading) for reading in readings]
        if any(code is None for code in codes):
            statistics["skipped"] += 1
            return
        # Multi-character words must have one pronunciation per character.
        if len(word) != len(codes):
            statistics["skipped"] += 1
            return
        code = " ".join(codes)
        key = (word, code)
        weight = max(1, min(frequencies.get(word, 0), 1_000_000))
        entries[key] = max(entries.get(key, 0), weight)
        statistics[origin] += 1

    with (source_dir / "BPMFBase.txt").open(encoding="utf-8") as stream:
        for line in stream:
            columns = line.split()
            if len(columns) < 3:
                continue
            # Source marks Big5/traditional characters explicitly. Skip
            # UTF8-only variants, including simplified duplicate glyphs.
            if columns[-1] != "big5":
                continue
            add(columns[0], [columns[1]], "base")

    with (source_dir / "BPMFMappings.txt").open(encoding="utf-8") as stream:
        for line in stream:
            columns = line.split()
            if len(columns) < 3:
                continue
            add(columns[0], columns[1:], "phrases")

    statistics["unique"] = len(entries)
    return entries, statistics


def render_dictionary(entries: dict[tuple[str, str], int]) -> str:
    output = [
        "# Rime dictionary",
        "# encoding: utf-8",
        "# Generated offline from MIT-licensed McBopomofo data; DO NOT EDIT.",
        "---",
        "name: osg_zhuyin",
        'version: "1.0"',
        "sort: by_weight",
        "use_preset_vocabulary: false",
        "columns:",
        "  - text",
        "  - code",
        "  - weight",
        "...",
    ]
    for (word, code), weight in sorted(
        entries.items(), key=lambda item: (-item[1], item[0][1], item[0][0])
    ):
        output.append(f"{word}\t{code}\t{weight}")
    return "\n".join(output) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=RESOURCE / "osg_zhuyin.dict.yaml")
    parser.add_argument("--manifest", type=Path, default=RESOURCE / "osg_zhuyin.manifest.json")
    parser.add_argument("--check", action="store_true", help="Verify existing files; write nothing")
    args = parser.parse_args()
    source = args.source_dir.resolve()
    missing = [name for name in DATA_FILES if not (source / name).is_file()]
    if missing:
        parser.error(
            f"Missing local McBopomofo source files: {', '.join(missing)}. "
            "No data will be downloaded."
        )
    source_hashes = {name: sha256(source / name) for name in DATA_FILES}
    if source_hashes != PINNED_HASHES:
        parser.error(
            "McBopomofo source files do not match the reviewed pinned revision. "
            "No network fetch or automatic source update is attempted."
        )

    entries, stats = build_entries(source)
    content = render_dictionary(entries)
    result_sha = hashlib.sha256(content.encode("utf-8")).hexdigest()
    manifest = {
        "source": SOURCE_URL,
        "commit": SOURCE_COMMIT,
        "license": "MIT",
        "files": source_hashes,
        "statistics": stats,
        "output": {"file": args.output.name, "sha256": result_sha},
    }
    manifest_text = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"

    if args.check:
        assert args.output.is_file() and sha256(args.output) == result_sha, (
            "Generated Zhuyin dictionary is missing or out of date"
        )
        assert args.manifest.is_file() and args.manifest.read_text() == manifest_text, (
            "Generated Zhuyin manifest is missing or out of date"
        )
        print(f"OK: {stats['unique']:,} entries; SHA-256 {result_sha}")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content, encoding="utf-8")
        args.manifest.write_text(manifest_text, encoding="utf-8")
        print(f"Created {args.output}: {stats['unique']:,} entries")
        print(f"Created {args.manifest}: {result_sha}")


if __name__ == "__main__":
    main()
