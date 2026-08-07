#!/usr/bin/env bash
# Cold-start stress on iOS Simulator.
#
# Usage:
#   ./Scripts/cold-start-stress.sh [COUNT=100] [DEVICE_NAME=iPhone 17]
#
# Method: terminate → simctl launch (host cold start that auto-arms PiP).
# Keyboard URL wake (osgkeyboard://startflow) is optional once scheme is approved.
#
# Limitations (documented in summary):
# - Simulator VideoCall PiP is typically `unsupported` — not a device signal.
# - Keyboard extension process (KVC.init) is not spawned here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

COUNT="${1:-100}"
DEVICE_NAME="${2:-iPhone 17}"
BUNDLE="com.osgkeyboard.ios"
OUT_DIR="${ROOT}/.tmp/cold-start-stress-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/report.jsonl"
SUMMARY="$OUT_DIR/summary.txt"
LOG_FILE="$OUT_DIR/unified.log"

echo "==> Out: $OUT_DIR"
echo "==> Count: $COUNT  Device: '$DEVICE_NAME'"

# Exact device name match (avoid "iPhone 17" → "iPhone 17 Pro")
UDID="$(xcrun simctl list devices available | awk -F '[()]' -v n="$DEVICE_NAME" '
  {
    line=$0
    # strip leading spaces
    sub(/^[[:space:]]+/, "", line)
    name=line
    sub(/ \(.*/, "", name)
    if (name == n && line ~ /Booted/) { print $2; exit }
  }
')"
if [[ -z "$UDID" ]]; then
  UDID="$(xcrun simctl list devices available | awk -F '[()]' -v n="$DEVICE_NAME" '
    {
      line=$0
      sub(/^[[:space:]]+/, "", line)
      name=line
      sub(/ \(.*/, "", name)
      if (name == n && line !~ /unavailable/) { print $2; exit }
    }
  ')"
fi
if [[ -z "$UDID" ]]; then
  echo "error: exact device '$DEVICE_NAME' not found" >&2
  xcrun simctl list devices available | grep -i iphone | head -40 >&2 || true
  exit 1
fi
echo "==> UDID: $UDID"

echo "==> Booting simulator"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

# Prefer signed cold-start DerivedData build, else any existing Debug-iphonesimulator app
APP=""
if [[ -d "$ROOT/.derivedData-cold-start/Build/Products/Debug-iphonesimulator/OSGKeyboard.app" ]]; then
  APP="$ROOT/.derivedData-cold-start/Build/Products/Debug-iphonesimulator/OSGKeyboard.app"
else
  APP="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/OSGKeyboard-*/Build/Products/Debug-iphonesimulator/OSGKeyboard.app 2>/dev/null | head -1 || true)"
fi
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "error: no built OSGKeyboard.app — build for simulator first" >&2
  exit 1
fi
echo "==> Installing $APP"
xcrun simctl install "$UDID" "$APP" >/dev/null
xcrun simctl privacy "$UDID" grant microphone "$BUNDLE" 2>/dev/null || true

seed_onboarding() {
  echo "==> Seeding onboarding (App Group + Keychain path)"
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null || true
  sleep 2
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  sleep 0.5

  local group_container prefs
  group_container="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" group.com.osgkeyboard.shared 2>/dev/null || true)"
  if [[ -z "$group_container" || ! -d "$group_container" ]]; then
    echo "warning: App Group container missing" >&2
    return 0
  fi
  prefs="$group_container/Library/Preferences/group.com.osgkeyboard.shared.plist"
  mkdir -p "$(dirname "$prefs")"
  if [[ -f "$prefs" ]]; then
    /usr/libexec/PlistBuddy -c "Set :config.hasCompletedOnboarding true" "$prefs" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :config.hasCompletedOnboarding bool true" "$prefs" 2>/dev/null || true
  else
    /usr/libexec/PlistBuddy -c "Add :config.hasCompletedOnboarding bool true" "$prefs" 2>/dev/null || true
  fi
  echo "==> Seeded hasCompletedOnboarding=$(/usr/libexec/PlistBuddy -c 'Print :config.hasCompletedOnboarding' "$prefs" 2>/dev/null || echo missing)"

  # One launch so ProviderConfig mirrors App Group → Keychain
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null || true
  sleep 2
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  sleep 0.4
}
seed_onboarding

: >"$LOG_FILE"
xcrun simctl spawn "$UDID" log stream \
  --style compact \
  --level debug \
  --predicate 'process == "OSGKeyboard"' \
  >"$LOG_FILE" 2>&1 &
LOG_PID=$!
trap 'kill $LOG_PID 2>/dev/null || true' EXIT
sleep 1

logfile_window() {
  local offset="$1"
  local start=$((offset + 1))
  tail -c +"$start" "$LOG_FILE" 2>/dev/null || true
}

# Returns: host|pip
# host: success|fail|unknown
# pip: success|unsupported|fail|permissions|onboarding|unknown
logfile_classify() {
  local chunk="$1"
  local host="unknown" pip="unknown"

  # Use here-string (not pipe) to avoid SIGPIPE under `set -o pipefail`.
  if grep -Eq "OSGKeyboardApp\.init" <<<"$chunk"; then
    host="success"
  fi
  if grep -Eq "MainAppRoot\.onAppear skip Flow.*onboarding incomplete" <<<"$chunk"; then
    pip="onboarding"
    echo "$host|$pip"
    return
  fi
  if grep -Eq "activateOnForeground aborted reason=permissions|startSessionAsync\.blocked.*permissions" <<<"$chunk"; then
    pip="permissions"
    echo "$host|$pip"
    return
  fi
  if grep -Eq "Flow session started \(PiP keep-alive\)|low-profile PiP active|startSessionAsync\.ready" <<<"$chunk"; then
    pip="success"
  elif grep -Eq "failure=unsupported|PiP keep-alive failed to start: unsupported" <<<"$chunk"; then
    pip="unsupported"
  elif grep -Eq "PiP keep-alive failed to start|PiP startAndWait failed|startSessionAsync\.failed.*pipUnavailable" <<<"$chunk"; then
    pip="fail"
  elif grep -Eq "activateOnForeground|startSession\.request.*autoPiP|startSessionAsync\.begin" <<<"$chunk"; then
    pip="seen_no_result"
  fi

  echo "$host|$pip"
}

HOST_OK=0
HOST_FAIL=0
PIP_SUCCESS=0
PIP_UNSUPPORTED=0
PIP_FAIL=0
PIP_PERMISSIONS=0
PIP_ONBOARDING=0
PIP_OTHER=0

echo "==> Running $COUNT cold starts (terminate → launch)"
for i in $(seq 1 "$COUNT"); do
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  sleep 0.35

  OFFSET=$(wc -c <"$LOG_FILE" | tr -d ' ')
  START_TS=$(date +%s)

  if ! xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>"$OUT_DIR/launch-$i.err"; then
    printf '{"i":%d,"host":"fail","pip":"unknown","elapsed_s":0,"note":"launch_failed"}\n' "$i" >>"$REPORT"
    printf "[%3d/%d] host=fail     pip=unknown\n" "$i" "$COUNT"
    HOST_FAIL=$((HOST_FAIL + 1))
    PIP_OTHER=$((PIP_OTHER + 1))
    continue
  fi

  RESULT="unknown|unknown"
  for _ in $(seq 1 50); do  # ~15s
    sleep 0.3
    CHUNK="$(logfile_window "$OFFSET")"
    RESULT="$(logfile_classify "$CHUNK")"
    PIP="${RESULT##*|}"
    if [[ "$PIP" == "success" || "$PIP" == "unsupported" || "$PIP" == "fail" || "$PIP" == "permissions" || "$PIP" == "onboarding" ]]; then
      break
    fi
  done

  ELAPSED=$(( $(date +%s) - START_TS ))
  HOST="${RESULT%%|*}"
  PIP="${RESULT##*|}"

  case "$HOST" in
    success) HOST_OK=$((HOST_OK + 1)) ;;
    *) HOST_FAIL=$((HOST_FAIL + 1)) ;;
  esac
  case "$PIP" in
    success) PIP_SUCCESS=$((PIP_SUCCESS + 1)) ;;
    unsupported) PIP_UNSUPPORTED=$((PIP_UNSUPPORTED + 1)) ;;
    fail) PIP_FAIL=$((PIP_FAIL + 1)) ;;
    permissions) PIP_PERMISSIONS=$((PIP_PERMISSIONS + 1)) ;;
    onboarding) PIP_ONBOARDING=$((PIP_ONBOARDING + 1)) ;;
    *) PIP_OTHER=$((PIP_OTHER + 1)) ;;
  esac

  printf '{"i":%d,"host":"%s","pip":"%s","elapsed_s":%d}\n' "$i" "$HOST" "$PIP" "$ELAPSED" >>"$REPORT"
  printf "[%3d/%d] host=%-8s pip=%-12s %2ds\n" "$i" "$COUNT" "$HOST" "$PIP" "$ELAPSED"
done

{
  echo "Cold-start stress summary"
  echo "device=$DEVICE_NAME udid=$UDID count=$COUNT"
  echo "method=terminate + simctl launch (host cold start / autoPiP path)"
  echo
  echo "Host cold start (OSGKeyboardApp.init observed):"
  echo "  success=$HOST_OK fail=$HOST_FAIL"
  echo "  fail_rate=$(python3 -c "print(f'{$HOST_FAIL/$COUNT*100:.1f}%')")"
  echo
  echo "PiP keep-alive outcome:"
  echo "  success=$PIP_SUCCESS"
  echo "  unsupported=$PIP_UNSUPPORTED  (expected on Simulator)"
  echo "  fail_other=$PIP_FAIL"
  echo "  permissions=$PIP_PERMISSIONS"
  echo "  onboarding=$PIP_ONBOARDING"
  echo "  unknown/other=$PIP_OTHER"
  echo "  non-unsupported fail_rate=$(python3 -c "print(f'{($PIP_FAIL+$PIP_PERMISSIONS+$PIP_ONBOARDING+$PIP_OTHER)/$COUNT*100:.1f}%')")"
  echo
  echo "Artifacts: $OUT_DIR"
  echo "Caveats:"
  echo "  - Simulator PiP is typically 'unsupported'; device PiP is the release gate."
  echo "  - Keyboard extension KVC.init / openHostApp is not covered (needs physical keyboard enablement)."
  echo "  - Host wake path covered = cold launch of the process the keyboard would open."
} | tee "$SUMMARY"

kill "$LOG_PID" 2>/dev/null || true
trap - EXIT
echo "==> Done"
