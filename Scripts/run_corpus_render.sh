#!/usr/bin/env bash
# Renders an Auto remix/mashup from real audio through the portable
# pipeline (see DevTests/AutoRemixCorpusRender.swift for the job format).
#   Scripts/run_corpus_render.sh job.json
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if command -v xcrun >/dev/null 2>&1; then
  SWIFTC=(xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)")
elif [[ -n "${SWIFT_BIN:-}" ]]; then SWIFTC=("$SWIFT_BIN/swiftc"); else SWIFTC=(swiftc); fi
BIN="${TMPDIR:-/tmp}/mixr_corpus_render"
SOURCES=(
  MixrTimeline ClipEffects MixrTrack SongAnalysis SongSignalAnalysis SongStructureAnalysis SoundEffects
  AutoCompatibility AutoSectionCatalog AutoRemixPlan AutoRemixPlanner AutoRemixValidator AutoRemixApplier
  AutoRemixRunner AutoArrangementEngine AutoTransitionEnvelope AutoGainPolicy AutoRemixDiagnostics AutoOfflineMixdown
)
FILES=()
for s in "${SOURCES[@]}"; do FILES+=("$ROOT/Mixr/Models/$s.swift"); done
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/DevTests/AutoRemixCorpusRender.swift" "$WORK/main.swift"
if [[ ! -x "$BIN" || -n "${REBUILD:-}" ]]; then
  "${SWIFTC[@]}" -O "${FILES[@]}" "$ROOT/DevTests/AutoRemixTestStubs.swift" "$WORK/main.swift" -o "$BIN"
fi
"$BIN" "$1"
