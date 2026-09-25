#!/usr/bin/env python3
"""Extract research-only blessing candidates from an official LCCC archive."""

from __future__ import annotations

import argparse
import hashlib
import heapq
import json
import re
import zipfile
from collections import Counter
from pathlib import Path

import ijson


SOURCE_URL = (
    "https://drive.google.com/file/d/"
    "1oobhYW_S_vPPzP5bLAUTIm7TaRzryxgW/view"
)
SOURCE_LICENSE = (
    "MIT dataset metadata; official README limits use to research; "
    "underlying Weibo rights unverified"
)
SOURCE_SPLIT = "LCCC-base_train.json"

PII_PATTERN = re.compile(
    r"(?:https?://|www\.)|(?:[\w.+-]+@[\w.-]+\.\w+)|"
    r"(?:@[\w\u4e00-\u9fff]{2,})|(?:\+?\d[\d ()-]{8,}\d)",
    re.IGNORECASE,
)
META_PATTERN = re.compile(
    r"(?:祝福语|祝福模板|帮我写.{0,12}祝福|怎么祝|如何祝|"
    r"可以.{0,12}说一?句.{0,8}(?:生日快乐|恭喜)|搜索.{0,12}祝福)"
)
RECEIVED_PATTERN = re.compile(
    r"(?:谢谢|感谢|收到|收到了|多谢).{0,20}"
    r"(?:祝福|祝愿|生日快乐|恭喜)"
)
CELEBRATION_PATTERN = re.compile(r"(?:庆祝|庆功|庆典)")
REPORTED_PATTERN = re.compile(
    r"(?:大家|他们|朋友们|粉丝|群里).{0,16}"
    r"(?:发来|送来|表达|都在|纷纷).{0,8}(?:祝福|祝愿|恭喜)"
)
GREETING_PATTERN = re.compile(
    r"^(?:你好|您好|早上好|中午好|下午好|晚上好|晚安|"
    r"好久不见|最近怎么样)[！!。,.，~～]*$"
)

DIRECT_WISH_PATTERN = re.compile(
    r"(?:^|[，。！!~～])(?:真心|衷心|提前|也|再)?"
    r"(?:祝(?:你|您|大家|各位|我们|她|他|他们|家人|朋友|宝贝|亲)?|"
    r"愿(?:你|您|大家|她|他|我们|家人)|衷心祝愿)"
    r".{0,60}(?:快乐|幸福|健康|平安|顺利|顺遂|如意|成功|开心|"
    r"安康|好运|好梦|康复|美满|甜蜜|长寿|发财|前程|愉快)"
)
CONGRATULATION_PATTERN = re.compile(
    r"^(?:亲|亲爱的|宝贝|朋友|同学|老师|大家|各位)?"
    r"[，,:：]?(?:恭喜|祝贺)(?:你|您|大家|各位|啦|啊|呀|发财|"
    r"获得|通过|成功|顺利|考上|毕业|结婚|新婚|升职)"
)
OCCASION_PATTERN = re.compile(
    r"(?:生日|新年|春节|元旦|中秋|端午|国庆|圣诞|结婚|新婚|"
    r"毕业|节日|周年)(?:快快乐乐|快乐|愉快|大吉)"
)
SHORT_WISH_PATTERN = re.compile(
    r"(?:一路顺风|一路平安|早日康复|前程似锦|万事如意|"
    r"心想事成|平安喜乐|好运连连|节哀顺变)"
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--per-category", type=int, default=5_000)
    parser.add_argument(
        "--exclude-corpus",
        action="append",
        default=[],
        type=Path,
        help="JSONL corpus whose normalized text must not enter candidates.",
    )
    return parser.parse_args()


def normalized_text(value: str) -> str:
    # LCCC is pre-segmented with spaces between Chinese tokens.
    return "".join(str(value).split()).strip()


def fingerprint(value: str) -> str:
    return normalized_text(value).casefold()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def excluded_fingerprints(paths: list[Path]) -> set[str]:
    values: set[str] = set()
    for path in paths:
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                values.add(fingerprint(json.loads(line)["text"]))
    return values


def classify(text: str) -> tuple[str, str] | None:
    has_question = "?" in text or "？" in text
    if (
        DIRECT_WISH_PATTERN.search(text)
        and not META_PATTERN.search(text)
        and not has_question
    ):
        return "positive", "direct_wish"
    if CONGRATULATION_PATTERN.search(text) and not has_question:
        return "positive", "congratulation"
    if (
        OCCASION_PATTERN.search(text)
        and len(text) <= 80
        and not META_PATTERN.search(text)
        and not RECEIVED_PATTERN.search(text)
        and not has_question
    ):
        return "positive", "occasion_wish"
    if (
        SHORT_WISH_PATTERN.search(text)
        and len(text) <= 80
        and not re.search(r"(?:我会让|希望它|祝福语|怎么说|写着|引用)", text)
        and not has_question
    ):
        return "positive", "short_wish"

    if META_PATTERN.search(text):
        return "negative", "meta_request"
    if RECEIVED_PATTERN.search(text):
        return "negative", "received_thanks"
    if CELEBRATION_PATTERN.search(text):
        return "negative", "celebration_mention"
    if REPORTED_PATTERN.search(text):
        return "negative", "reported_blessing"
    if GREETING_PATTERN.fullmatch(text):
        return "negative", "plain_greeting"
    return None


def add_candidate(
    heaps: dict[str, list[tuple[int, str, dict]]],
    *,
    category: str,
    priority: int,
    record_id: str,
    record_value: dict,
    limit: int,
) -> None:
    heap = heaps.setdefault(category, [])
    item = (-priority, record_id, record_value)
    if len(heap) < limit:
        heapq.heappush(heap, item)
        return
    if item > heap[0]:
        heapq.heapreplace(heap, item)


def main() -> None:
    arguments = parse_arguments()
    if arguments.per_category < 100:
        raise ValueError("--per-category must be at least 100")
    excluded = excluded_fingerprints(arguments.exclude_corpus)
    seen: set[str] = set()
    heaps: dict[str, list[tuple[int, str, dict]]] = {}
    scanned_dialogues = 0
    scanned_utterances = 0
    privacy_excluded = 0
    duplicate_excluded = 0
    overlap_excluded = 0

    with zipfile.ZipFile(arguments.archive) as archive:
        with archive.open(SOURCE_SPLIT) as stream:
            for dialogue_index, dialogue in enumerate(
                ijson.items(stream, "item"),
                start=1,
            ):
                scanned_dialogues += 1
                for utterance_index, raw_text in enumerate(dialogue):
                    scanned_utterances += 1
                    text = normalized_text(raw_text)
                    if not 2 <= len(text) <= 160 or PII_PATTERN.search(text):
                        privacy_excluded += 1
                        continue
                    result = classify(text)
                    if result is None:
                        continue
                    candidate_label, boundary_category = result
                    text_key = fingerprint(text)
                    if text_key in excluded:
                        overlap_excluded += 1
                        continue
                    if text_key in seen:
                        duplicate_excluded += 1
                        continue
                    seen.add(text_key)
                    record_id = (
                        f"lccc-base-{dialogue_index:07d}-{utterance_index:02d}"
                    )
                    priority = int.from_bytes(
                        hashlib.sha256(text_key.encode()).digest()[:8],
                        "big",
                    )
                    add_candidate(
                        heaps,
                        category=f"{candidate_label}:{boundary_category}",
                        priority=priority,
                        record_id=record_id,
                        record_value={
                            "id": record_id,
                            "text": text,
                            "language": "zh-Hans",
                            "candidateLabel": candidate_label,
                            "boundaryCategory": boundary_category,
                            "reviewStatus": "unreviewed",
                            "commercialUseStatus": "research-only",
                            "sourceDataset": "LCCC-base",
                            "sourceLicense": SOURCE_LICENSE,
                            "sourceURL": SOURCE_URL,
                            "sourceSplit": "train",
                        },
                        limit=arguments.per_category,
                    )

    selected = [
        item[2]
        for heap in heaps.values()
        for item in sorted(heap, reverse=True)
    ]
    selected.sort(key=lambda value: value["id"])
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(
        "\n".join(
            json.dumps(value, ensure_ascii=False, sort_keys=True)
            for value in selected
        )
        + "\n",
        encoding="utf-8",
    )
    counts = Counter(
        f"{value['candidateLabel']}:{value['boundaryCategory']}"
        for value in selected
    )
    manifest = {
        "schemaVersion": 1,
        "policy": (
            "Research-only candidate mining. No LCCC record may enter a "
            "commercial training corpus without legal, privacy, and manual "
            "label review."
        ),
        "source": {
            "dataset": "LCCC-base",
            "url": SOURCE_URL,
            "archiveSHA256": file_sha256(arguments.archive),
            "split": SOURCE_SPLIT,
            "license": SOURCE_LICENSE,
            "provenance": "Cleaned conversations originally crawled from Weibo.",
        },
        "scannedDialogues": scanned_dialogues,
        "scannedUtterances": scanned_utterances,
        "selectedRecords": len(selected),
        "categoryCounts": dict(sorted(counts.items())),
        "excluded": {
            "privacyOrLength": privacy_excluded,
            "duplicateNormalizedText": duplicate_excluded,
            "configuredCorpusOverlap": overlap_excluded,
        },
        "outputSHA256": file_sha256(arguments.output),
    }
    arguments.manifest.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
