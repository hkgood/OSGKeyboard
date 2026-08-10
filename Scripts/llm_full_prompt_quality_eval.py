#!/usr/bin/env python3
"""Replay complete production prompts against an explicit quality corpus.

This is deliberately separate from XCTest:
- XCTest protects deterministic prompt assembly and local fallbacks.
- this script sends the *complete* system prompt and complete user payload to
  the configured LLM, then records objective contract checks plus every output
  for human quality review.

It covers dictation polish: the user message is the user's outbound draft.
Questions must stay questions and never be answered.

Usage:
  python3 Scripts/llm_full_prompt_quality_eval.py --profile smoke
  python3 Scripts/llm_full_prompt_quality_eval.py --profile full --samples 2
"""

import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
import re
import time
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Scripts" / "fixtures" / "llm_quality_matrix.json"
QUESTION_EVAL = ROOT / "Scripts" / "polish_question_guard_eval.py"


def load_question_eval():
    spec = importlib.util.spec_from_file_location("question_eval", QUESTION_EVAL)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Cannot load {QUESTION_EVAL}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


Q = load_question_eval()


def is_english(text: str) -> bool:
    letters = len(re.findall(r"[A-Za-z]", text))
    cjk = len(re.findall(r"[\u3400-\u9fff]", text))
    return letters >= 12 and letters > cjk * 2


def objective_checks(case: dict, output: str, protocol: str) -> list[str]:
    """Checks only facts we can evaluate deterministically.

    Passing these checks means “no detected contract breach”, not “excellent
    writing”. The report deliberately keeps the raw output for a Cursor-agent
    and human sample review.
    """
    failures: list[str] = []
    normalized = output.strip()
    if not normalized:
        return ["empty_output"]
    if case.get("must_remain_question") and not Q.is_question_draft(normalized):
        failures.append("question_lost_or_answered")
    for token in case.get("required_all", []):
        if token not in normalized:
            failures.append(f"missing:{token}")
    for alternatives in case.get("required_one_of", []):
        if not any(token in normalized for token in alternatives):
            failures.append("missing_one_of:" + "|".join(alternatives))
    if case.get("required_any") and not any(
        token in normalized for token in case["required_any"]
    ):
        failures.append("missing_any:" + "|".join(case["required_any"]))
    for token in case.get("forbidden_any", []):
        if token in normalized:
            failures.append(f"forbidden:{token}")
    for token in case.get("forbidden_exact", []):
        if normalized.casefold() == token.casefold():
            failures.append(f"forbidden_exact:{token}")
    if pattern := case.get("must_match_regex"):
        if not re.search(pattern, normalized, re.DOTALL):
            failures.append(f"format_mismatch:{pattern}")
    if case.get("language") == "en":
        if not is_english(normalized):
            failures.append("expected_english_output")
        if case.get("target_language_only") and re.search(r"[\u3400-\u9fff]", normalized):
            failures.append("intermediate_non_english_output")
    return failures


def prompt_fingerprint(system: str, user: str) -> dict:
    return {
        "system_chars": len(system),
        "user_chars": len(user),
        "system_sha256": hashlib.sha256(system.encode()).hexdigest()[:16],
        "user_sha256": hashlib.sha256(user.encode()).hexdigest()[:16],
    }


def normal_job(case: dict, style_id: str, intensity: str) -> dict:
    text = case["input"]
    system = Q.build_prompt(style_id, intensity, text)
    # This mirrors normal dictation after the local skip gate. Skip outputs are
    # recorded instead of being sent, just like PolishingService.
    if Q.should_skip_llm(text, style_id):
        output = text
        error = None
        elapsed = 0.0
        source = "local_skip"
    else:
        started = time.monotonic()
        try:
            temperature = 0.65 if intensity == "heavy" and style_id in Q.FUN_STYLES else 0.1
            output = Q.call(Q.api_key, system, text, temperature=temperature)
            error = None
        except Exception as exc:  # noqa: BLE001
            output = ""
            error = str(exc)
        elapsed = round(time.monotonic() - started, 3)
        source = "llm"
    return {
        "protocol": "normal_polish",
        "case_id": case["id"],
        "style": style_id,
        "intensity": intensity,
        "input": text,
        "system_prompt": system,
        "user_payload": text,
        "output": output,
        "source": source,
        "checks": objective_checks(case, output, "normal"),
        "error": error,
        "elapsed_seconds": elapsed,
        "prompt_fingerprint": prompt_fingerprint(system, text),
    }


def print_summary(results: list[dict]) -> None:
    by_protocol: defaultdict[str, Counter] = defaultdict(Counter)
    by_case: defaultdict[str, Counter] = defaultdict(Counter)
    for result in results:
        status = "pass" if not result["checks"] and not result["error"] else "fail"
        by_protocol[result["protocol"]][status] += 1
        by_case[f"{result['protocol']}:{result['case_id']}"][status] += 1

    print("\nObjective contract summary:")
    for protocol, counts in sorted(by_protocol.items()):
        print(f"  {protocol}: pass={counts['pass']} fail={counts['fail']}")
    print("\nCases with a detected breach:")
    failures = 0
    for result in results:
        if result["checks"] or result["error"]:
            failures += 1
            reason = result["checks"] or [f"request_error:{result['error']}"]
            print(
                f"  [{result['protocol']} | {result['style']} | {result['case_id']}] "
                f"{', '.join(reason)}\n"
                f"    output={result['output']!r}"
            )
    if not failures:
        print("  none")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", choices=("smoke", "full"), default="smoke")
    parser.add_argument("--samples", type=int, default=1)
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--output", default=".tmp/llm-full-prompt-quality.json")
    args = parser.parse_args()

    fixtures = json.loads(FIXTURES.read_text())
    key_match = re.search(r'deepseek = "([^"]+)"', Q.KEYFILE.read_text())
    if not key_match:
        raise SystemExit("No DeepSeek key configured for live evaluation.")
    Q.api_key = key_match.group(1)

    if args.profile == "smoke":
        normal_styles = ("builtin.chat", "builtin.dating", "user.emoji-chat")
        normal_cases = fixtures["normal_polish"][:8]
    else:
        normal_styles = tuple(Q.STYLES)
        normal_cases = fixtures["normal_polish"]

    jobs = []
    for _ in range(args.samples):
        for case in normal_cases:
            for style_id in normal_styles:
                for intensity in ("light", "heavy"):
                    jobs.append(("normal", case, style_id, intensity))

    print(
        f"Running {len(jobs)} requests: profile={args.profile}, samples={args.samples}; "
        "each request includes the complete production-shaped system and user prompt."
    )
    results: list[dict] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = []
        for protocol, case, style_id, intensity in jobs:
            futures.append(pool.submit(normal_job, case, style_id, intensity))
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            results.append(result)
            flag = "PASS" if not result["checks"] and not result["error"] else "FAIL"
            print(
                f"[{flag:4}] {result['protocol']:17} {result['style']:16} "
                f"{result['case_id']} -> {result['output']!r}",
                flush=True,
            )

    results.sort(key=lambda item: (
        item["protocol"], item["case_id"], item["style"], item.get("intensity", "")
    ))
    destination = ROOT / args.output
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(results, ensure_ascii=False, indent=2))
    print_summary(results)
    print(f"\nFull prompts, payloads, outputs, and fingerprints: {destination}")


if __name__ == "__main__":
    main()
