#!/usr/bin/env bash
# Tests scripts/check_no_pipe_to_shell.py on any OS, on small stand-in trees in a temp folder. The check fails
# when a tracked file downloads something and hands it straight to a shell (the download is run before anyone,
# or any checksum, has looked at it). Reading JSON or text from a download, or checking its hash, is fine.
#
#   scripts/test_check_no_pipe_to_shell.sh
set -uo pipefail
cd "$(dirname "$0")/.."
check=$PWD/scripts/check_no_pipe_to_shell.py
[ -f "$check" ] || { echo "FAIL: $check is missing"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp" "$tmp.out" "$tmp.real"' EXIT
failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
ok() { echo "ok    $1"; }

run() { python3 -I "$check" --root "$tmp" >"$tmp.out" 2>&1; echo $?; }
tree() {  # file, one line of content
  rm -rf "$tmp"; mkdir -p "$tmp/$(dirname "$1")"; printf '%s\n' "$2" > "$tmp/$1"
}

bad() {  # description, file, line
  tree "$2" "$3"
  if [ "$(run)" = 1 ] && grep -q "$2:1" "$tmp.out"; then ok "fails: $1"; else fail "should fail: $1 [$3]"; cat "$tmp.out"; fi
}
good() {  # description, file, line
  tree "$2" "$3"
  if [ "$(run)" = 0 ]; then ok "passes: $1"; else fail "should pass: $1 [$3]"; cat "$tmp.out"; fi
}

# What it must catch, in scripts, workflows, docs and manifests alike.
bad "curl piped to sh"                       scripts/a.sh              'curl -fsSL https://example.com/install | sh'
bad "curl piped to bash with args"           scripts/a.sh              'curl -sSf https://example.com/i.sh | bash -s -- --yes'
bad "wget piped to bash"                     ci_scripts/b.sh           'wget -qO- https://example.com/x | bash'
bad "piped to sudo bash"                     scripts/a.sh              'curl -L https://example.com/x | sudo bash'
bad "piped to sudo -E sh"                    scripts/a.sh              'curl -L https://example.com/x | sudo -E sh'
bad "piped to zsh"                           scripts/a.sh              'curl -L https://example.com/x | zsh'
bad "inside a workflow run line"             .github/workflows/ci.yml  '        run: curl -fsSL https://example.com/x | bash'
bad "in a docs page"                         docs/setup.md             '    curl -fsSL https://example.com/x | sh'
bad "bash with process substitution"         scripts/a.sh              'bash <(curl -s https://example.com/x)'
bad "sh with process substitution"           scripts/a.sh              'sh <(wget -qO- https://example.com/x)'
bad "source with process substitution"       scripts/a.sh              'source <(curl -s https://example.com/x)'
bad "dot with process substitution"          scripts/a.sh              '. <(curl -s https://example.com/x)'
bad "sh -c with a command substitution"      scripts/a.sh              'sh -c "$(curl -fsSL https://example.com/x)"'
bad "bash -c with a command substitution"    scripts/a.sh              "bash -c \"\$(wget -qO- https://example.com/x)\""
bad "eval of a download"                     scripts/a.sh              'eval "$(curl -s https://example.com/x)"'
bad "with a Dockerfile RUN"                  Dockerfile                'RUN curl -fsSL https://example.com/x | sh'
bad "with a Makefile recipe"                 Makefile                  '	curl -fsSL https://example.com/x | sh'

# What it must leave alone.
good "download then check then run"          scripts/a.sh              'curl -fsSLO https://example.com/x.zip && shasum -a 256 -c x.sha256'
good "curl into a JSON parser"               scripts/a.sh              'curl -s https://example.com/x | python3 -c "import json,sys; print(json.load(sys.stdin))"'
good "curl into jq"                          scripts/a.sh              'curl -s https://example.com/x | jq .name'
good "curl into a hash tool"                 scripts/a.sh              'curl -sL https://example.com/x | shasum -a 256'
good "curl into sha256sum"                   scripts/a.sh              'curl -sL https://example.com/x | sha256sum'
good "curl into tar"                         scripts/a.sh              'curl -sL https://example.com/x | tar -xz'
good "grep for the word sh"                  scripts/a.sh              'curl -s https://example.com/x | grep -c shell'
good "a shell word in a later pipe stage"    scripts/a.sh              'curl -s https://example.com/x | head -1 | wc -l'
good "ordinary sh use"                       scripts/a.sh              'sh scripts/install_xcodegen.sh'
good "bash -c on a literal"                  scripts/a.sh              'bash -c "echo hello"'
good "a command substitution of something else" scripts/a.sh           'sh -c "$(git rev-parse HEAD)"'

# Places it does not look: history kept for reference, and folders other tools own.
good "archived reference"                    reference/old/notes.md    'curl -fsSL https://example.com/x | sh'
good "archived docs"                         docs/archive/old.md       'curl -fsSL https://example.com/x | sh'
good "node_modules"                          web/node_modules/p/i.sh   'curl -fsSL https://example.com/x | sh'
good "the check's own files"                 scripts/check_no_pipe_to_shell.py 'curl x | sh'
good "the check's own test"                  scripts/test_check_no_pipe_to_shell.sh 'curl x | sh'

# A tree with one good and one bad file names only the bad one, with its line number.
rm -rf "$tmp"; mkdir -p "$tmp/scripts"
printf 'echo fine\n' > "$tmp/scripts/ok.sh"
printf '#!/bin/sh\nset -e\ncurl -fsSL https://example.com/x | sh\n' > "$tmp/scripts/bad.sh"
if [ "$(run)" = 1 ] && grep -q 'scripts/bad.sh:3' "$tmp.out" && ! grep -q 'scripts/ok.sh' "$tmp.out"; then ok "names the file and line of the bad one only"; else fail "should name scripts/bad.sh:3 only"; cat "$tmp.out"; fi

# Binary files are skipped (no crash).
rm -rf "$tmp"; mkdir -p "$tmp/assets"; printf '\000\001curl x | sh\377\n' > "$tmp/assets/blob.bin"
[ "$(run)" = 0 ] && ok "a binary file is skipped" || { fail "a binary file should be skipped"; cat "$tmp.out"; }

# The real repository passes.
if python3 -I "$check" >"$tmp.real" 2>&1; then ok "this repository passes"; else fail "this repository should pass"; cat "$tmp.real"; fi

if [ "$failures" -ne 0 ]; then echo "FAIL: $failures check(s)"; exit 1; fi
echo "PASS: no tracked file downloads something and pipes it into a shell"
