#!/usr/bin/env python3
"""Offline eval: verify practical and fun question behavior.

Rebuilds the production split prompt from Swift sources: practical styles use
the full core and question guard, while fun styles use formatting plus their
own personality contract. Runs the result against the configured DeepSeek
endpoint. macOS-only concerns do not apply; this is pure HTTP.

Usage: python3 scripts/polish_question_guard_eval.py [--samples N]
"""

import argparse
import json
import re
import time
import urllib.request
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT / "OSGKeyboardShared"
STYLE_DIR = SHARED / "Resources" / "PolishStyles"
COMPOSER = SHARED / "Services" / "PolishPromptComposer.swift"
KEYFILE = SHARED / "Services" / "PreconfiguredKeys.local.swift"

ENDPOINT = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-v4-flash"
FUN_STYLES = {
    "builtin.dating",
    "builtin.flex",
    "builtin.corp",
    "builtin.diba",
    "builtin.xhs",
}


def swift_block(source: str, pattern: str) -> str:
    match = re.search(pattern, source, re.S)
    if not match:
        raise SystemExit(f"pattern not found: {pattern}")
    return match.group(1)


def style_prompt(style_id: str) -> str:
    payload = json.loads((STYLE_DIR / f"{style_id}.json").read_text())
    return payload["prompt"].replace("{{FUN_SINGLE_PASS_FOUNDATION}}", "")


def shared_contract(style_id: str) -> str:
    src = COMPOSER.read_text()
    name = "chineseFunFormattingPrompt" if style_id in FUN_STYLES else "chineseCorePrompt"
    return swift_block(src, rf'internal static let {name} = """(.*?)"""')


def router_blocks(style_id: str, preserves_question: bool) -> str:
    """Mirror PromptComposer's conditional Chinese question guard."""
    if style_id in FUN_STYLES or not preserves_question:
        return ""
    src = COMPOSER.read_text()
    body = swift_block(
        src,
        r"private static func questionGuardBlock\(\s*for text: String,\s*"
        r"useChineseGuidance: Bool\s*\) -> String \{(.*?)\n    \}",
    )
    return swift_block(
        body,
        r'if useChineseGuidance \{\s*return """(.*?)"""',
    ).strip()


QUESTION_PATTERNS = [
    r"吗[\s。！!]*$|吗[，,]",
    r"怎么样|如何|哪个|哪家|哪种|什么时候|为什么|为啥",
    r"能不能|可不可以|要不要|行不行|是不是|有没有|好不好",
    r"你觉得|你们觉得|大家觉得|你看呢|求推荐|求建议",
]
OPPONENT = ("回他", "回她", "对方", "他说", "她说", "你说的", "你这叫", "大家都")


def is_question_draft(text: str) -> bool:
    if "？" in text or "?" in text:
        return True
    return any(re.search(p, text) for p in QUESTION_PATTERNS)


def preserves_question(text: str) -> bool:
    return is_question_draft(text) and not any(m in text for m in OPPONENT)


def build_prompt(style_id: str, asr: str) -> str:
    guard = preserves_question(asr)
    sections = [
        shared_contract(style_id),
        style_prompt(style_id),
        router_blocks(style_id, guard),
        f"## 原始转写\n<TRANSCRIPT>\n{asr}\n</TRANSCRIPT>",
    ]
    return "\n\n".join(section for section in sections if section)


def call(api_key: str, prompt: str, temperature: float = 0.3) -> str:
    # Mirror LLMClient: DeepSeek V4 keeps chain-of-thought on unless explicitly
    # disabled, and the app sends no max_tokens. Diverging on either makes the
    # response come back with empty content once reasoning eats the budget.
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": "你是语音输入润色引擎。只输出润色后的正文。"},
            {"role": "user", "content": prompt},
        ],
        "temperature": temperature,
        "thinking": {"type": "disabled"},
    }
    request = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        return json.loads(response.read().decode())["choices"][0]["message"]["content"].strip()


ANSWER_TOKENS = ("还行", "顺眼", "不挑", "挺好看", "不错", "可以的", "一般般", "眼光不错")


def classify(asr: str, output: str) -> str:
    if not output:
        return "empty"
    still_asks = ("？" in output) or ("?" in output) or is_question_draft(output)
    if still_asks:
        return "keeps_question"
    if any(token in output for token in ANSWER_TOKENS):
        return "ANSWERED"
    return "statement"


CASES = [
    "你觉得这个包怎么样",
    "你觉得这个方案怎么样",
    "这家店你们觉得行不行",
    "明天要不要一起去看电影",
    "这个包多少钱能拿下",
]
STYLES = ["builtin.dating", "builtin.flex", "builtin.corp", "builtin.xhs", "builtin.chat"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=2)
    args = parser.parse_args()

    api_key = re.search(r'deepseek = "([^"]+)"', KEYFILE.read_text()).group(1)

    tally: Counter[str] = Counter()
    for style_id in STYLES:
        for asr in CASES:
            prompt = build_prompt(style_id, asr)
            for _ in range(args.samples):
                try:
                    output = call(api_key, prompt)
                except Exception as error:  # noqa: BLE001 - eval script
                    output = ""
                    print(f"  request failed: {error}")
                verdict = classify(asr, output)
                tally[verdict] += 1
                flag = "  <<< ANSWERED" if verdict == "ANSWERED" else ""
                print(f"[{style_id:16}] {asr} -> {output!r}{flag}")
                time.sleep(0.1)

    print("\nSummary:", dict(tally))
    print("ANSWERED count:", tally["ANSWERED"])


if __name__ == "__main__":
    main()
