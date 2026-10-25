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

# Some keys are DoddyCore's own (ADR-579, ADR-581), so the copy imports it as RootView does.
{ echo "import DoddyCore"; awk '/^enum PreferenceKey/{f=1} f{print} f&&/^}/{exit}' DoddyApp/App/RootView.swift; } > "$work/PreferenceKey.swift"
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
    // DODDY Capture (ADR-588): ShortcutRouter opens the newest recording through it.
    let recordingRepository: (any RecordingRepository)?
    static var shared: AppEnvironment { fatalError("a type-check stand-in is never run") }
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

# ShortcutRouter asks the weekly reminder scheduler (UserNotifications) to look again when the
# shortcut has run (ADR-559); only its one entry point is needed.
cat > "$work/OpenWaysReminderSchedulerStub.swift" <<'SWIFT'
@MainActor
enum OpenWaysReminderScheduler {
    static func refresh(_ setup: BackTapSetupModel) async {}
}
SWIFT

# DealsModel (SHOPPING.md 2) looks the server up through ServerConfig, which builds a URLSession
# transport; only the lookup is needed here.
cat > "$work/ServerConfigStub.swift" <<'SWIFT'
import DoddyCore
enum ServerConfig {
    static func client() -> DoddyServerClient? { nil }
}
SWIFT

# WatchModel (SHOPPING_WATCH.md) asks iOS for this iPhone's push token through WatchPush (UserNotifications)
# once the user said yes to a watch; only its one entry point is needed here.
cat > "$work/WatchPushStub.swift" <<'SWIFT'
@MainActor
enum WatchPush {
    static func register() async {}
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
  # The learning loop's view state (ADR-440); it listens to ActivityLogStore, listed further down.
  DoddyApp/Infrastructure/LearningStore.swift
  DoddyApp/Infrastructure/MemoryStore.swift
  DoddyApp/Infrastructure/MemoryStore+Lists.swift
  DoddyApp/Infrastructure/ProfileStore.swift
  DoddyApp/Infrastructure/ShortcutRouter.swift
  DoddyApp/Infrastructure/LegalAcceptanceStore.swift
  DoddyApp/Infrastructure/UnfinishedNoteStore.swift
  DoddyApp/Infrastructure/SiriNoteLookup.swift
  # The thread with Doddy (ADR-585): the Messages screen's state, without the views.
  DoddyApp/Features/Messages/MessagesModel.swift
  DoddyApp/Features/NoteReminders/NoteReminderStore.swift
  DoddyApp/Features/Opening/OpeningModel.swift
  DoddyApp/Features/Photos/PhotoFiles.swift
  # Only the part outside `#if canImport(AlarmKit)`: the AlarmKit code itself needs Xcode 26.
  DoddyApp/Features/Alarms/AlarmScheduler.swift
  # Timers through AlarmKit (ADR-650): the same, only the part outside `#if canImport(AlarmKit)`.
  DoddyApp/Features/Alarms/TimerRinger.swift
  # Reminders that ring like an alarm (ADR-651): NoteReminderStore calls it.
  DoddyApp/Features/Alarms/ReminderRinger.swift
  DoddyApp/Features/VoiceMemos/AudioFiles.swift
  DoddyApp/Features/Parking/ParkingStore.swift
  DoddyApp/Features/Lists/ListTemplateStore.swift
  Shared/Widgets/WidgetSnapshotFile.swift
  DoddyApp/Features/Voice/VoiceConfig.swift
  DoddyApp/Infrastructure/ActivityLogStore.swift
  Shared/Share/ShareInboxFile.swift
  # SiriNoteLookup picks Doddy's pose for an answer (ADR-313); IslandRect is stubbed above.
  Shared/IslandArt/IslandPose.swift
  # Motion v2: the one Doddy's director, kept free of SwiftUI so it is compiled here.
  DoddyApp/DesignSystem/Motion/DoddyDirector.swift
  # Calls Doddy places for the user (ADR-500): the screens' state, without the views.
  DoddyApp/Features/CallCases/CallCasesModel.swift
  # This week's leaflets (SHOPPING.md 2): the screen's state and the voice tool's answer, without the views.
  DoddyApp/Features/Shopping/DealsModel.swift
  # Price watch (SHOPPING_WATCH.md): the card's flow and the list's state, without the views.
  DoddyApp/Features/Shopping/WatchModel.swift
  # The parcel list (ADR-641): its state and the look-up flow, without the views or the InPost client.
  DoddyApp/Features/Parcels/ParcelsModel.swift
  # The kept training plan (ADR-625), without the screens.
  DoddyApp/Features/Sport/TrainingPlanStore.swift
  DoddyApp/Features/Sport/PlanText.swift
)
for f in "${files[@]}"; do [ -f "$f" ] || { echo "FAIL: $f is missing; update scripts/typecheck_app_logic.sh"; exit 1; }; done

echo "Type-checking ${#files[@]} app files against DoddyCore (Swift 6)"
swiftc -typecheck -swift-version 6 -I "$modules" "$work/PreferenceKey.swift" "$work/AppEnvironmentStub.swift" "$work/PlaceLocationStub.swift" "$work/SystemNoteNotificationsStub.swift" "$work/IslandRectStub.swift" "$work/OpenWaysReminderSchedulerStub.swift" "$work/ServerConfigStub.swift" "$work/WatchPushStub.swift" "${files[@]}"
echo "PASS: ${#files[@]} app files type-check (SwiftUI, App Intents and widget code are not covered)"

# App files that import no UI framework but aren't in the list: most use types this script can't
# build on Linux (URLSession transports, the EventKit wrapper). Named here so a new one gets noticed
# and added when it can be. The island art files are compiled by scripts/check_island_art.sh.
others=()
while IFS= read -r f; do
  case " ${files[*]} " in *" $f "*) continue ;; esac
  case "$f" in Shared/IslandArt/*) continue ;; esac
  if ! grep -E '^[[:space:]]*(@preconcurrency[[:space:]]+)?import[[:space:]]' "$f" \
      | grep -qvE 'import[[:space:]]+(Foundation|Observation|DoddyCore|os|OSLog)[[:space:]]*$'; then
    others+=("$f")
  fi
done < <(find DoddyApp Shared -name '*.swift' | sort)
if [ "${#others[@]}" -gt 0 ]; then
  echo "NOTE: ${#others[@]} app files import no UI framework but aren't type-checked here:"
  printf '  %s\n' "${others[@]}"
fi
