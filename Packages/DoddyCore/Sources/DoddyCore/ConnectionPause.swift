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
             .calculate, .convertUnits, .parkingSpot, .addIngredients,
             .addToList, .readList, .checkOff, .removeFromList, .createList, .noteCapabilityGap,
             .startStopwatch, .stopStopwatch, .checkStopwatch, .openTrainingPlan:
            // The stopwatch is Doddy's own tool on this iPhone (ADR-652), and so is the plan screen
            // (ADR-626): no other app or account.
            false
        case .checkErrands:
            // Reads the tasks Doddy keeps for the user (ADR-570); no other app or account.
            false
        case .handOverErrand:
            // Doddy's server searches and reads the web for it (ADR-570).
            true
        case .findDeals:
            // Doddy's server fetches the chains' leaflet pages for it (SHOPPING.md).
            true
        case .readCalendar, .findFreeTime, .leaveBy, .createCalendarEvent, .createReminder, .lookupContact, .upcomingBirthdays, .setTimer,
             .openMap, .runShortcut, .draftMessage, .draftBlikTransfer, .makePresentation, .readSteps, .readHealthWeek, .findPhotos, .openCamera, .cloudTool, .changeCalendarEvent, .changeReminder,
             .deleteCalendarEvent, .deleteReminder, .setAlarm, .undoLast,
             .deleteCalendarEvents, .moveReminders, .listAlarms, .cancelAlarm,
             .convertCurrency:
            // Currency rates come from the ECB's public file, another service (ADR-300).
            true
        case .remindAboutNote(let draft):
            // A time stays inside Doddy; a place is looked up in Apple Maps, another service.
            if case .place = draft.target { true } else { false }
        }
    }

    /// What the agent hears instead of a result. Nothing was looked up or changed.
    public static let reply = "paused: the user has paused all connections in Settings, so Doddy didn't use any other app or account. Nothing was looked up or changed. Tell the user in one sentence; they can turn connections back on in Settings, Connections, or on the conversation screen."
}
