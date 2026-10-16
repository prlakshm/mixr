#!/usr/bin/env bash
# Puts Mixr's copyright-free demo songs into a simulator's Files app
# ("On My iPhone > Mixr Demo") so UI tests can import them through the real
# document picker.
#   Scripts/stage_demo_songs.sh <simulator-udid>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID="${1:?simulator udid}"
SONGS="$ROOT/output/demo-songs"
if [[ ! -f "$SONGS/Arlo Vance - Night Signals.m4a" ]]; then
  python3 "$ROOT/Scripts/generate_demo_songs.py" "$SONGS" >/dev/null
fi
GROUPS_DIR="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Containers/Shared/AppGroup"
find_storage() {
  for g in "$GROUPS_DIR"/*/; do
    if plutil -p "$g/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null \
        | grep -q '"group.com.apple.FileProvider.LocalStorage"'; then
      echo "$g/File Provider Storage"; return 0
    fi
  done
  return 1
}
if ! STORAGE="$(find_storage)"; then
  # The Files app creates its local storage on first launch.
  xcrun simctl launch "$UDID" com.apple.DocumentsApp >/dev/null
  sleep 4
  xcrun simctl terminate "$UDID" com.apple.DocumentsApp >/dev/null || true
  STORAGE="$(find_storage)"
fi
rm -rf "${STORAGE:?}/Mixr Demo"
mkdir -p "$STORAGE/Mixr Demo"
cp "$SONGS"/*.m4a "$STORAGE/Mixr Demo/"
# Two copyright-free videos for the MP4 import tests: a demo song with a plain
# colour picture (named unlike any song, so title-based picks stay exact), and
# a clip with no audio track. Needs ffmpeg (skipped
# without it; those two tests then can't find their files).
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -v error -y -f lavfi -i "color=c=0x7231DD:s=320x180:r=15" \
    -i "$SONGS/Sable Coast - Paper Suns.m4a" -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac \
    "$STORAGE/Mixr Demo/Sable Coast - Sunburst Clip.mp4"
  ffmpeg -v error -y -f lavfi -i "color=c=0x101018:s=320x180:r=15" -t 3 -c:v libx264 -pix_fmt yuv420p \
    "$STORAGE/Mixr Demo/Silent Clip.mp4"
fi
echo "$STORAGE/Mixr Demo"
