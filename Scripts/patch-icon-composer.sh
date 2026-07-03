#!/usr/bin/env bash
# XcodeGen expands AppIcon.icon into a PBXGroup and adds icon.json / svg
# files to Copy Bundle Resources. Icon Composer bundles must be a single
# PBXFileReference (folder.iconcomposer.icon) linked to the target so actool
# compiles them together with Assets.xcassets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$ROOT/OSGKeyboard.xcodeproj/project.pbxproj"
ICON_PATH="$ROOT/OSGKeyboard/AppIcon.icon"

if [[ ! -f "$PBXPROJ" ]]; then
  echo "error: $PBXPROJ not found (run xcodegen generate first)" >&2
  exit 1
fi

if [[ ! -d "$ICON_PATH" ]]; then
  echo "error: $ICON_PATH not found" >&2
  exit 1
fi

python3 - "$PBXPROJ" <<'PY'
import re
import sys
import uuid
from pathlib import Path

pbxproj = Path(sys.argv[1])
text = pbxproj.read_text()

if "/* AppIcon.icon in Resources */" in text and "folder.iconcomposer.icon" in text:
    print("AppIcon.icon already patched")
    sys.exit(0)

icon_ref_match = re.search(
    r"(?P<indent>[ \t]*)(?P<uuid>[A-F0-9]{24}) /\* AppIcon\.icon \*/ = \{",
    text,
)
if not icon_ref_match:
    print("error: AppIcon.icon not found in project.pbxproj", file=sys.stderr)
    sys.exit(1)

icon_uuid = icon_ref_match.group("uuid")
indent = icon_ref_match.group("indent")
block_start = icon_ref_match.start()

# Brace-match the PBX object so we tolerate XcodeGen format drift.
brace_open = text.find("{", icon_ref_match.end() - 1)
depth = 0
block_end = None
for index in range(brace_open, len(text)):
    char = text[index]
    if char == "{":
        depth += 1
    elif char == "}":
        depth -= 1
        if depth == 0:
            # Include trailing semicolon when present.
            block_end = index + 1
            if block_end < len(text) and text[block_end] == ";":
                block_end += 1
            break

if block_end is None:
    print("error: could not parse AppIcon.icon PBX block", file=sys.stderr)
    sys.exit(1)

inner_indent = indent + "\t"
replacement = (
    f"{indent}{icon_uuid} /* AppIcon.icon */ = {{\n"
    f"{inner_indent}isa = PBXFileReference;\n"
    f"{inner_indent}lastKnownFileType = folder.iconcomposer.icon;\n"
    f"{inner_indent}path = AppIcon.icon;\n"
    f"{inner_indent}sourceTree = \"<group>\";\n"
    f"{indent}}};"
)
text = text[:block_start] + replacement + text[block_end:]

nested_resource_names = ("icon.json", "App Icon Template.svg")
lines = text.splitlines(keepends=True)
filtered: list[str] = []
for line in lines:
    if " in Resources */ = {isa = PBXBuildFile;" in line and any(
        name in line for name in nested_resource_names
    ):
        continue
    if " in Resources */," in line and any(name in line for name in nested_resource_names):
        continue
    filtered.append(line)
text = "".join(filtered)

build_uuid = uuid.uuid4().hex[:24].upper()
build_entry = (
    f"\t\t{build_uuid} /* AppIcon.icon in Resources */ = "
    f"{{isa = PBXBuildFile; fileRef = {icon_uuid} /* AppIcon.icon */; }};\n"
)
if f"{build_uuid} /* AppIcon.icon in Resources */" not in text:
    text = text.replace(
        "/* Begin PBXBuildFile section */\n",
        "/* Begin PBXBuildFile section */\n" + build_entry,
        1,
    )

if f"{build_uuid} /* AppIcon.icon in Resources */," not in text:
    resources_phase = re.search(
        r"\t\t(?P<phase_uuid>[A-F0-9]{24}) /\* Resources \*/ = \{\n"
        r"\t\t\tisa = PBXResourcesBuildPhase;\n"
        r"\t\t\tbuildActionMask = 2147483647;\n"
        r"\t\t\tfiles = \(\n"
        r"(?P<body>.*?Assets\.xcassets in Resources.*?\n)"
        r"(?P<rest>.*?)"
        r"\t\t\t\);\n"
        r"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        r"\t\t\};",
        text,
        re.DOTALL,
    )
    if not resources_phase:
        print("error: OSGKeyboard Resources phase not found", file=sys.stderr)
        sys.exit(1)

    insert_at = resources_phase.end("body")
    text = (
        text[:insert_at]
        + f"\t\t\t\t{build_uuid} /* AppIcon.icon in Resources */,\n"
        + text[insert_at:]
    )

pbxproj.write_text(text)
print("Patched AppIcon.icon -> folder.iconcomposer.icon (target Resources)")
PY
