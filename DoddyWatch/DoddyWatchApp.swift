import SwiftUI

/// Doddy on Apple Watch (ADR-232): a view of the iPhone's pinned notes, next note reminders and
/// lists, ticking list items and saving a new note, each done by the iPhone and read back there.
@main
struct DoddyWatchApp: App {
    @State private var link = WatchLink()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(link)
                .onAppear { link.activate() }
        }
    }
}
