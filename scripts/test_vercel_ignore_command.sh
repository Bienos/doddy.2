#!/usr/bin/env bash
# Tests for the ignoreCommand in site/, gateway/ and server/voice-token/vercel.json: when does a push to `main`
# build a Vercel project? Vercel runs the command in the project's folder; exit 0 skips the build, anything else
# builds. The costly mistake is skipping a change: on 9 Nov 2026 the site's changes (#271) never went live, because
# the last good deployment's commit was deeper than Vercel's shallow clone and the old command then compared only
# the last commit. So most cases here are "must build".
set -uo pipefail
cd "$(dirname "$0")/.."
root=$PWD

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A repository with a project folder `app/` and some other folder, on a few commits.
repo="$work/repo"
git init -q "$repo"
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
mkdir -p "$repo/app" "$repo/other"
commit() { echo "$2" > "$repo/$1"; git -C "$repo" add -A; git -C "$repo" commit -qm "$1 $2"; git -C "$repo" rev-parse HEAD; }
c0=$(commit app/page v0)          # the first commit
c1=$(commit app/page v1)          # the project changes
c2=$(commit other/file a)         # something else changes
c3=$(commit other/file b)         # something else changes again

failures=0
expect() {  # vercel.json, expected (build|skip), description, VERCEL_GIT_PREVIOUS_SHA, [repo to run in]
  local file=$1 want=$2 what=$3 previous=$4 dir=${5:-$repo}
  local command got
  command=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["ignoreCommand"])' "$root/$file")
  (cd "$dir/app" && VERCEL_GIT_PREVIOUS_SHA=$previous bash -c "$command") >/dev/null 2>&1
  [ $? -eq 0 ] && got=skip || got=build
  if [ "$got" = "$want" ]; then
    echo "ok    $want  $file: $what"
  else
    echo "FAIL  wanted $want, got $got: $file: $what"
    failures=$((failures + 1))
  fi
}

# A clone with only the last two commits, like Vercel's shallow clone when the last deployment is older than it:
# the parent is there (only `other/` changed in it), the last deployment's commit is not.
shallow="$work/shallow"
git clone -q --depth 2 "file://$repo" "$shallow"

for file in site/vercel.json gateway/vercel.json server/voice-token/vercel.json; do
  expect "$file" build "the project changed since the last deployment" "$c0"
  expect "$file" skip  "only another folder changed since the last deployment" "$c1"
  expect "$file" build "a redeploy of the same commit" "$c3"
  expect "$file" build "the last deployment's commit isn't in the clone (the 9 Nov bug)" "$c1" "$shallow"
  expect "$file" build "an unknown previous commit" "0000000000000000000000000000000000000000"
  expect "$file" skip  "no previous deployment, and the last commit didn't touch the project" ""
done

# No previous deployment, and the last commit changed the project: build.
c4=$(commit app/page v2)
for file in site/vercel.json gateway/vercel.json server/voice-token/vercel.json; do
  expect "$file" build "no previous deployment, and the last commit changed the project" ""
done

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed."
  exit 1
fi
echo "All cases pass."
