#!/usr/bin/env bash
# Build SFCustomLanguageModelData .bin on macOS (requires Speech framework).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
exec swift "$ROOT/Scripts/lexicon/export_clm.swift" "$@"
