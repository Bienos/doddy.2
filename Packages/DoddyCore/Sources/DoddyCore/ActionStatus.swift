import Foundation

// Action status model (OP-012 / OP-013, ADR-319). Every change Doddy makes in another app has:
//  - a typed status, where only `confirmed` counts as success, and only from the app's own read-back;
//  - a receipt: what the app read back, and its own identifier for it;
//  - a history of how the status moved (approved → running → not sure → checked: found);
//  - a retry rule: an unconfirmed try is checked before anything is repeated, and after
//    `ActionRetry.maxAttempts` tries without a confirmed result Doddy stops and the user looks.
// Plain Swift, so the Linux tests run it. The iPhone side records it in `ActivityLogStore`.

/// Where a change stands.
public enum ActionStatus: String, Codable, CaseIterable, Sendable {
    /// Shown on a card; the user hasn't answered.
    case proposed
    /// The user approved it and it is running.
    case pending
    /// The app read it back and it matches, or it was already there.
    case confirmed
    /// It did not happen.
    case failed
    /// It may or may not have happened. Never success, and never repeated without a check first.
    case unknown
    case declined
    /// Another app was opened; Doddy can't see what happened there.
    case handedOff

    /// No later status: only a new try (a new entry) can follow.
    public var isFinal: Bool {
        switch self {
        case .confirmed, .failed, .declined, .handedOff: true
        case .proposed, .pending, .unknown: false
        }
    }

    /// The moves the model allows. `unknown` leaves only through a check of the app itself;
    /// nothing leaves `confirmed`, `failed`, `declined` or `handedOff`.
    public func canMove(to next: ActionStatus) -> Bool {
        switch (self, next) {
        case (.proposed, .pending), (.proposed, .declined), (.proposed, .failed): true
        case (.pending, .confirmed), (.pending, .failed), (.pending, .unknown), (.pending, .handedOff): true
        case (.unknown, .confirmed), (.unknown, .failed): true
        default: false
        }
    }

    public var text: String {
        switch self {
        case .proposed: "Waiting for you"
        case .pending: "In progress"
        case .confirmed: "Confirmed"
        case .failed: "Didn't happen"
        case .unknown: "Not sure it happened"
        case .declined: "You said no"
        case .handedOff: "Opened another app"
        }
    }
}

extension ActivityOutcome {
    /// Nil for look-ups: nothing was changed, so there is no action to track.
    public var status: ActionStatus? {
        switch self {
        // A BLIK transfer card (ADR-483): Doddy did nothing to track; the user sends it in their bank app.
        case .lookedUp, .shown: nil
        case .done, .alreadyThere: .confirmed
        case .opened: .handedOff
        case .notSure: .unknown
        case .notDone: .failed
        case .declined: .declined
        case .inProgress: .pending
        }
    }
}

/// What the app read back after a change it confirmed. Kept on this iPhone with the entry;
/// `externalID` is the app's own identifier (EventKit's) and is never sent to the voice agent.
public struct ActivityReceipt: Codable, Equatable, Sendable {
    public let app: ActivityApp
    public let externalID: String?
    /// One fact per line, as read back: "“Buy milk”", "Mon 12 Oct 2026, 18:00 (Europe/Warsaw)", "List: Home".
    public let lines: [String]
    public let readAt: Date

    public init(app: ActivityApp, externalID: String?, lines: [String], readAt: Date) {
        self.app = app
        self.externalID = externalID
        self.lines = lines
        self.readAt = readAt
    }

    /// From a reminder as read back (added, or found already there).
    public init(reminder: ReminderReceipt, readAt: Date) {
        self.init(
            app: .reminders, externalID: reminder.id,
            lines: ["“\(reminder.title)”", ReminderText.due(reminder.due), "List: \(reminder.listTitle)"]
                + (reminder.repeats.map { ["Repeats \($0.text)"] } ?? []),
            readAt: readAt)
    }

    /// From an event as read back (added, or found already there).
    public init(event: CalendarEventSummary, calendar: Calendar, readAt: Date) {
        let when = event.allDay
            ? "\(VoiceToolReply.localText(event.start, hasTime: false, calendar: calendar)), all day"
            : "\(VoiceToolReply.localText(event.start, hasTime: true, calendar: calendar)) to \(VoiceToolReply.localText(event.end, hasTime: true, calendar: calendar))"
        self.init(app: .calendar, externalID: event.id, lines: ["“\(event.title)”", when], readAt: readAt)
    }
}

/// One step in an entry's status history.
public struct ActivityStatusChange: Codable, Equatable, Sendable {
    public let status: ActionStatus
    public let at: Date
    /// How Doddy knows, when it isn't the reply itself: "Checked in Reminders: found."
    public let note: String?

    public init(status: ActionStatus, at: Date, note: String? = nil) {
        self.status = status
        self.at = at
        self.note = note
    }
}

// MARK: Retry

/// What an earlier try of the same change means for a new one. The card is still shown and the
/// user still taps; this only decides whether Doddy may go ahead and what it must say.
public enum ActionRetryDecision: Equatable, Sendable {
    /// No earlier try is open.
    case go
    /// An earlier try is unconfirmed (or was cut off). Doddy looks in the app before writing,
    /// so a second copy is never added; the reply says it checked.
    case checkFirst(since: Date)
    /// `count` tries in the last day without a confirmed result. Doddy stops; the user looks.
    case stop(count: Int)
}

public enum ActionRetry {
    /// Tries of one change in `window` that can end without a confirmed result before Doddy stops.
    public static let maxAttempts = 3
    public static let window: TimeInterval = 86_400

    /// Looks at the log for earlier tries of the change with this key. A confirmed try ends the
    /// story: tries before it don't count (the app decides at the tap whether it is still there).
    /// Only tries where the app was actually asked to write count; a clarification, a switched-off
    /// connection or a "no" never wrote anything.
    /// `go` for requests without an operation key (they aren't tracked across tries).
    public static func decide(for request: ActivityRequest?, in entries: [ActivityEntry], now: Date) -> ActionRetryDecision {
        guard let key = request?.operationKey else { return .go }
        return decide(key: key, in: entries, now: now)
    }

    public static func decide(key: String, in entries: [ActivityEntry], now: Date) -> ActionRetryDecision {
        let cutoff = now.addingTimeInterval(-window)
        let tries = entries
            .filter { $0.operationKey == key && $0.at >= cutoff }
            .sorted { $0.at > $1.at }
        let open = tries.prefix { $0.status != .confirmed }
        let unconfirmed = open.filter { entry in
            switch entry.status {
            case .pending: true
            case .unknown, .failed: entry.attempted == true
            default: false
            }
        }
        if unconfirmed.count >= maxAttempts { return .stop(count: unconfirmed.count) }
        if let newest = open.first(where: { $0.status == .unknown || $0.status == .pending }) {
            return .checkFirst(since: newest.at)
        }
        return .go
    }
}

extension VoiceToolReply {
    /// Sent instead of a card when `ActionRetry` says stop. Starts with "failed" so the current
    /// agent prompt already handles it.
    public static func retryStopped(count: Int, app: ActivityApp) -> String {
        "failed: Doddy has tried this \(count) times in the last day without a confirmed result, so it did not try again. Ask the user to look in \(app.title) themselves; it may already be there. Nothing was added."
    }

    /// Added after a confirmed result when an earlier try was unconfirmed: the user hears that Doddy
    /// checked first instead of repeating blindly.
    public static func checkedFirst(_ reply: String, app: ActivityApp) -> String {
        "\(reply) Doddy checked \(app.title) first because an earlier try wasn't confirmed."
    }

    /// The change may or may not have gone through, and asking again is safe: Doddy looks in the
    /// app before it writes, so it never adds a second copy.
    public static func unconfirmedLooksFirst(app: ActivityApp, tool: String) -> String {
        "unknown: the app could not confirm it was added to \(app.title). It may not have gone through. Tell the user. If they ask to try again, call \(tool) again: Doddy checks \(app.title) first and will not add a second copy."
    }
}

// MARK: Calendar events: look before writing (OP-013)

public enum EventIdempotency {
    /// Same title (normalized), start, end and all-day: the same event. Stable across runs.
    public static func key(_ draft: CalendarEventDraft) -> String {
        let source = [
            ReminderIdempotency.normalizedTitle(draft.title),
            String(Int(draft.start.timeIntervalSince1970.rounded())),
            String(Int(draft.end.timeIntervalSince1970.rounded())),
            draft.allDay ? "all-day" : "timed",
        ].joined(separator: "\u{1F}")
        return "e1-" + ReminderIdempotency.fnv(source)
    }
}

/// The iPhone's Calendar, as adding one event needs it. `DeviceConnections` implements it with
/// EventKit; the tests use a fake.
@MainActor
public protocol CalendarEventWriter: AnyObject {
    /// Events overlapping the range, in every calendar.
    func events(in range: VoiceTimeRange) -> [CalendarEventSummary]
    /// Saves one event in the default calendar and returns it as read back with Calendar's identifier
    /// for it (which Undo uses, ADR-268), or nil when the read-back doesn't show what was written
    /// (its repeat included). A throw does not prove nothing was written.
    func saveEvent(_ draft: CalendarEventDraft) throws -> (event: CalendarEventSummary, eventID: String)?
}

public enum EventMatching {
    /// The event that already is this one: same title (normalized), same all-day, and the same
    /// start and end (for all-day, the same first day).
    public static func existing(for draft: CalendarEventDraft, in events: [CalendarEventSummary], calendar: Calendar) -> CalendarEventSummary? {
        let title = ReminderIdempotency.normalizedTitle(draft.title)
        return events.first { event in
            ReminderIdempotency.normalizedTitle(event.title) == title && same(event, draft, calendar: calendar)
        }
    }

    /// The read-back shows what was written: exact title, all-day, start and end.
    public static func confirms(_ back: CalendarEventSummary, _ draft: CalendarEventDraft, calendar: Calendar) -> Bool {
        back.title == draft.title && same(back, draft, calendar: calendar)
    }

    private static func same(_ event: CalendarEventSummary, _ draft: CalendarEventDraft, calendar: Calendar) -> Bool {
        guard event.allDay == draft.allDay else { return false }
        if draft.allDay { return calendar.isDate(event.start, inSameDayAs: draft.start) }
        return abs(event.start.timeIntervalSince(draft.start)) < 1 && abs(event.end.timeIntervalSince(draft.end)) < 1
    }

    /// Where to look: the event's own span, a minute either side (whole days for all-day).
    static func searchRange(_ draft: CalendarEventDraft, calendar: Calendar) -> VoiceTimeRange {
        guard draft.allDay else {
            return VoiceTimeRange(start: draft.start.addingTimeInterval(-60), end: draft.end.addingTimeInterval(60))
        }
        let day = calendar.startOfDay(for: draft.start)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(draft.end, draft.start))) ?? day.addingTimeInterval(86_400)
        return VoiceTimeRange(start: day, end: end)
    }
}

public enum EventAddOutcome: Equatable, Sendable {
    /// `eventID` is Calendar's identifier when the save itself returned it; nil when the event was
    /// found by a fresh look after a failed save (then Undo isn't offered).
    case added(CalendarEventSummary, eventID: String?)
    /// The same event was already there (an earlier tap or an unconfirmed try); nothing was written.
    case alreadyThere(CalendarEventSummary)
    /// Not written: the save failed and a fresh look shows it isn't there.
    case notAdded(String)
    /// Saved, or maybe saved, but the read-back didn't show it.
    case unknown
    case needsClarification(ReminderClarification)

    /// The app was asked to write. False when Doddy stopped first (found it, or the time passed).
    public var attemptedWrite: Bool {
        switch self {
        case .added, .notAdded, .unknown: true
        case .alreadyThere, .needsClarification: false
        }
    }
}

public enum EventAddAction {
    /// Runs after the user tapped Add. Looks first, so asking again after an unconfirmed try never
    /// makes a second copy, and says "added" only from what it read back.
    @MainActor
    public static func add(_ draft: CalendarEventDraft, to writer: some CalendarEventWriter, now: Date, calendar: Calendar) -> EventAddOutcome {
        // The start may have passed while the card waited (ADR-128).
        if let late = draft.passed(now: now, calendar: calendar) { return .needsClarification(late) }
        let range = EventMatching.searchRange(draft, calendar: calendar)

        // 1. Look first.
        if let same = EventMatching.existing(for: draft, in: writer.events(in: range), calendar: calendar) {
            return .alreadyThere(same)
        }

        // 2. Write.
        let saved: (event: CalendarEventSummary, eventID: String)?
        do {
            saved = try writer.saveEvent(draft)
        } catch {
            // 3a. The save failed, but it may still have gone through: look again before answering.
            guard let found = EventMatching.existing(for: draft, in: writer.events(in: range), calendar: calendar) else {
                return .notAdded(message(for: error))
            }
            // A repeat can't be seen in a summary, so a repeating event found this way stays unsure.
            guard draft.repeats == nil, EventMatching.confirms(found, draft, calendar: calendar) else { return .unknown }
            return .added(found, eventID: nil)
        }

        // 3b. The read-back must match what the card showed.
        guard let saved, EventMatching.confirms(saved.event, draft, calendar: calendar) else { return .unknown }
        return .added(saved.event, eventID: saved.eventID)
    }

    private static func message(for error: Error) -> String {
        if let described = (error as? LocalizedError)?.errorDescription, !described.isEmpty { return described }
        return "Calendar couldn't save it."
    }
}

extension VoiceToolReply {
    /// The agent's copy of an event add. Times come from the read-back, which matched the card.
    public static func event(_ outcome: EventAddOutcome, draft: CalendarEventDraft, calendar: Calendar) -> String {
        switch outcome {
        case .added:
            return eventAdded(draft, calendar: calendar)
        case .alreadyThere(let event):
            let when = event.allDay
                ? "on \(localText(event.start, hasTime: false, calendar: calendar)) (all day)"
                : "on \(localText(event.start, hasTime: true, calendar: calendar))"
            // The title is the calendar's words, so it follows as data (ADR-381); Doddy's own
            // sentence ends the reply, which is what "What Doddy did" reads.
            return "added: an event \(when). Its title:\n" + ToolData.block([quoted("Title", event.title)])
                + "\nThat event was already in Calendar, so Doddy did not add it a second time."
        case .notAdded(let reason):
            return notAdded(reason)
        case .unknown:
            return unconfirmedLooksFirst(app: .calendar, tool: VoiceToolName.createCalendarEvent)
        case .needsClarification(let question):
            return self.clarification(question, tool: VoiceToolName.createCalendarEvent)
        }
    }
}

extension ReminderOutcome {
    /// The app was asked to write. False when Doddy stopped first (not allowed, couldn't look,
    /// found it already there, or the time passed).
    public var attemptedWrite: Bool {
        switch self {
        case .added, .unknown, .notAdded(.saveFailed): true
        case .alreadyThere, .notAdded(.notAllowed), .notAdded(.couldNotCheck), .needsClarification: false
        }
    }
}
