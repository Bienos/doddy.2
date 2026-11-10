#!/usr/bin/env bash
# Should a Vercel "Account is blocked." commit status be replaced? (decision 2026-11-09-vercel-blocked-status)
#
# An old Vercel account that still has this repository connected posts "Account is blocked." on every
# push. On `main`, the live team (`doddyyyy`) posts its own result for the same context right after, so
# the red disappears. On `claude/…` branches the live team builds nothing (ADR-498), so the red stays on
# every pull request. .github/workflows/vercel-blocked-status.yml calls this script for each failed Vercel
# status and replaces only those that match all of these:
#   - the context is one of the three live projects;
#   - the state is failure and the description is exactly "Account is blocked.";
#   - the commit is the head of at least one branch, and every such branch is a `claude/…` branch
#     (`main` is never touched, so a real production failure always shows).
#
# Usage: CONTEXT=… STATE=… DESCRIPTION=… scripts/vercel_blocked_status.sh BRANCH...
# Prints "replace" and exits 0 when the status should be replaced; prints the reason and exits 1 otherwise.
set -uo pipefail

context=${CONTEXT-}
state=${STATE-}
description=${DESCRIPTION-}

case "$context" in
  "Vercel – doddy" | "Vercel – doddy-gateway" | "Vercel – doddy-voice-token") ;;
  *) echo "leave: not one of Doddy's Vercel projects ($context)"; exit 1 ;;
esac

if [ "$state" != "failure" ]; then
  echo "leave: state is $state, not failure"
  exit 1
fi

if [ "$description" != "Account is blocked." ]; then
  echo "leave: a different Vercel message ($description)"
  exit 1
fi

if [ "$#" -eq 0 ]; then
  echo "leave: the commit is not the head of any branch"
  exit 1
fi

for branch in "$@"; do
  case "$branch" in
    claude/?*) ;;
    *) echo "leave: the commit is also the head of $branch, which Vercel builds"; exit 1 ;;
  esac
done

echo "replace"
