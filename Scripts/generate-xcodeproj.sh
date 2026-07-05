#!/usr/bin/env bash
# Generate OSGKeyboard.xcodeproj from project.yml and apply the Icon Composer
# patch required by XcodeGen 2.43.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PBXPROJ="$ROOT/OSGKeyboard.xcodeproj/project.pbxproj"

# XcodeGen requires configFiles listed in project.yml to exist on disk.
# Signing.local.xcconfig is gitignored so each machine keeps its own team ID.
SIGNING_LOCAL="$ROOT/Signing.local.xcconfig"
SIGNING_EXAMPLE="$ROOT/Signing.local.xcconfig.example"
if [[ ! -f "$SIGNING_LOCAL" ]]; then
  if [[ ! -f "$SIGNING_EXAMPLE" ]]; then
    echo "error: missing $SIGNING_EXAMPLE" >&2
    exit 1
  fi
  cp "$SIGNING_EXAMPLE" "$SIGNING_LOCAL"
  echo "Created $SIGNING_LOCAL from Signing.local.xcconfig.example"
  echo "Edit DEVELOPMENT_TEAM there if you use a personal Apple Developer account."
fi

# Local-engine DeepSeek key (gitignored). XcodeGen compiles this file;
# the example ships a placeholder so fresh clones build after copy.
PRECONFIG_LOCAL="$ROOT/OSGKeyboardShared/Services/PreconfiguredKeys.local.swift"
PRECONFIG_EXAMPLE="$ROOT/OSGKeyboardShared/Services/PreconfiguredKeys.local.swift.example"
if [[ ! -f "$PRECONFIG_LOCAL" ]]; then
  if [[ ! -f "$PRECONFIG_EXAMPLE" ]]; then
    echo "error: missing $PRECONFIG_EXAMPLE" >&2
    exit 1
  fi
  cp "$PRECONFIG_EXAMPLE" "$PRECONFIG_LOCAL"
  echo "Created $PRECONFIG_LOCAL from PreconfiguredKeys.local.swift.example"
  echo "Edit deepseek in that file before using the local engine's built-in polish."
fi

xcodegen generate

if python3 - "$PBXPROJ" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
has_icon_type = "folder.iconcomposer.icon" in text
has_icon_path = bool(re.search(r"path = (?:OSGKeyboard/)?AppIcon\.icon;", text))
has_resources = bool(re.search(r"AppIcon\.icon in Resources", text))
sys.exit(0 if has_icon_type and has_icon_path and has_resources else 1)
PY
then
  echo "AppIcon.icon configured (XcodeGen native)"
else
  echo "Applying AppIcon.icon compatibility patch..."
  "$ROOT/Scripts/patch-icon-composer.sh"
fi
