import AppIntents

/// Makes `TalkToDoddyIntent`, `NewNoteIntent` (Shared/Shortcuts), `SaveToDoddyIntent`,
/// `FindInDoddyIntent`, `AskDoddyNoteIntent` (ADR-248), `StopListeningIntent` (ADR-361) and the list intents (ADR-226) appear under Doddy in
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
        // Turns things off only, so it works with the iPhone locked (ADR-361).
        AppShortcut(
            intent: StopListeningIntent(),
            phrases: [
                "Stop listening in \(.applicationName)",
                "Tell \(.applicationName) to stop listening",
                "\(.applicationName) stop listening",
            ],
            shortTitle: "Stop listening",
            systemImageName: "mic.slash")
        // DODDY Capture (ADR-588). The tenth and last App Shortcut iOS allows. It opens Doddy first, and
        // answers "Recording." only once the recorder delivers audio. Stop is "Stop listening" above.
        AppShortcut(
            intent: StartDoddyRecordingIntent(),
            phrases: [
                "Record this meeting in \(.applicationName)",
                "Record with \(.applicationName)",
                "Start recording in \(.applicationName)",
            ],
            shortTitle: "Record with DODDY",
            systemImageName: "record.circle")
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
        // Answers out loud without opening the app; Siri asks "What are you looking for?" (ADR-248).
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
        // Lists (ADR-226). Phrases with \(\.$list) work once the list names are known to Siri
        // (`updateAppShortcutParameters()` runs when lists change); the items are asked for.
        AppShortcut(
            intent: AddToListIntent(),
            phrases: [
                "Add to \(\.$list) in \(.applicationName)",
                "Add to my \(\.$list) list in \(.applicationName)",
                "Add to a list in \(.applicationName)",
            ],
            shortTitle: "Add to a list",
            systemImageName: "text.badge.plus")
        AppShortcut(
            intent: ReadListIntent(),
            phrases: [
                "What's on my \(\.$list) list in \(.applicationName)",
                "Read \(\.$list) in \(.applicationName)",
                "Read a list in \(.applicationName)",
            ],
            shortTitle: "Read a list",
            systemImageName: "list.bullet")
        AppShortcut(
            intent: CheckOffListItemIntent(),
            phrases: [
                "Tick something on \(\.$list) in \(.applicationName)",
                "Tick off an item in \(.applicationName)",
            ],
            shortTitle: "Tick an item",
            systemImageName: "checkmark.circle")
    }
}
