#!/usr/bin/env bash
# Tests scripts/install_xcodegen.sh on any OS, with a stand-in `curl` that serves a small zip instead of
# the real XcodeGen release (no network, nothing from the internet is run). What it checks: the file is
# unpacked only when its SHA-256 is the pinned one, a bad file leaves nothing behind, a failed download is
# tried again and gives up after the last try, the unpacked tool is never run, and a copy already checked
# is not downloaded again.
#
#   scripts/test_install_xcodegen.sh
set -uo pipefail
cd "$(dirname "$0")/.."
script=$PWD/scripts/install_xcodegen.sh
[ -x "$script" ] || { echo "FAIL: $script is missing or not executable"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
ok() { echo "ok    $1"; }

# The pin itself: a 64-digit checksum and a version that the download address names.
grep -Eq '^sha256=[0-9a-f]{64}$' "$script" || fail "the pinned sha256 is not 64 lowercase hex digits"
version=$(sed -n 's/^version=\([0-9][0-9.]*\)$/\1/p' "$script")
[ -n "$version" ] || fail "no pinned version in $script"
grep -q 'releases/download/\$version/xcodegen.zip' "$script" || fail "the download address does not use the pinned version"

# A stand-in release file: the same folder layout as XcodeGen's (bin/ with share/ beside it). Its "tool"
# records that it ran, which must never happen.
mkdir -p "$tmp/fixture/xcodegen/bin" "$tmp/fixture/xcodegen/share/xcodegen/SettingPresets"
printf '#!/bin/sh\necho ran > "%s/tool-ran"\n' "$tmp" > "$tmp/fixture/xcodegen/bin/xcodegen"
chmod +x "$tmp/fixture/xcodegen/bin/xcodegen"
echo "base: {}" > "$tmp/fixture/xcodegen/share/xcodegen/SettingPresets/base.yml"
python3 -I - "$tmp/fixture" "$tmp/good.zip" <<'EOF'
import os, sys, zipfile
root, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w") as z:
    for base, _dirs, files in os.walk(root):
        for f in files:
            p = os.path.join(base, f)
            info = zipfile.ZipInfo(os.path.relpath(p, root))
            info.external_attr = (0o755 if f == "xcodegen" else 0o644) << 16
            z.writestr(info, open(p, "rb").read())
EOF
printf 'not the release' > "$tmp/other.zip"
if command -v sha256sum >/dev/null 2>&1; then good_sha=$(sha256sum "$tmp/good.zip" | cut -d ' ' -f 1); else good_sha=$(shasum -a 256 "$tmp/good.zip" | cut -d ' ' -f 1); fi

# curl stand-in: counts its calls in $FAKE_COUNT, fails the first $FAKE_FAILS of them, otherwise copies
# $FAKE_ZIP to the file named after --output.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<'EOF'
#!/bin/sh
n=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FAKE_COUNT"
[ "$n" -le "${FAKE_FAILS:-0}" ] && { echo "curl: (22) The requested URL returned error: 504" >&2; exit 22; }
out=
while [ $# -gt 0 ]; do
  case "$1" in --output) out=$2; shift ;; esac
  shift
done
cp "$FAKE_ZIP" "$out"
EOF
chmod +x "$tmp/bin/curl"

mkdir -p "$tmp/tmpdir"
# run NAME ENV...: a fresh install folder unless FRESH=0; stdout in $tmp/out, stderr in $tmp/err.
dest="$tmp/dest"
run() {
  env PATH="$tmp/bin:$PATH" TMPDIR="$tmp/tmpdir" XCODEGEN_PREFIX="$dest" XCODEGEN_RETRY_WAIT=0 \
    FAKE_COUNT="$tmp/count" FAKE_ZIP="$tmp/good.zip" XCODEGEN_SHA256="$good_sha" "$@" \
    "$script" > "$tmp/out" 2> "$tmp/err"
}
calls() { cat "$tmp/count" 2>/dev/null || echo 0; }
reset() { rm -rf "$dest" "$tmp/count" "$tmp/tool-ran" "$tmp/gh-path"; }

# 1. The pinned file: unpacked, with share/ beside bin/, and the folder printed as the only stdout line.
reset; run
[ $? -eq 0 ] || fail "a file with the pinned checksum should install: $(cat "$tmp/err")"
[ "$(cat "$tmp/out")" = "$dest/xcodegen/bin" ] || fail "stdout should be only the bin folder, got: $(cat "$tmp/out")"
[ -x "$dest/xcodegen/bin/xcodegen" ] || fail "the tool should be unpacked and executable"
[ -f "$dest/xcodegen/share/xcodegen/SettingPresets/base.yml" ] || fail "the setting presets must sit beside bin/"
[ "$(calls)" = 1 ] || fail "one download expected, got $(calls)"
[ ! -e "$tmp/tool-ran" ] || fail "the unpacked tool must never be run by the installer"
[ -z "$(ls -A "$tmp/tmpdir")" ] || fail "the temporary download folder should be removed, left: $(ls -A "$tmp/tmpdir")"
grep -q "SHA-256 matches the pin" "$tmp/err" || fail "the log should say the checksum matched"
ok "the pinned file installs; stdout is the bin folder; the tool is not run; the temporary folder is gone"

# 2. A second run finds the checked copy and downloads nothing.
run
[ $? -eq 0 ] || fail "a repeat run should succeed"
[ "$(calls)" = 1 ] || fail "a repeat run must not download again, calls: $(calls)"
grep -q "already installed" "$tmp/err" || fail "a repeat run should say it found the copy"
ok "a copy that was already checked is not downloaded again"

# 3. A copy checked against another checksum is not trusted: it is fetched and checked again.
printf '%s\n' "0000" > "$dest/.verified-sha256"
run
[ "$(calls)" = 2 ] || fail "a marker for another checksum should cause a new download, calls: $(calls)"
ok "a marker that does not match the pin forces a fresh, checked download"

# 4. GitHub Actions: the folder is added to GITHUB_PATH as well.
reset; run GITHUB_PATH="$tmp/gh-path"
[ "$(cat "$tmp/gh-path" 2>/dev/null)" = "$dest/xcodegen/bin" ] || fail "GITHUB_PATH should get the bin folder"
ok "GITHUB_PATH gets the bin folder"

# 5. A different file than the pin: refused, nothing unpacked, nothing left to find.
reset; run FAKE_ZIP="$tmp/other.zip"
[ $? -ne 0 ] || fail "a file with another checksum must stop the install"
grep -q "not the pinned release" "$tmp/err" || fail "and say so: $(cat "$tmp/err")"
[ ! -e "$dest/xcodegen" ] || fail "nothing may be unpacked from a file that fails the check"
[ ! -s "$tmp/out" ] || fail "and nothing may be printed as a folder to use"
ok "a file that is not the pinned one is refused and leaves nothing behind"
reset; run XCODEGEN_SHA256=$(printf '%064d' 0)
[ $? -ne 0 ] || fail "a pin that the file does not match must stop the install"
ok "a wrong pin is refused as well"

# 6. A failed download is tried again; after the last try it stops.
reset; run FAKE_FAILS=2
[ $? -eq 0 ] || fail "two failed downloads and then a good one should install: $(cat "$tmp/err")"
[ "$(calls)" = 3 ] || fail "three attempts expected, got $(calls)"
ok "two failed downloads, then success: tried again (3 attempts)"
reset; run FAKE_FAILS=99 XCODEGEN_TRIES=3
[ $? -ne 0 ] || fail "a download that always fails must stop the install"
[ "$(calls)" = 3 ] || fail "XCODEGEN_TRIES=3 means three attempts, got $(calls)"
[ ! -e "$dest/xcodegen" ] || fail "nothing is installed after failed downloads"
ok "a download that always fails stops after the last try"

# 7. A release file without the tool in it.
python3 -I -c "
import zipfile, sys
with zipfile.ZipFile(sys.argv[1], 'w') as z: z.writestr('xcodegen/LICENSE', 'x')
" "$tmp/empty.zip"
if command -v sha256sum >/dev/null 2>&1; then empty_sha=$(sha256sum "$tmp/empty.zip" | cut -d ' ' -f 1); else empty_sha=$(shasum -a 256 "$tmp/empty.zip" | cut -d ' ' -f 1); fi
reset; run FAKE_ZIP="$tmp/empty.zip" XCODEGEN_SHA256="$empty_sha"
[ $? -ne 0 ] || fail "a checked file without xcodegen/bin/xcodegen must stop the install"
[ ! -e "$dest/xcodegen" ] || fail "nothing is installed from a file without the tool"
ok "a file without the tool in it stops the install"

# 8. The workflows use this script and not an unpinned install. (Xcode Cloud's ci_scripts/ is switched in a
# pull request of its own, which adds ci_scripts/*.sh to this check.)
if grep -n -E '^[[:space:]]*(run:[[:space:]]*)?(HOMEBREW_[A-Z_]*=[0-9A-Za-z]+[[:space:]]+)?brew install xcodegen' .github/workflows/*.yml; then
  fail "a workflow still runs 'brew install xcodegen'"
else
  ok "no workflow installs XcodeGen from Homebrew"
fi

if [ "$failures" -ne 0 ]; then echo "FAIL: $failures check(s)"; exit 1; fi
echo "PASS: install_xcodegen.sh unpacks only the pinned release, retries downloads, and never runs the tool"
