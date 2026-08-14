#!/usr/bin/env bash
# Physical-device keyboard appear/hide stress.
# Shows and dismisses the real OSGKeyboard extension N times, then checks
# crash reports.
#
# Usage:
#   ./Scripts/keyboard-appear-stress.sh [COUNT=50] [UDID]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

COUNT="${1:-50}"
UDID="${2:-00008130-001C249C0E52001C}"
BUNDLE="com.osgkeyboard.ios"
OUT_DIR="${ROOT}/.tmp/keyboard-appear-stress-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"
CONSOLE="$OUT_DIR/console.log"
SUMMARY="$OUT_DIR/summary.txt"
DERIVED="${ROOT}/.derivedData-device-stress"
APP="$DERIVED/Build/Products/Debug-iphoneos/OSGKeyboard.app"

echo "==> Out: $OUT_DIR"
echo "==> Count: $COUNT  Device: $UDID"

echo "==> Building Debug-iphoneos"
xcodebuild build \
  -project "$ROOT/OSGKeyboard.xcodeproj" \
  -scheme OSGKeyboard \
  -destination "platform=iOS,id=$UDID" \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=YES \
  >/dev/null

echo "==> Installing"
xcrun devicectl device install app --device "$UDID" "$APP" --timeout 180 >/dev/null

crash_list() {
  xcrun devicectl device info files \
    --device "$UDID" \
    --domain-type systemCrashLogs \
    --timeout 30 2>/dev/null \
    | awk '/OSGKeyboardExt-/{print $1}'
}

BEFORE="$OUT_DIR/crashes-before.txt"
AFTER="$OUT_DIR/crashes-after.txt"
crash_list | sort >"$BEFORE"

echo "==> Launching appear-stress count=$COUNT"
# 50 hide/show cycles plus first show; ~0.5s each + timeouts.
TIMEOUT_SECS=$((COUNT * 3 + 40))
set +e
python3 - "$TIMEOUT_SECS" "$UDID" "$BUNDLE" "$COUNT" "$CONSOLE" <<'PY'
import subprocess, sys, time, os, signal
timeout, udid, bundle, count, console = sys.argv[1:6]
cmd = [
    "xcrun", "devicectl", "device", "process", "launch",
    "--device", udid,
    "--console",
    "--terminate-existing",
    bundle,
    "--whats-new-host",
    "--whats-new-lang=en",
    "--whats-new-scenario=edit",
    f"--keyboard-appear-stress={count}",
]
with open(console, "w") as out:
    proc = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT)
    try:
        proc.wait(timeout=int(timeout))
    except subprocess.TimeoutExpired:
        proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()
        sys.exit(124)
    sys.exit(proc.returncode or 0)
PY
LAUNCH_STATUS=$?
set -e

crash_list | sort >"$AFTER"
NEW_CRASHES="$OUT_DIR/crashes-new.txt"
comm -13 "$BEFORE" "$AFTER" >"$NEW_CRASHES"

PASSED="$(python3 - "$CONSOLE" <<'PY'
import re, sys
text = open(sys.argv[1], errors="replace").read()
hits = re.findall(r"keyboard\.stress done passed=(\d+)/(\d+)", text)
print(hits[-1][0] if hits else "")
PY
)"
TOTAL="$(python3 - "$CONSOLE" <<'PY'
import re, sys
text = open(sys.argv[1], errors="replace").read()
hits = re.findall(r"keyboard\.stress done passed=(\d+)/(\d+)", text)
print(hits[-1][1] if hits else "")
PY
)"
FAIL_LINE="$(grep 'keyboard.stress FAIL' "$CONSOLE" | tail -1 || true)"

{
  echo "Keyboard appear/hide stress"
  echo "device=$UDID count=$COUNT"
  echo "launch_exit=$LAUNCH_STATUS"
  echo "passed=${PASSED:-0}/${TOTAL:-$COUNT}"
  echo "fail_line=${FAIL_LINE:-none}"
  echo "new_OSGKeyboardExt_crashes:"
  if [[ -s "$NEW_CRASHES" ]]; then
    cat "$NEW_CRASHES"
  else
    echo "  (none)"
  fi
  echo "console=$CONSOLE"
} | tee "$SUMMARY"

if [[ -s "$NEW_CRASHES" ]]; then
  echo "FAIL: new OSGKeyboardExt crash reports" >&2
  exit 1
fi
if [[ "${PASSED:-0}" != "$COUNT" ]]; then
  echo "FAIL: expected $COUNT cycles, got ${PASSED:-0}" >&2
  tail -40 "$CONSOLE" >&2
  exit 1
fi
echo "PASS: $COUNT/$COUNT appear-hide cycles, no new extension crashes"
