import AppIntents

/// Makes `TalkToDoddyIntent` (Shared/Shortcuts) appear under Doddy in Shortcuts, Siri and the
/// Action Button picker with no setup. App target only.
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
