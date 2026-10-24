import DoddyCore
import SwiftUI

/// DODDY V2. Local text memory (M1) and the reviewed profile, voice with the ElevenLabs agent (V1),
/// the Talk to Doddy shortcut and Back Tap guide (V2) and the conversation's Dynamic Island (V3).
/// Apple sign-in is optional for local notes and required only for voice; the optional messaging
/// server (notifications, texts, calls, news) uses a separate anonymous device account.
@main
struct DoddyApp: App {
    /// APNs device-token callbacks for Doddy's notifications (server/messaging).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: MemoryStore
    @State private var profiles: ProfileStore
    @State private var noteReminders: NoteReminderStore

    init() {
        LaunchWork.appInitBegan()
        defer { LaunchWork.appInitEnded() }
        // The screens' language is read when the app starts: English unless the person picked another (ADR-459).
        AppLanguageStore.applyAtLaunch()
        // Back Tap's old "Small island" becomes Settings › "Expand when Doddy speaks" (ADR-579),
        // before anything reads either preference.
        Self.migrateLaunchPreferences()
        #if DEBUG
        // UI tests of "Before we start" (ADR-581) start without an acceptance from an earlier test.
        if ProcessInfo.processInfo.arguments.contains("-resetLegalAcceptanceForUITests") {
            UserDefaults.standard.removeObject(forKey: LegalAcceptance.preferenceKey)
        }
        #endif
        VoiceSessionKeychain.removeLegacySetup()
        // Before anything reads them: a fresh install doesn't pick up an earlier install's server tokens.
        ServerKeychainStore.clearLeftoversOnFreshInstall()
        // The same for the keys a person pasted in for their own accounts (ADR-640).
        AccountKeyStore.clearLeftoversOnFreshInstall()
        let environment = AppEnvironment.shared
        let store = MemoryStore(environment: environment)
        let noteReminders = NoteReminderStore(coordinator: environment.noteReminders)
        store.noteReminders = noteReminders
        // The learning loop (ADR-440) listens to "What Doddy did" for what was corrected.
        let learning = LearningStore(service: environment.learningService)
        learning.attach(to: ActivityLogStore.shared)
        store.learning = learning
        // Deleting a note, or everything, also clears what "What Doddy did" kept of it (review C2).
        store.activity = ActivityLogStore.shared
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
        // Talk in the Island (ADR-577) greets by name with the app in the background.
        IntentStores.profiles = profiles
        // A conversation never survives a relaunch, so neither may its island.
        VoiceLiveActivity.endStale()
        // A focus timer does survive one (it is saved); this also lets its island's buttons work
        // when iOS starts the app just to run them (ADR-241). Read-aloud doesn't.
        FocusController.shared.refresh()
        ToolLiveActivity.endLeftovers(keeping: [.focus])
        // A call Doddy makes for the user runs on the server, so its island may outlive a
        // relaunch; its Take over and End buttons reach the server from here (ADR-504).
        CallLiveActivity.shared.registerActions()
        // DODDY Capture (ADR-588): the island's Stop, Pause and Resume reach the recorder from here, and
        // iOS starting the app just to run one of them finds it ready.
        RecordingCoordinator.shared.install()
    }

    private static func migrateLaunchPreferences(_ defaults: UserDefaults = .standard) {
        let stored = LaunchPreferencesMigration.Values(
            backTapAction: defaults.string(forKey: PreferenceKey.backTapAction),
            islandExpands: defaults.object(forKey: LaunchPreferencesMigration.islandExpandsKey) as? Bool)
        let moved = LaunchPreferencesMigration.migrate(stored)
        guard moved != stored else { return }
        defaults.set(moved.backTapAction, forKey: PreferenceKey.backTapAction)
        if let expands = moved.islandExpands {
            defaults.set(expands, forKey: LaunchPreferencesMigration.islandExpandsKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(profiles)
                .environment(noteReminders)
                .environment(\.appEnvironment, store.environment)
                // Start-up work waits for the first screen (ADR-547): the cheap local jobs at once,
                // the network and notification jobs a moment later, one at a time (`LaunchWork`).
                .task(id: profiles.hasLoaded) {
                    guard profiles.hasLoaded else { return }
                    LaunchWork.firstScreenShown()
                    await LaunchWork.afterFirstScreen(store: store)
                    await LaunchWork.later()
                }
        }
    }
}
