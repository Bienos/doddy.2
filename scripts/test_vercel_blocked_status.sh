#!/usr/bin/env bash
# Tests for scripts/vercel_blocked_status.sh (decision 2026-11-09-vercel-blocked-status): which Vercel
# statuses the workflow replaces. The costly mistake is hiding a real failure, so most cases must be left alone.
set -uo pipefail
cd "$(dirname "$0")/.."

failures=0
expect() {  # expected exit (0 replace | 1 leave), description, context, state, message, branches...
  local want=$1 what=$2 context=$3 state=$4 message=$5; shift 5
  local got
  CONTEXT=$context STATE=$state DESCRIPTION=$message scripts/vercel_blocked_status.sh "$@" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    echo "ok    exit=$want  $what"
  else
    echo "FAIL  wanted exit $want, got $got: $what"
    failures=$((failures + 1))
  fi
}

blocked="Account is blocked."

# Replaced: the old account's red on a working branch.
expect 0 "site, claude branch" "Vercel – doddy" failure "$blocked" claude/kind-maxwell-xpnfhj
expect 0 "gateway, claude branch" "Vercel – doddy-gateway" failure "$blocked" claude/x
expect 0 "voice token, claude branch" "Vercel – doddy-voice-token" failure "$blocked" claude/x
expect 0 "two claude branches at one commit" "Vercel – doddy" failure "$blocked" claude/a claude/b

# Left alone: anything on main, or a branch Vercel builds.
expect 1 "main" "Vercel – doddy" failure "$blocked" main
expect 1 "main and a claude branch at one commit" "Vercel – doddy" failure "$blocked" claude/a main
expect 1 "a dependabot branch (Vercel builds it)" "Vercel – doddy" failure "$blocked" dependabot/npm/x
expect 1 "a branch merely containing claude" "Vercel – doddy" failure "$blocked" work-claude/x
expect 1 "the bare prefix" "Vercel – doddy" failure "$blocked" claude/
expect 1 "no branch" "Vercel – doddy" failure "$blocked"

# Left alone: any other Vercel message or state.
expect 1 "a build error" "Vercel – doddy" failure "Deployment has failed" claude/x
expect 1 "rate limited" "Vercel – doddy" failure "Deployment rate limited" claude/x
expect 1 "an error state" "Vercel – doddy" error "$blocked" claude/x
expect 1 "pending" "Vercel – doddy" pending "Vercel is deploying your app" claude/x
expect 1 "success" "Vercel – doddy" success "Canceled by Ignored Build Step" claude/x

# Left alone: another check or another Vercel project.
expect 1 "another Vercel project" "Vercel – mealprep" failure "$blocked" claude/x
expect 1 "a hyphen instead of the en dash" "Vercel - doddy" failure "$blocked" claude/x
expect 1 "Xcode Cloud" "Doddy | Default" failure "$blocked" claude/x
expect 1 "no context" "" failure "$blocked" claude/x

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed."
  exit 1
fi
echo "All cases pass."
