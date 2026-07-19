#!/usr/bin/env bash
# Compiles and runs the standalone Auto remix test harnesses against the
# plan-pipeline sources (no Xcode test target required).
#
#   Scripts/run_auto_remix_tests.sh            # run all harnesses
#   Scripts/run_auto_remix_tests.sh pipeline   # plan-legality tests only
#   Scripts/run_auto_remix_tests.sh render     # rendered-PCM quality tests only
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

# Shared plan-pipeline sources (pure Foundation — compile everywhere).
SOURCES=(
  "$ROOT/Mixr/Models/MixrTimeline.swift"
  "$ROOT/Mixr/Models/ClipEffects.swift"
  "$ROOT/Mixr/Models/MixrTrack.swift"
  "$ROOT/Mixr/Models/SongAnalysis.swift"
  "$ROOT/Mixr/Models/SongSignalAnalysis.swift"
  "$ROOT/Mixr/Models/SoundEffects.swift"
  "$ROOT/Mixr/Models/AutoCompatibility.swift"
  "$ROOT/Mixr/Models/AutoSectionCatalog.swift"
  "$ROOT/Mixr/Models/AutoRemixPlan.swift"
  "$ROOT/Mixr/Models/AutoRemixPlanner.swift"
  "$ROOT/Mixr/Models/AutoRemixValidator.swift"
  "$ROOT/Mixr/Models/AutoRemixApplier.swift"
  "$ROOT/Mixr/Models/AutoRemixRunner.swift"
  "$ROOT/Mixr/Models/AutoArrangementEngine.swift"
  "$ROOT/Mixr/Models/AutoTransitionEnvelope.swift"
  "$ROOT/Mixr/Models/AutoGainPolicy.swift"
  "$ROOT/Mixr/Models/AutoRemixDiagnostics.swift"
  "$ROOT/Mixr/Models/AutoOfflineMixdown.swift"
  "$ROOT/DevTests/AutoRemixTestStubs.swift"
)

run_harness() {
  local test_file="$1" out="$2"
  # Top-level statements require a single main file.
  local main="$ROOT/main.swift"
  cp "$test_file" "$main"
  trap 'rm -f "$ROOT/main.swift"' EXIT

  echo "Compiling $(basename "$test_file")…"
  "${SWIFTC[@]}" -O "${SOURCES[@]}" "$main" -o "$out"
  rm -f "$main"

  echo "Running…"
  "$out"
}

WHICH="${1:-all}"

if [[ "$WHICH" == "pipeline" || "$WHICH" == "all" ]]; then
  run_harness "$ROOT/DevTests/AutoRemixPipelineTests.swift" /tmp/mixr_auto_remix_tests
fi

if [[ "$WHICH" == "render" || "$WHICH" == "all" ]]; then
  run_harness "$ROOT/DevTests/AutoRemixRenderQualityTests.swift" /tmp/mixr_auto_render_tests
fi
