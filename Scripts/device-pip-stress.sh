#!/usr/bin/env bash
# Physical-device PiP / host-wake stress using `devicectl --console` logs.
#
# Usage:
#   ./Scripts/device-pip-stress.sh [UDID] [COUNT=50]
#
# Suites:
#   cold — terminate-existing launch (force-quit / cold start)
#   bgfg — open Safari (background) then relaunch OSG (foreground restore)
#   hold — start PiP, wait 20s in session, relaunch to verify still recoverable
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

UDID="${1:-00008130-001C249C0E52001C}"
COUNT="${2:-50}"
BUNDLE="com.osgkeyboard.ios"
SAFARI="com.apple.mobilesafari"
OUT_DIR="${ROOT}/.tmp/device-pip-stress-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/report.jsonl"
SUMMARY="$OUT_DIR/summary.txt"
APP="$ROOT/.derivedData-device-stress/Build/Products/Debug-iphoneos/OSGKeyboard.app"

echo "==> Out: $OUT_DIR"
echo "==> Device: $UDID  count/suite: $COUNT"

if [[ ! -d "$APP" ]]; then
  echo "error: missing $APP — build for device first" >&2
  exit 1
fi

echo "==> Ensuring install"
xcrun devicectl device install app --device "$UDID" "$APP" --timeout 180 >/dev/null

# Capture one console launch (timeout seconds). Prints raw console to stdout file.
console_launch() {
  local outfile="$1"
  local secs="${2:-14}"
  local extra_flags="${3:-}" # e.g. --terminate-existing
  # shellcheck disable=SC2086
  timeout "$secs" xcrun devicectl device process launch \
    --device "$UDID" \
    --console \
    $extra_flags \
    "$BUNDLE" >"$outfile" 2>&1 || true
}

classify_file() {
  local f="$1"
  local host="unknown" pip="unknown" mic="unknown"

  if grep -Eq "OSGKeyboardApp\.init|MainAppRoot\.onAppear|activateOnForeground" "$f"; then
    host="success"
  elif grep -Eq "Launched application with com\.osgkeyboard\.ios" "$f"; then
    host="launch_only"
  fi

  if grep -Eq "onboarding incomplete" "$f"; then
    pip="onboarding"
  elif grep -Eq "aborted reason=permissions|blocked.*permissions" "$f"; then
    pip="permissions"
  elif grep -Eq "Flow session started \(PiP keep-alive\)|low-profile PiP active|startSessionAsync\.ready" "$f"; then
    pip="success"
  elif grep -Eq "failure=unsupported|failed to start: unsupported" "$f"; then
    pip="unsupported"
  elif grep -Eq "PiP keep-alive failed to start|startSessionAsync\.failed.*pipUnavailable|startAndWait failed" "$f"; then
    pip="fail"
  elif grep -Eq "PiP start attempt failed" "$f"; then
    # Retry path — only fail if we never saw success above
    pip="retry_then_unknown"
  elif grep -Eq "activateOnForeground|autoPiP|startSessionAsync\.begin" "$f"; then
    pip="seen_no_result"
  fi

  # Mic keep-alive contract: idle releases mic after PiP proves
  if grep -Eq "mic released between utterances|released audio session and frame pump" "$f"; then
    mic="released_ok"
  elif grep -Eq "PiP audio session ready" "$f"; then
    mic="armed"
  else
    mic="unknown"
  fi

  # Promote retry_then_unknown if success markers appeared (grep order already handled)
  if [[ "$pip" == "retry_then_unknown" ]]; then
    if grep -Eq "low-profile PiP active|Flow session started \(PiP keep-alive\)" "$f"; then
      pip="success"
    else
      pip="fail"
    fi
  fi

  echo "$host|$pip|$mic"
}

run_suite() {
  local suite="$1"
  local i outfile result host pip mic start_ts elapsed flags
  echo "==> Suite: $suite × $COUNT"
  for i in $(seq 1 "$COUNT"); do
    outfile="$OUT_DIR/${suite}-$i.console.log"
    start_ts=$(date +%s)
    flags=""

    case "$suite" in
      cold)
        flags="--terminate-existing"
        console_launch "$outfile" 14 "$flags"
        ;;
      bgfg)
        # Ensure app running with PiP first
        console_launch "$OUT_DIR/${suite}-$i.prep.log" 12 "--terminate-existing" >/dev/null || true
        # Background by opening Safari
        xcrun devicectl device process launch --device "$UDID" "$SAFARI" >/dev/null 2>&1 || true
        sleep 3
        # Resume OSG without terminate
        console_launch "$outfile" 12 ""
        ;;
      hold)
        console_launch "$OUT_DIR/${suite}-$i.prep.log" 12 "--terminate-existing" >/dev/null || true
        # Leave session alive ~20s (PiP should keep host)
        sleep 20
        # Background briefly then resume
        xcrun devicectl device process launch --device "$UDID" "$SAFARI" >/dev/null 2>&1 || true
        sleep 2
        console_launch "$outfile" 12 ""
        ;;
    esac

    elapsed=$(( $(date +%s) - start_ts ))
    result="$(classify_file "$outfile")"
    host="${result%%|*}"
    rest="${result#*|}"
    pip="${rest%%|*}"
    mic="${rest##*|}"

    printf '{"suite":"%s","i":%d,"host":"%s","pip":"%s","mic":"%s","elapsed_s":%d}\n' \
      "$suite" "$i" "$host" "$pip" "$mic" "$elapsed" >>"$REPORT"
    printf "[%s %3d/%d] host=%-11s pip=%-12s mic=%-12s %2ds\n" \
      "$suite" "$i" "$COUNT" "$host" "$pip" "$mic" "$elapsed"
  done
}

: >"$REPORT"
run_suite cold
run_suite bgfg
run_suite hold

python3 - "$REPORT" "$SUMMARY" "$UDID" "$COUNT" "$OUT_DIR" <<'PY'
import json, collections, sys
from pathlib import Path
report, summary, udid, count, out = sys.argv[1:6]
rows = [json.loads(l) for l in Path(report).read_text().splitlines() if l.strip()]
by = collections.defaultdict(list)
for r in rows:
    by[r["suite"]].append(r)

lines = [
    "Device PiP / mic keep-alive stress summary",
    f"device=Rocky 15 PM udid={udid} count_per_suite={count}",
    f"total_rows={len(rows)}",
    "",
]
for suite in ("cold", "bgfg", "hold"):
    rs = by.get(suite, [])
    n = max(len(rs), 1)
    host_ok = sum(1 for r in rs if r["host"] in ("success", "launch_only"))
    pip_c = collections.Counter(r["pip"] for r in rs)
    mic_c = collections.Counter(r["mic"] for r in rs)
    pip_ok = pip_c.get("success", 0)
    lines += [
        f"[{suite}]",
        f"  host_ok={host_ok}/{len(rs)} ({host_ok/n*100:.1f}%)",
        f"  pip_success={pip_ok}/{len(rs)} ({pip_ok/n*100:.1f}%)  breakdown={dict(pip_c)}",
        f"  mic={dict(mic_c)}",
        "",
    ]
lines += [
    f"Artifacts: {out}",
    "Notes:",
    "  - cold uses --terminate-existing (force-quit recovery).",
    "  - bgfg backgrounds via Safari then resumes.",
    "  - hold keeps session ~20s then Safari background + resume.",
    "  - Keyboard-extension mic tap is not automated.",
]
text = "\n".join(lines) + "\n"
Path(summary).write_text(text)
print(text)
PY

echo "==> Done"
