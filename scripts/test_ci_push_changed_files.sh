#!/usr/bin/env bash
# Tests for scripts/ci_push_changed_files.sh (decision 2026-11-15-faster-mac-ci), together with
# scripts/ci_needs_mac.sh as the workflow chains them on a push to `main`, in a throwaway git repository
# with a shallow clone like the hosted checkout. When the list can't be made, the Mac must run.
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

git_q() { git -c user.name=t -c user.email=t@example.invalid -c init.defaultBranch=main "$@" >/dev/null 2>&1; }
origin="$tmp/origin"
git_q init "$origin"
commit() {  # message, files...
  local msg=$1; shift
  for f in "$@"; do mkdir -p "$origin/$(dirname "$f")"; echo "$msg" >> "$origin/$f"; done
  git_q -C "$origin" add -A
  git_q -C "$origin" commit -m "$msg"
  git -C "$origin" rev-parse HEAD
}
base=$(commit base README.md DoddyApp/A.swift docs/x.md)
docs=$(commit docs docs/x.md changes/note.md STATUS.md)
app=$(commit app DoddyApp/A.swift docs/x.md)
server=$(commit server server/messaging/src/a.ts backend/b.ts)

# expect WANTED_MAC DESCRIPTION BEFORE PUSHED: a depth-2 clone of PUSHED, as actions/checkout makes it.
expect() {
  local want=$1 what=$2 before=$3 pushed=$4 work="$tmp/work" got
  rm -rf "$work"
  git_q clone -q --no-local --depth=2 --branch main "file://$origin" "$work"
  git_q -C "$work" checkout -q "$pushed"
  got=$(cd "$work" && "$repo/scripts/ci_push_changed_files.sh" "$before" 2>/dev/null | "$repo/scripts/ci_needs_mac.sh" 2>/dev/null)
  if [ "$got" = "mac=$want" ]; then echo "ok    mac=$want  $what"; else echo "FAIL  wanted mac=$want, got '$got': $what"; failures=$((failures + 1)); fi
}
git_q -C "$origin" checkout -q -B main "$docs"
expect false "a push of documents and change notes only" "$base" "$docs"
git_q -C "$origin" checkout -q -B main "$app"
expect true "a push that changes app code (with documents)" "$docs" "$app"
git_q -C "$origin" checkout -q -B main "$server"
expect false "a push of server code only (the Linux groups test it)" "$app" "$server"
expect true "several commits at once, one of them app code: the diff covers them all" "$docs" "$server"
expect true "a new branch (before is all zeros)" 0000000000000000000000000000000000000000 "$server"
expect true "no before at all" "" "$server"
expect true "a before that isn't a commit id" "not-a-sha;rm" "$server"
expect true "a before that can't be fetched" 1234567890abcdef1234567890abcdef12345678 "$server"

if [ "$failures" -ne 0 ]; then echo "$failures check(s) failed"; exit 1; fi
echo "all push changed-file cases passed"
