import SwiftUI

/// DODDY V2. Local text memory (M1), foreground voice (V1) and on-phone connections (V4a).
@main
struct DoddyApp: App {
    @State private var store: MemoryStore
    @State private var connections: ConnectionsStore
    /// Retained here: the notification centre holds its delegate weakly.
    private let nudgeDelegate = NudgePresentationDelegate()

    init() {
        let environment = AppEnvironment.live()
        _store = State(initialValue: MemoryStore(environment: environment))
        _connections = State(initialValue: ConnectionsStore(environment: environment))
        NudgePresentationDelegate.install(nudgeDelegate)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(connections)
                .environment(\.appEnvironment, store.environment)
        }
    }
}
