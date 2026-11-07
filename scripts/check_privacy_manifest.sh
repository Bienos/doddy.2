#!/usr/bin/env bash
# Does the app's privacy manifest declare every "required reason" API the app's code uses?
# App Store Connect refuses or flags an upload (ITMS-91053) when the binary calls one of these APIs
# and the bundle's PrivacyInfo.xcprivacy doesn't declare its category. Until 7 Nov 2026 the manifest
# declared only UserDefaults while the app also read the system uptime, file dates and free space
# (engineering audit, docs/engineering/AUDIT_2026-11-07.md).
#
# Scans the Swift that goes into the app: DoddyApp/, Shared/ and DoddyCore's sources. The widget
# and share extensions use none of these APIs today; if one starts to, it needs its own manifest.
# A pattern match is a heuristic: it can over-report (a comment), which costs one declaration.
#
#   scripts/check_privacy_manifest.sh            check the real tree
#   scripts/check_privacy_manifest.sh DIR MANIFEST   check other sources against another manifest (tests)
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -ge 2 ]; then
  dirs=$1 manifest=$2
else
  dirs="DoddyApp Shared Packages/DoddyCore/Sources" manifest=DoddyApp/Resources/PrivacyInfo.xcprivacy
fi
[ -f "$manifest" ] || { echo "No privacy manifest at $manifest" >&2; exit 1; }

# category|extended regular expression for the Swift that uses it
checks='NSPrivacyAccessedAPICategoryUserDefaults|UserDefaults
NSPrivacyAccessedAPICategorySystemBootTime|systemUptime|mach_absolute_time
NSPrivacyAccessedAPICategoryFileTimestamp|creationDate|modificationDate|contentModificationDate|attributesOfItem|creationDateKey|contentAccessDate
NSPrivacyAccessedAPICategoryDiskSpace|volumeAvailableCapacity|volumeTotalCapacity|systemFreeSize|systemSize|statfs
NSPrivacyAccessedAPICategoryActiveKeyboards|activeInputModes'

missing=0
while IFS= read -r line; do
  category=${line%%|*}
  pattern=${line#*|}
  # shellcheck disable=SC2086
  hits=$(grep -rlE --include='*.swift' "$pattern" $dirs 2>/dev/null | grep -v '/Tests/' | head -3 || true)
  [ -n "$hits" ] || continue
  if grep -q "<string>$category</string>" "$manifest"; then
    echo "ok       $category"
  else
    echo "MISSING  $category: used in $(echo "$hits" | tr '\n' ' ')" >&2
    missing=$((missing + 1))
  fi
done <<EOF
$checks
EOF

# PhotoKit's PHAsset.creationDate is photo metadata, not a file timestamp; it matches the pattern
# anyway, and the app declares the category for its own files, so no exception is needed.
if [ "$missing" -ne 0 ]; then
  echo "$missing required-reason API categor(ies) used but not declared in $manifest" >&2
  exit 1
fi
echo "Privacy manifest declares every required-reason API the app uses."
