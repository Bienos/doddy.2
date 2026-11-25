#!/usr/bin/env bash
# Gives every tracked file under the named paths a modification time derived from its content (25 Nov 2026).
#
# Why: CI restores SwiftPM's .build folder from a cache, but a fresh checkout gives every file a new time, so
# the Swift driver recompiles all of DoddyCore (101 of the swift job's 190 s on run 45575743664). With the
# time taken from the file's git blob hash, a file whose content is the same as when the cache was built has
# the same time as then, and only changed files (and what depends on them) compile again. A changed file
# gets a different time, because its hash differs; two different contents share a time only if the first
# seven hex digits of their hashes agree modulo 300,000,000 (about one in 300 million per changed file).
# Every time lies between September 2001 and November 2011, never in the future.
#
#   scripts/ci_content_mtimes.sh Packages/DoddyCore [more paths...]
set -euo pipefail
[ "$#" -gt 0 ] || { echo "usage: ci_content_mtimes.sh PATH..." >&2; exit 64; }
cd "$(dirname "$0")/.."

base=1000000000   # 2001-09-09
span=300000000    # about 9.5 years
count=0
# safe.directory: in CI's container the checkout belongs to another user, and git refuses to read it otherwise.
while IFS= read -r -d '' entry; do
  meta=${entry%%$'\t'*} path=${entry#*$'\t'}
  sha=$(cut -d' ' -f2 <<<"$meta")
  [ -f "$path" ] || continue
  touch -m -d "@$((base + 16#${sha:0:7} % span))" "$path"
  count=$((count + 1))
done < <(git -c safe.directory='*' ls-files -s -z -- "$@")
echo "Content-based times set on $count file(s) under: $*"
