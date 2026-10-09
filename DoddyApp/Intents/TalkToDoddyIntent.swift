import AppIntents

/// "Talk to Doddy": opens the app in the foreground and starts (or focuses) the voice
/// conversation. Because it is an App Shortcut it shows up in the Shortcuts app, Siri and the
/// Action Button picker without any setup, and it can be used inside a personal shortcut for
/// Back Tap. During an active Back Tap test the invocation is the test's receipt instead.
struct TalkToDoddyIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Doddy"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutRouter.shared.talkToDoddyInvoked()
        return .result()
    }
}

struct DoddyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TalkToDoddyIntent(),
            phrases: [
                "Talk to \(.applicationName)",
                "Hey \(.applicationName)",
                "Open \(.applicationName)",
            ],
            shortTitle: "Talk to Doddy",
            systemImageName: "waveform")
    }
}
