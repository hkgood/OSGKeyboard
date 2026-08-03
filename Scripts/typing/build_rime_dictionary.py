#!/usr/bin/env python3
"""Build OSG's commercially permissive Simplified Chinese Rime dictionary.

Sources are pinned and independently redistributable:
  - rime-pinyin-simp (Apache-2.0): baseline entries
  - jieba (MIT): modern word frequencies
  - phrase-pinyin-data (MIT): phrase pronunciations
  - pinyin-data (MIT): per-character pronunciation fallback

The script deliberately does not consume rime-ice, rime-double-pinyin,
Luna, or Essay.
"""

from __future__ import annotations

import hashlib
import json
import re
import unicodedata
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = ROOT / "OSGKeyboardShared" / "Resources" / "Typing" / "Rime"
CACHE_DIR = ROOT / ".cache" / "typing-rime"

SOURCES = {
    "pinyin_simp": {
        "license": "Apache-2.0",
        "commit": "0c6861ef7420ee780270ca6d993d18d4101049d0",
        "url": (
            "https://raw.githubusercontent.com/rime/rime-pinyin-simp/"
            "0c6861ef7420ee780270ca6d993d18d4101049d0/pinyin_simp.dict.yaml"
        ),
    },
    "jieba": {
        "license": "MIT",
        "commit": "67fa2e36e72f69d9134b8a1037b83fbb070b9775",
        "url": (
            "https://raw.githubusercontent.com/fxsjy/jieba/"
            "67fa2e36e72f69d9134b8a1037b83fbb070b9775/jieba/dict.txt"
        ),
    },
    "phrase_pinyin": {
        "license": "MIT",
        "commit": "cee0ed6e6e4898580cafd2bd5e3723e20b214aa0",
        "url": (
            "https://raw.githubusercontent.com/mozillazg/phrase-pinyin-data/"
            "cee0ed6e6e4898580cafd2bd5e3723e20b214aa0/pinyin.txt"
        ),
    },
    "character_pinyin": {
        "license": "MIT",
        "commit": "923b108dc5d45dee061324c011b478fb649f8b73",
        "url": (
            "https://raw.githubusercontent.com/mozillazg/pinyin-data/"
            "923b108dc5d45dee061324c011b478fb649f8b73/pinyin.txt"
        ),
    },
}

CJK_RE = re.compile(r"^[\u3400-\u9fff\uf900-\ufaff]+$")


def download(name: str, source: dict[str, str]) -> tuple[Path, str]:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    path = CACHE_DIR / f"{name}.txt"
    if not path.exists():
        request = urllib.request.Request(
            source["url"],
            headers={"User-Agent": "OSGKeyboard-rime-builder/1"},
        )
        with urllib.request.urlopen(request, timeout=90) as response:
            path.write_bytes(response.read())
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return path, digest


def strip_tones(value: str) -> str:
    normalized = unicodedata.normalize("NFD", value.lower())
    return "".join(
        char
        for char in normalized
        if unicodedata.category(char) != "Mn" and ("a" <= char <= "z" or char == " ")
    )


def parse_phrase_pinyin(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or ": " not in line:
            continue
        phrase, pinyin = line.split(": ", 1)
        code = " ".join(strip_tones(pinyin).split())
        if phrase and code:
            result[phrase] = code
    return result


def parse_character_pinyin(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or " # " not in line or ": " not in line:
            continue
        encoded, character = line.split(" # ", 1)
        pinyin = encoded.split(": ", 1)[1].split(",", 1)[0]
        code = strip_tones(pinyin).strip()
        if character and code:
            result[character[0]] = code
    return result


def parse_baseline(path: Path) -> dict[tuple[str, str], int]:
    entries: dict[tuple[str, str], int] = {}
    in_body = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line == "...":
            in_body = True
            continue
        if not in_body or not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        text = parts[0]
        weight = int(parts[-1]) if parts[-1].isdigit() else 1
        code_parts = parts[1:-1] if parts[-1].isdigit() else parts[1:]
        code = " ".join(code_parts)
        entries[(text, code)] = max(entries.get((text, code), 0), weight)
    return entries


def merge_jieba(
    path: Path,
    entries: dict[tuple[str, str], int],
    phrase_pinyin: dict[str, str],
    character_pinyin: dict[str, str],
) -> tuple[int, int]:
    accepted = 0
    inferred = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.rsplit(" ", 2)
        if len(parts) != 3:
            continue
        word, frequency, _ = parts
        if not frequency.isdigit() or not (2 <= len(word) <= 12) or not CJK_RE.fullmatch(word):
            continue
        code = phrase_pinyin.get(word)
        if code is None:
            syllables = [character_pinyin.get(char) for char in word]
            if any(item is None for item in syllables):
                continue
            code = " ".join(item for item in syllables if item)
            inferred += 1
        weight = max(1, int(frequency))
        key = (word, code)
        entries[key] = max(entries.get(key, 0), weight)
        accepted += 1
    return accepted, inferred


def write_dictionary(entries: dict[tuple[str, str], int]) -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output = OUTPUT_DIR / "osg_pinyin.dict.yaml"
    header = """# Rime dictionary
# encoding: utf-8
# Generated by Scripts/typing/build_rime_dictionary.py — DO NOT EDIT.
---
name: osg_pinyin
version: "1.0"
sort: by_weight
use_preset_vocabulary: false
columns:
  - text
  - code
  - weight
...
"""
    ordered = sorted(entries.items(), key=lambda item: (item[0][1], -item[1], item[0][0]))
    body = "".join(f"{text}\t{code}\t{weight}\n" for (text, code), weight in ordered)
    output.write_text(header + body, encoding="utf-8")
    return output


def main() -> None:
    downloaded: dict[str, Path] = {}
    manifest_sources: dict[str, dict[str, str]] = {}
    for name, source in SOURCES.items():
        path, digest = download(name, source)
        downloaded[name] = path
        manifest_sources[name] = {**source, "sha256": digest}

    entries = parse_baseline(downloaded["pinyin_simp"])
    baseline_count = len(entries)
    phrase_pinyin = parse_phrase_pinyin(downloaded["phrase_pinyin"])
    character_pinyin = parse_character_pinyin(downloaded["character_pinyin"])
    jieba_count, inferred_count = merge_jieba(
        downloaded["jieba"],
        entries,
        phrase_pinyin,
        character_pinyin,
    )
    output = write_dictionary(entries)
    output_digest = hashlib.sha256(output.read_bytes()).hexdigest()

    manifest = {
        "formatVersion": 1,
        "sources": manifest_sources,
        "statistics": {
            "baselineEntries": baseline_count,
            "jiebaWordsAccepted": jieba_count,
            "jiebaWordsUsingCharacterFallback": inferred_count,
            "outputEntries": len(entries),
        },
        "output": {
            "file": output.name,
            "sha256": output_digest,
        },
        "excluded": [
            "rime-ice (GPL-3.0)",
            "rime-double-pinyin (GPL-3.0)",
            "rime-essay (LGPL-3.0)",
            "rime-luna-pinyin (LGPL-3.0)",
        ],
    }
    (OUTPUT_DIR / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest["statistics"], ensure_ascii=False))


if __name__ == "__main__":
    main()
