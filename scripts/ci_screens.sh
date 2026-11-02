#!/usr/bin/env bash
# The screens run (owner, 2 Nov 2026: "Do", after asking for real pictures of every screen instead
# of mockups; ADR-693): builds the app once and runs only DoddyUITests/ScreenAtlasTests, which walks
# to each screen on the simulator and keeps a picture of it in build/screen-atlas/ (and an index.tsv
# of reached and missed screens), then ScreenFixtureTests, which launches the app with sample states
# (ADR-694) for what the offline simulator can't reach. The attachments in the .xcresult are exported too, in case the
# simulator couldn't write to build/. It checks nothing about how the app behaves: before a merge the
# full run (scripts/ci.sh) still has to pass. macOS with Xcode and XcodeGen only.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodebuild >/dev/null 2>&1 || { echo "NOT RUN: xcodebuild not found (needs macOS with Xcode)"; exit 2; }
command -v xcodegen >/dev/null 2>&1 || { echo "NOT RUN: xcodegen not found (brew install xcodegen)"; exit 2; }

rm -rf build/screen-atlas build/screen-atlas-attachments build/screen-atlas.xcresult
mkdir -p build/screen-atlas
xcodegen generate --spec project.yml
sim_id=$(xcrun simctl list devices available | grep -E '^ +iPhone' | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$sim_id" ] || { echo "NOT RUN: no available iPhone simulator"; exit 2; }
dest="platform=iOS Simulator,id=${sim_id}"
echo "Destination: $dest"

xcodebuild build-for-testing -project Doddy.xcodeproj -scheme Doddy -destination "$dest"
# As in ci.sh (ADR-561): the UI tests start on a freshly restarted simulator.
xcrun simctl shutdown "$sim_id" 2>/dev/null || true
xcrun simctl bootstatus "$sim_id" -b
# Each group is one test with its own 10-minute limit (ADR-680). TEST_RUNNER_ hands
# DODDY_SCREEN_ATLAS=1 to the test runner; without it every ScreenAtlasTests test skips.
status=0
# SCREENS_ONLY=fixtures (workflow input only=fixtures): skip the atlas walk, take only the sample-state pictures.
only_tests=(-only-testing:DoddyUITests/ScreenFixtureTests)
[ "${SCREENS_ONLY:-}" = "fixtures" ] || only_tests=(-only-testing:DoddyUITests/ScreenAtlasTests "${only_tests[@]}")
TEST_RUNNER_DODDY_SCREEN_ATLAS=1 xcodebuild test-without-building -project Doddy.xcodeproj -scheme Doddy -destination "$dest" \
  "${only_tests[@]}" -resultBundlePath build/screen-atlas.xcresult \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 600 || status=$?

# Every picture is also an attachment; export them (Xcode 16 and later) as a second copy.
xcrun xcresulttool export attachments --path build/screen-atlas.xcresult --output-path build/screen-atlas-attachments \
  >/dev/null 2>&1 || echo "Note: couldn't export the attachments from the .xcresult (needs Xcode 16 or later)"

reached=$(grep -c $'\treached' build/screen-atlas/index.tsv 2>/dev/null || true)
missed=$(grep -c $'\tmissed' build/screen-atlas/index.tsv 2>/dev/null || true)
echo "Screens kept: ${reached:-0} reached, ${missed:-0} missed (build/screen-atlas/index.tsv)"
if [ "$status" -ne 0 ]; then
  echo "RESULT: the screens run ended with xcodebuild status $status; the pictures it kept are still in build/"
  exit "$status"
fi
echo "RESULT: pictures only; nothing about the app's behaviour is verified by this run"
