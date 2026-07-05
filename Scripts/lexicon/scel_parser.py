#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Parse Sogou .scel cell dictionaries into (word, pinyin) entries.

Layout follows the classic SCEL format used by imewlconverter / SogouPopularDict.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ScelInfo:
    word_count: int
    name: str
    type_name: str
    description: str


def _read_uint16(handle) -> int:
    data = handle.read(2)
    if not data or len(data) < 2:
        return 0
    return struct.unpack("<H", data)[0]


def _read_uint32(handle) -> int:
    data = handle.read(4)
    if not data or len(data) < 4:
        return 0
    return struct.unpack("<I", data)[0]


def _read_utf16_str(handle, *, offset: int = -1, length: int = 0) -> str:
    if offset >= 0:
        handle.seek(offset)
    if length > 0:
        data = handle.read(length)
        end = 0
        for index in range(0, len(data), 2):
            if index + 1 < len(data) and data[index] == 0 and data[index + 1] == 0:
                end = index
                break
        if end > 0:
            data = data[:end]
        return data.decode("utf-16le", errors="ignore")

    result = bytearray()
    while True:
        char = handle.read(2)
        if not char or len(char) < 2 or (char[0] == 0 and char[1] == 0):
            break
        result.extend(char)
    return result.decode("utf-16le", errors="ignore")


def is_valid_word(word: str) -> bool:
    if not word or not (1 <= len(word) <= 10):
        return False
    allowed_punct = "，。：；？！（）【】《》""''、"
    return all("\u4e00" <= char <= "\u9fff" or char.isdigit() or char in allowed_punct for char in word)


def get_scel_info(scel_path: Path) -> ScelInfo:
    with scel_path.open("rb") as handle:
        handle.seek(0x124)
        word_count = _read_uint32(handle)
        handle.seek(0x130)
        name = _read_utf16_str(handle, length=64)
        handle.seek(0x338)
        type_name = _read_utf16_str(handle, length=64)
        handle.seek(0x540)
        description = _read_utf16_str(handle, length=1024)
    return ScelInfo(word_count=word_count, name=name, type_name=type_name, description=description)


def parse_scel_file(scel_path: Path) -> list[tuple[str, str]]:
    """Return ordered (word, pinyin) pairs from a .scel file."""
    entries: list[tuple[str, str]] = []

    with scel_path.open("rb") as handle:
        handle.seek(0x1540)
        pinyin_count = _read_uint32(handle)
        pinyin_dict: dict[int, str] = {}
        for _ in range(pinyin_count):
            pinyin_idx = _read_uint16(handle)
            pinyin_len = _read_uint16(handle)
            pinyin = handle.read(pinyin_len).decode("utf-16le", errors="ignore").strip().lower()
            pinyin_dict[pinyin_idx] = pinyin

        try:
            while True:
                same_pinyin_count = _read_uint16(handle)
                pinyin_index_len = _read_uint16(handle)
                if pinyin_index_len <= 0 or same_pinyin_count <= 0:
                    break

                pinyin_parts: list[str] = []
                for _ in range(pinyin_index_len // 2):
                    idx = _read_uint16(handle)
                    part = pinyin_dict.get(idx, "")
                    if part:
                        pinyin_parts.append(part)
                joined_pinyin = " ".join(pinyin_parts).strip()

                for _ in range(same_pinyin_count):
                    word_len = _read_uint16(handle)
                    word = handle.read(word_len).decode("utf-16le", errors="ignore")
                    _ = _read_uint16(handle)
                    _ = _read_uint32(handle)
                    _ = handle.read(6)
                    if is_valid_word(word):
                        entries.append((word, joined_pinyin))
        except (struct.error, OSError):
            pass

    return entries


def load_pinyin_tsv(tsv_path: Path) -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    with tsv_path.open(encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line:
                continue
            word, _, pinyin = line.partition("\t")
            if word and pinyin:
                entries.append((word, pinyin.strip()))
    return entries
