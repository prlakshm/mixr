#!/usr/bin/env bash
# Encode a copyright-free control through the app's AAC delivery path.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/DevTests/AutoAACPeakTests.swift"
RESULTS="${1:?Usage: run_aac_peak_tests.sh OUTPUT_DIRECTORY}"
mkdir -p "$RESULTS"
OUT="$RESULTS/aac-peak-tests"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
# Swift needs top-level code in a file called main.swift, but NOT at the repo
# root: run_auto_remix_tests.sh uses $ROOT/main.swift too, and running both at
# once made each clobber the other ("input file was modified during the
# build"). Own directory = the two harnesses are safe to run concurrently.
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mixr-listen-XXXXXX")"
MAIN="$BUILD_DIR/main.swift"

cp "$SRC" "$MAIN"
trap 'rm -rf "$BUILD_DIR"' EXIT

SOURCES=(
  "$ROOT/Mixr/Models/MixrTimeline.swift"
  "$ROOT/Mixr/Models/ClipEffects.swift"
  "$ROOT/Mixr/Models/ClipEffectDSP.swift"
  "$ROOT/Mixr/Models/ClipFlanger.swift"
  "$ROOT/Mixr/Models/MixrTrack.swift"
  "$ROOT/Mixr/Models/MixrExportRenderer.swift"
  "$ROOT/Mixr/Models/SongAnalysis.swift"
  "$ROOT/Mixr/Models/SongSignalAnalysis.swift"
  "$ROOT/Mixr/Models/SoundEffects.swift"
  "$ROOT/Mixr/Models/SFXSynthesizer.swift"
  "$ROOT/Mixr/Models/AutoClubTempo.swift"
  "$ROOT/Mixr/Models/AutoClubPulse.swift"
  "$ROOT/Mixr/Models/AutoClubFlavor.swift"
  "$ROOT/Mixr/Models/AutoCompatibility.swift"
  "$ROOT/Mixr/Models/AutoMashability.swift"
  "$ROOT/Mixr/Models/AutoPivotWord.swift"
  "$ROOT/Mixr/Models/AutoStemSidecar.swift"
  "$ROOT/Mixr/Models/AutoSectionCatalog.swift"
  "$ROOT/Mixr/Models/AutoChorusIsland.swift"
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

echo "Compiling AAC peak control…"
xcrun swiftc -sdk "$SDK" -O \
  -framework AVFoundation -framework CoreMedia -framework AudioToolbox -framework CoreAudio \
  "${SOURCES[@]}" "$MAIN" -o "$OUT"
rm -rf "$BUILD_DIR"
trap - EXIT

echo "Encoding AAC control..."
"$OUT" "$RESULTS" "${@:2}"
