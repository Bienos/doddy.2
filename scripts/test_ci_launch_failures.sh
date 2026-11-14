#!/usr/bin/env bash
# Tests for scripts/ci_launch_failures.sh (decision 2026-11-13-ui-launch-retry): a failed UI test is
# run again only when the app would not start. The costly mistake is retrying a test that failed for
# a real reason, so most cases are those. The log lines are copied from hosted runs 43412031979,
# 43412040308 and 43412113691 (13 Nov 2026).
set -uo pipefail
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

case_log() {  # name; the log is on stdin
  cat > "$work/$1.log"
}
expect() {  # name, expected exit code, expected stdout, description
  local got rc
  got=$(scripts/ci_launch_failures.sh "$work/$1.log" 2>/dev/null); rc=$?
  if [ "$rc" = "$2" ] && [ "$got" = "$3" ]; then
    echo "ok    $4"
  else
    echo "FAIL  $4 (exit $rc, wanted $2; output '$got')"
    failures=$((failures + 1))
  fi
}

launch_timeout() {  # class, test: the first launch timed out (run 43412113691)
  echo "<unknown>:0: error: -[DoddyUITests.$1 $2] : Failed to launch <XCUIApplicationImpl: 0x600001720400 com.bienos.doddy2.dev at /Users/runner/DerivedData/Doddy.app> via Xcode: Timed out while launching application via Xcode."
  echo "Test Case '-[DoddyUITests.$1 $2]' failed (75.754 seconds)."
}
launch_progress() {  # class, test: no launch progress for 10 minutes (run 43412113691)
  echo "<unknown>:0: error: -[DoddyUITests.$1 $2] : Failed to get launch progress for <XCUIApplicationImpl: 0x600001720400 com.bienos.doddy2.dev>: No failure details provided"
  echo "Test Case '-[DoddyUITests.$1 $2]' failed (602.405 seconds)."
}
assertion() {  # class, test: the real failure behind run 43412031979
  echo "/Users/runner/work/doddy.2/doddy.2/DoddyUITests/MotionEvidenceTests.swift:63: error: -[DoddyUITests.$1 $2] : XCTAssertTrue failed"
  echo "Test Case '-[DoddyUITests.$1 $2]' failed (21.674 seconds)."
}

# Two tests that never launched the app: both are named, once, in the form -only-testing wants.
{ launch_timeout DoddyArtTests testAFailedSaveNeverPops; launch_progress DoddyArtTests testEmptyActivityShowsDoddyWaiting; } | case_log two
expect two 0 "-only-testing:DoddyUITests/DoddyArtTests/testAFailedSaveNeverPops
-only-testing:DoddyUITests/DoddyArtTests/testEmptyActivityShowsDoddyWaiting" "two tests that never launched the app are named"

# The hosted log puts a timestamp in front of every line.
launch_timeout DoddyArtTests testAFailedSaveNeverPops | sed 's/^/2026-11-13T11:47:35.7898510Z /' | case_log stamped
expect stamped 0 "-only-testing:DoddyUITests/DoddyArtTests/testAFailedSaveNeverPops" "lines with the runner's timestamp are read"

# A real failure is never retried.
assertion MotionEvidenceTests testHiddenPicturesLeaveNoGap | case_log assertion
expect assertion 1 "" "an assertion failure is not retried"

# One test that never launched next to a test that failed for a real reason: nothing is retried.
{ launch_timeout DoddyArtTests testAFailedSaveNeverPops; assertion MotionEvidenceTests testHiddenPicturesLeaveNoGap; } | case_log mixed
expect mixed 1 "" "a launch failure next to a real failure retries nothing"

# A test with both kinds of error (an assertion, then the app would not relaunch) is a real failure.
{ assertion MotionEvidenceTests testX | head -1; launch_timeout MotionEvidenceTests testX; } | case_log both
expect both 1 "" "a test with an assertion error and a launch error is a real failure"

# No test failed.
echo "Test Case '-[DoddyUITests.DoddyArtTests testOK]' passed (3.1 seconds)." | case_log passed
expect passed 1 "" "no failed test, nothing to retry"

# A failure with no error line (a crash, a kill) cannot be shown to be a launch failure.
echo "Test Case '-[DoddyUITests.DoddyArtTests testCrash]' failed (3.1 seconds)." | case_log silent
expect silent 1 "" "a failed test with no error line is not retried"

# The same test failing twice in one log is named once.
{ launch_timeout DoddyArtTests testA; launch_timeout DoddyArtTests testA; } | case_log twice
expect twice 0 "-only-testing:DoddyUITests/DoddyArtTests/testA" "a test that failed twice is named once"

# A test that merely mentions a launch message in its name does not make a real failure a launch one.
assertion DoddyArtTests testFailedToLaunch | case_log name
expect name 1 "" "a test name that looks like a launch error does not count"

# 25 tests that never launched the app are retried; 26 mean something bigger is wrong.
for n in $(seq 1 25); do launch_timeout DoddyArtTests "test$n"; done | case_log n25
for n in $(seq 1 26); do launch_timeout DoddyArtTests "test$n"; done | case_log n26
expect n25 0 "$(for n in $(seq 1 25); do echo "-only-testing:DoddyUITests/DoddyArtTests/test$n"; done | sort)" "25 tests that never launched the app are retried (named in sorted order)"
expect n26 1 "" "26 tests that never launched the app are not retried"

# No log at all.
if scripts/ci_launch_failures.sh "$work/missing.log" >/dev/null 2>&1; then rc=0; else rc=$?; fi
if [ "$rc" = 64 ]; then echo "ok    a missing log file is a usage error"; else echo "FAIL  a missing log file: exit $rc, wanted 64"; failures=$((failures + 1)); fi

if [ "$failures" -ne 0 ]; then echo "$failures case(s) failed"; exit 1; fi
echo "all cases passed"
