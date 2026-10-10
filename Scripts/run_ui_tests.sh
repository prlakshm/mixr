#!/usr/bin/env bash
# Mixr UI tests (XCUITest, landscape iPhone).
#   Scripts/run_ui_tests.sh [simulator-udid-or-name] [-only-testing:MixrUITests/...]
# Screenshots land in output/ui-test-screenshots/ (EXIF-rotated landscape).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:-iPhone 16 Pro Max}"; shift || true
UDID="$(xcrun simctl list devices available | grep -F "$DEVICE (" | head -1 | grep -oE '[0-9A-F-]{36}' || true)"
[[ -z "$UDID" ]] && UDID="$DEVICE"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
python3 "$ROOT/Scripts/generate_demo_songs.py" "$ROOT/output/demo-songs" >/dev/null
"$ROOT/Scripts/stage_demo_songs.sh" "$UDID" >/dev/null
export TEST_RUNNER_MIXR_DEMO_SONGS_DIR="$ROOT/output/demo-songs"
export TEST_RUNNER_MIXR_DESIGN_CAPTURE="${MIXR_DESIGN_CAPTURE:-0}"
export TEST_RUNNER_MIXR_SHOCKWAVE="${MIXR_SHOCKWAVE:-}"
export TEST_RUNNER_MIXR_SCREENSHOT_DIR="${MIXR_SCREENSHOT_DIR:-$ROOT/output/ui-test-screenshots}"
STATUS=0
xcodebuild test -project "$ROOT/Mixr.xcodeproj" -scheme Mixr \
  -destination "id=$UDID" \
  -derivedDataPath "${MIXR_DERIVED_DATA:-$ROOT/.build/DerivedData}" \
  "$@" || STATUS=$?
if compgen -G "$TEST_RUNNER_MIXR_SCREENSHOT_DIR/*.png" >/dev/null; then
  python3 "$ROOT/Scripts/normalize_screenshots.py" "$TEST_RUNNER_MIXR_SCREENSHOT_DIR"
fi
exit $STATUS
