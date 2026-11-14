#!/usr/bin/env bash
# Tests scripts/check_render_install_scripts.py on any OS, on small stand-in projects in a temp folder.
# The check: where render.yaml installs with `npm ci --ignore-scripts`, nothing in that folder's lockfile may
# have an install script, and its package.json may not have a lifecycle script of its own, because the flag
# would skip both and the build would still pass with a package that was never set up.
#
#   scripts/test_check_render_install_scripts.sh
set -uo pipefail
cd "$(dirname "$0")/.."
check=$PWD/scripts/check_render_install_scripts.py
[ -f "$check" ] || { echo "FAIL: $check is missing"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
ok() { echo "ok    $1"; }

# A project folder: lockfile (version 3) with the given package entries, and a package.json.
project() {  # dir, lockfile packages json (object), package.json scripts json (object)
  mkdir -p "$tmp/$1"
  printf '{"name":"x","lockfileVersion":3,"packages":{"":{"name":"x"},%s}}\n' "$2" > "$tmp/$1/package-lock.json"
  printf '{"name":"x","scripts":%s}\n' "$3" > "$tmp/$1/package.json"
}
render() {  # the render.yaml body
  printf 'services:\n%s\n' "$1" > "$tmp/render.yaml"
}
clean_pkgs='"node_modules/a":{"version":"1.0.0"},"node_modules/b":{"version":"2.0.0","dev":true}'
script_pkgs='"node_modules/a":{"version":"1.0.0"},"node_modules/native":{"version":"3.0.0","hasInstallScript":true}'

run() { python3 -I "$check" --root "$tmp" >"$tmp/out" 2>&1; echo $?; }

# 1. The flag, a clean lockfile, no lifecycle scripts: passes.
rm -rf "$tmp"/*
project server "$clean_pkgs" '{"build":"tsc","start":"node x"}'
render '  - type: web
    name: one
    rootDir: server
    buildCommand: npm ci --ignore-scripts && npm run build'
[ "$(run)" = 0 ] && ok "a clean lockfile with the flag passes" || { fail "a clean lockfile with the flag should pass"; cat "$tmp/out"; }

# 2. The flag and one package with an install script: fails and names the package, not a secret.
project server "$script_pkgs" '{"build":"tsc"}'
[ "$(run)" = 1 ] && ok "an install script in the lockfile fails" || fail "an install script in the lockfile should fail"
grep -q 'node_modules/native' "$tmp/out" && ok "the failure names the package" || fail "the failure should name node_modules/native"

# 3. The flag and a lifecycle script in the folder's own package.json: fails.
for hook in preinstall install postinstall prepare; do
  project server "$clean_pkgs" "{\"build\":\"tsc\",\"$hook\":\"node setup.js\"}"
  [ "$(run)" = 1 ] && ok "a $hook script of its own fails" || fail "a $hook script of its own should fail"
done

# 4. No flag on a folder whose lockfile has install scripts: not this check's business, passes.
project server "$script_pkgs" '{"build":"tsc"}'
render '  - type: web
    name: one
    rootDir: server
    buildCommand: npm ci && npm run build'
[ "$(run)" = 0 ] && ok "an install without the flag is left alone" || fail "an install without the flag should pass"

# 5. The doddy shape: the server's install has the flag, the web install (--prefix) does not and may have install scripts.
project server "$clean_pkgs" '{"build":"tsc"}'
project web "$script_pkgs" '{"build":"vite build"}'
render '  - type: web
    name: doddy
    rootDir: server
    buildCommand: npm ci --ignore-scripts && npm run build && npm ci --prefix ../web && npm run build --prefix ../web'
[ "$(run)" = 0 ] && ok "the flag on one install and not on the --prefix install passes" || { fail "flag on the server install only should pass"; cat "$tmp/out"; }

# 6. The flag on the --prefix install of a folder with install scripts: fails.
render '  - type: web
    name: doddy
    rootDir: server
    buildCommand: npm ci --ignore-scripts --prefix ../web && npm run build'
[ "$(run)" = 1 ] && ok "the flag on a --prefix install is checked against that folder" || fail "the flag on --prefix ../web should fail"

# 7. --include=dev and other flags in between do not hide the flag.
project server "$script_pkgs" '{"build":"tsc"}'
render '  - type: worker
    name: w
    rootDir: server
    buildCommand: npm ci --include=dev --ignore-scripts && npm run build'
[ "$(run)" = 1 ] && ok "other flags around --ignore-scripts are read" || fail "--include=dev --ignore-scripts should be checked"

# 8. The flag but no lockfile: fails (there is nothing to prove it safe).
rm "$tmp/server/package-lock.json"
[ "$(run)" = 1 ] && ok "no lockfile fails" || fail "no lockfile should fail"

# 9. An old lockfile format has no install-script marks: fails rather than guessing.
printf '{"name":"x","lockfileVersion":1,"dependencies":{}}\n' > "$tmp/server/package-lock.json"
[ "$(run)" = 1 ] && ok "lockfile version 1 fails" || fail "lockfile version 1 should fail"

# 10. Several services in one file are each checked.
project a "$clean_pkgs" '{"build":"tsc"}'
project b "$script_pkgs" '{"build":"tsc"}'
render '  - type: web
    name: a
    rootDir: a
    buildCommand: npm ci --ignore-scripts
  - type: web
    name: b
    rootDir: b
    buildCommand: npm ci --ignore-scripts'
[ "$(run)" = 1 ] && grep -q 'service b ' "$tmp/out" && ! grep -q 'service a ' "$tmp/out" && ok "the second service is checked, and named" || fail "service b should fail and service a should not be named"

# 11. The real repository passes.
if python3 -I "$check" >"$tmp/real" 2>&1; then ok "this repository passes"; else fail "this repository should pass"; cat "$tmp/real"; fi

if [ "$failures" -ne 0 ]; then echo "FAIL: $failures check(s)"; exit 1; fi
echo "PASS: render.yaml's --ignore-scripts installs are only on folders with no install scripts"
