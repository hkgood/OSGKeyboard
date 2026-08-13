#!/usr/bin/env bash
# Installs the reviewed XcodeGen release into RUNNER_TEMP for GitHub Actions.
set -euo pipefail

VERSION="2.43.0"
SHA256="a4847ed77d3341a4d24049bc4424a3babca4c94ff1dcaaee923eaca2b32c678f"
DESTINATION="${RUNNER_TEMP:?RUNNER_TEMP is required}/xcodegen-$VERSION"
ARCHIVE="$RUNNER_TEMP/xcodegen-$VERSION.zip"

curl -fsSL --retry 3 --retry-all-errors --retry-delay 2 \
  --connect-timeout 15 --max-time 120 \
  "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip" \
  -o "$ARCHIVE"
echo "$SHA256  $ARCHIVE" | shasum -a 256 -c -
rm -rf "$DESTINATION"
mkdir -p "$DESTINATION"
unzip -q "$ARCHIVE" -d "$DESTINATION"

test -x "$DESTINATION/bin/xcodegen"
echo "$DESTINATION/bin" >> "$GITHUB_PATH"
"$DESTINATION/bin/xcodegen" --version
