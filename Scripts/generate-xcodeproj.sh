#!/usr/bin/env bash
# Generate OSGKeyboard.xcodeproj from project.yml and apply the Icon Composer
# patch required by XcodeGen 2.43.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate
"$ROOT/Scripts/patch-icon-composer.sh"
