#!/usr/bin/env bash
# Compile SFCustomLanguageModelData .bin into LM + Vocab on macOS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
exec swift "$ROOT/Scripts/lexicon/prepare_clm.swift" "$@"
