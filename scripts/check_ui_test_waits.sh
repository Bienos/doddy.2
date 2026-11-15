#!/usr/bin/env bash
# The UI tests wait with `appears(timeout:)` and `pollUntil` (DoddyUITests/UITestLaunch.swift), never with
# XCTest's `waitForExistence(timeout:)` or an XCTNSPredicateExpectation, which look the first time only
# about a second after they start: on 15 Nov 2026 that second was about 8 of the full UI suite's 33
# minutes (decision docs/decisions/2026-11-15-faster-mac-ci.md). Fails, naming the lines, when one comes
# back; comments don't count. `scripts/check_ui_test_waits.sh DIR` checks another folder (its tests).
set -uo pipefail
dir=${1:-DoddyUITests}
hits=$(grep -rnE '\.waitForExistence\(|XCTNSPredicateExpectation\(' --include='*.swift' "$dir" \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*///?' || true)
if [ -n "$hits" ]; then
  echo "These UI test lines use XCTest's one-second wait; use appears(timeout:) or pollUntil (UITestLaunch.swift):" >&2
  printf '%s\n' "$hits" >&2
  exit 1
fi
echo "No UI test waits on XCTest's one-second check."
