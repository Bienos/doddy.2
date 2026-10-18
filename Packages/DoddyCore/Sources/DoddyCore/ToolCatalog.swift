import Foundation

/// What one voice tool does and what it needs before it runs (DODDY Brain Phase 3b, ADR-444).
///
/// Only `effect` and `approval` are declared here, for the phone and web tools. Everything else is
/// read from the constants that already decide it, so this is not a second list to keep in step:
/// the switch from `VoiceConnection.serving`, plan use from `PlanTool.allowed`, and the online
/// account tools (with read or write) from `CloudToolName`. `ToolCatalogTests` checks all of it
/// against `voice-agent/tools.json` and the server's `CLOUD_TOOLS`, so a drift fails a test before
/// it reaches the live agent.
public struct ToolDescriptor: Equatable, Sendable {
    public enum Effect: String, Sendable, CaseIterable {
        /// Reads and answers; nothing changes anywhere.
        case lookup
        /// Changes something on this iPhone: a note, a list, Calendar, Reminders, a timer.
        case localChange
        /// Changes something in an online account, through Doddy's server.
        case accountWrite
        /// Opens another app with something filled in; the user finishes there.
        case handoff
        /// A text from Doddy's own number to the user's verified number (ADR-490 U2), through
        /// Doddy's messaging server. Never to anyone else.
        case sendText
        /// Changes the conversation itself (translator mode, the plan card).
        case session
    }

    public enum Approval: String, Sendable, CaseIterable {
        /// Runs when the agent calls it.
        case none
        /// Shows a card first; nothing happens until the user taps.
        case card
        /// A card, and the server's single-use approval for exactly the arguments shown.
        case serverApproval
    }

    public let name: String
    public let runsOn: RealtimeToolSpec.RunsOn
    public let effect: Effect
    public let approval: Approval

    public init(_ name: String, _ effect: Effect, _ approval: Approval, runsOn: RealtimeToolSpec.RunsOn = .phone) {
        self.name = name
        self.effect = effect
        self.approval = approval
        self.runsOn = runsOn
    }

    /// The Settings → Connections switch it needs; nil for tools that are always on.
    public var connection: VoiceConnection? { VoiceConnection.serving(name) }
    /// May be a step of a plan card (ADR-204). The plan card is then the approval for the step.
    public var planEligible: Bool { PlanTool.allowed.contains(name) }
    /// An online-account tool, run by Doddy's server.
    public var isCloud: Bool { CloudToolName.all.contains(name) }
}

public enum ToolCatalog {
    /// Every tool in `voice-agent/tools.json`, by name.
    public static let all: [ToolDescriptor] = phone + web + cloud

    public static func descriptor(_ name: String) -> ToolDescriptor? {
        byName[name]
    }

    private static let byName: [String: ToolDescriptor] = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    private static let phone: [ToolDescriptor] = [
        // Notes and lists (ADR-216): a note waits for the card; list items the user named go
        // straight on, with a receipt and Undo.
        .init(VoiceToolName.searchMemories, .lookup, .none),
        .init(VoiceToolName.saveMemory, .localChange, .card),
        .init(VoiceToolName.remindAboutNote, .localChange, .card),
        .init(VoiceToolName.readList, .lookup, .none),
        .init(VoiceToolName.addToList, .localChange, .none),
        .init(VoiceToolName.checkOff, .localChange, .none),
        .init(VoiceToolName.removeFromList, .localChange, .none),
        .init(VoiceToolName.createList, .localChange, .card),
        .init(VoiceToolName.addIngredients, .localChange, .card),
        // One row on this iPhone, a category only (ADR-440).
        .init(VoiceToolName.noteCapabilityGap, .localChange, .none),
        // Calendar and Reminders.
        .init(VoiceToolName.readCalendar, .lookup, .none),
        .init(VoiceToolName.findFreeTime, .lookup, .none),
        .init(VoiceToolName.createCalendarEvent, .localChange, .card),
        .init(VoiceToolName.createReminder, .localChange, .card),
        .init(VoiceToolName.changeCalendarEvent, .localChange, .card),
        .init(VoiceToolName.changeReminder, .localChange, .card),
        .init(VoiceToolName.deleteCalendarEvent, .localChange, .card),
        .init(VoiceToolName.deleteReminder, .localChange, .card),
        .init(VoiceToolName.deleteCalendarEvents, .localChange, .card),
        .init(VoiceToolName.moveReminders, .localChange, .card),
        .init(VoiceToolName.undoLast, .localChange, .card),
        // Contacts, timers and alarms, places.
        .init(VoiceToolName.lookupContact, .lookup, .none),
        .init(VoiceToolName.upcomingBirthdays, .lookup, .none),
        .init(VoiceToolName.setTimer, .localChange, .card),
        .init(VoiceToolName.setAlarm, .localChange, .card),
        .init(VoiceToolName.listAlarms, .lookup, .none),
        .init(VoiceToolName.cancelAlarm, .localChange, .card),
        // Saving a spot shows a card; "find" answers and "clear" removes the saved spot without
        // one (ADR-301). The card is the strictest of its three actions.
        .init(VoiceToolName.parkingSpot, .localChange, .card),
        .init(VoiceToolName.remindWhenToLeave, .localChange, .card),
        // Worked out on the iPhone, or the ECB's public rates file (ADR-270, ADR-300).
        .init(VoiceToolName.calculate, .lookup, .none),
        .init(VoiceToolName.convertUnits, .lookup, .none),
        .init(VoiceToolName.convertCurrency, .lookup, .none),
        // Another app opens with it filled in; nothing is sent by Doddy.
        .init(VoiceToolName.openMap, .handoff, .card),
        .init(VoiceToolName.runShortcut, .handoff, .card),
        .init(VoiceToolName.draftMessage, .handoff, .card),
        // Sent by Doddy, so the card shows the exact text and the tap approves exactly that
        // text; the server checks the same approval hash (ADR-490 U2).
        .init(VoiceToolName.textMe, .sendText, .card),
        // The conversation itself.
        .init(VoiceToolName.startTranslator, .session, .none),
        .init(VoiceToolName.stopTranslator, .session, .none),
        .init(VoiceToolName.proposePlan, .session, .card),
    ]

    /// Plain HTTPS lookups that ElevenLabs runs itself (`runs_on: web`); the app never sees them.
    private static let web: [ToolDescriptor] = ["geocode_place", "get_weather", "wikipedia_search", "wikipedia_summary"]
        .map { ToolDescriptor($0, .lookup, .none, runsOn: .web) }

    /// From `CloudToolName`: a write is an account write behind the server's approval, the rest are reads.
    private static let cloud: [ToolDescriptor] = CloudToolName.all.sorted().map { name in
        CloudToolName.isWrite(name)
            ? ToolDescriptor(name, .accountWrite, .serverApproval)
            : ToolDescriptor(name, .lookup, .none)
    }
}
