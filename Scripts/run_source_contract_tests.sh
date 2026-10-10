#!/usr/bin/env bash
# Source-level UI contract harnesses in DevTests/ (no Xcode target needed).
# Each is a standalone Swift script that reads the app sources from the
# repo root.
#   Scripts/run_source_contract_tests.sh [Name ...]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if command -v xcrun >/dev/null 2>&1; then
  SWIFTC=(xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)")
else
  SWIFTC=(swiftc)
fi
TESTS=("$@")
if [[ ${#TESTS[@]} -eq 0 ]]; then
  TESTS=(ClipEditingUILayoutTests SFXUILayoutTests TimelineEmptyStateUILayoutTests
         GrayContrastTokenTests PartyModeArchitectureTests)
fi
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
STATUS=0
for name in "${TESTS[@]}"; do
  cp "DevTests/$name.swift" "$WORK/main.swift"
  if ! "${SWIFTC[@]}" "$WORK/main.swift" -o "$WORK/$name" 2>"$WORK/$name.log"; then
    echo "== $name: COMPILE ERROR"; cat "$WORK/$name.log"; STATUS=1; continue
  fi
  if "$WORK/$name" >"$WORK/$name.out" 2>&1; then
    echo "== $name: passed ($(grep -c '^PASS' "$WORK/$name.out") checks)"
  else
    echo "== $name: FAILED"; grep -E '^FAIL|rror' "$WORK/$name.out"; STATUS=1
  fi
done
exit $STATUS
