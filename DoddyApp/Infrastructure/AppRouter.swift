import DoddyCore
import Foundation
import Observation

/// Process-wide objects shared by the SwiftUI scene and the App Intents (Siri, Shortcuts,
/// Control Center), so both use one memory store and one SQLite connection.
@MainActor
enum AppServices {
    static let store = MemoryStore(environment: .live())
    static let router = AppRouter()
}

/// Requests that come from outside the screen (App Intents) or from Home.
@MainActor
@Observable
final class AppRouter {
    /// Bumped each time "Talk to Doddy" should open; RootView presents the voice screen.
    private(set) var talkRequest = 0
    /// Armed by the Back Tap setup's tap test. While waiting, an arriving shortcut completes
    /// the test instead of starting a conversation.
    var shortcutTest = ShortcutTest()

    func requestTalk() { talkRequest += 1 }

    /// Called by `TalkToDoddyIntent`, whatever ran it (Siri, Shortcuts, Back Tap, Action Button,
    /// Control Center); iOS doesn't say which.
    func talkShortcutArrived(at date: Date = .now) {
        if shortcutTest.receiveShortcut(at: date) { return }
        requestTalk()
    }
}
