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

# --- Host-app bare LocalizedStringKey check -------------------------------
#
# SwiftUI resolves a bare `Text("some.key")` through `Bundle.main`, whose
# localization is fixed at launch from the *system* language. That silently
# ignores the in-app language override (Settings → App Language), so such a
# call site renders the system language no matter what the user picked.
# `.environment(\.locale, …)` does NOT fix this — it only drives formatting.
#
# The host app must therefore go through `AppL10n.string` / `AppL10n.format`,
# which resolve the `.lproj` sub-bundle manually. The keyboard extension and
# the Mac app already do this via `ExtL10n` / `MacL10n`.
KEY_RE='"[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_+-]+)+"'
BARE_RE="(\\.(navigationTitle|navigationBarTitle|alert|confirmationDialog|help|accessibilityLabel|accessibilityHint)|[^A-Za-z0-9_](Text|Button|Section|Label|Toggle|TextField|Picker|Stepper|Link|NavigationLink))\\([[:space:]]*${KEY_RE}"

bare_hits="$(
  grep -rnE "$BARE_RE|LocalizedStringKey\\([[:space:]]*${KEY_RE}" \
    --include='*.swift' "$ROOT/OSGKeyboard" 2>/dev/null \
    | grep -v '/Tests/' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
    || true
)"

if [[ -n "$bare_hits" ]]; then
  echo "❌ Host app uses bare LocalizedStringKey — these ignore the in-app language override:"
  echo "$bare_hits" | sed "s|^$ROOT/||" | sed 's/^/   /'
  echo ""
  echo "   Wrap the key: Text(\"foo.bar\") → Text(AppL10n.string(\"foo.bar\"))"
  fail=1
fi

# The host app must not reintroduce `LocalizedStringKey` at all: any value of
# that type is resolved by SwiftUI through `Bundle.main` and so ignores the
# in-app language override. Keys travel as `String` and are resolved at the
# render site with `AppL10n.string`.
lsk_hits="$(
  grep -rn 'LocalizedStringKey' --include='*.swift' "$ROOT/OSGKeyboard" 2>/dev/null \
    | grep -v '/Tests/' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
    || true
)"

if [[ -n "$lsk_hits" ]]; then
  echo "❌ Host app reintroduced LocalizedStringKey — it resolves via Bundle.main (system language):"
  echo "$lsk_hits" | sed "s|^$ROOT/||" | sed 's/^/   /'
  echo ""
  echo "   Store the key as String and resolve at render: Text(AppL10n.string(key))"
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo ""
  echo "L10n check failed."
  exit 1
fi

echo "✅ L10n key parity check passed (Shared / App / Extension en ↔ zh-Hans)."
echo "✅ Host app has no bare LocalizedStringKey call sites."
echo "✅ Host app does not use LocalizedStringKey."
