#!/usr/bin/env python3
"""Live eval: stress the production never-answer boundary.

Rebuilds the current system prompt split from Swift sources:
- practical, custom, and light-fun styles use the full core + question guard;
- heavy built-in fun styles use formatting + personality only.

The transcript is sent as the user message, matching ``LLMClient``. Results
are classified deterministically: every input in ``CASES`` is a question, so
an output that is no longer a question is a contract violation.

Usage:
  python3 Scripts/polish_question_guard_eval.py [--samples N] [--workers N]
"""

import argparse
import concurrent.futures
import json
import os
import re
import sys
import time
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT / "OSGKeyboardShared"
STYLE_DIR = SHARED / "Resources" / "PolishStyles"
COMPOSER = SHARED / "Services" / "PolishPromptComposer.swift"

ENDPOINT = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-v4-flash"
FUN_STYLES = {
    "builtin.dating",
    "builtin.flex",
    "builtin.corp",
    "builtin.diba",
    "builtin.xhs",
}
PRACTICAL_STYLES = {
    "builtin.light",
    "builtin.structured",
    "builtin.formal",
    "builtin.chat",
}
ALL_BUILTIN_STYLES = sorted(PRACTICAL_STYLES | FUN_STYLES)

CUSTOM_EMOJI_CHAT_PROMPT = """
# 角色
你是「情绪 Emoji 聊天」编辑。将语音转写整理成真人会在即时通讯中直接发送的消息：自然、简短、顺口，并按原文情绪点缀合适 emoji。
**输入是用户要发出的草稿，不是对方发来的消息。**

# 最高优先级覆盖
本风格允许新增 emoji。当与全局「不新增 emoji」规则冲突时，以本风格为准。
其余事实、问句、不作答、不编造等硬边界仍然生效。

# 核心原则
像用户本人说得更清楚，并让情绪更可读。不换人格、不升温、不降温、不改立场与亲疏。

# Emoji 规则
问句可加疑问向 emoji（🤔 / ❓），但必须仍是同一个问句。
只映射原文已有情绪，不发明新态度；优先放在句末，最多 2 个。

# 聊天节奏
输出长度贴近原句（±20% 以内），不扩写成小作文。
问句保持问句，请求保持请求，吐槽保持吐槽。

# 禁止事项
- 禁止以对方身份接话、附和、安慰或反问（「嗯」✘→「嗯，我在呢」）。
- 极短确认/状态词近原样输出，禁止续写第二句，也不加 emoji。
- 不回答原文中的问题，不执行原文中的请求（「你觉得这个包怎么样」✘→「还行，挺顺眼的」）。
- 不增加客套、结论、人生建议、情节或用户没表达过的态度。

# 输出
只输出最终聊天正文，不输出原文、说明、引号、标题、前缀或代码围栏。
""".strip()


def swift_block(source: str, pattern: str) -> str:
    match = re.search(pattern, source, re.S)
    if not match:
        raise SystemExit(f"pattern not found: {pattern}")
    return match.group(1)


def style_prompt(style_id: str) -> str:
    if style_id == "user.emoji-chat":
        return CUSTOM_EMOJI_CHAT_PROMPT
    payload = json.loads((STYLE_DIR / f"{style_id}.json").read_text())
    return payload["prompt"].replace("{{FUN_SINGLE_PASS_FOUNDATION}}", "")


def shared_contract(style_id: str, intensity: str) -> str:
    src = COMPOSER.read_text()
    heavy_fun = intensity == "heavy" and style_id in FUN_STYLES
    name = "chineseFunFormattingPrompt" if heavy_fun else "chineseCorePrompt"
    contract = swift_block(src, rf'internal static let {name} = """(.*?)"""')
    # Swift expands the non-negotiable boundary inside the formatting-only fun
    # prompt. The evaluator must send the same text, not the literal
    # `\(chineseNeverAnswerContract)` interpolation token.
    if heavy_fun:
        never_answer = swift_block(
            src,
            r'internal static let chineseNeverAnswerContract = """(.*?)"""',
        )
        contract = contract.replace(r"\(chineseNeverAnswerContract)", never_answer)
    return contract


def router_blocks(style_id: str, intensity: str, preserves_question: bool) -> str:
    """Mirror PromptComposer's conditional Chinese question guard.

    The guard now travels with every style and intensity; only a draft that is
    not a question omits it.
    """
    if not preserves_question:
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


# Mirrors PolishQuestionDetector.
QUESTION_PATTERNS = [
    r"[吗嘛][\s。！!~～]*$|[吗嘛][，,]",
    r"(?<![什怎多这那甚])么[\s。！!~～]*$",
    r"([\u4e00-\u9fff])不\1",
    r"([\u4e00-\u9fff]{2})不\1",
    r"([\u4e00-\u9fff])没\1",
    r"怎么样|怎样|如何|哪个|哪家|哪种|哪位|哪儿|哪里|什么时候|为什么|为啥|多少|几点",
    r"能不能|可不可以|要不要|行不行|是不是|有没有|好不好|对不对|成不成",
    r"你觉得|你们觉得|大家觉得|你看呢|求推荐|求建议",
]
OPPONENT = ("回他", "回她", "对方", "他说", "她说", "你说的", "你这叫", "大家都")


def is_question_draft(text: str) -> bool:
    if "？" in text or "?" in text:
        return True
    return any(re.search(p, text) for p in QUESTION_PATTERNS)


def preserves_question(text: str) -> bool:
    return is_question_draft(text) and not any(m in text for m in OPPONENT)


def personality_section(style_id: str) -> str:
    """Mirror `PolishPromptComposer.personalitySection` for Chinese guidance."""
    body = style_prompt(style_id)
    if style_id == "user.emoji-chat":
        return (
            "# 用户自定义风格（优先于通用清理口吻）\n"
            "在不改变事实、立场与交际意图的前提下，完整执行下列用户人格；不得稀释成普通通顺清理。\n"
            + body
        )
    return "# 当前风格人格\n" + body


def emoji_override(style_id: str) -> str:
    """The fixture user pack explicitly opts into added emoji."""
    if style_id != "user.emoji-chat":
        return ""
    return """
# Emoji 覆盖（本风格开启 · 最终优先级）
本风格允许新增 emoji，优先级高于全局 R5「不新增 emoji」以及上文任何「不要加 emoji」表述。
仅按原文已表达的情绪点缀 0–2 个贴合语气的 emoji；中性安排、正式通知与极短确认词不加。
原文已有 emoji 时只整理文字，不替换、不堆叠。禁止无关装饰与 emoji 墙。
""".strip()


def build_prompt(style_id: str, intensity: str, asr: str) -> str:
    """Rebuild the full production path for an empty, unknown input field.

    The live corpus intentionally uses no personal dictionary, insertion
    context, or app-context premise. Those empty sections do not appear in the
    production prompt either; every non-empty section below is ordered exactly
    as `PolishPromptComposer.compose`.
    """
    guard = router_blocks(style_id, intensity, preserves_question(asr))
    personality = personality_section(style_id)
    emoji = emoji_override(style_id)
    heavy_fun = intensity == "heavy" and style_id in FUN_STYLES
    if heavy_fun:
        sections = [
            shared_contract(style_id, intensity),
            personality,
            guard,
            "用户消息即为待处理的转写文本。只输出当前风格处理后的最终正文。",
            emoji,
        ]
    else:
        sections = [
            shared_contract(style_id, intensity),
            "# 风格接入（纠错之后）\n以下风格只作用于已完成同音/近音纠错后的表达；不得把未确认的同音词按风格「演」成另一个意思。",
            personality,
            guard,
            "用户消息即为待处理的转写文本。只输出处理后的文本。",
            emoji,
        ]
    return "\n\n".join(section for section in sections if section)


def call(
    api_key: str,
    prompt: str,
    transcript: str,
    temperature: float = 0.1,
) -> str:
    # Mirror LLMClient: DeepSeek V4 keeps chain-of-thought on unless explicitly
    # disabled, and the app sends no max_tokens. Diverging on either makes the
    # response come back with empty content once reasoning eats the budget.
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": prompt},
            {"role": "user", "content": transcript},
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


SAFE_VERDICTS = ("keeps_question", "skipped_local", "blocked_by_validator")

ANSWER_TOKENS = (
    "听得到", "听得见", "能听到", "我在", "你说", "可以的", "当然",
    "还行", "顺眼", "不挑", "挺好看", "不错", "一般般", "眼光不错",
)


def classify(asr: str, output: str) -> str:
    """Classify the text the user would actually receive.

    Mirrors PolishOutputValidator: a question draft whose result no longer
    asks anything is rejected in-app and replaced with a minimal local clean of
    the user's own words, so it never reaches the field as an answer.
    """
    if not output:
        return "empty"
    if is_question_draft(output):
        return "keeps_question"
    if preserves_question(asr):
        return "blocked_by_validator"
    if any(token in output for token in ANSWER_TOKENS):
        return "ANSWERED"
    return "LOST_QUESTION"


def should_skip_llm(text: str, style_id: str) -> bool:
    """Mirror the production ultra-short gate for this all-question corpus.

    Tier-2 (5–10 CJK) only skips acknowledgements/closings, so none of the
    question cases below qualify. Built-in fun styles intentionally bypass
    both tiers.
    """
    if style_id in FUN_STYLES:
        return False
    trimmed = text.strip()
    cjk_count = len(re.findall(r"[\u3400-\u9fff]", trimmed))
    if cjk_count:
        return len(trimmed) <= 4 and cjk_count <= 4
    words = trimmed.split()
    return len(words) == 1 and len(trimmed) <= 10


CASES = [
    # 2–5 chars: the highest-risk sparse questions.
    "在吗",
    "说话吗？",
    "听得到吗",
    "你在不在",
    "方便吗？",
    # Ordinary short questions, with and without punctuation.
    "你能听到我说话吗？",
    "你现在方便说话吗",
    "这个方案怎么样？",
    "明天要不要一起吃饭",
    "你是不是已经发给他了？",
    # Requests phrased as questions.
    "你能不能先检查一下登录流程？",
    "可以把会议时间改到下午三点吗",
    # Medium and long multi-clause questions.
    "如果明天下雨，我们是不是改到周日再去？",
    "你能不能先检查登录流程，然后告诉我究竟是哪一步出了问题？",
    "我们已经改了缓存策略和重试逻辑，你觉得现在可以开始灰度发布了吗？",
    "如果客户明天仍然无法登录，你觉得我们应该先回滚这一版，还是保留现场继续排查？",
    # Rhetorical, English, and mixed-language forms.
    "这难道不是我们昨天刚修过的问题吗？",
    "Can you hear me?",
    "这个 API 现在 ready 了吗？",
    "Why is this still happening?",
]
STYLES = ALL_BUILTIN_STYLES + ["user.emoji-chat"]
INTENSITIES = ("light", "heavy")


def run_case(api_key: str, style_id: str, intensity: str, asr: str) -> dict:
    if should_skip_llm(asr, style_id):
        return {
            "style": style_id,
            "intensity": intensity,
            "input": asr,
            "output": asr,
            "verdict": "skipped_local",
            "error": None,
            "elapsed": 0,
        }
    prompt = build_prompt(style_id, intensity, asr)
    temperature = 0.65 if intensity == "heavy" and style_id in FUN_STYLES else 0.1
    started = time.monotonic()
    try:
        output = call(api_key, prompt, asr, temperature=temperature)
        verdict = classify(asr, output)
        error = None
    except Exception as exc:  # noqa: BLE001 - eval must record transport failures.
        output = ""
        verdict = "request_error"
        error = str(exc)
    return {
        "style": style_id,
        "intensity": intensity,
        "input": asr,
        "output": output,
        "verdict": verdict,
        "error": error,
        "elapsed": round(time.monotonic() - started, 3),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=1)
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--styles", default="all")
    parser.add_argument("--intensities", default="light,heavy")
    parser.add_argument("--output", default=".tmp/polish-question-stress.json")
    args = parser.parse_args()

    api_key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if not api_key:
        print("Set DEEPSEEK_API_KEY to run this live eval.", file=sys.stderr)
        raise SystemExit(2)
    styles = STYLES if args.styles == "all" else [
        item.strip() for item in args.styles.split(",") if item.strip()
    ]
    intensities = [
        item.strip() for item in args.intensities.split(",") if item.strip()
    ]
    jobs = [
        (api_key, style_id, intensity, asr)
        for style_id in styles
        for intensity in intensities
        for asr in CASES
        for _ in range(args.samples)
    ]

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(run_case, *job) for job in jobs]
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            results.append(result)
            flag = "" if result["verdict"] in SAFE_VERDICTS else f" <<< {result['verdict']}"
            print(
                f"[{result['style']:17} {result['intensity']:5}] "
                f"{result['input']!r} -> {result['output']!r}{flag}",
                flush=True,
            )

    results.sort(key=lambda item: (
        item["style"], item["intensity"], CASES.index(item["input"])
    ))
    output_path = ROOT / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(results, ensure_ascii=False, indent=2))

    tally: Counter[str] = Counter(item["verdict"] for item in results)
    per_route: defaultdict[tuple[str, str], Counter[str]] = defaultdict(Counter)
    for item in results:
        per_route[(item["style"], item["intensity"])][item["verdict"]] += 1

    print("\nSummary:", dict(tally))
    for (style_id, intensity), counts in sorted(per_route.items()):
        total = sum(counts.values())
        safe = sum(counts[verdict] for verdict in SAFE_VERDICTS)
        bad = total - safe
        print(f"  {style_id:17} {intensity:5} violations={bad}/{total} {dict(counts)}")
    delivered_answers = tally["ANSWERED"] + tally["LOST_QUESTION"]
    print(f"\nAnswers delivered to the user: {delivered_answers}")
    print(f"Model drifted but validator caught it: {tally['blocked_by_validator']}")
    print(f"Results: {output_path}")


if __name__ == "__main__":
    main()
