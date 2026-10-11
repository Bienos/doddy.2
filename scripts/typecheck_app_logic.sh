#!/usr/bin/env bash
# Type-checks the app files that need no Apple UI framework (they import only Foundation,
# Observation and DoddyCore) against the real DoddyCore module, in Swift 6 mode, on Linux.
#
# This is a compile check, which `swiftc -parse` is not: it catches wrong types, missing members,
# access-control mistakes and Swift 6 isolation errors in these files. It does NOT cover SwiftUI
# views, App Intents, widgets or anything importing UIKit, AVFoundation, EventKit and so on;
# those still need Xcode (see docs/implementation/MAC_VERIFICATION_CHECKLIST_2026-10-10.md).
#
# Four stand-ins keep it honest and small: PreferenceKey is copied out of RootView.swift as it is
# (so key names can't drift); AppEnvironment, which imports SwiftUI, is replaced by a struct with
# just the members these files read; and PlaceLocation, which imports CoreLocation and MapKit, is
# replaced by a class with only the one method NoteReminderStore calls; SystemNoteNotifications
# (UserNotifications) by its one static method. The stand-ins are only
# type-checked, never run, so their bodies say nothing about real location behaviour.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v swift >/dev/null 2>&1 || { echo "NOT RUN: swift not found on PATH"; exit 2; }

package=Packages/DoddyCore
flags=()
[ "$(uname)" = "Linux" ] && flags=(-Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined)

# Builds the DoddyCore module (a no-op when `swift test` already did).
swift build --package-path "$package" ${flags[@]+"${flags[@]}"} >/dev/null
modules="$(swift build --package-path "$package" ${flags[@]+"${flags[@]}"} --show-bin-path)/Modules"
[ -d "$modules" ] || { echo "FAIL: DoddyCore module directory not found at $modules"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

awk '/^enum PreferenceKey/{f=1} f{print} f&&/^}/{exit}' DoddyApp/App/RootView.swift > "$work/PreferenceKey.swift"
[ -s "$work/PreferenceKey.swift" ] || { echo "FAIL: could not extract PreferenceKey from RootView.swift"; exit 1; }
cat > "$work/AppEnvironmentStub.swift" <<'SWIFT'
import DoddyCore
struct AppEnvironment {
    let memoryRepository: any MemoryRepository
    let recallService: any RecallService
    let profileRepository: any ProfileRepository
    let noteReminders: NoteReminderCoordinator?
    let capabilities: CapabilityCatalog
    let storageProblem: String?
    let listRepository: any ListRepository
    let photoRepository: any PhotoRepository
    let photoFiles: PhotoFiles
    let audioRepository: any AudioRepository
    let audioFiles: AudioFiles
}
SWIFT
# SystemNoteNotifications imports UserNotifications; NoteReminderStore only calls its static
# registerCategory() when the iPhone's language changes (ADR-213).
cat > "$work/SystemNoteNotificationsStub.swift" <<'SWIFT'
struct SystemNoteNotifications {
    static func registerCategory() async {}
}
SWIFT
cat > "$work/PlaceLocationStub.swift" <<'SWIFT'
import DoddyCore
@MainActor
final class PlaceLocation {
    static let shared = PlaceLocation()
    private init() {}
    func requestWhenInUse() async -> LocationReadiness { .unavailable }
}
SWIFT

# The one type IslandPose.swift needs from the island drawing model (ADR-313).
cat > "$work/IslandRectStub.swift" <<'SWIFT'
struct IslandRect: Equatable, Sendable {
    var x: Double, y: Double, width: Double, height: Double
}
SWIFT

files=(
  DoddyApp/Infrastructure/PersonalityPreferences.swift
  DoddyApp/Infrastructure/PinnedNotesStorage.swift
  DoddyApp/Infrastructure/ConversationLogStore.swift
  DoddyApp/Infrastructure/MemoryStore.swift
  DoddyApp/Infrastructure/MemoryStore+Lists.swift
  DoddyApp/Infrastructure/ProfileStore.swift
  DoddyApp/Infrastructure/ShortcutRouter.swift
  DoddyApp/Infrastructure/SiriNoteLookup.swift
  DoddyApp/Features/Ask/AskController.swift
  DoddyApp/Features/NoteReminders/NoteReminderStore.swift
  DoddyApp/Features/Opening/OpeningModel.swift
  DoddyApp/Features/Photos/PhotoFiles.swift
  # Only the part outside `#if canImport(AlarmKit)`: the AlarmKit code itself needs Xcode 26.
  DoddyApp/Features/Alarms/AlarmScheduler.swift
  DoddyApp/Features/VoiceMemos/AudioFiles.swift
  DoddyApp/Features/Parking/ParkingStore.swift
  Shared/Widgets/WidgetSnapshotFile.swift
  Shared/Share/ShareInboxFile.swift
  # SiriNoteLookup picks Doddy's pose for an answer (ADR-313); IslandRect is stubbed above.
  Shared/IslandArt/IslandPose.swift
)
for f in "${files[@]}"; do [ -f "$f" ] || { echo "FAIL: $f is missing; update scripts/typecheck_app_logic.sh"; exit 1; }; done

echo "Type-checking ${#files[@]} app files against DoddyCore (Swift 6)"
swiftc -typecheck -swift-version 6 -I "$modules" "$work/PreferenceKey.swift" "$work/AppEnvironmentStub.swift" "$work/PlaceLocationStub.swift" "$work/SystemNoteNotificationsStub.swift" "$work/IslandRectStub.swift" "${files[@]}"
echo "PASS: ${#files[@]} app files type-check (SwiftUI, App Intents and widget code are not covered)"
