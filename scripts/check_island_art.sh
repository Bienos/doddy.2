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
art=Shared/IslandArt/IslandBoardArt.generated.swift
# The generator writes over the committed file; put it back however this script ends (an
# interrupted run must not leave a modified tracked file).
trap '[ -f "$work/committed.swift" ] && cp "$work/committed.swift" "$art"; rm -rf "$work"' EXIT

cp "$art" "$work/committed.swift"
python3 -I tools/island_boards/generate_island_art.py >/dev/null
if ! cmp -s "$work/committed.swift" "$art"; then
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
# Whole Doddy (ADR-264): every pose has its picture in the app and the widget catalogs.
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
for name in $("$work/island-check" --talking-assets); do
    for file in Contents.json art@2x.png art@3x.png; do
        if [ ! -f "DoddyApp/Resources/Assets.xcassets/$name.imageset/$file" ]; then
            echo "FAIL: DoddyApp/Resources/Assets.xcassets/$name.imageset/$file is missing"; missing=1
        fi
    done
done
# The storyboards' panels (ADR-299, ADR-380): one day picture each, app catalog only.
for name in $("$work/island-check" --story-assets); do
    for file in Contents.json day.jpg; do
        if [ ! -f "DoddyApp/Resources/Assets.xcassets/$name.imageset/$file" ]; then
            echo "FAIL: DoddyApp/Resources/Assets.xcassets/$name.imageset/$file is missing"; missing=1
        fi
    done
done
# The watch app's two poses (ADR-323), in its own catalog.
for name in WatchDoddy_crosslegged WatchDoddy_fistpump WatchDoddy_turned_away; do
    for file in Contents.json art@2x.png; do
        if [ ! -f "DoddyWatch/Assets.xcassets/$name.imageset/$file" ]; then
            echo "FAIL: DoddyWatch/Assets.xcassets/$name.imageset/$file is missing"; missing=1
        fi
    done
done
# The Lock Screen widget's face (ADR-313), widget catalog only.
for file in Contents.json art@2x.png art@3x.png; do
    if [ ! -f "DoddyWidgets/Assets.xcassets/WidgetDoddy_face.imageset/$file" ]; then
        echo "FAIL: DoddyWidgets/Assets.xcassets/WidgetDoddy_face.imageset/$file is missing"; missing=1
    fi
done
# Notifications and the other Live Activities (ADR-546). The mappings are checked by the binary
# above; these greps check the app and widget files really use them (they can't be compiled here).
# Each notification kind is named at exactly one call site, in the file that schedules it.
notification_file() {
    case "$1" in
        noteReminder)   echo DoddyApp/Infrastructure/Connections/NoteReminderNotifications.swift ;;
        morningCheckIn) echo DoddyApp/Features/MorningCheckIn/MorningCheckInScheduler.swift ;;
        birthday)       echo DoddyApp/Features/Birthdays/BirthdayViews.swift ;;
        eveningWrapUp)  echo DoddyApp/Features/EveningWrapUp/EveningWrapUpViews.swift ;;
        weeklyLookBack) echo DoddyApp/Features/WeeklyLookBack/WeeklyLookBackViews.swift ;;
        leaveBy)        echo DoddyApp/Features/LeaveBy/LeaveByScheduler.swift ;;
        tidyUp)         echo DoddyApp/Features/TidyUp/TidyUpViews.swift ;;
        focusDone)      echo DoddyApp/Features/Focus/FocusController.swift ;;
        *)              echo "" ;;
    esac
}
for kind in $("$work/island-check" --notification-kinds); do
    file="$(notification_file "$kind")"
    if [ -z "$file" ]; then
        echo "FAIL: notification kind '$kind' has no call site listed in scripts/check_island_art.sh"; missing=1; continue
    fi
    count="$(grep -c "NotificationArt.attachment(for: \.$kind)" "$file" || true)"
    if [ "$count" -ne 1 ]; then
        echo "FAIL: $file should name NotificationArt.attachment(for: .$kind) once, found $count"; missing=1
    fi
done
# No call site may hold a raw pose: `attachment(.crosslegged)` would dodge the mapping above.
if grep -rn "NotificationArt\.attachment(\." DoddyApp --include=*.swift; then
    echo "FAIL: NotificationArt.attachment must be called with 'for: <DoddyNotificationKind>'"; missing=1
fi
# Every file that builds a local notification either uses a picture or is listed here as one
# that deliberately has none (DeviceConnections.swift: the event nudge and "Timer done", left
# without a picture until the owner decides; WHOLE_DODDY_ISLAND_STATUS.md).
for file in $(grep -rl "UNMutableNotificationContent" DoddyApp --include=*.swift); do
    case "$file" in
        DoddyApp/Infrastructure/Connections/DeviceConnections.swift) continue ;;
    esac
    if ! grep -q "NotificationArt\.attachment(for:" "$file"; then
        echo "FAIL: $file builds a notification with no Doddy picture (add a DoddyNotificationKind, or list it as pictureless here)"; missing=1
    fi
done
# The Live Activities that draw through DoddyActivityPose name no pose themselves, so a mapping
# can't be changed in a widget file without the binary's checks seeing it.
for file in DoddyWidgets/AlarmLiveActivity.swift DoddyWidgets/ShoppingLiveActivity.swift DoddyWidgets/DoddyCallLiveActivity.swift; do
    if grep -nE "(IslandPoseView|WidgetPose)\(pose: \." "$file"; then
        echo "FAIL: $file names a pose directly; use DoddyActivityPose"; missing=1
    fi
    if ! grep -q "DoddyActivityPose\." "$file"; then
        echo "FAIL: $file does not use DoddyActivityPose"; missing=1
    fi
done
# The conversation island keeps one rule for "ended": the fist pump needs a saved note.
if ! grep -q "isEnded { return savedCount > 0 ? .fistpump : .crosslegged }" Shared/IslandArt/IslandScene.swift; then
    echo "FAIL: IslandScene.swift lost the 'ended needs a saved note for the fist pump' rule"; missing=1
fi
[ "$missing" -eq 0 ] || exit 1
"$work/island-check" "$@"
