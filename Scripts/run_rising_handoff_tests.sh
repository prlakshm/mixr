#!/usr/bin/env bash
# Check phrase continuity, handoff timing and a rendered consonant control.
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

RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mixr-handoff-tests.XXXXXX")"
trap 'rm -rf "$RUN_DIR"' EXIT
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/mixr-handoff-cache}"
export SWIFT_MODULECACHE_PATH="$CLANG_MODULE_CACHE_PATH"
cp "$ROOT/DevTests/AutoRisingHandoffTests.swift" "$RUN_DIR/main.swift"
"${SWIFTC[@]}" -O "${SOURCES[@]}" "$RUN_DIR/main.swift" -o "$RUN_DIR/tests"
"$RUN_DIR/tests"
