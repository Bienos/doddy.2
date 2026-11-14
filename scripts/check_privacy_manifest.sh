#!/usr/bin/env bash
# Does each bundle's privacy manifest declare every "required reason" API its code uses?
# App Store Connect refuses or flags an upload (ITMS-91053) when a binary calls one of these APIs
# and the bundle's PrivacyInfo.xcprivacy doesn't declare its category. Until 7 Nov 2026 the manifest
# declared only UserDefaults while the app also read the system uptime, file dates and free space
# (engineering audit, docs/engineering/AUDIT_2026-11-07.md).
#
# Each bundle is checked against the Swift that goes into it (project.yml): the app (DoddyApp/,
# Shared/ and DoddyCore's sources), and each extension (its own folder, the part of Shared/ it
# compiles, and the DoddyCore product it links). An extension's own code may call none of these
# APIs, but DoddyCore's code is linked into its binary, so a DoddyCore call counts for it too.
# An extension that uses none needs no manifest; one that uses any must have its own.
# A pattern match is a heuristic: it can over-report (a string, or a comment after code), which costs
# one declaration; a line that is only a comment is skipped.
#
#   scripts/check_privacy_manifest.sh                 check the real tree, every bundle
#   scripts/check_privacy_manifest.sh DIR MANIFEST    check other sources against another manifest (tests);
#                                                     a MANIFEST that doesn't exist passes only if DIR uses none
set -euo pipefail
cd "$(dirname "$0")/.."

# category|extended regular expression for the Swift that uses it
checks='NSPrivacyAccessedAPICategoryUserDefaults|UserDefaults
NSPrivacyAccessedAPICategorySystemBootTime|systemUptime|mach_absolute_time
NSPrivacyAccessedAPICategoryFileTimestamp|creationDate|modificationDate|contentModificationDate|attributesOfItem|creationDateKey|contentAccessDate
NSPrivacyAccessedAPICategoryDiskSpace|volumeAvailableCapacity|volumeTotalCapacity|systemFreeSize|systemSize|statfs
NSPrivacyAccessedAPICategoryActiveKeyboards|activeInputModes'

failed=0

# check NAME "DIRS" MANIFEST REQUIRED: REQUIRED=yes means the manifest must exist even if nothing is used
# (the app's also declares the data Doddy collects).
check() {
  local name=$1 dirs=$2 manifest=$3 required=$4 missing=0 used=0 line category pattern hits
  if [ ! -f "$manifest" ] && [ "$required" = yes ]; then
    echo "No privacy manifest at $manifest ($name)" >&2
    failed=$((failed + 1))
    return
  fi
  while IFS= read -r line; do
    category=${line%%|*}
    pattern=${line#*|}
    # Lines that are only a comment (`//`, `///`) don't count: DoddyCore's docs name `systemUptime`.
    # shellcheck disable=SC2086
    hits=$(grep -rnE --include='*.swift' "$pattern" $dirs 2>/dev/null | grep -v '/Tests/' \
      | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' | cut -d: -f1 | sort -u | head -3 || true)
    [ -n "$hits" ] || continue
    used=$((used + 1))
    if [ -f "$manifest" ] && grep -q "<string>$category</string>" "$manifest"; then
      echo "ok       $name: $category"
    else
      echo "MISSING  $name: $category, used in $(echo "$hits" | tr '\n' ' ')" >&2
      missing=$((missing + 1))
    fi
  done <<EOF
$checks
EOF
  if [ "$missing" -ne 0 ]; then
    if [ -f "$manifest" ]; then
      echo "$missing required-reason API categor(ies) used but not declared in $manifest" >&2
    else
      echo "$name uses $missing required-reason API categor(ies) and has no privacy manifest; add $manifest" >&2
    fi
    failed=$((failed + 1))
  elif [ "$used" -eq 0 ] && [ ! -f "$manifest" ]; then
    echo "ok       $name: uses none, needs no manifest"
  fi
}

if [ $# -ge 2 ]; then
  check "sources" "$1" "$2" no
else
  core=Packages/DoddyCore/Sources
  check Doddy "DoddyApp Shared $core" DoddyApp/Resources/PrivacyInfo.xcprivacy yes
  # The extensions, as project.yml builds them (sources and the DoddyCore product each links).
  check DoddyWidgets "DoddyWidgets Shared $core/DoddyCore" DoddyWidgets/PrivacyInfo.xcprivacy no
  check DoddyShare "DoddyShare Shared/Share $core/DoddyCore" DoddyShare/PrivacyInfo.xcprivacy no
  check DoddyScreen "DoddyScreen Shared/Screen $core/DoddyCore" DoddyScreen/PrivacyInfo.xcprivacy no
  check DoddyNotificationContent "DoddyNotificationContent $core/DoddyDesignTokens" DoddyNotificationContent/PrivacyInfo.xcprivacy no
fi

# PhotoKit's PHAsset.creationDate is photo metadata, not a file timestamp; it matches the pattern
# anyway, and the app declares the category for its own files, so no exception is needed.
if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "Every bundle's privacy manifest declares the required-reason APIs its code uses."
