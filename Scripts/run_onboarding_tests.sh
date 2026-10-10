#!/usr/bin/env bash
# Onboarding tour: flow model + wiring checks (no Xcode needed).
#   Scripts/run_onboarding_tests.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if command -v xcrun >/dev/null 2>&1; then
  SWIFTC=(xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)")
elif [[ -n "${SWIFT_BIN:-}" ]]; then SWIFTC=("$SWIFT_BIN/swiftc"); else SWIFTC=(swiftc); fi
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/DevTests/OnboardingTourTests.swift" "$WORK/main.swift"
"${SWIFTC[@]}" "$ROOT/Mixr/Models/OnboardingTour.swift" "$WORK/main.swift" -o "$WORK/onboarding_tests"
"$WORK/onboarding_tests" "$ROOT"
