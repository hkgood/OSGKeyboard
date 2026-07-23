#!/usr/bin/env bash
# Ensures vendored mlx-audio-swift is present and patched for StreamingConfig.context.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/ThirdParty/mlx-audio-swift"
PATCH_MARKER="$VENDOR/.osg-context-patch-applied"

if [[ ! -f "$VENDOR/Package.swift" ]]; then
  echo "Cloning mlx-audio-swift into ThirdParty/..."
  git clone --depth 1 https://github.com/Blaizzy/mlx-audio-swift "$VENDOR"
fi

if [[ -f "$PATCH_MARKER" ]]; then
  echo "mlx-audio-swift context patch already applied."
  exit 0
fi

python3 <<'PY'
from pathlib import Path

root = Path("ThirdParty/mlx-audio-swift")
manifest = root / "Package.swift"
types = root / "Sources/MLXAudioSTT/Streaming/StreamingTypes.swift"
session = root / "Sources/MLXAudioSTT/Streaming/StreamingInferenceSession.swift"

# Pin mlx-swift to 0.31.3: 0.31.4+ adds an unconditional swift-argument-parser
# dependency (for its `encuda` executable) that breaks offline resolution here.
mtext = manifest.read_text()
if "mlx-swift.git\", exact:" not in mtext:
    mtext = mtext.replace(
        '.package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMajor(from: "0.30.6")),',
        '.package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.31.3"),',
    )
    manifest.write_text(mtext)

text = types.read_text()
if "public var context: String?" not in text:
    text = text.replace(
        "    public var language: String?\n",
        "    public var language: String?\n"
        "    /// Optional soft-prompt context (vocabulary / domain hints) injected into the system turn.\n"
        "    public var context: String?\n",
    )
    text = text.replace(
        "        language: String? = \"English\",\n        temperature: Float = 0.0,",
        "        language: String? = \"English\",\n        context: String? = nil,\n        temperature: Float = 0.0,",
    )
    text = text.replace(
        "        self.language = language\n        self.temperature = temperature",
        "        self.language = language\n        self.context = context\n        self.temperature = temperature",
    )
    types.write_text(text)

text = session.read_text()
text = text.replace(
    "            language: params.config.language\n        )",
    "            context: params.config.context ?? \"\",\n            language: params.config.language\n        )",
)
text = text.replace(
    "            language: config.language\n        )",
    "            context: config.context ?? \"\",\n            language: config.language\n        )",
)
session.write_text(text)
PY

touch "$PATCH_MARKER"
echo "Applied mlx-audio-swift context patch."
