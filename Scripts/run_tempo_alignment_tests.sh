#!/usr/bin/env bash
# Fast exact-rate contract tests; actual DSP is tested separately by
# run_tempo_render_tests.sh and check_tempo_render.py.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/mixr-tempo-contract.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$BUILD/module-cache}"
cp "$ROOT/DevTests/AutoTempoAlignmentTests.swift" "$BUILD/main.swift"
xcrun swiftc "$ROOT/Mixr/Models/AutoClubTempo.swift" "$BUILD/main.swift" -o "$BUILD/tests"
"$BUILD/tests"
