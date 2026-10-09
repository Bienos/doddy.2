import SwiftUI

/// DODDY V2. Local text memory (M1), voice (V1) and App Shortcuts (V2) are built; reminders,
/// other apps and accounts are not.
@main
struct DoddyApp: App {
    @State private var store = AppServices.store
    @State private var router = AppServices.router

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(\.appEnvironment, store.environment)
        }
    }
}
