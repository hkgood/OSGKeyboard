#!/usr/bin/env bash
# Generate OSGKeyboard.xcodeproj from project.yml and apply the Icon Composer
# patch required by XcodeGen 2.43.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

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

xcodegen generate
"$ROOT/Scripts/patch-icon-composer.sh"
