#!/usr/bin/env bash
# Fallback patch when XcodeGen does not emit folder.iconcomposer.icon for
# AppIcon.icon (older XcodeGen) or uses an unexpected PBX layout.
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

PATCH_VERSION = 3

def extract_block(text: str, brace_open: int) -> tuple[str, int] | None:
    depth = 0
    for index in range(brace_open, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                block_end = index + 1
                if block_end < len(text) and text[block_end] == ";":
                    block_end += 1
                return text[brace_open:block_end], block_end
    return None

def is_valid_icon_setup(text: str) -> bool:
    return (
        "folder.iconcomposer.icon" in text
        and bool(re.search(r"path = (?:OSGKeyboard/)?AppIcon\.icon;", text))
        and bool(re.search(r"AppIcon\.icon in Resources", text))
    )

pbxproj = Path(sys.argv[1])
text = pbxproj.read_text()

if is_valid_icon_setup(text):
    print(f"AppIcon.icon already configured (patch v{PATCH_VERSION})")
    sys.exit(0)

icon_ref_match = None
for pattern in (
    r"(?P<indent>[ \t]*)(?P<uuid>[A-F0-9]{24}) /\* AppIcon\.icon \*/ = \{",
    r"(?P<indent>[ \t]*)(?P<uuid>[A-F0-9]{24}) /\* OSGKeyboard/AppIcon\.icon \*/ = \{",
):
    icon_ref_match = re.search(pattern, text)
    if icon_ref_match:
        break

if not icon_ref_match:
    for match in re.finditer(
        r"(?P<indent>[ \t]*)(?P<uuid>[A-F0-9]{24}) /\* (?P<comment>[^*]+) \*/ = \{",
        text,
    ):
        brace_open = text.find("{", match.end() - 1)
        block = extract_block(text, brace_open)
        if block and re.search(r"path = (?:OSGKeyboard/)?AppIcon\.icon;", block[0]):
            icon_ref_match = match
            break

if not icon_ref_match:
    print(
        f"error: AppIcon.icon not found in project.pbxproj (patch v{PATCH_VERSION}).\n"
        "Run: git pull origin main && brew upgrade xcodegen\n"
        "Then re-run ./Scripts/generate-xcodeproj.sh",
        file=sys.stderr,
    )
    sys.exit(1)

icon_uuid = icon_ref_match.group("uuid")
indent = icon_ref_match.group("indent")
block_start = icon_ref_match.start()
brace_open = text.find("{", icon_ref_match.end() - 1)
parsed = extract_block(text, brace_open)
if not parsed:
    print(
        f"error: could not parse AppIcon.icon PBX block (patch v{PATCH_VERSION})",
        file=sys.stderr,
    )
    sys.exit(1)
_, block_end = parsed

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

if not re.search(r"AppIcon\.icon in Resources", text):
    build_uuid = uuid.uuid4().hex[:24].upper()
    build_entry = (
        f"\t\t{build_uuid} /* AppIcon.icon in Resources */ = "
        f"{{isa = PBXBuildFile; fileRef = {icon_uuid} /* AppIcon.icon */; }};\n"
    )
    text = text.replace(
        "/* Begin PBXBuildFile section */\n",
        "/* Begin PBXBuildFile section */\n" + build_entry,
        1,
    )

    resources_phase = re.search(
        r"\t\t(?P<phase_uuid>[A-F0-9]{24}) /\* Resources \*/ = \{\n"
        r"\t\t\tisa = PBXResourcesBuildPhase;\n"
        r"\t\t\tbuildActionMask = 2147483647;\n"
        r"\t\t\tfiles = \(\n"
        r"(?P<body>.*? in Resources.*?\n)"
        r"(?P<rest>.*?)"
        r"\t\t\t\);\n"
        r"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        r"\t\t\};",
        text,
        re.DOTALL,
    )
    if not resources_phase:
        print(
            f"error: OSGKeyboard Resources phase not found (patch v{PATCH_VERSION})",
            file=sys.stderr,
        )
        sys.exit(1)

    insert_at = resources_phase.end("body")
    text = (
        text[:insert_at]
        + f"\t\t\t\t{build_uuid} /* AppIcon.icon in Resources */,\n"
        + text[insert_at:]
    )

pbxproj.write_text(text)

if not is_valid_icon_setup(pbxproj.read_text()):
    print(
        f"error: AppIcon.icon patch finished but validation failed (patch v{PATCH_VERSION})",
        file=sys.stderr,
    )
    sys.exit(1)

print(f"Patched AppIcon.icon -> folder.iconcomposer.icon (patch v{PATCH_VERSION})")
PY
