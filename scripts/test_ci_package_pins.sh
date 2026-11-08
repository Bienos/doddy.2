#!/usr/bin/env bash
# Tests the Mac section of scripts/ci.sh around the app's package pins, on any OS, with stand-ins for
# xcodegen, xcrun and xcodebuild (nothing here builds an app).
#
# Why: in run 42409624440 (7 Nov 2026) `xcodebuild -list` wrote no Package.resolved, the pin step logged
# NOT RUN, and that alone ended an otherwise green job as BLOCKED (exit 2). The pins are only checked
# when committed; with none, a missing file must not block anything.
#
#   scripts/test_ci_package_pins.sh
#   CI_SCRIPT=/path/to/older/ci.sh scripts/test_ci_package_pins.sh   (run the cases against another copy)
set -uo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
ci_script=${CI_SCRIPT:-$repo/scripts/ci.sh}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

bin="$tmp/bin"
mkdir -p "$bin"
cat > "$bin/xcodegen" <<'EOF'
#!/bin/sh
mkdir -p Doddy.xcodeproj/project.xcworkspace
EOF
cat > "$bin/xcrun" <<'EOF'
#!/bin/sh
if [ "$1 $2" = "simctl list" ]; then echo "    iPhone 17 (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA) (Shutdown)"; fi
exit 0
EOF
# FAKE_RESOLVE_WRITES / FAKE_BUILD_WRITES say which xcodebuild command writes the pins file (FAKE_PINS),
# FAKE_WHERE where.
cat > "$bin/xcodebuild" <<'EOF'
#!/bin/sh
dest=Doddy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
# FAKE_WHERE=derived: Xcode keeps the file under DerivedData instead of the project folder.
[ "${FAKE_WHERE:-project}" = derived ] && dest="$DODDY_DERIVED_DATA/Doddy-abc/SourcePackages"
write() { mkdir -p "$dest"; printf '%s\n' "$FAKE_PINS" > "$dest/Package.resolved"; }
case "$1" in
  -resolvePackageDependencies) [ "${FAKE_RESOLVE_WRITES:-0}" = 1 ] && write ;;
  build-for-testing) [ "${FAKE_BUILD_WRITES:-0}" = 1 ] && write ;;
esac
exit 0
EOF
chmod +x "$bin"/*

root="$tmp/case"
# run_case DESCRIPTION WANTED_EXIT WANTED_TEXT COMMITTED_PINS RESOLVE_WRITES BUILD_WRITES XCODE_PINS [WHERE]
# COMMITTED_PINS is the text of Config/Package.resolved, or "none".
run_case() {
  local name=$1 want_exit=$2 want_text=$3 committed=$4 resolve=$5 build=$6 xcode_pins=$7 where=${8:-project}
  rm -rf "$root"; mkdir -p "$root/scripts" "$root/Config"
  cp "$ci_script" "$root/scripts/ci.sh"
  cp "$repo/scripts/install_package_resolved.sh" "$root/scripts/"
  : > "$root/project.yml"
  if [ "$committed" != none ]; then printf '%s\n' "$committed" > "$root/Config/Package.resolved"; fi
  local out got
  out=$(cd "$root" && PATH="$bin:$PATH" FAKE_PINS=$xcode_pins FAKE_RESOLVE_WRITES=$resolve FAKE_BUILD_WRITES=$build \
        FAKE_WHERE=$where DODDY_DERIVED_DATA="$root/derived" DODDY_UI_TESTS=smoke bash scripts/ci.sh --only ios 2>&1)
  got=$?
  if [ "$got" = "$want_exit" ] && grep -q -- "$want_text" <<<"$out"; then
    echo "ok    exit=$want_exit  $name"
  else
    echo "FAIL  $name: wanted exit $want_exit with \"$want_text\", got exit $got"
    grep -E "App package versions|RESULT:|Resolve the app" <<<"$out" | sed 's/^/        /'
    failures=$((failures + 1))
  fi
}
copied() {  # description, expected text of build/Package.resolved ("" = must not exist)
  if [ -z "$2" ]; then
    [ ! -e "$root/build/Package.resolved" ] && echo "ok    $1" || { echo "FAIL  $1"; failures=$((failures + 1)); }
  elif [ "$(cat "$root/build/Package.resolved" 2>/dev/null)" = "$2" ]; then
    echo "ok    $1"
  else
    echo "FAIL  $1"; failures=$((failures + 1))
  fi
}

# No pins committed: capture whatever Xcode resolved, and never block when it wrote nothing.
run_case "no pins; resolve writes the file" 0 "no pins committed yet: commit build" none 1 0 xcode-pins
copied "build/Package.resolved holds what Xcode resolved" xcode-pins
[ -f "$root/build/packages-ok" ] && echo "ok    build/packages-ok is written once the packages resolved (the cache may be saved)" \
  || { echo "FAIL  no build/packages-ok after a successful resolve"; failures=$((failures + 1)); }
run_case "no pins; only the build writes the file (late capture)" 0 "no pins committed yet: commit build" none 0 1 xcode-pins
copied "build/Package.resolved exists after the late capture" xcode-pins
run_case "no pins; nothing writes the file (run 42409624440): not blocked" 0 "no Package.resolved naming LiveKit" none 0 0 xcode-pins
copied "no build/Package.resolved when there was nothing to copy" ""

# Xcode 26.6 kept the file out of the project folder (run 42416065085): take it from DerivedData when it
# names LiveKit, and never take one that doesn't (DoddyCore's own file).
run_case "no pins; Xcode wrote it under DerivedData: found" 0 "no pins committed yet: commit build" none 1 0 "livekit pins" derived
copied "build/Package.resolved holds the DerivedData file" "livekit pins"
run_case "no pins; a DerivedData file without LiveKit is ignored" 0 "no Package.resolved naming LiveKit" none 1 0 xcode-pins derived
copied "no build/Package.resolved from a file that doesn't name LiveKit" ""

# Pins committed: they are installed first, so the file is there. Unchanged passes; a move fails.
run_case "pins committed and unchanged: PASS" 0 "PASS     App package versions match" committed-pins 0 0 xcode-pins
run_case "pins committed and resolution moved them: FAIL" 1 "FAIL     App package versions match" committed-pins 1 0 other-pins

if [ "$failures" -ne 0 ]; then echo "$failures check(s) failed"; exit 1; fi
echo "all package-pin cases passed"
