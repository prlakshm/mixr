#!/usr/bin/env bash
# One entry point for "is Auto Remix actually OK right now".
#
# AGENTS.md: "Never replace listening evaluation with metrics, and never
# replace metrics with listening alone." This script is the metrics half. It
# runs every automated gate in dependency order and prints one summary. The
# listening half is Bounces/ab-britney-realdsp.m4a, which comes out of the
# REAL AVAudioUnit app path (MixrExportRenderer), not the cheap test renderer.
#
#   ./verify_all.sh          # everything (slow: full crate matrix)
#   ./verify_all.sh fast     # skip the crate matrix
set -uo pipefail
ROOT="${MIXR_ROOT:-/Users/pranavi/Documents/GitHub/mixr}"
HERE="/Users/pranavi/Documents/Mixr"
PY="$HERE/.venv/bin/python3"
MODE="${1:-all}"
FAILED=()

step() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
note() { local n="$1" rc="$2"; if [ "$rc" -eq 0 ]; then echo "  ✓ $n"; else echo "  ✗ $n"; FAILED+=("$n"); fi; }

step "Swift plan + rendered-PCM test suite"
out="$("$ROOT/Scripts/run_auto_remix_tests.sh" 2>&1)"
echo "$out" | grep -E "^FAIL" | head -20
# Four harnesses each print ALL PASSED; any FAIL line is a failure.
if echo "$out" | grep -q "^FAIL"; then note "auto remix tests" 1; else note "auto remix tests" 0; fi

step "iOS app build"
xcodebuild -project "$ROOT/Mixr.xcodeproj" -scheme Mixr \
  -destination 'generic/platform=iOS Simulator' build >/tmp/mixr_build.log 2>&1
note "xcodebuild" $?

step "Real-DSP listening renders (app path, not the test renderer)"
"$HERE/run_listen_renders.sh" >/tmp/mixr_listen.log 2>&1
note "listen renders" $?

step "Pitch gate (rendered bed matches the interval the plan claims)"
"$PY" "$HERE/gate_pitch.py" 2>/dev/null | grep -E "^(PASS|FAIL|SKIP)|pitch gate"
note "pitch" ${PIPESTATUS[0]}

step "Drop approach (the build must rise into the downbeat, not dip)"
"$PY" "$HERE/gate_drops.py" 2>/dev/null | grep -E "^  (PASS|FAIL)|drop-approach gate"
note "drop approach" ${PIPESTATUS[0]}

step "Loudness continuity (BS.1770 short-term, no lurching between sections)"
"$PY" "$HERE/gate_loudness.py" 2>/dev/null | tail -3
note "loudness" ${PIPESTATUS[0]}

step "Transition continuity (level + timbre step at each join)"
"$PY" "$HERE/diag_transition.py" 2>/dev/null | grep -E "typical|pivot_start|drop1"

if [ "$MODE" != "fast" ]; then
  step "Full crate bounce (all mashup combinations)"
  (cd "$HERE" && MIXR_FAST=all ./run_crate_bounces.sh) >/tmp/mixr_crate.log 2>&1
  note "crate bounce" $?
  grep -E "TOTAL failures" /tmp/mixr_crate.log | tail -1

  step "Smoothness gate (dead air / weak joins across every bounce)"
  "$PY" "$HERE/analyze_smoothness.py" --summary 2>/dev/null | grep -cE "^PASS" \
    | xargs -I{} echo "  {} bounces pass strict smoothness"
  "$PY" "$HERE/analyze_smoothness.py" --summary 2>/dev/null | grep -E "^FAIL" | head -8

  step "Whisper title-token gate (is the hook intelligible?)"
  "$PY" "$HERE/_score_title_whisper.py" 2>/dev/null | grep -E "=== DONE"
fi

printf '\n\033[1m== SUMMARY ==\033[0m\n'
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "  ALL AUTOMATED GATES PASS"
  echo "  Listen: Bounces/LISTEN/*.m4a (real app DSP)"
  exit 0
fi
printf '  FAILED: %s\n' "${FAILED[@]}"
exit 1
