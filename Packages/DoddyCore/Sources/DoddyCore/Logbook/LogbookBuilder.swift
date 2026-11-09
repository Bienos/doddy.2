import Foundation

/// One finished voice conversation, as Logbook keeps it on the iPhone: times, how it ended, its
/// language and how Doddy was opened. Never a word of what was said.
public struct LogbookConversation: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let endedAt: Date
    /// `VoiceSessionEnd.code`: "user", "doddy", "stopped", "dropped-…". Nil when not known.
    public let ended: String?
    /// The language the conversation was set to, a short code ("pl", "en"). Nil when not known.
    public let language: String?
    public let wayIn: LogbookWayIn?

    public init(startedAt: Date, endedAt: Date, ended: String?, language: String?, wayIn: LogbookWayIn? = nil) {
        self.startedAt = startedAt
        self.endedAt = max(endedAt, startedAt)
        self.ended = ended
        self.language = language
        self.wayIn = wayIn
    }
}

/// How Doddy was opened for a conversation (decision 5 of 22 Oct: counts only).
public enum LogbookWayIn: String, Codable, CaseIterable, Sendable {
    case app
    case backTap = "back_tap"
    case actionButton = "action_button"
    case widget, siri, island
}

/// A task handed over to Doddy's server, as far as Logbook needs it.
public struct LogbookErrand: Equatable, Sendable {
    public let createdAt: Date
    public let finishedAt: Date?
    public let state: ErrandState

    public init(createdAt: Date, finishedAt: Date?, state: ErrandState) {
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.state = state
    }

    public init(_ summary: ErrandSummary) {
        self.init(createdAt: summary.createdAt, finishedAt: summary.finishedAt, state: summary.state)
    }

    /// The iPhone's own copy: a finished errand's last change is when it finished.
    public init(_ stored: StoredErrand) {
        self.init(createdAt: stored.createdAt, finishedAt: stored.state.isFinished ? stored.updatedAt : nil, state: stored.state)
    }
}

/// Everything on the iPhone a day's counts are made from. The app fills it from its own stores.
public struct LogbookSources: Sendable {
    public var conversations: [LogbookConversation]
    /// What Doddy did (`ActivityLog`), with each entry's tool and result.
    public var activity: [ActivityEntry]
    /// Every note and list record. Private notes are left out by `privateNoteIDs`, lists by type.
    public var notes: [MemoryRecord]
    /// Private notes (ADR-310): not counted at all.
    public var privateNoteIDs: Set<UUID>
    public var listItems: [ListItem]
    public var errands: [LogbookErrand]

    public init(
        conversations: [LogbookConversation] = [], activity: [ActivityEntry] = [], notes: [MemoryRecord] = [],
        privateNoteIDs: Set<UUID> = [], listItems: [ListItem] = [], errands: [LogbookErrand] = []
    ) {
        self.conversations = conversations
        self.activity = activity
        self.notes = notes
        self.privateNoteIDs = privateNoteIDs
        self.listItems = listItems
        self.errands = errands
    }
}

/// Adds up one day from the iPhone's own records. Counts only: each input is reduced to a number
/// under a fixed key before anything leaves this function.
public enum LogbookBuilder {
    /// The tool ids a day may name: Doddy's voice tools (`ToolCatalog`, the same list as
    /// `voice-agent/tools.json`, which the server checks against).
    public static let toolNames: Set<String> = Set(ToolCatalog.all.map(\.name))

    public static func day(
        _ day: String, from sources: LogbookSources, calendar: Calendar, toolNames: Set<String> = toolNames
    ) -> LogbookDay {
        var summary = LogbookDay(day: day)
        func onDay(_ date: Date?) -> Bool { date.map { LogbookCalendar.dayKey($0, calendar: calendar) == day } ?? false }

        // Conversations: on the day they started.
        for conversation in sources.conversations where onDay(conversation.startedAt) {
            var c = summary.conversations
            c.count += 1
            let seconds = Int(min(conversation.endedAt.timeIntervalSince(conversation.startedAt), 3_600).rounded())
            c.seconds = min(c.seconds + max(seconds, 0), LogbookDay.maxSeconds)
            c.byHour[calendar.component(.hour, from: conversation.startedAt)] += 1
            switch seconds {
            case ..<60: c.lengths.under1 += 1
            case ..<180: c.lengths.from1To3 += 1
            case ..<300: c.lengths.from3To5 += 1
            default: c.lengths.from5To10 += 1
            }
            switch ending(conversation.ended) {
            case .you: c.ended.you += 1
            case .doddy: c.ended.doddy += 1
            case .quiet: c.ended.quiet += 1
            case .dropped: c.ended.dropped += 1
            }
            if let code = conversation.language, LogbookCalendar.isLanguageCode(code),
               c.languages[code] != nil || c.languages.count < 12 {
                c.languages[code, default: 0] += 1
            }
            switch conversation.wayIn {
            case .app: c.waysIn.app += 1
            case .backTap: c.waysIn.backTap += 1
            case .actionButton: c.waysIn.actionButton += 1
            case .widget: c.waysIn.widget += 1
            case .siri: c.waysIn.siri += 1
            case .island: c.waysIn.island += 1
            case nil: break
            }
            summary.conversations = c
        }

        // What Doddy did, by tool and result. Entries from before tools were named (ADR-440) have none.
        for entry in sources.activity where onDay(entry.at) {
            guard let tool = entry.tool, toolNames.contains(tool) else { continue }
            var row = summary.tools[tool] ?? LogbookDay.Outcomes()
            switch entry.outcome {
            case .lookedUp, .done, .alreadyThere, .opened, .shown: row.done += 1
            case .declined: row.declined += 1
            case .notSure, .inProgress: row.unsure += 1
            case .notDone: row.failed += 1
            }
            if case .undone = entry.undoState { row.undone += 1 }
            summary.tools[tool] = row
        }

        // Notes saved that day, by how and by type; private notes and lists left out.
        for note in sources.notes where note.category != .list && !sources.privateNoteIDs.contains(note.id) {
            if onDay(note.capturedAt) {
                switch note.source {
                case .explicitVoice, .notedByDoddy, .conversationRecap: summary.notes.bySource.voice += 1
                case .explicitText: summary.notes.bySource.typed += 1
                case .sharedContent: summary.notes.bySource.shared += 1
                case .importedFile, .importedLegacyUnknown: summary.notes.bySource.imported += 1
                case .sampleFixture: continue
                }
                summary.notes.byKind[note.category.rawValue, default: 0] += 1
            }
            if note.userEdited, onDay(note.updatedAt) { summary.notes.edited += 1 }
        }

        // List items added and ticked off that day.
        for item in sources.listItems {
            if onDay(item.addedAt) {
                switch item.source {
                case .voice: summary.lists.addedVoice += 1
                case .typed: summary.lists.addedTyped += 1
                }
            }
            if onDay(item.doneAt) { summary.lists.ticked += 1 }
        }

        // Tasks handed over that day, and how those ended (so a day never has more ended than started).
        for errand in sources.errands where onDay(errand.createdAt) {
            summary.errands.handedOver += 1
            switch errand.state {
            case .done: summary.errands.finished += 1
            case .failed, .cancelled: summary.errands.stopped += 1
            case .draft, .queued, .running, .unknown: continue
            }
            if let finished = errand.finishedAt {
                summary.errands.minutes += max(0, Int((finished.timeIntervalSince(errand.createdAt) / 60).rounded()))
            }
        }

        return clamped(summary)
    }

    enum Ending { case you, doddy, quiet, dropped }

    /// How a conversation ended, as Logbook names it. "Stop listening" is the person ending it; an
    /// unknown ending is counted as theirs, the way `stop()` defaults.
    static func ending(_ code: String?) -> Ending {
        switch code {
        case "doddy": .doddy
        case "quiet": .quiet
        case let code? where code.hasPrefix("dropped"): .dropped
        default: .you
        }
    }

    /// No value above the server's limit. A real day never comes close; this keeps a broken clock
    /// or a runaway counter from getting the whole day refused.
    private static func clamped(_ day: LogbookDay) -> LogbookDay {
        var day = day
        let cap = LogbookDay.maxCount
        day.tools = day.tools.mapValues { o in
            var o = o
            o.done = min(o.done, cap); o.declined = min(o.declined, cap); o.unsure = min(o.unsure, cap)
            o.failed = min(o.failed, cap); o.undone = min(o.undone, cap)
            return o
        }
        day.notes.byKind = day.notes.byKind.mapValues { min($0, cap) }
        day.lists.addedVoice = min(day.lists.addedVoice, cap)
        day.lists.addedTyped = min(day.lists.addedTyped, cap)
        day.lists.ticked = min(day.lists.ticked, cap)
        day.errands.minutes = min(day.errands.minutes, cap)
        return day
    }
}
