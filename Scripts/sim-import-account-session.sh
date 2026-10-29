#!/usr/bin/env bash
# Hand a signed-in account session from a physical device to an iOS Simulator.
#
# The Simulator cannot produce DeviceCheck / App Attest evidence, so the
# account server rejects its Apple sign-in (`integrity_evidence_missing`).
# Refresh and managed-gateway calls only need the session, so a DEBUG build on
# a device can relinquish its session instead:
#
#   1. Device (DEBUG build): Settings → Diagnostics → 把账号会话交给模拟器,
#      then AirDrop the file to this Mac.
#   2. Mac: Scripts/sim-import-account-session.sh ~/Downloads/osg-account-handoff.json [udid]
#
# The DEBUG Simulator build must already be installed. The script places the
# file in the app's Documents, deletes the source, and relaunches the app,
# which adopts the session and deletes the file. The file holds a live refresh
# token — treat it like a password.

set -euo pipefail

usage() {
  echo "usage: $0 <osg-account-handoff.json> [simulator-udid|booted]" >&2
  exit 64
}

[[ $# -ge 1 && $# -le 2 ]] || usage
source_file=$1
device=${2:-booted}
bundle_id=com.osgkeyboard.ios
format=osg-debug-account-handoff-v1

[[ -f "$source_file" ]] || { echo "error: $source_file not found" >&2; exit 66; }
grep -q "\"$format\"" "$source_file" || {
  echo "error: $source_file is not an OSG account handoff file" >&2
  exit 65
}

container=$(xcrun simctl get_app_container "$device" "$bundle_id" data) || {
  echo "error: $bundle_id is not installed on simulator '$device' — run the DEBUG build first" >&2
  exit 69
}

mkdir -p "$container/Documents"
install -m 600 "$source_file" "$container/Documents/osg-account-handoff.json"
rm -f "$source_file"

xcrun simctl terminate "$device" "$bundle_id" >/dev/null 2>&1 || true
xcrun simctl launch "$device" "$bundle_id" >/dev/null

echo "Session handed to simulator '$device'. The app adopts it on launch and deletes the file."
