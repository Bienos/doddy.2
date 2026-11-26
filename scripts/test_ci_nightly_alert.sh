#!/usr/bin/env bash
# Tests for scripts/ci_nightly_alert.sh with a stand-in `gh` that writes down what it was asked to do.
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
mkdir -p "$tmp/bin"
# FAKE_OPEN: the number of the open alert issue, or empty for none.
cat > "$tmp/bin/gh" <<'EOF'
#!/bin/sh
echo "gh $*" >> "$FAKE_CALLS"
if [ "$1 $2" = "issue list" ]; then printf '%s\n' "$FAKE_OPEN"; fi
exit 0
EOF
chmod +x "$tmp/bin/gh"

run() {  # name, results, open issue number ("" for none)
  rm -f "$tmp/calls"
  out=$(PATH="$tmp/bin:$PATH" FAKE_CALLS="$tmp/calls" FAKE_OPEN="$3" RESULTS="$2" RUN_URL="https://example.test/run/1" \
    "$repo/scripts/ci_nightly_alert.sh" 2>&1) || { echo "FAIL  $1: exit non-zero: $out"; failures=$((failures + 1)); }
}
called() { if grep -qF -- "$2" "$tmp/calls"; then echo "ok    $1"; else echo "FAIL  $1: no call with \"$2\""; failures=$((failures + 1)); fi; }
not_called() { if ! grep -qF -- "$2" "$tmp/calls"; then echo "ok    $1"; else echo "FAIL  $1: called with \"$2\""; failures=$((failures + 1)); fi; }

run "a red night with no alert open" "success failure skipped" ""
called "it opens the alert" "gh issue create --title Nightly run on main failed"
called "the alert links the run" "https://example.test/run/1"

run "a red night with the alert open" "failure success" "42"
called "it comments on the open alert" "gh issue comment 42"
not_called "it opens no second alert" "issue create"

run "a cancelled job counts as red" "cancelled success" ""
called "a cancel opens the alert" "gh issue create"

run "a green night with the alert open" "success skipped success" "42"
called "it closes the alert" "gh issue close 42"

run "a green night with no alert" "success skipped" ""
not_called "nothing is opened" "issue create"
not_called "nothing is closed" "issue close"

out=$(RUN_URL=x "$repo/scripts/ci_nightly_alert.sh" 2>&1) && { echo "FAIL  no RESULTS, yet it ran"; failures=$((failures + 1)); } || echo "ok    no RESULTS: an error"

if [ "$failures" -ne 0 ]; then echo "$failures check(s) failed"; exit 1; fi
echo "all nightly alert checks pass"
