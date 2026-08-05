#!/usr/bin/env bash
# Run OSGKeyboard grouped XCTest suites from Tests/suite-manifest.json.
#
# Usage:
#   ./Scripts/run-tests.sh list
#   ./Scripts/run-tests.sh validate
#   ./Scripts/run-tests.sh pr
#   ./Scripts/run-tests.sh api polish
#   ./Scripts/run-tests.sh keyboard
#   ./Scripts/run-tests.sh all
#   ./Scripts/run-tests.sh mac
#
# Env overrides:
#   DESTINATION       iOS Simulator destination (default from manifest)
#   MAC_DESTINATION   macOS destination (default from manifest)
#   CONFIGURATION     Debug (default) | Release
#   DRY_RUN=1         Print xcodebuild commands without running
#   SKIP_GENERATE=1   Skip ./Scripts/generate-xcodeproj.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RESOLVE=(python3 "$ROOT/Scripts/resolve_test_suite.py")
CONFIGURATION="${CONFIGURATION:-Debug}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_GENERATE="${SKIP_GENERATE:-0}"

usage() {
  cat <<'EOF'
Usage: ./Scripts/run-tests.sh <preset|group> [<preset|group> ...]
       ./Scripts/run-tests.sh list
       ./Scripts/run-tests.sh validate
       ./Scripts/run-tests.sh help

Presets (compose atomic groups; no duplicated test classes):
  all       Full iOS+Ext hermetic suite (includes host_misc + pipeline_perf; excludes mac/live_api)
  pr        Default CI / PR gate (critical path)
  api       cloud_asr + polish
  asr       cloud_asr + local_asr + utterance
  polish    polish only
  keyboard  keyboard + flow
  flow      flow only
  sync      sync only
  perf      voice→polish stage timings (hermetic)
  mac       macOS host tests only

Atomic groups: config sync polish cloud_asr local_asr utterance flow keyboard host_misc pipeline_perf mac live_api

Examples:
  ./Scripts/run-tests.sh pr
  ./Scripts/run-tests.sh api
  ./Scripts/run-tests.sh perf
  ./Scripts/run-tests.sh cloud_asr utterance
  DRY_RUN=1 ./Scripts/run-tests.sh keyboard
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

case "$1" in
  help|-h|--help)
    usage
    exit 0
    ;;
  list)
    "${RESOLVE[@]}" list
    exit 0
    ;;
  validate)
    "${RESOLVE[@]}" validate
    exit 0
    ;;
esac

NAMES=("$@")

# Ensure project exists for local runs (CI usually generates earlier).
if [[ "$SKIP_GENERATE" != "1" ]]; then
  if [[ ! -d "$ROOT/OSGKeyboard.xcodeproj" ]]; then
    echo "==> Generating Xcode project"
    "$ROOT/Scripts/generate-xcodeproj.sh"
  fi
fi

PAYLOAD="$("${RESOLVE[@]}" xcodebuild-args "${NAMES[@]}")"

# Single Python decode — avoids GROUPS name clash with some env arrays.
eval "$(python3 - "$PAYLOAD" <<'PY'
import json, shlex, sys
data = json.loads(sys.argv[1])
d = data["defaults"]
print(f"IOS_DESTINATION={shlex.quote(d['ios_destination'])}")
print(f"MAC_DESTINATION={shlex.quote(d['mac_destination'])}")
print(f"IOS_SCHEME={shlex.quote(d['ios_scheme'])}")
print(f"MAC_SCHEME={shlex.quote(d['mac_scheme'])}")
print(f"PROJECT={shlex.quote(d['ios_project'])}")
print(f"SUITE_GROUPS={shlex.quote(' '.join(data['groups']))}")
print(f"IOS_COUNT={len(data['ios_tests'])}")
print(f"MAC_COUNT={len(data['mac_tests'])}")
print("IOS_TESTS=(" + " ".join(shlex.quote(t) for t in data["ios_tests"]) + ")")
print("MAC_TESTS=(" + " ".join(shlex.quote(t) for t in data["mac_tests"]) + ")")
PY
)"

# Allow env overrides after decoding defaults.
IOS_DESTINATION="${DESTINATION:-$IOS_DESTINATION}"
MAC_DESTINATION="${MAC_DESTINATION:-$MAC_DESTINATION}"

echo "==> Suite: ${NAMES[*]}"
if [[ -n "$SUITE_GROUPS" ]]; then
  echo "==> Groups: $SUITE_GROUPS"
else
  echo "==> Groups: (none)"
fi
echo "==> iOS classes: $IOS_COUNT | mac classes: $MAC_COUNT"

run_xcodebuild() {
  local scheme="$1"
  local destination="$2"
  shift 2
  local -a only_testing=("$@")

  if [[ ${#only_testing[@]} -eq 0 ]]; then
    return 0
  fi

  local -a cmd=(
    xcodebuild test
    -project "$PROJECT"
    -scheme "$scheme"
    -destination "$destination"
    -configuration "$CONFIGURATION"
    CODE_SIGNING_ALLOWED=NO
  )
  local test_id
  for test_id in "${only_testing[@]}"; do
    cmd+=(-only-testing:"$test_id")
  done

  echo "==> ${cmd[*]}"
  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  set -o pipefail
  if command -v xcpretty >/dev/null 2>&1; then
    "${cmd[@]}" | xcpretty
  else
    "${cmd[@]}"
  fi
}

if [[ "$IOS_COUNT" == "0" && "$MAC_COUNT" == "0" ]]; then
  echo "error: selection resolved to zero test classes (live_api is empty by design)" >&2
  exit 1
fi

if [[ ${#IOS_TESTS[@]} -gt 0 ]]; then
  run_xcodebuild "$IOS_SCHEME" "$IOS_DESTINATION" "${IOS_TESTS[@]}"
fi

if [[ ${#MAC_TESTS[@]} -gt 0 ]]; then
  run_xcodebuild "$MAC_SCHEME" "$MAC_DESTINATION" "${MAC_TESTS[@]}"
fi

echo "==> Done"
