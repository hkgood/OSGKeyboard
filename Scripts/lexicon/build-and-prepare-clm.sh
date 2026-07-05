#!/usr/bin/env bash
# Full offline CLM pipeline on macOS:
#   1) export .bin from TSVs
#   2) prepare compiled LM + Vocab
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
"$ROOT/Scripts/lexicon/build-clm-bin.sh" "$@"
"$ROOT/Scripts/lexicon/prepare-clm.sh" "$@"
