#!/usr/bin/env bash
# Tests for scripts/ci_content_mtimes.sh in a throwaway git repository: the same content gets the same time
# in any checkout, changed content gets another time, every time is in the past, and only the named paths
# are touched.
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; failures=$((failures + 1)); }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

setup() {  # DIR: a repository with the script, two files of the same content, one other, and one outside
  mkdir -p "$1/scripts" "$1/Pkg/Sources" "$1/Other"
  cp "$repo/scripts/ci_content_mtimes.sh" "$1/scripts/"
  printf 'let a = 1\n' > "$1/Pkg/Sources/A.swift"
  printf 'let a = 1\n' > "$1/Pkg/Sources/Same.swift"
  printf 'let b = 2\n' > "$1/Pkg/Sources/B.swift"
  printf 'outside\n' > "$1/Other/C.txt"
  (cd "$1" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm one)
}

setup "$tmp/one"
touch -d "@1700000000" "$tmp/one/Other/C.txt"
out=$("$tmp/one/scripts/ci_content_mtimes.sh" Pkg 2>&1) || bad "the script failed: $out"
a=$(mtime "$tmp/one/Pkg/Sources/A.swift") same=$(mtime "$tmp/one/Pkg/Sources/Same.swift") b=$(mtime "$tmp/one/Pkg/Sources/B.swift")
[ "$a" = "$same" ] && ok "the same content gets the same time" || bad "same content, different times ($a, $same)"
[ "$a" != "$b" ] && ok "different content gets a different time" || bad "different content, same time ($a)"
now=$(date +%s)
[ "$a" -lt "$now" ] && [ "$b" -lt "$now" ] && [ "$a" -ge 1000000000 ] && ok "every time is in the past, after 2001" || bad "a time out of range ($a, $b)"
[ "$(mtime "$tmp/one/Other/C.txt")" = "1700000000" ] && ok "files outside the named paths are left alone" || bad "a file outside the named paths was touched"
grep -q "3 file(s)" <<<"$out" && ok "it says how many files it set" || bad "unexpected output: $out"

# A second checkout of the same content gets the same times; a changed file in it gets a new one.
setup "$tmp/two"
printf 'let b = 3\n' > "$tmp/two/Pkg/Sources/B.swift"
(cd "$tmp/two" && git add -A && git -c user.email=t@t -c user.name=t commit -qm two)
sleep 1; touch "$tmp/two/Pkg/Sources/A.swift"
"$tmp/two/scripts/ci_content_mtimes.sh" Pkg >/dev/null 2>&1 || bad "the script failed in the second checkout"
[ "$(mtime "$tmp/two/Pkg/Sources/A.swift")" = "$a" ] && ok "an unchanged file has the same time in another checkout" || bad "an unchanged file's time differs between checkouts"
[ "$(mtime "$tmp/two/Pkg/Sources/B.swift")" != "$b" ] && ok "a changed file's time differs from the cached build's" || bad "a changed file kept the old time"

"$tmp/one/scripts/ci_content_mtimes.sh" >/dev/null 2>&1 && bad "no path given, yet it ran" || ok "no path given: a usage error"

# scripts/test_screen_models.sh --prepare: the fixed folder, the same content-based times on every run.
prepared="$repo/Packages/DoddyCore/Tests/DoddyCoreTests/_ScreenModels.ci"
if [ -e "$prepared" ]; then
  bad "$prepared exists before the test; remove it first"
else
  "$repo/scripts/test_screen_models.sh" --prepare >/dev/null 2>&1 || bad "--prepare failed"
  first=$(cd "$prepared" && for f in *.swift; do printf '%s %s\n' "$f" "$(mtime "$f")"; done)
  [ "$(printf '%s\n' "$first" | wc -l | tr -d ' ')" -eq 12 ] && ok "--prepare writes the 12 screen-model files" || bad "--prepare wrote: $first"
  sleep 1
  "$repo/scripts/test_screen_models.sh" --prepare >/dev/null 2>&1
  second=$(cd "$prepared" && for f in *.swift; do printf '%s %s\n' "$f" "$(mtime "$f")"; done)
  [ "$first" = "$second" ] && ok "--prepare gives the same times on every run" || bad "--prepare's times changed between runs"
  rm -rf "$prepared"
fi

if [ "$failures" -ne 0 ]; then echo "$failures check(s) failed"; exit 1; fi
echo "all content-time checks pass"
