#!/usr/bin/env bash
# XcodeGen 2.43 omits `package = …` on XCSwiftPackageProductDependency for local
# path packages, which makes Xcode show "Missing package product 'MLXAudioSTT'".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$ROOT/OSGKeyboard.xcodeproj/project.pbxproj"

if [[ ! -f "$PBXPROJ" ]]; then
  echo "patch-spm-local-package: $PBXPROJ not found — run xcodegen first." >&2
  exit 1
fi

python3 - "$PBXPROJ" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

package_ref = re.search(
    r'(\w+) /\* XCLocalSwiftPackageReference "ThirdParty/mlx-audio-swift" \*/ = \{\n'
    r'\s*isa = XCLocalSwiftPackageReference;\n'
    r'\s*relativePath = "ThirdParty/mlx-audio-swift";\n'
    r'\s*\};',
    text,
)
if not package_ref:
    print("patch-spm-local-package: local package reference not found — skip")
    sys.exit(0)

package_id = package_ref.group(1)
product_block = re.search(
    r'(\w+) /\* MLXAudioSTT \*/ = \{\n'
    r'\s*isa = XCSwiftPackageProductDependency;\n'
    r'(\s*productName = MLXAudioSTT;\n)'
    r'\s*\};',
    text,
)
if not product_block:
    print("patch-spm-local-package: MLXAudioSTT product dependency not found — skip")
    sys.exit(0)

product_id = product_block.group(1)
if f"package = {package_id}" in text:
    print("patch-spm-local-package: already patched")
    sys.exit(0)

replacement = (
    f"{product_id} /* MLXAudioSTT */ = {{\n"
    f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
    f"\t\t\tpackage = {package_id} /* XCLocalSwiftPackageReference \"ThirdParty/mlx-audio-swift\" */;\n"
    f"\t\t\tproductName = MLXAudioSTT;\n"
    f"\t\t}};"
)
text = text[: product_block.start()] + replacement + text[product_block.end() :]
path.write_text(text)
print("patch-spm-local-package: linked MLXAudioSTT → ThirdParty/mlx-audio-swift")
PY
