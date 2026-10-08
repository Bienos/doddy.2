import SwiftUI

/// DODDY V2. Local text memory (M1) works; AI, voice, reminders and accounts do not exist yet.
@main
struct DoddyApp: App {
    @State private var store = MemoryStore(environment: .live())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.appEnvironment, store.environment)
        }
    }
}
