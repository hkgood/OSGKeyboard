#!/usr/bin/env bash
# check_l10n_keys.sh
# Compares localization key sets across App / Extension / Shared bundles.
# Fails when a key referenced in Shared.strings is missing from any bundle
# that should mirror it, or when Shared keys are absent from Shared.strings.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

extract_keys() {
  local file="$1"
  grep -E '^"[^"]+"' "$file" 2>/dev/null | sed -E 's/^"([^"]+)".*/\1/' | sort -u
}

SHARED_EN="$ROOT/OSGKeyboardShared/en.lproj/Shared.strings"
SHARED_ZH="$ROOT/OSGKeyboardShared/zh-Hans.lproj/Shared.strings"
APP_EN="$ROOT/OSGKeyboard/en.lproj/Localizable.strings"
APP_ZH="$ROOT/OSGKeyboard/zh-Hans.lproj/Localizable.strings"
EXT_EN="$ROOT/OSGKeyboardExt/en.lproj/Keyboard.strings"
EXT_ZH="$ROOT/OSGKeyboardExt/zh-Hans.lproj/Keyboard.strings"

fail=0

compare_pair() {
  local left="$1"
  local right="$2"
  local label="$3"
  local missing
  missing="$(comm -23 "$left" "$right" || true)"
  if [[ -n "$missing" ]]; then
    echo "❌ $label — keys in first file missing from second:"
    echo "$missing" | sed 's/^/   /'
    fail=1
  fi
}

SHARED_EN_KEYS="$(mktemp)"
SHARED_ZH_KEYS="$(mktemp)"
APP_EN_KEYS="$(mktemp)"
APP_ZH_KEYS="$(mktemp)"
EXT_EN_KEYS="$(mktemp)"
EXT_ZH_KEYS="$(mktemp)"
trap 'rm -f "$SHARED_EN_KEYS" "$SHARED_ZH_KEYS" "$APP_EN_KEYS" "$APP_ZH_KEYS" "$EXT_EN_KEYS" "$EXT_ZH_KEYS"' EXIT

extract_keys "$SHARED_EN" > "$SHARED_EN_KEYS"
extract_keys "$SHARED_ZH" > "$SHARED_ZH_KEYS"
extract_keys "$APP_EN" > "$APP_EN_KEYS"
extract_keys "$APP_ZH" > "$APP_ZH_KEYS"
extract_keys "$EXT_EN" > "$EXT_EN_KEYS"
extract_keys "$EXT_ZH" > "$EXT_ZH_KEYS"

compare_pair "$SHARED_EN_KEYS" "$SHARED_ZH_KEYS" "Shared en vs zh-Hans"
compare_pair "$SHARED_ZH_KEYS" "$SHARED_EN_KEYS" "Shared zh-Hans vs en"
compare_pair "$APP_EN_KEYS" "$APP_ZH_KEYS" "App Localizable en vs zh-Hans"
compare_pair "$APP_ZH_KEYS" "$APP_EN_KEYS" "App Localizable zh-Hans vs en"
compare_pair "$EXT_EN_KEYS" "$EXT_ZH_KEYS" "Extension Keyboard en vs zh-Hans"
compare_pair "$EXT_ZH_KEYS" "$EXT_EN_KEYS" "Extension Keyboard zh-Hans vs en"

if [[ "$fail" -ne 0 ]]; then
  echo ""
  echo "L10n key parity check failed."
  exit 1
fi

echo "✅ L10n key parity check passed (Shared / App / Extension en ↔ zh-Hans)."
