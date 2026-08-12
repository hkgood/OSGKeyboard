#!/usr/bin/env python3
"""Reject obvious credential and user-text interpolation in Swift logs."""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
EXCLUDED_PARTS = {
    ".build",
    ".git",
    "Carthage",
    "DerivedData",
    "OSGKeyboardExtTests",
    "OSGKeyboardMacTests",
    "OSGKeyboardTests",
    "Pods",
    "Scripts",
    "Tests",
    "ThirdParty",
    "Vendor",
    "build",
}
LOG_START = re.compile(
    r"""
    (?:
        \bprint\s*\(
        |\bOSGLog(?:\.\w+)+\s*\(
        |\bOSGDiag\.log\s*\(
        |\bFlowDiagnostics\.log\s*\(
        |\bFlowTrace\.(?:capture|pipeline|asr|polish|keyboard|warn)\s*\(
        |\bdebug\s*\(
        |\b(?:log|logger)\.(?:debug|info|notice|warning|error|fault)\s*\(
    )
    """,
    re.VERBOSE,
)
SENSITIVE_IDENTIFIER = re.compile(
    r"""
    \b(?:
        apiKey
        |asrApiKey
        |Authorization
        |httpBody
        |bodyText
        |responseBody
        |result\.text
        |error\.message
        |(?:raw|final|full|partial)?Transcript
        |(?:system|user|raw)?Prompt
        |clipboard(?:Text|Content)?
    )\b
    """,
    re.IGNORECASE | re.VERBOSE,
)
INTERPOLATION = re.compile(r"\\\((.*?)\)", re.DOTALL)
SENSITIVE_LABEL = re.compile(
    r"\b(?:apiKey|Authorization|httpBody|bodyText|responseBody|transcript|prompt|clipboard)\s*[:=]",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Violation:
    path: Path
    line: int
    message: str


def swift_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for current, directories, names in os.walk(root):
        directories[:] = [
            directory
            for directory in directories
            if directory not in EXCLUDED_PARTS
            and not directory.endswith("Tests")
            and not directory.startswith(".")
        ]
        current_path = Path(current)
        files.extend(current_path / name for name in names if name.endswith(".swift"))
    return sorted(files)


def line_number(source: str, offset: int) -> int:
    return source.count("\n", 0, offset) + 1


def extract_call(source: str, start: int) -> str:
    depth = 0
    saw_open = False
    for index in range(start, min(len(source), start + 16_384)):
        character = source[index]
        if character == "(":
            depth += 1
            saw_open = True
        elif character == ")" and saw_open:
            depth -= 1
            if depth == 0:
                return source[start : index + 1]
    return source[start : min(len(source), start + 16_384)]


def extract_transcript_function(source: str) -> tuple[int, str] | None:
    match = re.search(r"\bfunc\s+transcript\s*\(", source)
    if match is None:
        return None
    brace = source.find("{", match.end())
    if brace < 0:
        return None
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return match.start(), source[brace : index + 1]
    return match.start(), source[brace:]


def scan_file(path: Path) -> list[Violation]:
    source = path.read_text(encoding="utf-8")
    violations: list[Violation] = []

    for match in LOG_START.finditer(source):
        line_start = source.rfind("\n", 0, match.start()) + 1
        if source[line_start : match.start()].lstrip().startswith("//"):
            continue
        call = extract_call(source, match.start())
        expressions = INTERPOLATION.findall(call)
        exposed_expressions = [
            re.sub(r"\b(?:result\.text\?|error\.message)\.count\b", "", expression)
            for expression in expressions
        ]
        if any(SENSITIVE_IDENTIFIER.search(expression) for expression in exposed_expressions):
            violations.append(
                Violation(
                    path,
                    line_number(source, match.start()),
                    "sensitive identifier interpolated into a log",
                )
            )
            continue
        if SENSITIVE_LABEL.search(call) and (expressions or "+" in call):
            violations.append(
                Violation(
                    path,
                    line_number(source, match.start()),
                    "sensitive log label may expose user or credential text",
                )
            )
            continue
        opening = call.find("(")
        direct_argument = call[opening + 1 :] if opening >= 0 else call
        if SENSITIVE_IDENTIFIER.match(direct_argument.lstrip()):
            violations.append(
                Violation(
                    path,
                    line_number(source, match.start()),
                    "sensitive value passed directly to a log",
                )
            )
            continue
        if "CloudASR" in path.parts and re.search(
            r"\\\([^)]*\.localizedDescription\b", call
        ):
            violations.append(
                Violation(
                    path,
                    line_number(source, match.start()),
                    "cloud ASR log exposes localized error detail",
                )
            )

    if path.name == "FlowTrace.swift" or "enum FlowTrace" in source:
        transcript_function = extract_transcript_function(source)
        if transcript_function is not None:
            offset, body = transcript_function
            if re.search(r"\\\(\s*text\b", body):
                violations.append(
                    Violation(
                        path,
                        line_number(source, offset),
                        "FlowTrace.transcript must not interpolate text",
                    )
                )

    return violations


def scan(paths: list[Path]) -> list[Violation]:
    violations: list[Violation] = []
    for path in paths:
        violations.extend(scan_file(path))
    return violations


def run_self_test() -> bool:
    fixture_root = ROOT / "Scripts"
    safe = fixture_root / "sensitive_logs_safe.fixture.swift"
    unsafe = fixture_root / "sensitive_logs_unsafe.fixture.swift"
    safe_violations = scan([safe])
    unsafe_violations = scan([unsafe])
    if safe_violations:
        print("self-test failed: safe fixture was rejected", file=sys.stderr)
        return False
    if len(unsafe_violations) < 4:
        print("self-test failed: unsafe fixture was not fully rejected", file=sys.stderr)
        return False
    print("Sensitive-log gate self-test passed.")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="verify the scanner against safe and unsafe fixtures",
    )
    args = parser.parse_args()

    if args.self_test:
        return 0 if run_self_test() else 1

    violations = scan(swift_files(ROOT))
    if violations:
        for violation in violations:
            relative = violation.path.relative_to(ROOT)
            print(f"{relative}:{violation.line}: {violation.message}", file=sys.stderr)
        print(f"Sensitive-log gate failed with {len(violations)} violation(s).", file=sys.stderr)
        return 1
    print("Sensitive-log gate passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
