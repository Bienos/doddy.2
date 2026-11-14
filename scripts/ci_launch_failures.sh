#!/usr/bin/env bash
# Which UI tests failed only because the app would not start? (decision 2026-11-13-ui-launch-retry)
#
# Reads an xcodebuild test log (the file named by $1). When at least one test failed and EVERY failed
# test failed with nothing but a launch error, it prints one `-only-testing:Target/Class/test` line per
# failed test (the arguments to run just those tests again) and exits 0. Otherwise it prints nothing
# and exits 1: no failed test, a failed test with any other error (an assertion, a crash, a timeout in
# the test's own code) or with no error line at all, or more than 25 failed tests (something bigger
# than a slow first launch is wrong). It never says a test passed; it only names tests worth running once more.
#
# A launch error is one of the messages XCTest gives when the simulator did not let it take hold of
# the app, so no test code ran: "Failed to launch ... via Xcode: Timed out while launching
# application", "Failed to get launch progress for ..." (hosted runs 43412031979 and 43412113691,
# 13 Nov 2026; the same class as run 39496321722 on 20 Oct, ADR-561).
set -uo pipefail

log=${1:-}
[ -f "$log" ] || { echo "usage: ci_launch_failures.sh XCODEBUILD_LOG" >&2; exit 64; }
max_tests=25
launch='Failed to launch|Failed to get launch progress|Timed out while launching'

# "Test Case '-[DoddyUITests.DoddyArtTests testAFailedSaveNeverPops]' failed (67.247 seconds)."
failed=$(sed -nE "s/.*Test Case '-\[([A-Za-z0-9_]+)\.([A-Za-z0-9_]+) ([A-Za-z0-9_]+)\]' failed .*/\1 \2 \3/p" "$log" | sort -u)
[ -n "$failed" ] || exit 1
[ "$(printf '%s\n' "$failed" | wc -l | tr -d ' ')" -le "$max_tests" ] || exit 1

out=""
while read -r target class name; do
  # The test's own error lines: "<file>:<line>: error: -[Target.Class name] : <message>".
  errors=$(grep -F "error: -[$target.$class $name] :" "$log" || true)
  [ -n "$errors" ] || exit 1
  if printf '%s\n' "$errors" | grep -v -E "$launch" >/dev/null; then exit 1; fi
  out="$out-only-testing:$target/$class/$name
"
done <<EOF
$failed
EOF
printf '%s' "$out"
