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
echo "$STORAGE/Mixr Demo"
