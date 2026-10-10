import SwiftUI

/// DODDY V2. Local memory, ElevenLabs voice and approved Apple Reminders; no accounts or sync.
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
