#!/usr/bin/env bash
# Record the four Chinese feature preview clips off an iOS Simulator.
#
# Drives the DEBUG in-app demo hosts, which render the **real** keyboard views
# (`AIKeyboardView`, `LastInputEditView`, `ClipboardHistoryPanelView`, …) and
# the real `PolishStylesView` against a scripted `KeyboardState` — no ASR, no
# LLM, no network. `--preview-fullscreen` adds the Notes / Messages host
# document above the keyboard band so the frame works as a full-screen App
# Store preview instead of a cropped What's New card.
#
# Why not the keyboard extension (`--whats-new-host`)? Making a third-party
# keyboard the *active* one needs a globe-key tap that cannot be scripted
# through simctl. The in-app hosts use the same views and need no tap.
#
# Device must be an iPhone 16 Plus (native 1290x2796 — the App Store Connect
# 6.9" preview slot) on a runtime new enough for the app's Liquid Glass APIs
# (iOS 26.5 at time of writing; iOS 26.0 is missing `View.glassEffect(_:in:)`).
#
# Usage:
#   Scripts/record_feature_previews.sh <UDID> [slug ...]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

UDID="${1:?usage: record_feature_previews.sh <UDID> [slug ...]}"
shift || true

BUNDLE="com.osgkeyboard.ios"
RAW_DIR="$ROOT/.tmp/feature-previews/raw"
mkdir -p "$RAW_DIR"

# slug | seconds | launch args
CLIPS=(
  "voice-polish|23|--edit-demo --preview-fullscreen"
  # Static page — the motion is a post-production push-in, so this only needs
  # to be long enough to fill the App Store 15s minimum after trimming.
  "personal-style|22|--polish-styles-screenshot"
  "clipboard-agent|46|--clipboard-demo --preview-fullscreen"
  "ask-ai|36|--ai-demo --preview-fullscreen --whats-new-lang=zh"
)

want() {
  local slug="$1"; shift
  # No slug filter left on the command line -> record everything.
  [[ $# -eq 0 ]] && return 0
  for requested in "$@"; do
    [[ "$slug" == "$requested" ]] && return 0
  done
  return 1
}

echo "==> Device: $UDID"

# Installing over an existing copy does not refresh the App Group container.
# When it is missing the app renders `AppGroupErrorView` instead of the demo,
# and the recording silently captures an error screen — so fail loudly here.
DEVICE_ROOT="$HOME/Library/Developer/CoreSimulator/Devices/$UDID"
if ! grep -qls "group.com.osgkeyboard.shared" \
  "$DEVICE_ROOT"/data/Containers/Shared/AppGroup/*/.com.apple.mobile_container_manager.metadata.plist
then
  echo "FAIL: App Group container missing on $UDID." >&2
  echo "      Reinstall cleanly, then retry:" >&2
  echo "      xcrun simctl uninstall $UDID $BUNDLE && xcrun simctl install $UDID <path>.app" >&2
  exit 1
fi

# Marketing status bar: fixed time, full bars, full battery.
xcrun simctl status_bar "$UDID" override \
  --time "9:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100

for entry in "${CLIPS[@]}"; do
  IFS='|' read -r slug seconds args <<<"$entry"
  want "$slug" "$@" || continue

  out="$RAW_DIR/$slug.mov"
  echo "==> Recording $slug (${seconds}s) [$args]"

  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 1

  rm -f "$out"
  xcrun simctl io "$UDID" recordVideo --codec h264 --force "$out" &
  RECORD_PID=$!
  # Let the recorder attach before the first frame we care about.
  sleep 1.5

  # shellcheck disable=SC2086 -- args are intentionally word-split.
  xcrun simctl launch "$UDID" "$BUNDLE" $args >/dev/null

  sleep "$seconds"

  kill -INT "$RECORD_PID" 2>/dev/null || true
  wait "$RECORD_PID" 2>/dev/null || true
  sleep 1

  if [[ -s "$out" ]]; then
    ffprobe -v error -select_streams v:0 \
      -show_entries stream=width,height -show_entries format=duration \
      -of default=noprint_wrappers=1 "$out"
  else
    echo "FAIL: no footage captured for $slug" >&2
    exit 1
  fi
done

xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
echo "==> Raw footage in $RAW_DIR"
