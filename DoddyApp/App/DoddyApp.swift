import SwiftUI

/// DODDY V2. Local text memory, the reviewed profile and the written Back Tap guide work, and
/// voice runs on an ElevenLabs agent. Reminders and accounts do not exist yet.
@main
struct DoddyApp: App {
    @State private var store: MemoryStore
    @State private var profiles: ProfileStore

    init() {
        let environment = AppEnvironment.live()
        _store = State(initialValue: MemoryStore(environment: environment))
        _profiles = State(initialValue: ProfileStore(environment: environment))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(profiles)
                .environment(\.appEnvironment, store.environment)
        }
    }
}
