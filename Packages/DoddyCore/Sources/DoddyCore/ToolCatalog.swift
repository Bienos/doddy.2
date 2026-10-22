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
        /// Changes the conversation itself (translator mode, the plan card).
        case session
    }

    /// ASK-01 (ADR-483): every tool asks first, except the public lookups that run at once (ADR-575).
    public enum Approval: String, Sendable, CaseIterable {
        /// A public lookup that reads nothing of the user's and changes nothing (`AskFirst.publicLookups`):
        /// runs when the agent calls it (owner, 21 Oct 2026, ADR-575).
        case runsNow
        /// Changes nothing: the app shows what it will do and runs it on a tap or the user's own
        /// spoken yes (`AskFirst.Need.yesFirst`).
        case askFirst
        /// Shows a card with the exact change first; nothing happens until the user taps.
        case card
        /// A read through Doddy's server: the server's single-use approval for exactly these
        /// arguments, sent once the user said yes or tapped.
        case serverAsk
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
    /// Every tool in `voice-agent/tools.json`, by name. The `runs_on: web` tools are public
    /// lookups ElevenLabs runs itself (weather, Wikipedia). ASK-01 took them out because the app
    /// can't ask before them; since ADR-575 public lookups run at once, so they are back.
    public static let all: [ToolDescriptor] = phone + cloud + web

    /// Public lookups ElevenLabs runs on its own servers (ADR-575). With OpenAI Realtime the app
    /// answers them as not available (`OpenAISpec.webTools`).
    public static let webLookups: Set<String> = ["geocode_place", "get_weather", "wikipedia_search", "wikipedia_summary"]

    private static let web: [ToolDescriptor] = webLookups.sorted().map {
        ToolDescriptor($0, .lookup, .runsNow, runsOn: .web)
    }

    public static func descriptor(_ name: String) -> ToolDescriptor? {
        byName[name]
    }

    private static let byName: [String: ToolDescriptor] = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    private static let phone: [ToolDescriptor] = [
        // Notes and lists (ADR-216). Since ASK-01 list changes show a card too.
        .init(VoiceToolName.searchMemories, .lookup, .askFirst),
        .init(VoiceToolName.saveMemory, .localChange, .card),
        .init(VoiceToolName.remindAboutNote, .localChange, .card),
        .init(VoiceToolName.readList, .lookup, .askFirst),
        .init(VoiceToolName.addToList, .localChange, .card),
        .init(VoiceToolName.checkOff, .localChange, .card),
        .init(VoiceToolName.removeFromList, .localChange, .card),
        .init(VoiceToolName.createList, .localChange, .card),
        .init(VoiceToolName.addIngredients, .localChange, .card),
        // One row on this iPhone, a category only (ADR-440).
        .init(VoiceToolName.noteCapabilityGap, .localChange, .card),
        // Calendar and Reminders.
        .init(VoiceToolName.readCalendar, .lookup, .askFirst),
        .init(VoiceToolName.findFreeTime, .lookup, .askFirst),
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
        .init(VoiceToolName.lookupContact, .lookup, .askFirst),
        .init(VoiceToolName.upcomingBirthdays, .lookup, .askFirst),
        // Motion & Fitness, read only (ADR-568).
        .init(VoiceToolName.readSteps, .lookup, .askFirst),
        // Counts and times from the photo library; the pictures stay on screen (ADR-569).
        .init(VoiceToolName.findPhotos, .lookup, .askFirst),
        .init(VoiceToolName.setTimer, .localChange, .card),
        .init(VoiceToolName.setAlarm, .localChange, .card),
        .init(VoiceToolName.listAlarms, .lookup, .askFirst),
        .init(VoiceToolName.cancelAlarm, .localChange, .card),
        // Saving or clearing a spot shows a card; "find" asks first (ADR-301, ASK-01). The card is
        // the strictest of its three actions.
        .init(VoiceToolName.parkingSpot, .localChange, .card),
        .init(VoiceToolName.remindWhenToLeave, .localChange, .card),
        // Worked out on the iPhone, or the ECB's public rates file (ADR-270, ADR-300). Run at once (ADR-575).
        .init(VoiceToolName.calculate, .lookup, .runsNow),
        .init(VoiceToolName.convertUnits, .lookup, .runsNow),
        .init(VoiceToolName.convertCurrency, .lookup, .runsNow),
        // Another app opens with it filled in; nothing is sent by Doddy.
        .init(VoiceToolName.openMap, .handoff, .card),
        .init(VoiceToolName.runShortcut, .handoff, .card),
        .init(VoiceToolName.draftMessage, .handoff, .card),
        // A BLIK transfer on a card; the user sends it in their bank app, never Doddy (ADR-510).
        .init(VoiceToolName.draftBlikTransfer, .handoff, .card),
        // A file made on the iPhone on a tap, then the share sheet to Keynote or Files (ADR-567).
        .init(VoiceToolName.makePresentation, .handoff, .card),
        // Doddy's camera opens on the tap; a kept photo becomes a note the user saves (ADR-569).
        .init(VoiceToolName.openCamera, .handoff, .card),
        // A task handed over (ADR-570): web research on Doddy's server that changes nothing, so a
        // spoken yes or a tap starts it; one yes covers every look-up of that task.
        .init(VoiceToolName.handOverErrand, .lookup, .askFirst),
        .init(VoiceToolName.checkErrands, .lookup, .askFirst),
        // A Studio job (ADR-584): web research and files made on Doddy's server, nothing else
        // changes; a spoken yes or a tap starts it.
        .init(VoiceToolName.makeSomething, .lookup, .askFirst),
        // The conversation itself.
        .init(VoiceToolName.startTranslator, .session, .askFirst),
        .init(VoiceToolName.stopTranslator, .session, .askFirst),
        .init(VoiceToolName.proposePlan, .session, .card),
    ]

    /// From `CloudToolName`: a write is an account write behind the server's approval, the rest are reads.
    private static let cloud: [ToolDescriptor] = CloudToolName.all.sorted().map { name in
        CloudToolName.isWrite(name)
            ? ToolDescriptor(name, .accountWrite, .serverApproval)
            : ToolDescriptor(name, .lookup, AskFirst.publicLookups.contains(name) ? .runsNow : .serverAsk)
    }
}
