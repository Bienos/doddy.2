import Foundation

/// "Pause all connections" (docs/design/SETTINGS_AND_CONNECTIONS.md §6): one switch that stops
/// Doddy using every other app and online account at once, without touching iOS permissions or
/// each connection's own switch. Saved notes stay available. Turning it off restores exactly the
/// connections that were on before.
public enum ConnectionPause {
    /// Per-device preference key (@AppStorage). Off unless the user turns it on.
    public static let preferenceKey = "connections.pauseAll"

    /// True for tool calls that would reach another app or account.
    public static func applies(to request: VoiceToolRequest) -> Bool {
        switch request {
        case .searchMemories, .saveMemory, .unsupported, .invalid, .needsClarification, .startTranslator, .stopTranslator,
             .addToList, .readList, .checkOff, .removeFromList, .createList:
            false
        case .readCalendar, .createCalendarEvent, .createReminder, .lookupContact, .setTimer,
             .openMap, .runShortcut, .draftMessage, .cloudTool, .changeCalendarEvent, .changeReminder:
            true
        case .remindAboutNote(let draft):
            // A time stays inside Doddy; a place is looked up in Apple Maps, another service.
            if case .place = draft.target { true } else { false }
        }
    }

    /// What the agent hears instead of a result. Nothing was looked up or changed.
    public static let reply = "paused: the user has paused all connections in Settings, so Doddy didn't use any other app or account. Nothing was looked up or changed. Tell the user in one sentence; they can turn connections back on in Settings, Connections, or on the conversation screen."
}
