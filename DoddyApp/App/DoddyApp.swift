import SwiftUI

/// DODDY V2. Local text memory (M1), voice with the ElevenLabs agent (V1), the Talk to Doddy
/// shortcut (V2) and the conversation's Dynamic Island (V3). No accounts.
@main
struct DoddyApp: App {
    @State private var store = MemoryStore(environment: .live())

    init() {
        // A conversation never survives a relaunch, so neither may its island.
        VoiceLiveActivity.endStale()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.appEnvironment, store.environment)
        }
    }
}
