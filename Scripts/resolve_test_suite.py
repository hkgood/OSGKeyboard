#!/usr/bin/env python3
"""Resolve OSGKeyboard test suite groups/presets from Tests/suite-manifest.json.

Usage:
  resolve_test_suite.py list
  resolve_test_suite.py resolve <name> [<name> ...]
  resolve_test_suite.py validate
  resolve_test_suite.py xcodebuild-args <name> [<name> ...]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "Tests" / "suite-manifest.json"

TEST_ROOTS = [
    ROOT / "OSGKeyboardTests",
    ROOT / "OSGKeyboardExtTests",
    ROOT / "OSGKeyboardMacTests",
]


def load_manifest() -> dict:
    with MANIFEST_PATH.open(encoding="utf-8") as fh:
        return json.load(fh)


def known_names(manifest: dict) -> set[str]:
    return set(manifest["groups"]) | set(manifest["presets"])


def expand_names(manifest: dict, names: list[str]) -> list[str]:
    """Expand presets/groups into a de-duplicated ordered list of atomic groups."""
    groups = manifest["groups"]
    presets = manifest["presets"]
    ordered: list[str] = []
    seen: set[str] = set()

    def add_group(group_id: str) -> None:
        if group_id not in groups:
            raise SystemExit(f"unknown group: {group_id}")
        if group_id in seen:
            return
        seen.add(group_id)
        ordered.append(group_id)

    for name in names:
        if name in presets:
            for group_id in presets[name]["groups"]:
                add_group(group_id)
        elif name in groups:
            add_group(name)
        else:
            known = ", ".join(sorted(known_names(manifest)))
            raise SystemExit(f"unknown preset/group: {name}\nKnown: {known}")
    return ordered


def collect_tests(manifest: dict, group_ids: list[str]) -> list[str]:
    tests: list[str] = []
    seen: set[str] = set()
    for group_id in group_ids:
        for test_id in manifest["groups"][group_id]["tests"]:
            if test_id in seen:
                raise SystemExit(
                    f"duplicate test id across selected groups: {test_id}"
                )
            seen.add(test_id)
            tests.append(test_id)
    return tests


def discover_on_disk_test_classes() -> dict[str, Path]:
    """Map Target/ClassName -> swift path for *Tests.swift files (exclude helpers)."""
    found: dict[str, Path] = {}
    for root in TEST_ROOTS:
        if not root.is_dir():
            continue
        target = root.name
        for path in sorted(root.glob("*Tests.swift")):
            # Skip non-XCTest helpers that happen to end with Tests (none today).
            class_name = path.stem
            test_id = f"{target}/{class_name}"
            found[test_id] = path
    return found


def validate(manifest: dict) -> int:
    errors: list[str] = []
    warnings: list[str] = []

    # Each class appears in at most one group.
    ownership: dict[str, str] = {}
    for group_id, group in manifest["groups"].items():
        for test_id in group["tests"]:
            if test_id in ownership:
                errors.append(
                    f"duplicate membership: {test_id} in "
                    f"{ownership[test_id]} and {group_id}"
                )
            else:
                ownership[test_id] = group_id

    on_disk = discover_on_disk_test_classes()
    for test_id in sorted(on_disk):
        if test_id not in ownership:
            errors.append(f"on-disk test class missing from manifest: {test_id}")

    for test_id in sorted(ownership):
        if test_id not in on_disk:
            errors.append(f"manifest lists missing test class: {test_id}")

    # Presets must only reference known groups; no nested presets.
    for preset_id, preset in manifest["presets"].items():
        for group_id in preset["groups"]:
            if group_id not in manifest["groups"]:
                errors.append(
                    f"preset {preset_id} references unknown group: {group_id}"
                )

    # live_api may be empty by design.
    if not manifest["groups"]["live_api"]["tests"]:
        warnings.append("live_api group is empty (placeholder for future live smoke)")

    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)

    if errors:
        for err in errors:
            print(f"error: {err}", file=sys.stderr)
        return 1

    print(
        f"OK: {len(ownership)} test classes across "
        f"{len(manifest['groups'])} groups / {len(manifest['presets'])} presets"
    )
    return 0


def print_list(manifest: dict) -> None:
    print("Presets:")
    for preset_id, preset in manifest["presets"].items():
        groups = ", ".join(preset["groups"])
        print(f"  {preset_id:12}  {preset['description']}")
        print(f"               → {groups}")
    print("\nAtomic groups:")
    for group_id, group in manifest["groups"].items():
        count = len(group["tests"])
        print(
            f"  {group_id:12}  [{group['platform']}] "
            f"{count} class(es) — {group['description']}"
        )


def split_by_platform(
    manifest: dict, group_ids: list[str]
) -> tuple[list[str], list[str]]:
    ios: list[str] = []
    mac: list[str] = []
    for group_id in group_ids:
        platform = manifest["groups"][group_id]["platform"]
        tests = manifest["groups"][group_id]["tests"]
        if platform == "mac":
            mac.extend(tests)
        else:
            ios.extend(tests)
    return ios, mac


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="List presets and groups")
    sub.add_parser("validate", help="Validate manifest vs on-disk *Tests.swift")

    resolve_p = sub.add_parser(
        "resolve", help="Print expanded group ids and test identifiers"
    )
    resolve_p.add_argument("names", nargs="+")

    xcode_p = sub.add_parser(
        "xcodebuild-args",
        help="Print JSON with ios/mac -only-testing lists for the shell runner",
    )
    xcode_p.add_argument("names", nargs="+")

    args = parser.parse_args()
    manifest = load_manifest()

    if args.cmd == "list":
        print_list(manifest)
        return 0

    if args.cmd == "validate":
        return validate(manifest)

    group_ids = expand_names(manifest, args.names)
    tests = collect_tests(manifest, group_ids)

    if args.cmd == "resolve":
        print("groups:", " ".join(group_ids) if group_ids else "(none)")
        for test_id in tests:
            print(test_id)
        return 0

    if args.cmd == "xcodebuild-args":
        ios_tests, mac_tests = split_by_platform(manifest, group_ids)
        payload = {
            "groups": group_ids,
            "defaults": manifest["defaults"],
            "ios_tests": ios_tests,
            "mac_tests": mac_tests,
        }
        json.dump(payload, sys.stdout, indent=2)
        print()
        return 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
