#!/usr/bin/env bash
# Compiles and runs DevTests/AutoRemixPipelineTests.swift against the Auto
# plan pipeline sources (no Xcode test target required).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="/tmp/mixr_auto_remix_tests"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

SOURCES=(
  "$ROOT/Mixr/Models/MixrTimeline.swift"
  "$ROOT/Mixr/Models/ClipEffects.swift"
  "$ROOT/Mixr/Models/MixrTrack.swift"
  "$ROOT/Mixr/Models/SongAnalysis.swift"
  "$ROOT/Mixr/Models/SoundEffects.swift"
  "$ROOT/Mixr/Models/AutoCompatibility.swift"
  "$ROOT/Mixr/Models/AutoSectionCatalog.swift"
  "$ROOT/Mixr/Models/AutoRemixPlan.swift"
  "$ROOT/Mixr/Models/AutoRemixPlanner.swift"
  "$ROOT/Mixr/Models/AutoRemixValidator.swift"
  "$ROOT/Mixr/Models/AutoRemixApplier.swift"
  "$ROOT/Mixr/Models/AutoRemixRunner.swift"
  "$ROOT/Mixr/Models/AutoArrangementEngine.swift"
  "$ROOT/DevTests/AutoRemixTestStubs.swift"
  "$ROOT/DevTests/AutoRemixPipelineTests.swift"
)

# Top-level statements require a single main file (same pattern as FlangerKernelTests).
MAIN="$ROOT/main.swift"
cp "$ROOT/DevTests/AutoRemixPipelineTests.swift" "$MAIN"
trap 'rm -f "$MAIN"' EXIT

# Drop the tests file from SOURCES — it's now main.swift
FILTERED=()
for s in "${SOURCES[@]}"; do
  [[ "$s" == *AutoRemixPipelineTests.swift ]] && continue
  FILTERED+=("$s")
done

echo "Compiling Auto remix pipeline tests…"
xcrun swiftc -sdk "$SDK" -O \
  "${FILTERED[@]}" \
  "$MAIN" \
  -o "$OUT"

echo "Running…"
"$OUT"
