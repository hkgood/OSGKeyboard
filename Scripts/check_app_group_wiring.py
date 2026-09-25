#!/usr/bin/env python3
"""Validate the App Group / Keychain wiring that the app hard-depends on.

Why this is a CI gate and not a unit test: `AppGroup.defaults`,
`AppGroupStore`, `FlowSessionBridge` and `FlowSessionPolicy` all call
`fatalError` when the App Group container is missing, by design — a silent
`.standard` fallback would desync the keyboard extension from the host app and
produce "I set my API key and nothing happens". The cost of that design is that
a single typo or a dropped entitlement turns into a keyboard that crashes on
every presentation for every user. Nothing else catches it: the failure needs a
signed build on a real device.

Checks (all static, no Xcode required):

  1. `AppGroup.identifier` in Swift matches `com.apple.security.application-groups`
     in every entitlements file that ships an App Group, and in `project.yml`.
  2. Both the iOS app and the keyboard extension declare the App Group — they
     are the two processes that must share one suite.
  3. `keychain-access-groups` lists `$(AppIdentifierPrefix)com.osgkeyboard.shared`
     FIRST in every target. `Keychain.swift` deliberately relies on the default
     access group (the first entry) instead of passing `kSecAttrAccessGroup`,
     so a reorder silently moves every stored API key to a different store.
  4. `project.yml` and the checked-in `.entitlements` files agree. XcodeGen
     regenerates the latter from the former, so a drifted `.entitlements` means
     someone hand-edited the generated output.

Run: python3 Scripts/check_app_group_wiring.py
     python3 Scripts/check_app_group_wiring.py --self-test
"""

from __future__ import annotations

import plistlib
import re
import shutil
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

APP_GROUP_SWIFT = REPO / "OSGKeyboardShared/Constants/AppGroup.swift"
PROJECT_YML = REPO / "project.yml"

# target label -> (entitlements path, must declare an App Group)
TARGETS = {
    "OSGKeyboard (iOS app)": ("OSGKeyboard/OSGKeyboard.entitlements", True),
    "OSGKeyboardExt (keyboard)": ("OSGKeyboardExt/OSGKeyboardExt.entitlements", True),
    "OSGKeyboardMac (menu bar)": ("OSGKeyboardMac/OSGKeyboardMac.entitlements", False),
}

APP_GROUP_KEY = "com.apple.security.application-groups"
KEYCHAIN_KEY = "keychain-access-groups"
EXPECTED_DEFAULT_KEYCHAIN_GROUP = "$(AppIdentifierPrefix)com.osgkeyboard.shared"

errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


def swift_app_group_identifier() -> str | None:
    text = APP_GROUP_SWIFT.read_text(encoding="utf-8")
    match = re.search(
        r'public\s+static\s+let\s+identifier\s*=\s*"([^"]+)"', text
    )
    if not match:
        fail(f"{APP_GROUP_SWIFT.relative_to(REPO)}: could not find `AppGroup.identifier`")
        return None
    return match.group(1)


def load_entitlements(path: Path) -> dict | None:
    if not path.exists():
        fail(f"{path.relative_to(REPO)}: entitlements file is missing")
        return None
    try:
        with path.open("rb") as handle:
            return plistlib.load(handle)
    except Exception as error:  # noqa: BLE001 - surfaced verbatim to the developer
        fail(f"{path.relative_to(REPO)}: not a readable plist ({error})")
        return None


def project_yml_blocks() -> dict[str, str]:
    """Split `project.yml` into one text block per `entitlements:` stanza."""
    text = PROJECT_YML.read_text(encoding="utf-8")
    blocks: dict[str, str] = {}
    for match in re.finditer(
        r"^    entitlements:\n      path:\s*(\S+)\n(.*?)(?=^    \w|\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    ):
        blocks[match.group(1)] = match.group(2)
    return blocks


def yaml_list_after(block: str, key: str) -> list[str] | None:
    """Reads a simple `key:` / `- value` list out of one entitlements stanza."""
    pattern = re.compile(rf"^\s*{re.escape(key)}:\s*\n((?:\s*(?:#.*)?\n|\s*-\s*\S.*\n)+)", re.MULTILINE)
    match = pattern.search(block)
    if not match:
        return None
    values = []
    for line in match.group(1).splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not stripped.startswith("- "):
            break
        values.append(stripped[2:].strip())
    return values


def main() -> int:
    identifier = swift_app_group_identifier()
    if identifier is None:
        print("\n".join(f"✗ {error}" for error in errors))
        return 1

    print(f"AppGroup.identifier = {identifier}")

    yml_blocks = project_yml_blocks()

    for label, (relative_path, requires_app_group) in TARGETS.items():
        before = len(errors)
        path = REPO / relative_path
        plist = load_entitlements(path)
        if plist is None:
            continue

        groups = plist.get(APP_GROUP_KEY)
        if requires_app_group:
            if not groups:
                fail(f"{label}: entitlements declare no `{APP_GROUP_KEY}`")
            elif identifier not in groups:
                fail(
                    f"{label}: entitlements declare {groups!r}, "
                    f"which does not contain AppGroup.identifier ({identifier!r})"
                )

        keychain = plist.get(KEYCHAIN_KEY)
        if not keychain:
            fail(f"{label}: entitlements declare no `{KEYCHAIN_KEY}`")
        elif keychain[0] != EXPECTED_DEFAULT_KEYCHAIN_GROUP:
            fail(
                f"{label}: `{KEYCHAIN_KEY}` starts with {keychain[0]!r}; "
                f"Keychain.swift relies on {EXPECTED_DEFAULT_KEYCHAIN_GROUP!r} "
                "being the FIRST (default) entry"
            )

        block = yml_blocks.get(relative_path)
        if block is None:
            fail(f"{label}: project.yml has no `entitlements: path: {relative_path}` stanza")
            print(f"  ✗ {label}")
            continue

        yml_groups = yaml_list_after(block, APP_GROUP_KEY)
        if requires_app_group and (yml_groups or []) != (groups or []):
            fail(
                f"{label}: project.yml `{APP_GROUP_KEY}` ({yml_groups!r}) "
                f"disagrees with the generated entitlements ({groups!r})"
            )

        yml_keychain = yaml_list_after(block, KEYCHAIN_KEY)
        if (yml_keychain or []) != (keychain or []):
            fail(
                f"{label}: project.yml `{KEYCHAIN_KEY}` ({yml_keychain!r}) "
                f"disagrees with the generated entitlements ({keychain!r})"
            )

        if len(errors) == before:
            print(f"  ✓ {label}")
        else:
            print(f"  ✗ {label}")

    if errors:
        print()
        for error in errors:
            print(f"✗ {error}")
        print(
            "\nThe App Group is a hard dependency: the keyboard extension calls "
            "fatalError() when its container is missing, so a mismatch here ships "
            "a keyboard that crashes on every presentation."
        )
        return 1

    print("\nApp Group and Keychain wiring OK.")
    return 0


def self_test() -> int:
    """Proves the guard fails on the two regressions it exists to catch.

    A checker that cannot fail is worse than no checker — it reads green
    forever while the thing it guards rots.
    """
    global REPO, APP_GROUP_SWIFT, PROJECT_YML, errors

    original_repo = REPO
    cases = [
        (
            "App Group typo in the keyboard extension",
            "OSGKeyboardExt/OSGKeyboardExt.entitlements",
            lambda text: text.replace(
                "group.com.osgkeyboard.shared", "group.com.osgkeyboard.shard"
            ),
        ),
        (
            "keychain-access-groups reordered in the iOS app",
            "OSGKeyboard/OSGKeyboard.entitlements",
            lambda text: text.replace(
                "<string>$(AppIdentifierPrefix)com.osgkeyboard.shared</string>\n"
                "\t\t<string>$(AppIdentifierPrefix)com.osgkeyboard.ios</string>",
                "<string>$(AppIdentifierPrefix)com.osgkeyboard.ios</string>\n"
                "\t\t<string>$(AppIdentifierPrefix)com.osgkeyboard.shared</string>",
            ),
        ),
    ]

    failures = 0
    for label, relative_path, mutate in cases:
        with tempfile.TemporaryDirectory() as temporary:
            sandbox = Path(temporary) / "repo"
            shutil.copytree(
                original_repo,
                sandbox,
                symlinks=True,
                ignore=shutil.ignore_patterns(
                    ".git", "build", "DerivedData", "ThirdParty", ".claude"
                ),
            )
            target = sandbox / relative_path
            mutated = mutate(target.read_text(encoding="utf-8"))
            if mutated == target.read_text(encoding="utf-8"):
                print(f"✗ self-test could not apply the mutation for: {label}")
                failures += 1
                continue
            target.write_text(mutated, encoding="utf-8")

            REPO = sandbox
            APP_GROUP_SWIFT = sandbox / "OSGKeyboardShared/Constants/AppGroup.swift"
            PROJECT_YML = sandbox / "project.yml"
            errors = []
            code = main()
            REPO = original_repo
            APP_GROUP_SWIFT = original_repo / "OSGKeyboardShared/Constants/AppGroup.swift"
            PROJECT_YML = original_repo / "project.yml"
            errors = []

            if code == 0:
                print(f"✗ self-test: guard did NOT catch: {label}")
                failures += 1
            else:
                print(f"✓ self-test: guard catches: {label}")

    return 1 if failures else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv[1:]:
        sys.exit(self_test())
    sys.exit(main())
