#!/usr/bin/env bash
# Tests for scripts/copy_binary_dsyms.sh (ADR-693) with a stand-in dwarfdump that reads the UUID from a file's first
# line, so they run on Linux. They show what the script copies, what it leaves alone and what it refuses; they say
# nothing about a real archive or real dwarfdump output.
set -uo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/dwarfdump" <<'EOF'
#!/usr/bin/env bash
# dwarfdump --uuid <path>: a dSYM bundle keeps its UUID in Contents/uuid, a framework binary in its own first line.
f=$2
[ -d "$f" ] && f="$f/Contents/uuid"
[ -f "$f" ] || exit 1
echo "UUID: $(head -n1 "$f") (arm64) $2"
EOF
chmod +x "$tmp/dwarfdump"
export DWARFDUMP="$tmp/dwarfdump"

failures=0
check() {  # description, condition result (0 = ok)
  if [ "$2" -eq 0 ]; then echo "ok    $1"; else echo "FAIL  $1"; failures=$((failures + 1)); fi
}
make_archive() {  # dir, framework UUID
  mkdir -p "$1/Products/Applications/Doddy.app/Frameworks/LiveKitWebRTC.framework"
  echo "$2" > "$1/Products/Applications/Doddy.app/Frameworks/LiveKitWebRTC.framework/LiveKitWebRTC"
}
make_dsym() {  # packages dir, slice, dsym UUID, framework name
  local d="$1/artifacts/webrtc-xcframework/LiveKitWebRTC/LiveKitWebRTC.xcframework/$2/dSYMs/$4.dSYM/Contents"
  mkdir -p "$d"; echo "$3" > "$d/uuid"
}

# 1. Matching UUID: copied into the archive's dSYMs.
a="$tmp/a.xcarchive"; p="$tmp/pa"; make_archive "$a" 4C4C44F8-5555-3144-A124-1F7C8D605662
make_dsym "$p" ios-arm64 4c4c44f8-5555-3144-a124-1f7c8d605662 LiveKitWebRTC.framework
out=$(scripts/copy_binary_dsyms.sh "$a" "$p"); rc=$?
check "exit 0" $((rc != 0))
check "a matching dSYM is copied (UUID compared without regard to case)" $([ -d "$a/dSYMs/LiveKitWebRTC.framework.dSYM" ]; echo $?)
check "it says so" $(grep -q '^copied     LiveKitWebRTC.framework' <<<"$out"; echo $?)

# 2. Different UUID: not copied, reported.
a="$tmp/b.xcarchive"; p="$tmp/pb"; make_archive "$a" AAAAAAAA-0000-0000-0000-000000000001
make_dsym "$p" ios-arm64 BBBBBBBB-0000-0000-0000-000000000002 LiveKitWebRTC.framework
out=$(scripts/copy_binary_dsyms.sh "$a" "$p"); rc=$?
check "a mismatch is not an error" $((rc != 0))
check "a dSYM with another UUID is not copied" $([ ! -e "$a/dSYMs/LiveKitWebRTC.framework.dSYM" ]; echo $?)
check "the mismatch is reported with both UUIDs" $(grep -q 'UNMATCHED.*AAAAAAAA.*BBBBBBBB' <<<"$out"; echo $?)

# 3. Only the iPhone slice is considered.
a="$tmp/c.xcarchive"; p="$tmp/pc"; make_archive "$a" 4C4C44F8-5555-3144-A124-1F7C8D605662
make_dsym "$p" ios-arm64_x86_64-simulator 4C4C44F8-5555-3144-A124-1F7C8D605662 LiveKitWebRTC.framework
scripts/copy_binary_dsyms.sh "$a" "$p" >/dev/null
check "a simulator slice's dSYM is ignored" $([ ! -e "$a/dSYMs/LiveKitWebRTC.framework.dSYM" ]; echo $?)

# 4. A dSYM already in the archive is left alone.
a="$tmp/d.xcarchive"; p="$tmp/pd"; make_archive "$a" 4C4C44F8-5555-3144-A124-1F7C8D605662
make_dsym "$p" ios-arm64 4C4C44F8-5555-3144-A124-1F7C8D605662 LiveKitWebRTC.framework
mkdir -p "$a/dSYMs/LiveKitWebRTC.framework.dSYM/Contents"; echo KEEP > "$a/dSYMs/LiveKitWebRTC.framework.dSYM/Contents/uuid"
out=$(scripts/copy_binary_dsyms.sh "$a" "$p")
check "an existing dSYM is not overwritten" $([ "$(cat "$a/dSYMs/LiveKitWebRTC.framework.dSYM/Contents/uuid")" = KEEP ]; echo $?)
check "and the output says it is present" $(grep -q '^present' <<<"$out"; echo $?)

# 5. A package framework that is not in the app is skipped.
a="$tmp/e.xcarchive"; p="$tmp/pe"; mkdir -p "$a/Products/Applications/Doddy.app/Frameworks"
make_dsym "$p" ios-arm64 4C4C44F8-5555-3144-A124-1F7C8D605662 LiveKitWebRTC.framework
scripts/copy_binary_dsyms.sh "$a" "$p" >/dev/null
check "a framework that is not embedded is skipped" $([ ! -e "$a/dSYMs/LiveKitWebRTC.framework.dSYM" ]; echo $?)

# 6. Usage errors.
scripts/copy_binary_dsyms.sh >/dev/null 2>&1; check "no arguments: exit 2" $(( $? == 2 ? 0 : 1 ))
mkdir -p "$tmp/empty.xcarchive" "$tmp/pf"
scripts/copy_binary_dsyms.sh "$tmp/empty.xcarchive" "$tmp/pf" >/dev/null 2>&1; check "an archive with no app: exit 2" $(( $? == 2 ? 0 : 1 ))

[ "$failures" -eq 0 ] && echo "PASS: copy_binary_dsyms" || { echo "$failures failure(s)"; exit 1; }
