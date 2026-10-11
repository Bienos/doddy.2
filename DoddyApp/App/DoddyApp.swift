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
        let environment = AppEnvironment.shared
        let store = MemoryStore(environment: environment)
        let noteReminders = NoteReminderStore(coordinator: environment.noteReminders)
        store.noteReminders = noteReminders
        // A reminder's "Done" or "Tomorrow 09:00" can start the app in the background.
        NoteReminderRouter.shared.reminders = noteReminders
        // A tick from a widget can also start the app in the background (ADR-219).
        WidgetSync.shared.store = store
        // Siri and Shortcuts list actions (ADR-226) use the same store.
        IntentStores.store = store
        WidgetSync.shared.reminders = noteReminders
        // The Apple Watch app asks through the same store (ADR-232).
        PhoneWatchLink.shared.store = store
        PhoneWatchLink.shared.activate()
        // Shopping mode (ADR-257) runs on the Lock Screen across relaunches.
        ShoppingModeController.shared.store = store
        // Shared lists (ADR-263) sync through the same store.
        SharedListsController.shared.store = store
        _store = State(initialValue: store)
        _noteReminders = State(initialValue: noteReminders)
        let profiles = ProfileStore(environment: environment)
        _profiles = State(initialValue: profiles)
        // A conversation never survives a relaunch, so neither may its island.
        VoiceLiveActivity.endStale()
        // A focus timer does survive one (it is saved); this also lets its island's buttons work
        // when iOS starts the app just to run them (ADR-241). Breathing and read-aloud don't.
        FocusController.shared.refresh()
        ToolLiveActivity.endLeftovers(keeping: [.focus])
        // "Hey Doddy" (ADR-254) starts conversations with the same notes and profile.
        WakeWordListener.shared.store = store
        WakeWordListener.shared.profiles = profiles
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
                .task { ShoppingModeController.shared.reattach() }
                .task {
                    await SharedListsController.shared.load()
                    await SharedListsController.shared.syncAll()
                    await SharedListsController.shared.startLiveUpdates()
                }
                // Keeps the morning check-in's words in the iPhone's current language (ADR-220).
                .task { if MorningCheckInSettings.stored().isOn { _ = await MorningCheckInScheduler.apply(.stored()) } }
                .task { if TidyUpSettings.stored().isOn { _ = await TidyUpScheduler.apply(.stored()) } }
                .task { if EveningWrapUpSettings.stored().isOn { _ = await EveningWrapUpScheduler.apply(.stored()) } }
                .task { if WeeklyLookBackSettings.stored().isOn { _ = await WeeklyLookBackScheduler.apply(.stored()) } }
                .task { await BirthdayScheduler.refresh() }
        }
    }
}
