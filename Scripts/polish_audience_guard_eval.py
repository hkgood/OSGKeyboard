#!/usr/bin/env python3
"""Offline eval: RED Note polish must not invent an audience.

Drafts that never address a crowd must come back without 姐妹们 / 集美们 /
大家 style greetings or comment CTAs. Drafts that already speak to a group may
keep that audience.

Usage: python3 scripts/polish_audience_guard_eval.py [--samples N]
"""

import argparse
import re
import time
from collections import Counter, defaultdict
from pathlib import Path

import polish_question_guard_eval as base

AUDIENCE_TOKENS = (
    "姐妹们",
    "集美们",
    "集美",
    "宝子们",
    "家人们",
    "各位",
    "大家好",
    "姐妹",
    "你们",
    "大家",
)
CTA_TOKENS = ("评论区", "蹲一个", "蹲个", "在线等", "求反馈", "安利我", "宝藏吗")

# (draft, addresses_a_group)
CASES = [
    ("我最近开始早睡感觉皮肤状态好了很多心情也好了", False),
    ("这家店排队太久了味道一般不推荐", False),
    ("这个防晒霜我用了挺好的不油夏天能用", False),
    ("你觉得这个包怎么样", False),
    ("今天这个会开得有点久但结论还算清楚", False),
    ("这个防晒霜我用了感觉挺好的不油夏天用可以推荐给你们", True),
    ("姐妹们这家店到底行不行求个真实反馈", True),
]

NEGATIVE_HOOKS = ("避雷", "踩坑", "翻车", "劝退", "别买", "会谢")
# Drafts whose stance is positive; a negative hook would flip their meaning.
POSITIVE_DRAFTS = {
    "我最近开始早睡感觉皮肤状态好了很多心情也好了",
    "这个防晒霜我用了挺好的不油夏天能用",
    "这个防晒霜我用了感觉挺好的不油夏天用可以推荐给你们",
}


def flips_stance(draft: str, output: str) -> bool:
    """A negative hook on a positive draft flips its meaning.

    Only the opening line counts: mentioning 踩坑 later while inviting other
    people's experiences does not reverse the author's own stance.
    """
    if draft not in POSITIVE_DRAFTS:
        return False
    hook = output.strip().splitlines()[0] if output.strip() else ""
    return any(negative in hook for negative in NEGATIVE_HOOKS)


def has_audience(text: str) -> bool:
    return any(token in text for token in AUDIENCE_TOKENS)


def has_cta(text: str) -> bool:
    return any(token in text for token in CTA_TOKENS)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=2)
    parser.add_argument("--levels", default="light,medium,heavy")
    args = parser.parse_args()

    api_key = re.search(r'deepseek = "([^"]+)"', Path(base.KEYFILE).read_text()).group(1)
    levels = [level.strip() for level in args.levels.split(",") if level.strip()]

    tally: Counter[str] = Counter()
    per_level: defaultdict[str, Counter] = defaultdict(Counter)
    violations = []

    for level in levels:
        for draft, group in CASES:
            prompt = base.build_prompt("builtin.xhs", level, draft)
            for _ in range(args.samples):
                try:
                    temperature = 0.65 if level == "heavy" else 0.1
                    output = base.call(api_key, prompt, draft, temperature=temperature)
                except Exception as error:  # noqa: BLE001 - eval script
                    print(f"  request failed: {error}")
                    continue

                injected = (not group) and (has_audience(output) or has_cta(output))
                flipped = flips_stance(draft, output)
                if injected:
                    verdict = "INVENTED_AUDIENCE"
                elif flipped:
                    verdict = "FLIPPED_STANCE"
                else:
                    verdict = "ok"
                tally[verdict] += 1
                per_level[level][verdict] += 1
                if verdict != "ok":
                    violations.append((level, verdict, draft, output))
                flag = "" if verdict == "ok" else f"  <<< {verdict}"
                print(f"[{level:6}] {draft[:14]}… -> {output!r}{flag}")
                time.sleep(0.1)

    print("\nSummary:", dict(tally))
    for level in levels:
        counts = per_level[level]
        total = sum(counts.values())
        print(f"  {level:6} ok={counts['ok']}/{total}")
    if violations:
        print("\nViolations:")
        for level, verdict, draft, output in violations:
            print(f"  [{level}][{verdict}] {draft} => {output!r}")


if __name__ == "__main__":
    main()
