import AppIntents

/// Makes `TalkToDoddyIntent` (Shared/Shortcuts) and `SaveToDoddyIntent` appear under Doddy in
/// Shortcuts, Siri and the Action Button picker with no setup. App target only.
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
        // Free text can't be part of a phrase, so Siri asks "What should Doddy keep?".
        AppShortcut(
            intent: SaveToDoddyIntent(),
            phrases: [
                "Save a note in \(.applicationName)",
                "Save to \(.applicationName)",
                "Keep this in \(.applicationName)",
            ],
            shortTitle: "Save to Doddy",
            systemImageName: "square.and.arrow.down")
    }
}
