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

    init() {
        let environment = AppEnvironment.live()
        _store = State(initialValue: MemoryStore(environment: environment))
        _profiles = State(initialValue: ProfileStore(environment: environment))
        // A conversation never survives a relaunch, so neither may its island.
        VoiceLiveActivity.endStale()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(profiles)
                .environment(\.appEnvironment, store.environment)
                // If the user turned Doddy's notifications on earlier, re-send the (possibly new) token.
                .task { await UpdatesModel().syncPushTokenIfOn() }
        }
    }
}
