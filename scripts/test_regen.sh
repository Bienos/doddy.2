#!/usr/bin/env bash
# Tests scripts/regen.sh: one run brings every generated file up to date. It works on a copy of the
# checkout (tracked files and new ones not yet added; not the design/ and reference/ archives, which
# no generator reads), where the English pages build_blog.py and build_day.py write are left stale,
# the way a merge conflict leaves them: the "What can Doddy do?" page and the blog index carry an
# extra line, and one post's page is missing, as if just published. Then regen.sh runs once, and
# every generator it runs must pass its own --check. Each of them must also be a --check step in
# scripts/ci.sh, and each generator checked there must be in regen.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

generators=$(sed -n 's|^python3 -I \(tools/[A-Za-z0-9_]*\.py\)$|\1|p' scripts/regen.sh)
[ -n "$generators" ] || { echo "FAIL: found no generator lines in scripts/regen.sh"; exit 1; }
for g in $generators; do
  grep -qF "python3 -I $g --check" scripts/ci.sh || fail "scripts/ci.sh has no '$g --check' step"
done
for g in $(grep -o 'python3 -I tools/[A-Za-z0-9_]*\.py --check' scripts/ci.sh | cut -d' ' -f3); do
  printf '%s\n' "$generators" | grep -qxF "$g" || fail "scripts/ci.sh checks $g, but scripts/regen.sh doesn't run it"
done

git ls-files -z --cached --others --exclude-standard > "$work/files" \
  || { echo "FAIL: git ls-files failed (run this from a git checkout)"; exit 1; }
python3 -I - "$work/files" "$work/repo" <<'EOF' || { echo "FAIL: could not copy the checkout"; exit 1; }
import os, shutil, sys
names, dest = sys.argv[1], sys.argv[2]
for name in open(names, "rb").read().decode("utf-8").split("\0"):
    if not name or name.startswith(("design/", "reference/")) or not os.path.lexists(name):
        continue
    target = os.path.join(dest, name)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    shutil.copy2(name, target, follow_symlinks=False)
EOF

repo=$work/repo
marker='<!-- stale: left by scripts/test_regen.sh -->'
for page in site/what-can-doddy-do/index.html site/blog/index.html; do
  if [ -f "$repo/$page" ]; then printf '%s\n' "$marker" >> "$repo/$page"; else fail "$page is missing"; fi
done
post=$(cd "$repo" && ls -d site/blog/*/ 2>/dev/null | head -1)
if [ -n "$post" ]; then rm -rf "${repo:?}/$post"; else fail "no post pages under site/blog/"; fi

if ! (cd "$repo" && scripts/regen.sh) > "$work/regen.out" 2>&1; then
  fail "scripts/regen.sh failed:"; tail -20 "$work/regen.out"
else
  for g in $generators; do
    (cd "$repo" && python3 -I "$g" --check) > "$work/check.out" 2>&1 \
      || { fail "after one scripts/regen.sh run, $g --check fails:"; head -12 "$work/check.out"; }
  done
fi

if [ "$failures" -ne 0 ]; then echo "$failures failure(s)"; exit 1; fi
echo "PASS: one scripts/regen.sh run leaves all $(printf '%s\n' "$generators" | wc -l | tr -d ' ') generators' --check passing (stale day page, blog index and ${post%/})."
