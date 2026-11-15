#!/usr/bin/env bash
# Lists the files a push to `main` changed, for scripts/ci_needs_mac.sh (decision
# docs/decisions/2026-11-15-faster-mac-ci.md): a push whose files can't reach the app build (documents,
# change notes, the servers, the site; the same list pull requests use) doesn't take a Mac for 50 minutes.
# Every Linux group still runs on every push (ADR-811); only the Mac jobs read this list.
#
#   scripts/ci_push_changed_files.sh BEFORE_SHA     (in a checkout of the pushed commit)
#
# Prints the changed paths on stdout, one per line. Prints nothing when it can't tell (a new branch, a
# commit it can't fetch, a diff that fails), and ci_needs_mac.sh runs the Mac for an empty list: when in
# doubt, everything runs.
set -uo pipefail

before=${1:-}
case "$before" in
  "" | *[!0-9a-f]* | 0000000000000000000000000000000000000000)
    echo "No usable previous commit for this push ('$before'): everything runs." >&2
    exit 0 ;;
esac
if ! git cat-file -e "$before^{commit}" 2>/dev/null; then
  if ! git fetch -q --depth=1 origin "$before" 2>/dev/null; then
    echo "Couldn't fetch the previous commit $before: everything runs." >&2
    exit 0
  fi
fi
if ! list=$(git diff --name-only --no-renames "$before" HEAD 2>/dev/null); then
  echo "Couldn't compare $before with the pushed commit: everything runs." >&2
  exit 0
fi
printf '%s\n' "$list" | sed '/^$/d'
