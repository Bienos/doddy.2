#!/usr/bin/env bash
# Puts the debug symbols (dSYMs) of binary Swift packages into a Release archive (ADR-693).
#
# Why: App Store Connect warns "The archive did not include a dSYM for LiveKitWebRTC.framework with the UUIDs [...]".
# LiveKit's WebRTC is a prebuilt binary (a binaryTarget xcframework). The vendor ships its dSYM inside the xcframework
# (checked for release 150.7871.05: ios-arm64/dSYMs/LiveKitWebRTC.framework.dSYM, the same UUID as the framework),
# but Xcode does not always copy it into the archive's dSYMs folder. This copies it, and only when its UUID equals
# the UUID of the framework that is really inside the archive, so a stale or foreign dSYM is never added.
#
#   scripts/copy_binary_dsyms.sh <path/to/Doddy.xcarchive> <SourcePackages dir>
#
# The SourcePackages dir is where Xcode resolved the packages: DerivedData/<project>/SourcePackages, or the folder
# given to xcodebuild with -clonedSourcePackagesDirPath. Run it after `xcodebuild archive` and before the export
# or upload. Needs macOS (dwarfdump); set DWARFDUMP to use another command (the tests do). It changes only the
# archive's dSYMs folder, never the app, and a framework with no match is reported, not failed: the warning it
# targets does not block an upload. Exit 2 is a usage error or an archive with no app in it.
set -uo pipefail

archive=${1:-}
packages=${2:-}
dwarfdump=${DWARFDUMP:-dwarfdump}
if [ -z "$archive" ] || [ -z "$packages" ] || [ ! -d "$archive" ] || [ ! -d "$packages" ]; then
  echo "Usage: $0 <path/to/Doddy.xcarchive> <SourcePackages dir>" >&2
  exit 2
fi
app=$(find "$archive/Products/Applications" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null)
if [ -z "$app" ]; then
  echo "No .app in $archive/Products/Applications: is this an iOS archive?" >&2
  exit 2
fi
mkdir -p "$archive/dSYMs"

uuids() {  # the UUIDs dwarfdump reports for a Mach-O file or a dSYM, one per line
  "$dwarfdump" --uuid "$1" 2>/dev/null | sed -n 's/^UUID: \([0-9A-Fa-f-]*\).*/\1/p' | tr 'a-f' 'A-F' | sort -u
}

copied=0 skipped=0 unmatched=0
# Only the iPhone slice (ios-arm64): the simulator and other platforms never go in a device archive.
while IFS= read -r dsym; do
  [ -n "$dsym" ] || continue
  name=$(basename "$dsym" .dSYM)             # LiveKitWebRTC.framework
  fw="$app/Frameworks/$name"
  bin="$fw/${name%.framework}"
  if [ ! -f "$bin" ]; then
    echo "skip       $name: not embedded in the app (a static or unused package)"
    skipped=$((skipped + 1)); continue
  fi
  if [ -d "$archive/dSYMs/$name.dSYM" ]; then
    echo "present    $name: the archive already has its dSYM"
    skipped=$((skipped + 1)); continue
  fi
  want=$(uuids "$bin")
  have=$(uuids "$dsym")
  if [ -n "$want" ] && [ -n "$have" ] && [ "$want" = "$have" ]; then
    cp -R "$dsym" "$archive/dSYMs/" && { echo "copied     $name (UUID $(echo "$want" | tr '\n' ' '))"; copied=$((copied + 1)); }
  else
    echo "UNMATCHED  $name: the framework in the archive has UUID [$(echo "$want" | tr '\n' ' ')], the dSYM in the package has [$(echo "$have" | tr '\n' ' ')]. Not copied."
    unmatched=$((unmatched + 1))
  fi
done < <(find "$packages/artifacts" -path '*.xcframework/ios-arm64/dSYMs/*.dSYM' -maxdepth 8 -type d 2>/dev/null | sort)

echo "dSYMs: $copied copied, $skipped skipped, $unmatched unmatched."
exit 0
