import SwiftUI

/// DODDY V2. Local text memory (M1) and the reviewed profile, voice with the ElevenLabs agent (V1),
/// the Talk to Doddy shortcut and Back Tap guide (V2) and the conversation's Dynamic Island (V3).
/// No sign-in: the optional messaging server (notifications, texts, calls, news) uses an anonymous
/// device account.
@main
struct DoddyApp: App {
    /// APNs device-token callbacks for Doddy's notifications (server/messaging).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: MemoryStore
    @State private var profiles: ProfileStore
    @State private var noteReminders: NoteReminderStore

    init() {
        let environment = AppEnvironment.live()
        let store = MemoryStore(environment: environment)
        let noteReminders = NoteReminderStore(coordinator: environment.noteReminders)
        store.noteReminders = noteReminders
        // A reminder's "Done" or "Tomorrow 09:00" can start the app in the background.
        NoteReminderRouter.shared.reminders = noteReminders
        _store = State(initialValue: store)
        _noteReminders = State(initialValue: noteReminders)
        _profiles = State(initialValue: ProfileStore(environment: environment))
        // A conversation never survives a relaunch, so neither may its island.
        VoiceLiveActivity.endStale()
        // A focus timer does survive one (it is saved); this also lets its island's buttons work
        // when iOS starts the app just to run them (ADR-214). Breathing and read-aloud don't.
        FocusController.shared.refresh()
        ToolLiveActivity.endLeftovers(keeping: [.focus])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(profiles)
                .environment(noteReminders)
                .environment(\.appEnvironment, store.environment)
                // If the user turned Doddy's notifications on earlier, re-send the (possibly new) token.
                .task { await UpdatesModel().syncPushTokenIfOn() }
                .task { await SystemNoteNotifications.registerCategory() }
        }
    }
}
