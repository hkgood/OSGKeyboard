#!/usr/bin/env bash
# XcodeGen 2.43 expands AppIcon.icon into a PBXGroup and adds icon.json / svg
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

icon_uuid_match = re.search(
    r"([A-F0-9]{24}) /\* AppIcon\.icon \*/ = \{",
    text,
)
if not icon_uuid_match:
    print("error: AppIcon.icon not found in project.pbxproj", file=sys.stderr)
    sys.exit(1)
icon_uuid = icon_uuid_match.group(1)

group_pattern = re.compile(
    rf"(?P<indent>\t\t){icon_uuid} /\* AppIcon\.icon \*/ = \{{\n"
    r"\t\t\tisa = PBXGroup;\n"
    r"\t\t\tchildren = \(\n"
    r"(?:\t\t\t\t[A-F0-9]{24} /\* .* \*/,\n)*"
    r"\t\t\t\);\n"
    r"\t\t\tpath = AppIcon\.icon;\n"
    r"\t\t\tsourceTree = \"<group>\";\n"
    r"\t\t\};",
    re.MULTILINE,
)

group_match = group_pattern.search(text)
if group_match:
    indent = group_match.group("indent")
    replacement = (
        f"{indent}{icon_uuid} /* AppIcon.icon */ = {{\n"
        f"\t\t\tisa = PBXFileReference;\n"
        f"\t\t\tlastKnownFileType = folder.iconcomposer.icon;\n"
        f"\t\t\tpath = AppIcon.icon;\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )
    text = text[: group_match.start()] + replacement + text[group_match.end() :]
else:
    file_ref_pattern = re.compile(
        rf"\t\t{icon_uuid} /\* AppIcon\.icon \*/ = \{{\n"
        r"\t\t\tisa = PBXFileReference;\n"
        r"\t\t\tlastKnownFileType = [^;]+;\n"
        r"\t\t\tpath = AppIcon\.icon;\n"
        r"\t\t\tsourceTree = \"<group>\";\n"
        r"\t\t\};",
        re.MULTILINE,
    )
    file_ref_match = file_ref_pattern.search(text)
    if not file_ref_match:
        print("error: AppIcon.icon entry has unexpected shape", file=sys.stderr)
        sys.exit(1)
    replacement = (
        f"\t\t{icon_uuid} /* AppIcon.icon */ = {{\n"
        f"\t\t\tisa = PBXFileReference;\n"
        f"\t\t\tlastKnownFileType = folder.iconcomposer.icon;\n"
        f"\t\t\tpath = AppIcon.icon;\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )
    text = text[: file_ref_match.start()] + replacement + text[file_ref_match.end() :]

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
text = text.replace("/* Begin PBXBuildFile section */\n", "/* Begin PBXBuildFile section */\n" + build_entry, 1)

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
