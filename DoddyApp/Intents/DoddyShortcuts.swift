import AppIntents

/// Makes `TalkToDoddyIntent`, `NewNoteIntent` (Shared/Shortcuts), `SaveToDoddyIntent`,
/// `FindInDoddyIntent` and `AskDoddyNoteIntent` appear under Doddy in
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
        AppShortcut(
            intent: NewNoteIntent(),
            phrases: [
                "New note in \(.applicationName)",
                "Write a note in \(.applicationName)",
            ],
            shortTitle: "New note",
            systemImageName: "square.and.pencil")
        AppShortcut(
            intent: FindInDoddyIntent(),
            phrases: [
                "Find in \(.applicationName)",
                "Search \(.applicationName)",
                "Look it up in \(.applicationName)",
            ],
            shortTitle: "Find in Doddy",
            systemImageName: "magnifyingglass")
        // Answers out loud without opening the app; Siri asks "What are you looking for?" (ADR-214).
        AppShortcut(
            intent: AskDoddyNoteIntent(),
            phrases: [
                "Ask \(.applicationName) what I saved",
                "What did I save in \(.applicationName)",
                "Read my note from \(.applicationName)",
                "Check my notes in \(.applicationName)",
            ],
            shortTitle: "Ask what I saved",
            systemImageName: "text.bubble")
    }
}
