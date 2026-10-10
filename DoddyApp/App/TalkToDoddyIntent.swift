import AppIntents

/// "Talk to Doddy": the action behind the Shortcuts app, Siri, Spotlight, the Action Button and
/// Back Tap. iOS only lets a conversation start with the app in front, so this opens Doddy and
/// asks it to start talking. Once the Dynamic Island is showing you can switch back to Safari
/// (or anything else) and the conversation carries on.
struct TalkToDoddyIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Doddy"
    static let description = IntentDescription("Opens Doddy and starts a voice conversation.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        VoiceLaunchRouter.shared.requestConversation()
        return .result()
    }
}

/// Makes the shortcut appear in Shortcuts and Spotlight without the user creating anything.
/// It does NOT assign Back Tap: the user picks it once in Settings (see Settings → Voice).
struct DoddyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TalkToDoddyIntent(),
            phrases: [
                "Talk to \(.applicationName)",
                "Start \(.applicationName)",
            ],
            shortTitle: "Talk to Doddy",
            systemImageName: "waveform")
    }
}
