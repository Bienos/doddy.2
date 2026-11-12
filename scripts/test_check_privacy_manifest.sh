#!/usr/bin/env bash
# Tests for scripts/check_privacy_manifest.sh: an undeclared required-reason API fails, a declared
# one passes, a missing manifest passes only when nothing is used, and the real tree (the app and
# each extension) passes.
set -uo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

manifest() {  # categories...
  { echo '<plist><dict><key>NSPrivacyAccessedAPITypes</key><array>'
    for c in "$@"; do echo "<dict><key>NSPrivacyAccessedAPIType</key><string>$c</string></dict>"; done
    echo '</array></dict></plist>'; } > "$tmp/PrivacyInfo.xcprivacy"
}
source_with() {  # swift line
  rm -rf "$tmp/src"; mkdir -p "$tmp/src"; printf '%s\n' "$1" > "$tmp/src/A.swift"
}
expect() {  # expected exit, description
  scripts/check_privacy_manifest.sh "$tmp/src" "$tmp/PrivacyInfo.xcprivacy" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$1" ]; then echo "ok    exit=$1  $2"; else echo "FAIL  wanted $1, got $got: $2"; failures=$((failures + 1)); fi
}

source_with 'let t = ProcessInfo.processInfo.systemUptime'
manifest NSPrivacyAccessedAPICategoryUserDefaults
expect 1 "system uptime used, not declared"
manifest NSPrivacyAccessedAPICategorySystemBootTime
expect 0 "system uptime used and declared"

source_with 'let d = try? FileManager.default.attributesOfItem(atPath: p)'
manifest NSPrivacyAccessedAPICategoryUserDefaults
expect 1 "file attributes used, not declared"
manifest NSPrivacyAccessedAPICategoryFileTimestamp
expect 0 "file attributes used and declared"

source_with 'let v = url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])'
manifest
expect 1 "free space used, nothing declared"
manifest NSPrivacyAccessedAPICategoryDiskSpace
expect 0 "free space used and declared"

source_with 'UserDefaults.standard.set(true, forKey: "x")'
manifest NSPrivacyAccessedAPICategoryDiskSpace
expect 1 "UserDefaults used, not declared"

source_with 'let x = 1'
manifest
expect 0 "no required-reason API, empty manifest"

source_with '/// Times come from `ProcessInfo.systemUptime` in the app.'
manifest
expect 0 "an API named only in a comment"

# An extension: no manifest is fine while its code (DoddyCore included) uses none, and fails once it does.
rm -f "$tmp/PrivacyInfo.xcprivacy"
expect 0 "no required-reason API, no manifest"
source_with 'let flag = UserDefaults.standard.bool(forKey: "x")'
expect 1 "UserDefaults used, no manifest at all"

if scripts/check_privacy_manifest.sh >/dev/null 2>&1; then
  echo "ok    the real tree passes (the app and each extension)"
else
  echo "FAIL  a real manifest misses a category:"; scripts/check_privacy_manifest.sh 2>&1 | grep MISSING
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then echo "$failures case(s) failed"; exit 1; fi
echo "All cases passed."
