import Foundation

// DODDY Brain, Phase 3c (docs/architecture/brain/04_CAPABILITY_AND_TOOL_REGISTRY.md, ADR-445): what
// each voice tool does and how it is approved, in one typed table. The table holds only the two
// facts no other registry states (effect and approval); everything else is derived from the
// existing constants, so this is not a second list of tools:
// - the connection a tool needs: `VoiceConnection.serving`
// - online-account reads and writes: `CloudToolName.all` / `.writes`
// - whether a tool may be a plan step: `PlanTool.allowed`
//
// `ToolCatalogTests` checks the table against `voice-agent/tools.json` (names, `runs_on`,
// `confirm_on_screen`) and against the server's own read/write list (`backend/src/tools/catalog.ts`),
// so a tool added or changed in one place and not the others fails CI before it reaches the agent.
// Nothing here runs or authorises a tool; the cards in the app still do that.

/// What a tool does when it runs.
public enum ToolEffect: String, Equatable, Sendable {
    /// Reads and answers; changes nothing (risk tiers L0 public, L1 private read).
    case lookup
    /// Changes something on this iPhone: a note, a list, Calendar, Reminders, a timer (L2).
    case localChange
    /// Changes something in an online account through Doddy's server (L3).
    case accountWrite
    /// Hands over to another app (Maps, Shortcuts, Messages); Doddy can't see what happens next.
    case handoff
    /// Changes how the conversation runs (translator mode), not the user's data.
    case session
}

/// How the user approves a tool before it acts.
public enum ToolApproval: String, Equatable, Sendable {
    /// Runs on the user's spoken request, with no card.
    case none
    /// A card on screen; nothing happens until the user taps.
    case card
    /// A card whose preview and single-use approval come from Doddy's server for exactly these
    /// arguments (ADR-209); the server checks the approval again when the tool runs.
    case serverApprovedCard
}

public struct ToolDescriptor: Equatable, Sendable {
    public let name: String
    public let runsOn: RealtimeToolSpec.RunsOn
    public let effect: ToolEffect
    public let approval: ToolApproval

    /// The Settings → Connections switch the tool needs, if any.
    public var connection: VoiceConnection? { VoiceConnection.serving(name) }
    /// Gmail, Drive, Notion, Todoist, Outlook or web search, through Doddy's server.
    public var isOnlineAccountTool: Bool { CloudToolName.all.contains(name) }
    public var canBePlanStep: Bool { PlanTool.allowed.contains(name) }
    /// Changes something the user would notice (data, an account, or another app opened).
    public var changesSomething: Bool { effect != .lookup && effect != .session }
}

public enum ToolCatalog {
    /// Lookups the voice provider runs itself over plain HTTPS (`runs_on: web`); the app has no
    /// Swift constant for them because it never handles them (OpenAI test voice says "not here").
    public static let webLookups: Set<String> = ["geocode_place", "get_weather", "wikipedia_search", "wikipedia_summary"]

    /// Changes that run on the user's spoken request without a card, each with the decision that
    /// allows it. A new change without a card must be added here with its ADR, or the tests fail.
    public static let changesWithoutCard: [String: String] = [
        VoiceToolName.addToList: "ADR-216 L1: the user asked; read back with a receipt and Undo",
        VoiceToolName.checkOff: "ADR-216 L1: clear matches only; receipt and Undo",
        VoiceToolName.removeFromList: "ADR-216 L1 + review C9: exact matches only; receipt and Undo",
        VoiceToolName.noteCapabilityGap: "ADR-440: one local row with a category, no user text; nothing runs",
    ]

    /// Every tool the voice agent may call, by name.
    public static let all: [String: ToolDescriptor] = {
        var table: [String: ToolDescriptor] = [:]
        func add(_ names: [String], _ effect: ToolEffect, _ approval: ToolApproval, on runsOn: RealtimeToolSpec.RunsOn = .phone) {
            for name in names {
                precondition(table[name] == nil, "duplicate tool \(name)")
                table[name] = ToolDescriptor(name: name, runsOn: runsOn, effect: effect, approval: approval)
            }
        }
        add([
            VoiceToolName.searchMemories, VoiceToolName.readCalendar, VoiceToolName.findFreeTime, VoiceToolName.lookupContact,
            VoiceToolName.upcomingBirthdays, VoiceToolName.calculate, VoiceToolName.convertUnits, VoiceToolName.convertCurrency,
            VoiceToolName.listAlarms, VoiceToolName.readList,
        ], .lookup, .none)
        add(Array(webLookups), .lookup, .none, on: .web)
        add(Array(CloudToolName.all.subtracting(CloudToolName.writes)), .lookup, .none)
        add(Array(CloudToolName.writes), .accountWrite, .serverApprovedCard)
        add([
            VoiceToolName.saveMemory, VoiceToolName.createCalendarEvent, VoiceToolName.createReminder,
            VoiceToolName.changeCalendarEvent, VoiceToolName.changeReminder, VoiceToolName.deleteCalendarEvent,
            VoiceToolName.deleteReminder, VoiceToolName.deleteCalendarEvents, VoiceToolName.moveReminders,
            VoiceToolName.remindAboutNote, VoiceToolName.remindWhenToLeave, VoiceToolName.undoLast,
            VoiceToolName.setTimer, VoiceToolName.setAlarm, VoiceToolName.cancelAlarm,
            // Save or clear shows a card; "where did I park" only reads (the card setting is per tool).
            VoiceToolName.parkingSpot,
            VoiceToolName.createList, VoiceToolName.addIngredients,
            // The plan card; each step is then checked as if asked on its own (ADR-204).
            VoiceToolName.proposePlan,
        ], .localChange, .card)
        add(Array(changesWithoutCard.keys), .localChange, .none)
        add([VoiceToolName.openMap, VoiceToolName.runShortcut, VoiceToolName.draftMessage], .handoff, .card)
        add([VoiceToolName.startTranslator], .session, .card)
        add([VoiceToolName.stopTranslator], .session, .none)
        return table
    }()

    public static func descriptor(_ name: String) -> ToolDescriptor? { all[name] }
}
