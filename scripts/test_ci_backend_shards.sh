#!/usr/bin/env bash
# The hosted `backend` job runs the backend's test files as n shares side by side (25 Nov 2026).
# A share that no job runs would be tests nobody ran under a green `core`, so this checks, on any OS:
#   - .github/workflows/ios.yml lists every share 1..n exactly once, for the same n it hands to ci.sh,
#     with fail-fast off, and `core` still needs the backend job;
#   - scripts/ci.sh passes the share to Node's --test-shard and to nothing else, runs every test when
#     no share is named, and reports NOT RUN (never PASS) for a share that makes no sense.
#
#   scripts/test_ci_backend_shards.sh
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
workflow=${WORKFLOW:-$repo/.github/workflows/ios.yml}
ci_script=${CI_SCRIPT:-$repo/scripts/ci.sh}
failures=0
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; failures=$((failures + 1)); }

# The backend job's own lines: from `  backend:` to the next job (a line of two spaces and a name).
job=$(awk '/^  backend:$/{f=1; next} f && /^  [A-Za-z_-]+:$/{exit} f' "$workflow")
[ -n "$job" ] && ok "the workflow has a backend job" || bad "no backend job in $workflow"

shards=$(printf '%s\n' "$job" | sed -n 's/^ *shard: *\[\(.*\)\] *$/\1/p' | tr -d ' ')
total=$(printf '%s\n' "$job" | sed -n 's|^ *DODDY_BACKEND_TEST_SHARD: *\${{ *matrix\.shard *}}/\([1-9]\) *$|\1|p')
if [ -z "$shards" ] || [ -z "$total" ]; then
  bad "the backend job names its shares (shard: [...]) and DODDY_BACKEND_TEST_SHARD: \${{ matrix.shard }}/n"
else
  want=1; i=2
  while [ "$i" -le "$total" ]; do want="$want,$i"; i=$((i + 1)); done  # no `seq -s`: BSD's adds a trailing comma
  [ "$shards" = "$want" ] && ok "every share of $total runs exactly once ($shards)" \
    || bad "the shares are [$shards] but the job splits the files in $total: want [$want]"
fi
printf '%s\n' "$job" | grep -qE '^ *fail-fast: *false *$' && ok "a red share does not cancel the others" \
  || bad "fail-fast: false is missing from the backend job"
awk '/^  core:$/{f=1; next} f && /^  [A-Za-z_-]+:$/{exit} f' "$workflow" | grep -E '^ *needs:' | grep -qw backend \
  && ok "core needs the backend job" || bad "core no longer needs the backend job"

# ci.sh with stand-ins for node and npm that write down what they were asked and with which NODE_OPTIONS.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/case/scripts" "$tmp/case/backend/node_modules"
cp "$ci_script" "$tmp/case/scripts/ci.sh"
cat > "$tmp/bin/npm" <<'EOF'
#!/bin/sh
echo "npm $* [NODE_OPTIONS=${NODE_OPTIONS:-}]" >> "$FAKE_CALLS"
EOF
cat > "$tmp/bin/node" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$tmp/bin/npm" "$tmp/bin/node"
run_ci() {  # wanted exit, then environment assignments
  local want=$1; shift
  rm -f "$tmp/calls"
  out=$(cd "$tmp/case" && env PATH="$tmp/bin:$PATH" FAKE_CALLS="$tmp/calls" "$@" bash scripts/ci.sh --only backend 2>&1)
  rc=$?
  [ "$rc" -eq "$want" ] || { bad "ci.sh --only backend with '$*' exits $want (got $rc)"; printf '%s\n' "$out" | tail -5; }
}

run_ci 0 NODE_OPTIONS=
grep -q '^npm test --prefix backend \[NODE_OPTIONS=\]$' "$tmp/calls" && ok "no share named: every test runs, NODE_OPTIONS untouched" \
  || bad "no share named: npm test was not run plainly"

run_ci 0 DODDY_BACKEND_TEST_SHARD=2/3 NODE_OPTIONS=
grep -q '^npm test --prefix backend \[NODE_OPTIONS=--test-shard=2/3\]$' "$tmp/calls" && ok "share 2/3 reaches Node as --test-shard=2/3" \
  || bad "share 2/3 did not reach npm test as NODE_OPTIONS=--test-shard=2/3"
grep -q '^npm run --prefix backend typecheck \[NODE_OPTIONS=\]$' "$tmp/calls" && ok "the type-check is not given the share" \
  || bad "the type-check ran with the share in NODE_OPTIONS"
printf '%s\n' "$out" | grep -q 'PASS *Backend tests, share 2/3' && ok "the summary names the share" || bad "the summary does not name the share"

run_ci 0 DODDY_BACKEND_TEST_SHARD=1/3 NODE_OPTIONS=--max-old-space-size=4096
grep -q '^npm test --prefix backend \[NODE_OPTIONS=--max-old-space-size=4096 --test-shard=1/3\]$' "$tmp/calls" \
  && ok "NODE_OPTIONS already set is kept" || bad "NODE_OPTIONS already set was lost"

for wrong in 0/3 4/3 3 x/y 1/3/5; do
  run_ci 2 DODDY_BACKEND_TEST_SHARD=$wrong NODE_OPTIONS=
  if grep -q '^npm test' "$tmp/calls" 2>/dev/null; then bad "share '$wrong' still ran tests"
  elif printf '%s\n' "$out" | grep -q 'NOT RUN *Backend tests'; then ok "share '$wrong' is NOT RUN, never PASS"
  else bad "share '$wrong' was not reported NOT RUN"; fi
done

if [ "$failures" -ne 0 ]; then echo "$failures check(s) failed"; exit 1; fi
echo "all backend share checks pass"
