#!/usr/bin/env python3
"""Build compact English unigram + bigram TSVs from Peter Norvig's public-domain
n-gram counts (https://norvig.com/ngrams/).

Norvig: “I hereby release all these files into the public domain.”
We store log-scaled ranks (not raw counts) so the keyboard extension stays small
and we are not redistributing the full Google Web Trillion Word Corpus dump.
"""

from __future__ import annotations

import argparse
import math
import re
import struct
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "OSGKeyboardShared" / "Resources" / "Typing" / "English"
UNIGRAM_URL = "https://norvig.com/ngrams/count_1w.txt"
BIGRAM_URL = "https://norvig.com/ngrams/count_2w.txt"

WORD_RE = re.compile(r"^[a-z]+(?:'[a-z]+)?$")
MAX_UNIGRAMS = 40_000
MAX_BIGRAMS = 8_000
MAX_WORD_LEN = 20
# Stop reading the 2-gram file once we have enough accepted rows; the file is
# already sorted by descending count.
BIGRAM_SCAN_LIMIT = 80_000

# Seed collocations so next-word still works if the 2-gram download fails.
FALLBACK_BIGRAMS: list[tuple[str, list[str]]] = [
    ("the", "of and to in is for that with on a".split()),
    ("of", "the a this my our their these those course them".split()),
    ("to", "the be a do make see get go have my".split()),
    ("and", "the a then also other more so we you".split()),
    ("a", "lot few new good great little bit way time person".split()),
    ("in", "the a my this order fact front time case addition".split()),
    ("is", "a the not to that this it one more also".split()),
    ("for", "the a example me you us this that now sure".split()),
    ("that", "the is was I you it we they this are".split()),
    ("i", "am have will would can do think know want was".split()),
    ("it", "is was would will can be has had to not".split()),
    ("on", "the a my this time top of it you that".split()),
    ("you", "are can will would have do know want to should".split()),
    ("with", "the a my you it this that him her them".split()),
    ("as", "a the well much soon far long if of to".split()),
    ("this", "is was the a time one way thing point case".split()),
    ("we", "are have will can would do need want should were".split()),
    ("have", "a the been to been a been the time been".split()),
    ("be", "a the able to in on there here with as".split()),
    ("are", "a the not you we they going to in on".split()),
    ("not", "a the be to sure only yet even really the".split()),
    ("but", "the I a it is also then we you not".split()),
    ("from", "the a my this that it you now here there".split()),
    ("at", "the a my this time least home work school night".split()),
    ("by", "the a this that now then far me you email".split()),
    ("or", "the a not so to it you we they this".split()),
    ("an", "hour example email idea issue update account apple app".split()),
    ("if", "you the I we it that this not so a".split()),
    ("will", "be you I we the not have to a get".split()),
    ("can", "be you I we not the a help see get".split()),
    ("would", "be you I we like have not the a to".split()),
    ("do", "you not the I we it that this a".split()),
    ("there", "is are was were a the no not been have".split()),
    ("their", "own new first last time way work house car".split()),
    ("what", "is the a you I we do time about if".split()),
    ("when", "the I you we it is a this that not".split()),
    ("which", "is the a you we they of in to that".split()),
    ("who", "is are was were the a you I we".split()),
    ("how", "to much many long about is the a you".split()),
    ("about", "the a this that it you to time me".split()),
    ("into", "the a this that my it you a new".split()),
    ("just", "a the like to be now want wanted got".split()),
    ("like", "a the to this that it you I we".split()),
    ("so", "I the a you we that this much many".split()),
    ("than", "the a I you we this that it to".split()),
    ("then", "the I you we a it to is was".split()),
    ("them", "to a the in on with for and I".split()),
    ("these", "are is the a days things people ones two".split()),
    ("those", "are is the a who were days people ones".split()),
    ("my", "own new first last time way email phone name".split()),
    ("your", "own new email phone name time way account".split()),
    ("our", "own new first last time team way house".split()),
    ("going", "to be the a in on for with".split()),
    ("want", "to a the you I we it".split()),
    ("need", "to a the you I we it".split()),
    ("let", "me you us the a".split()),
    ("please", "let me you the a".split()),
    ("thank", "you so much".split()),
    ("thanks", "for so much".split()),
    ("looking", "forward to for at".split()),
    ("let", "me you us know".split()),
]


def fetch_lines(url: str, max_lines: int | None = None) -> list[str]:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "OSGKeyboard-lexicon-builder/1.0"},
    )
    with urllib.request.urlopen(req, timeout=120) as response:
        lines: list[str] = []
        for raw in response:
            line = raw.decode("utf-8", errors="ignore").strip()
            if not line:
                continue
            lines.append(line)
            if max_lines is not None and len(lines) >= max_lines:
                break
        return lines


def parse_count_line(line: str) -> tuple[str, int] | None:
    parts = line.split()
    if len(parts) < 2:
        return None
    token = parts[0].lower()
    try:
        count = int(parts[-1])
    except ValueError:
        return None
    return token, count


def log_rank(count: int) -> int:
    return max(1, int(round(math.log10(count) * 100)))


def build_unigrams(lines: list[str]) -> dict[str, int]:
    ranked: list[tuple[str, int]] = []
    seen: set[str] = set()
    for line in lines:
        parsed = parse_count_line(line)
        if parsed is None:
            continue
        word, count = parsed
        if word in seen:
            continue
        if not WORD_RE.match(word) or len(word) > MAX_WORD_LEN:
            continue
        seen.add(word)
        ranked.append((word, count))
        if len(ranked) >= MAX_UNIGRAMS:
            break
    return {word: log_rank(count) for word, count in ranked}


def build_bigrams(
    lines: list[str],
    unigrams: dict[str, int],
) -> dict[str, list[str]]:
    grouped: dict[str, list[tuple[str, int]]] = {}
    accepted = 0
    for line in lines:
        parsed = parse_count_line(line)
        if parsed is None:
            continue
        token, count = parsed
        parts = token.split("_")
        if len(parts) != 2:
            # Norvig 2-grams are "word1 word2 count"
            bits = line.lower().split()
            if len(bits) < 3:
                continue
            left, right, count_s = bits[0], bits[1], bits[-1]
            try:
                count = int(count_s)
            except ValueError:
                continue
        else:
            left, right = parts
        if left not in unigrams or right not in unigrams:
            continue
        if left == right:
            continue
        bucket = grouped.setdefault(left, [])
        if any(word == right for word, _ in bucket):
            continue
        bucket.append((right, count))
        accepted += 1
        if accepted >= MAX_BIGRAMS * 3:
            break

    result: dict[str, list[str]] = {}
    used = 0
    for left, pairs in grouped.items():
        pairs.sort(key=lambda item: item[1], reverse=True)
        nxt = [word for word, _ in pairs[:8]]
        if not nxt:
            continue
        result[left] = nxt
        used += len(nxt)
        if used >= MAX_BIGRAMS:
            break
    return result


def merge_fallback(bigrams: dict[str, list[str]]) -> dict[str, list[str]]:
    merged = dict(bigrams)
    for left, rights in FALLBACK_BIGRAMS:
        existing = merged.get(left, [])
        seen = set(existing)
        for word in rights:
            if word not in seen:
                existing.append(word)
                seen.add(word)
        merged[left] = existing[:10]
    return merged


def write_unigrams(path: Path, unigrams: dict[str, int]) -> None:
    rows = sorted(unigrams.items(), key=lambda item: (-item[1], item[0]))
    path.write_text("".join(f"{word}\t{freq}\n" for word, freq in rows), encoding="utf-8")


def write_bigrams(path: Path, bigrams: dict[str, list[str]]) -> None:
    rows = sorted(bigrams.items(), key=lambda item: item[0])
    path.write_text(
        "".join(f"{left}\t{' '.join(rights)}\n" for left, rights in rows),
        encoding="utf-8",
    )


# mmap binary (`english_lexicon.bin`), little-endian. Layout:
#   64-byte header, then unigram records, freq-rank indices, 26 initial
#   ranges, bigram groups, packed next-word indices, ASCII string pool.
# The keyboard maps this file; it must not parse TSV into Swift dictionaries.
BIN_MAGIC = b"OSGENG01"
BIN_VERSION = 1
BIN_HEADER_SIZE = 64
BIN_INITIAL_COUNT = 26


def _align4(offset: int) -> int:
    return (offset + 3) & ~3


def write_binary(
    path: Path,
    unigrams: dict[str, int],
    bigrams: dict[str, list[str]],
) -> None:
    words = sorted(unigrams.keys())
    index_of = {word: index for index, word in enumerate(words)}

    pool = bytearray()
    records: list[tuple[int, int, int]] = []
    for word in words:
        encoded = word.encode("ascii")
        if len(encoded) > 255:
            continue
        freq = min(int(unigrams[word]), 65_535)
        records.append((len(pool), len(encoded), freq))
        pool.extend(encoded)

    initials = [(0, 0)] * BIN_INITIAL_COUNT
    cursor = 0
    while cursor < len(words):
        first = words[cursor][0]
        if "a" <= first <= "z":
            start = cursor
            while cursor < len(words) and words[cursor][0] == first:
                cursor += 1
            initials[ord(first) - ord("a")] = (start, cursor - start)
        else:
            cursor += 1

    freq_order = sorted(
        range(len(words)),
        key=lambda index: (-unigrams[words[index]], words[index]),
    )

    groups: list[tuple[int, int, int]] = []
    next_indices: list[int] = []
    for left in sorted(bigrams.keys()):
        prev_index = index_of.get(left)
        if prev_index is None:
            continue
        rights = [index_of[word] for word in bigrams[left] if word in index_of]
        if not rights:
            continue
        groups.append((prev_index, len(rights), len(next_indices)))
        next_indices.extend(rights)

    unigram_offset = _align4(BIN_HEADER_SIZE)
    freq_offset = _align4(unigram_offset + len(records) * 8)
    initial_offset = _align4(freq_offset + len(freq_order) * 2)
    bigram_index_offset = _align4(initial_offset + BIN_INITIAL_COUNT * 4)
    bigram_next_offset = _align4(bigram_index_offset + len(groups) * 8)
    pool_offset = _align4(bigram_next_offset + len(next_indices) * 2)
    total = pool_offset + len(pool)

    blob = bytearray(total)
    struct.pack_into(
        "<8s14I",
        blob,
        0,
        BIN_MAGIC,
        BIN_VERSION,
        len(records),
        len(groups),
        pool_offset,
        len(pool),
        unigram_offset,
        freq_offset,
        initial_offset,
        bigram_index_offset,
        bigram_next_offset,
        0,
        0,
        0,
        0,
    )
    for index, (pool_off, length, freq) in enumerate(records):
        struct.pack_into(
            "<IBBH",
            blob,
            unigram_offset + index * 8,
            pool_off,
            length,
            0,
            freq,
        )
    for index, word_index in enumerate(freq_order):
        struct.pack_into("<H", blob, freq_offset + index * 2, word_index)
    for letter, (start, count) in enumerate(initials):
        struct.pack_into("<HH", blob, initial_offset + letter * 4, start, count)
    for index, (prev_index, count, first_next) in enumerate(groups):
        struct.pack_into(
            "<HHI",
            blob,
            bigram_index_offset + index * 8,
            prev_index,
            count,
            first_next,
        )
    for index, word_index in enumerate(next_indices):
        struct.pack_into("<H", blob, bigram_next_offset + index * 2, word_index)
    blob[pool_offset : pool_offset + len(pool)] = pool
    path.write_bytes(blob)


def read_unigrams_tsv(path: Path) -> dict[str, int]:
    result: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        word, freq_s = line.split("\t", 1)
        result[word.lower()] = int(freq_s)
    return result


def read_bigrams_tsv(path: Path) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        left, rights = line.split("\t", 1)
        result[left.lower()] = [word.lower() for word in rights.split() if word]
    return result


def emit_outputs(unigrams: dict[str, int], bigrams: dict[str, list[str]]) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_unigrams(OUT_DIR / "english_lexicon.tsv", unigrams)
    write_bigrams(OUT_DIR / "english_bigrams.tsv", bigrams)
    write_binary(OUT_DIR / "english_lexicon.bin", unigrams, bigrams)
    print(f"Wrote {OUT_DIR / 'english_lexicon.tsv'}", file=sys.stderr)
    print(f"Wrote {OUT_DIR / 'english_bigrams.tsv'}", file=sys.stderr)
    print(
        f"Wrote {OUT_DIR / 'english_lexicon.bin'} "
        f"({(OUT_DIR / 'english_lexicon.bin').stat().st_size} bytes)",
        file=sys.stderr,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--from-tsv",
        action="store_true",
        help="Compile english_lexicon.bin from existing TSV files (no network).",
    )
    args = parser.parse_args()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    if args.from_tsv:
        unigram_path = OUT_DIR / "english_lexicon.tsv"
        bigram_path = OUT_DIR / "english_bigrams.tsv"
        if not unigram_path.is_file() or not bigram_path.is_file():
            print("Missing english_lexicon.tsv / english_bigrams.tsv", file=sys.stderr)
            return 1
        unigrams = read_unigrams_tsv(unigram_path)
        bigrams = read_bigrams_tsv(bigram_path)
        write_binary(OUT_DIR / "english_lexicon.bin", unigrams, bigrams)
        print(
            f"Wrote {OUT_DIR / 'english_lexicon.bin'} "
            f"({(OUT_DIR / 'english_lexicon.bin').stat().st_size} bytes) "
            f"from {len(unigrams)} unigrams / {len(bigrams)} bigram keys",
            file=sys.stderr,
        )
        return 0

    print(f"Fetching unigrams from {UNIGRAM_URL}", file=sys.stderr)
    unigram_lines = fetch_lines(UNIGRAM_URL, max_lines=200_000)
    unigrams = build_unigrams(unigram_lines)
    print(f"Kept {len(unigrams)} unigrams", file=sys.stderr)

    bigrams: dict[str, list[str]] = {}
    try:
        print(f"Fetching bigrams from {BIGRAM_URL}", file=sys.stderr)
        bigram_lines = fetch_lines(BIGRAM_URL, max_lines=BIGRAM_SCAN_LIMIT)
        bigrams = build_bigrams(bigram_lines, unigrams)
        print(f"Kept {sum(len(v) for v in bigrams.values())} bigram edges", file=sys.stderr)
    except Exception as exc:  # noqa: BLE001 — fallback is intentional
        print(f"Bigram download failed ({exc}); using fallback collocations", file=sys.stderr)

    bigrams = merge_fallback(bigrams)
    emit_outputs(unigrams, bigrams)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
