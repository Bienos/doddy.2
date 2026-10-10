import SwiftUI

/// DODDY V2. Local memory, voice, and (with a Doddy server) push and text updates.
@main
struct DoddyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = MemoryStore(environment: .live())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.appEnvironment, store.environment)
                // APNs tokens can change; re-send it if the user turned notifications on.
                .task { await UpdatesModel().syncPushTokenIfOn() }
        }
    }
}
