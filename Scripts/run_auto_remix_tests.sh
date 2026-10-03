#!/usr/bin/env bash
# Compiles and runs the standalone Auto remix test harnesses against the
# plan-pipeline sources (no Xcode test target required).
#
#   Scripts/run_auto_remix_tests.sh            # run all harnesses
#   Scripts/run_auto_remix_tests.sh pipeline   # plan-legality tests only
#   Scripts/run_auto_remix_tests.sh render     # rendered-PCM quality tests only
#   Scripts/run_auto_remix_tests.sh golden     # perceptual golden tier
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
  "$ROOT/Mixr/Models/AutoChorusIsland.swift"
  "$ROOT/Mixr/Models/SoundEffects.swift"
  "$ROOT/Mixr/Models/AutoClubTempo.swift"
  "$ROOT/Mixr/Models/AutoClubPulse.swift"
  "$ROOT/Mixr/Models/AutoClubFlavor.swift"
  "$ROOT/Mixr/Models/AutoCompatibility.swift"
  "$ROOT/Mixr/Models/AutoMashability.swift"
  "$ROOT/Mixr/Models/AutoPivotWord.swift"
  "$ROOT/Mixr/Models/AutoStemSidecar.swift"
  "$ROOT/Mixr/Models/AutoSectionCatalog.swift"
  "$ROOT/Mixr/Models/AutoRemixPlan.swift"
  "$ROOT/Mixr/Models/AutoJoinManifest.swift"
  "$ROOT/Mixr/Models/AutoRemixPlanner.swift"
  "$ROOT/Mixr/Models/AutoJoinEngine.swift"
  "$ROOT/Mixr/Models/AutoRemixValidator.swift"
  "$ROOT/Mixr/Models/AutoRemixApplier.swift"
  "$ROOT/Mixr/Models/AutoRemixRunner.swift"
  "$ROOT/Mixr/Models/AutoArrangementEngine.swift"
  "$ROOT/Mixr/Models/AutoTransitionEnvelope.swift"
  "$ROOT/Mixr/Models/AutoGainPolicy.swift"
  "$ROOT/Mixr/Models/AutoRemixDiagnostics.swift"
  "$ROOT/Mixr/Models/AutoOfflineMixdown.swift"
  "$ROOT/Mixr/Models/AutoListenLoop.swift"
  "$ROOT/Mixr/Models/AutoMasterBus.swift"
  "$ROOT/Mixr/Models/AutoPCMLoader.swift"
  "$ROOT/DevTests/AutoRemixTestStubs.swift"
)

WHICH="${1:-all}"
case "$WHICH" in
  all) EXPECTED=5 ;;
  pipeline|render|club|join|golden) EXPECTED=1 ;;
  *) echo "Unknown harness: $WHICH" >&2; exit 2 ;;
esac

# Each invocation owns its compiler inputs and outputs. Never overwrite a
# caller's main.swift or collide with another simultaneous test run.
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mixr-auto-tests.XXXXXX")"
trap 'rm -rf "$RUN_DIR"' EXIT
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$RUN_DIR/module-cache}"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-$CLANG_MODULE_CACHE_PATH}"
COMPLETED=0

run_harness() {
  local test_file="$1" name="$2"
  local main="$RUN_DIR/main.swift" out="$RUN_DIR/$name" log="$RUN_DIR/$name.log"
  cp "$test_file" "$main"
  echo "Compiling $(basename "$test_file")…"
  "${SWIFTC[@]}" -O "${SOURCES[@]}" "$main" -o "$out"
  echo "Running ${name}..."
  local rc=0
  "$out" >"$log" 2>&1 || rc=$?
  cat "$log"
  if [[ "$rc" -ne 0 ]] || grep -qiE '^[[:space:]]*FAIL(ED)?([[:space:]:]|$)' "$log" \
     || grep -qE '^[[:space:]]*(SKIP(PED)?|INCONCLUSIVE)([[:space:]:]|$)' "$log" \
     || grep -qiE '[[:alnum:]_.-]+[[:space:]]*=[[:space:]]*(SKIP(PED)?|INCONCLUSIVE)([^[:alnum:]_]|$)' "$log" \
     || ! grep -qE '^PASS[[:space:]]' "$log" \
     || [[ "$(grep -c '^ALL PASSED$' "$log" || true)" -ne 1 ]]; then
    echo "HARNESS_FAILED name=$name exit=$rc (failure or incomplete evidence)" >&2
    return 1
  fi
  COMPLETED=$((COMPLETED + 1))
}

if [[ "$WHICH" == "pipeline" || "$WHICH" == "all" ]]; then
  run_harness "$ROOT/DevTests/AutoRemixPipelineTests.swift" pipeline
fi
if [[ "$WHICH" == "render" || "$WHICH" == "all" ]]; then
  run_harness "$ROOT/DevTests/AutoRemixRenderQualityTests.swift" render
fi
if [[ "$WHICH" == "club" || "$WHICH" == "all" ]]; then
  run_harness "$ROOT/DevTests/AutoClubRemixTests.swift" club
fi
if [[ "$WHICH" == "join" || "$WHICH" == "all" ]]; then
  run_harness "$ROOT/DevTests/AutoJoinEngineTests.swift" join
fi
if [[ "$WHICH" == "golden" || "$WHICH" == "all" ]]; then
  run_harness "$ROOT/DevTests/AutoRemixGoldenTests.swift" golden
fi
[[ "$COMPLETED" -eq "$EXPECTED" ]]
echo "HARNESS_SUMMARY completed=$COMPLETED expected=$EXPECTED"
