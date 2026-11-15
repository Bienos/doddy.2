#!/usr/bin/env bash
# Tests for scripts/check_ui_test_waits.sh (decision 2026-11-15-faster-mac-ci).
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
failures=0
expect() {  # wanted exit, description, swift source
  mkdir -p "$tmp/t"; rm -f "$tmp/t"/*.swift; printf '%s\n' "$3" > "$tmp/t/A.swift"
  "$repo/scripts/check_ui_test_waits.sh" "$tmp/t" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$1" ]; then echo "ok    exit=$1  $2"; else echo "FAIL  wanted exit $1, got $got: $2"; failures=$((failures + 1)); fi
}
expect 0 "appears(timeout:)" '        XCTAssertTrue(app.buttons["x"].appears(timeout: 5))'
expect 1 "waitForExistence comes back" '        XCTAssertTrue(app.buttons["x"].waitForExistence(timeout: 5))'
expect 1 "a predicate expectation" '        let w = XCTNSPredicateExpectation(predicate: p, object: e)'
expect 0 "named in a doc comment" '    /// `waitForExistence(timeout:)` without its first second'
expect 0 "named in a comment" '        // .waitForExistence(timeout: 5) looked only after a second'
"$repo/scripts/check_ui_test_waits.sh" "$repo/DoddyUITests" >/dev/null 2>&1 \
  && echo "ok    the repository's UI tests pass" || { echo "FAIL  the repository's UI tests use a one-second wait"; failures=$((failures + 1)); }
if [ "$failures" -ne 0 ]; then echo "$failures check(s) failed"; exit 1; fi
echo "all UI-test wait cases passed"
