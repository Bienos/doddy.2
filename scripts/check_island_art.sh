#!/usr/bin/env bash
# Checks the Dynamic Island drawing data and scene logic on any machine with Swift (Linux too):
#   1. Shared/IslandArt/IslandBoardArt.generated.swift is exactly what the generator makes from
#      design/dynamic-island-v4/02-states (the owner's pack), so nobody hand-edits the art.
#   2. Every path in every board parses, every drawing fits its view box, orange turns grey
#      when Doddy can't hear you, and each conversation state maps to the expected island
#      (tools/island_boards/IslandSceneChecks.swift), including decoding older content.
# ActivityKit is replaced by a one-protocol stand-in (tools/island_boards/stubs). This does NOT
# compile the SwiftUI views or the widget; that needs Xcode (scripts/ci.sh on macOS).
set -euo pipefail
cd "$(dirname "$0")/.."

command -v swiftc >/dev/null 2>&1 || { echo "NOT RUN: swiftc not found on PATH"; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp Shared/IslandArt/IslandBoardArt.generated.swift "$work/committed.swift"
python3 -I tools/island_boards/generate_island_art.py >/dev/null
if ! cmp -s "$work/committed.swift" Shared/IslandArt/IslandBoardArt.generated.swift; then
    cp "$work/committed.swift" Shared/IslandArt/IslandBoardArt.generated.swift
    echo "FAIL: IslandBoardArt.generated.swift differs from a fresh run of the generator"
    exit 1
fi

swiftc -swift-version 6 -parse-as-library -emit-module -module-name ActivityKit \
    -emit-module-path "$work/ActivityKit.swiftmodule" -o "$work/ActivityKit.o" -c tools/island_boards/stubs/ActivityKit.swift
swiftc -swift-version 6 -parse-as-library -I "$work" -o "$work/island-check" \
    "$work/ActivityKit.o" \
    Shared/IslandArt/IslandArtModel.swift \
    Shared/IslandArt/IslandPathParser.swift \
    Shared/IslandArt/IslandBoardArt.generated.swift \
    Shared/IslandArt/IslandScene.swift \
    Shared/IslandArt/IslandPose.swift \
    Shared/VoiceActivity/DoddyVoiceAttributes.swift \
    Shared/ToolActivity/DoddyToolAttributes.swift \
    tools/island_boards/IslandSceneChecks.swift \
    tools/island_boards/IslandArtCheck.swift
# Whole Doddy (ADR-255): every pose has its picture in the app and the widget catalogs.
missing=0
for name in $("$work/island-check" --pose-assets); do
    for catalog in DoddyApp/Resources/Assets.xcassets DoddyWidgets/Assets.xcassets; do
        for file in Contents.json art@2x.png art@3x.png; do
            if [ ! -f "$catalog/$name.imageset/$file" ]; then
                echo "FAIL: $catalog/$name.imageset/$file is missing"; missing=1
            fi
        done
    done
done
[ "$missing" -eq 0 ] || exit 1
"$work/island-check" "$@"
