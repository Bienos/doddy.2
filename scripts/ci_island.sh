#!/usr/bin/env bash
# The quick island-only Mac check (owner, 24 Oct 2026: "zrób szybko", ADR-610): builds the app once
# and runs only the Dynamic Island's tests, so its pictures (build/island-screenshots) and the
# simulator's screenshots of the real island (in the .xcresult) come in about 15 to 20 minutes
# instead of the full run's 45. It proves nothing about the rest of the app: before a merge the
# full run (scripts/ci.sh) still has to pass. macOS with Xcode and XcodeGen only.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodebuild >/dev/null 2>&1 || { echo "NOT RUN: xcodebuild not found (needs macOS with Xcode)"; exit 2; }
command -v xcodegen >/dev/null 2>&1 || { echo "NOT RUN: xcodegen not found (brew install xcodegen)"; exit 2; }

xcodegen generate --spec project.yml
sim_id=$(xcrun simctl list devices available | grep -E '^ +iPhone' | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$sim_id" ] || { echo "NOT RUN: no available iPhone simulator"; exit 2; }
dest="platform=iOS Simulator,id=${sim_id}"
echo "Destination: $dest"

xcodebuild build-for-testing -project Doddy.xcodeproj -scheme Doddy -destination "$dest"
# The island's views drawn in every state, in English and Polish, and their checks.
xcodebuild test-without-building -project Doddy.xcodeproj -scheme Doddy -destination "$dest" \
  -only-testing:DoddyTests/IslandScreenshotTests -only-testing:DoddyTests/IslandBaselineTests \
  -only-testing:DoddyTests/VoiceSessionControllerTests/testTranslatorStartsAtOnceWithoutAQuestion
# As in ci.sh (ADR-561): the UI tests start on a freshly restarted simulator.
xcrun simctl shutdown "$sim_id" 2>/dev/null || true
xcrun simctl bootstatus "$sim_id" -b
# The real island on the simulator, in English and in Polish (offline fixture).
xcodebuild test-without-building -project Doddy.xcodeproj -scheme Doddy -destination "$dest" \
  -only-testing:DoddyUITests/MemoryBaselineTests/testNativeIslandOfflineFixtureCanStartMuteAndEnd \
  -only-testing:DoddyUITests/IslandPolishTests
echo "RESULT: PASS for the island only; the rest of the app is NOT verified by this run"
