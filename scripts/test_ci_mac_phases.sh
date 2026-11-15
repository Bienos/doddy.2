#!/usr/bin/env bash
# Tests the Mac section of scripts/ci.sh as the hosted jobs drive it since 15 Nov 2026 (decision
# docs/decisions/2026-11-15-faster-mac-ci.md), on any OS, with stand-ins for xcodegen, xcrun, xcodebuild
# and swift that write down what they were asked to do:
#   - the simulator's boot starts before the build and is waited for before the unit tests;
#   - a failed background boot is booted again, and only a failed second boot fails the step;
#   - DODDY_RELEASE_BUILD=only builds Release for a device and nothing else, with no simulator;
#   - DODDY_SKIP_PACKAGE_TESTS=1 with --app-only leaves out the Swift package tests and says so.
#
#   scripts/test_ci_mac_phases.sh
#   CI_SCRIPT=/path/to/older/ci.sh scripts/test_ci_mac_phases.sh   (run the cases against another copy)
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
ci_script=${CI_SCRIPT:-$repo/scripts/ci.sh}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
calls="$tmp/calls"

bin="$tmp/bin"
mkdir -p "$bin"
cat > "$bin/xcodegen" <<'EOF'
#!/bin/sh
mkdir -p Doddy.xcodeproj/project.xcworkspace
EOF
# FAKE_BOOT_FAILS=N: the first N boots fail. FAKE_BOOT_COUNTER counts them.
cat > "$bin/xcrun" <<'EOF'
#!/bin/sh
echo "xcrun $*" >> "$FAKE_CALLS"
case "$1 $2" in
  "simctl list") echo "    iPhone 17 (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA) (Shutdown)" ;;
  "simctl bootstatus")
    n=$(cat "$FAKE_BOOT_COUNTER" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FAKE_BOOT_COUNTER"
    if [ "$n" -le "${FAKE_BOOT_FAILS:-0}" ]; then echo "fake boot failed"; exit 149; fi ;;
esac
exit 0
EOF
cat > "$bin/xcodebuild" <<'EOF'
#!/bin/sh
echo "xcodebuild $*" >> "$FAKE_CALLS"
exit 0
EOF
cat > "$bin/swift" <<'EOF'
#!/bin/sh
echo "swift $*" >> "$FAKE_CALLS"
exit 0
EOF
chmod +x "$bin"/*

root="$tmp/case"
out=""
# run_ci DESCRIPTION WANTED_EXIT ARGS ENV... : runs ci.sh in a fresh copy; $out holds its output.
run_ci() {
  local name=$1 want_exit=$2 args=$3; shift 3
  rm -rf "$root"; mkdir -p "$root/scripts" "$root/Config"; rm -f "$calls" "$tmp/boots"
  cp "$ci_script" "$root/scripts/ci.sh"
  cp "$repo/scripts/install_package_resolved.sh" "$root/scripts/"
  : > "$root/project.yml"
  local got
  # shellcheck disable=SC2086
  out=$(cd "$root" && env PATH="$bin:$PATH" FAKE_CALLS="$calls" FAKE_BOOT_COUNTER="$tmp/boots" CI_FETCH_WAIT=0 \
        DODDY_UI_TESTS=smoke "$@" bash scripts/ci.sh $args 2>&1)
  got=$?
  if [ "$got" = "$want_exit" ]; then echo "ok    exit=$want_exit  $name"
  else echo "FAIL  $name: wanted exit $want_exit, got $got"; grep -E "^(PASS|FAIL|SKIPPED|NOT RUN) |RESULT:" <<<"$out" | sed 's/^/        /'; failures=$((failures + 1)); fi
}
has() {  # description, fixed text that must be in the output
  if grep -qF -- "$2" <<<"$out"; then echo "ok    $1"; else echo "FAIL  $1: no \"$2\" in the output"; failures=$((failures + 1)); fi
}
called() {  # description, fixed text that must be in a call
  if grep -qF -- "$2" "$calls" 2>/dev/null; then echo "ok    $1"; else echo "FAIL  $1: nothing called with \"$2\""; failures=$((failures + 1)); fi
}
not_called() {  # description, fixed text that must be in no call
  if ! grep -qF -- "$2" "$calls" 2>/dev/null; then echo "ok    $1"; else echo "FAIL  $1: called with \"$2\""; failures=$((failures + 1)); fi
}
line_of() { grep -nF -- "$1" "$calls" 2>/dev/null | head -1 | cut -d: -f1; }
before() {  # description, earlier call text, later call text
  local a b; a=$(line_of "$2"); b=$(line_of "$3")
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then echo "ok    $1"; else echo "FAIL  $1: \"$2\" (line ${a:-none}) not before \"$3\" (line ${b:-none})"; failures=$((failures + 1)); fi
}

# The usual pull-request run: boot in the background before the build, wait for it before the unit tests.
run_ci "simulator boot started before the build" 0 "--only ios"
before "the boot is asked for before build-for-testing" "simctl bootstatus AAAAAAAA" "xcodebuild build-for-testing"
before "the unit tests start after the build" "xcodebuild build-for-testing" "test-without-building"
has "the wait for the boot is its own step and passes" "PASS     Simulator booted (started before the build)"
not_called "no Release build on a pull request" "-configuration Release"

# A failed background boot loses only the head start.
run_ci "background boot fails once: booted again, run passes" 0 "--only ios" FAKE_BOOT_FAILS=1
has "the second boot is announced" "The background boot failed (exit 149); booting the simulator again now."
has "the step passes after the second boot" "PASS     Simulator booted (started before the build)"
run_ci "both boots fail: the step fails, the run fails" 1 "--only ios" FAKE_BOOT_FAILS=2
has "the failed boot is in the summary" "FAIL     Simulator booted (started before the build)"

# A named destination: this script did not pick the simulator, so it boots nothing early.
run_ci "DODDY_DESTINATION: no early boot" 0 "--only ios" "DODDY_DESTINATION=platform=iOS Simulator,name=iPhone 17"
not_called "no bootstatus call with a named destination" "simctl bootstatus"

# The ios-release job: Release for a device, nothing else, no simulator.
run_ci "DODDY_RELEASE_BUILD=only" 0 "--only ios" DODDY_RELEASE_BUILD=only
called "Release is built for a generic device" "-configuration Release -destination generic/platform=iOS"
not_called "no build for testing" "build-for-testing"
not_called "no tests" "test-without-building"
not_called "no simulator is booted" "simctl bootstatus"
has "the skipped tests are in the summary" "SKIPPED  xcodebuild build-for-testing, unit and UI tests (DODDY_RELEASE_BUILD=only: the ios-build job runs them)"

# DODDY_RELEASE_BUILD=1 (a full run) still builds Release after the tests.
run_ci "DODDY_RELEASE_BUILD=1: tests, then Release" 0 "--only ios" DODDY_RELEASE_BUILD=1
before "Release comes after the tests" "test-without-building" "-configuration Release"

# Hosted pull requests: the Linux swift job runs the package tests, the Mac leaves them out.
run_ci "--app-only with DODDY_SKIP_PACKAGE_TESTS=1" 0 "--app-only" DODDY_SKIP_PACKAGE_TESTS=1
not_called "swift test is not run" "swift test"
has "the summary says why" "SKIPPED  Swift package tests (DoddyCore) (DODDY_SKIP_PACKAGE_TESTS=1: the Linux swift job runs them; pushes to main run them here too)"
called "the app is still built" "xcodebuild build-for-testing"

if [ "$failures" -ne 0 ]; then echo "$failures check(s) failed"; exit 1; fi
echo "all Mac phase cases passed"
