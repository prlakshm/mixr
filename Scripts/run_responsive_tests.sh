#!/usr/bin/env bash
# Compiles and runs the standalone responsive-editor harnesses against the
# layout model (no Xcode test target required).
#
#   Scripts/run_responsive_tests.sh            # run all harnesses
#   Scripts/run_responsive_tests.sh layout     # column / transport / effects math
#   Scripts/run_responsive_tests.sh interaction
#   Scripts/run_responsive_tests.sh contract   # source-level contracts
#
# Works on macOS (xcrun swiftc) and Linux (swiftc on PATH or $SWIFT_BIN).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if command -v xcrun >/dev/null 2>&1; then
  SDK="$(xcrun --sdk macosx --show-sdk-path)"
  SWIFTC=(xcrun swiftc -sdk "$SDK")
elif [[ -n "${SWIFT_BIN:-}" ]]; then
  SWIFTC=("$SWIFT_BIN/swiftc")
else
  SWIFTC=(swiftc)
fi

# Pure CoreGraphics layout model — compiles without SwiftUI or UIKit.
SOURCES=(
  "$ROOT/Mixr/DesignSystem/EditorLayoutMetrics.swift"
)

run_harness() {
  local test_file="$1" out="$2"
  shift 2
  # Top-level statements require a single main file.
  local main="$ROOT/main.swift"
  cp "$test_file" "$main"
  trap 'rm -f "$ROOT/main.swift"' EXIT

  echo "Compiling $(basename "$test_file")…"
  "${SWIFTC[@]}" -O "$@" "$main" -o "$out"
  rm -f "$main"

  echo "Running…"
  (cd "$ROOT" && "$out")
}

WHICH="${1:-all}"

if [[ "$WHICH" == "layout" || "$WHICH" == "all" ]]; then
  run_harness "$ROOT/DevTests/ResponsiveEditorLayoutTests.swift" \
    /tmp/mixr_responsive_layout_tests "${SOURCES[@]}"
fi

if [[ "$WHICH" == "interaction" || "$WHICH" == "all" ]]; then
  run_harness "$ROOT/DevTests/ResponsiveEditorInteractionTests.swift" \
    /tmp/mixr_responsive_interaction_tests "${SOURCES[@]}"
fi

# Reads the sources from disk, so it needs no app files compiled in.
if [[ "$WHICH" == "contract" || "$WHICH" == "all" ]]; then
  run_harness "$ROOT/DevTests/ResponsiveEditorSourceContractTests.swift" \
    /tmp/mixr_responsive_contract_tests
fi
