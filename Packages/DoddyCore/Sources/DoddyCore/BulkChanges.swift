import Foundation

// Several changes on one card (ADR-264). "Clear my Thursday afternoon" and "move all of today's
// reminders to tomorrow" become one card that lists every event or reminder it would touch, each
// with a tick (all ticked, because the user asked for all of them; any can be unticked). Only the
// ticked ones change, after one tap, and each one separately: it must still look as the card
// showed it, it changes, it is read back. The answer says how many changed and names the ones
// that didn't. A repeating event loses only the occurrence in the range. Deletes can't be undone
// from Doddy, and the card says so.

extension VoiceToolName {
    public static let deleteCalendarEvents = "delete_calendar_events"
    public static let moveReminders = "move_reminders"
}

/// One item on a several-changes card.
public enum BulkItem: Equatable, Sendable, Identifiable {
    case deleteEvent(CalendarEventSummary)
    /// The reminder as read, and its new due (same time, another day).
    case moveReminder(ReminderSnapshot, to: ReminderDue)

    public var id: String {
        switch self {
        case .deleteEvent(let event): "event:\(event.id ?? event.title)@\(event.start.timeIntervalSince1970)"
        case .moveReminder(let reminder, _): "reminder:\(reminder.id)"
        }
    }

    public var title: String {
        switch self {
        case .deleteEvent(let event): event.title
        case .moveReminder(let reminder, _): reminder.title
        }
    }
}

/// What happened to one ticked item, from the read-back.
public enum BulkResult: Equatable, Sendable {
    case done
    /// It changed elsewhere since the card was shown; nothing was written.
    case changedElsewhere
    /// Written, but the read-back didn't show it.
    case unconfirmed
    case failed
}

public enum BulkChange {
    /// At most this many items on one card; more are named in the answer, not changed.
    public static let maxItems = 20
    /// The longest range one "clear" may cover.
    public static let maxRangeDays = 31

    /// Events that start in the range, in time order. Events that started earlier and run into
    /// it are left alone: the user named a time, not everything that overlaps it.
    public static func eventsToDelete(_ events: [CalendarEventSummary], in range: VoiceTimeRange) -> [CalendarEventSummary] {
        events.filter { $0.start >= range.start && $0.start < range.end }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// Open reminders due on `dueBy`'s day or earlier, each moved to `to`'s day at its own time
    /// (a day-only reminder stays day-only). A time the clocks skip or repeat that day is left
    /// out and counted, not guessed.
    public static func remindersToMove(
        _ reminders: [ReminderSnapshot], dueBy: ReminderDue, to: ReminderDue, local: Calendar
    ) -> (moves: [BulkItem], skipped: [String]) {
        let limit = key(dueBy)
        var moves: [BulkItem] = [], skipped: [String] = []
        let due = reminders.filter { reminder in
            guard !reminder.isCompleted, let date = reminder.due else { return false }
            return key(date) <= limit && key(date) != key(to)
        }
        .sorted { lhs, rhs in
            let a = lhs.due.flatMap { EventChange.moment($0, local: local) } ?? .distantPast
            let b = rhs.due.flatMap { EventChange.moment($0, local: local) } ?? .distantPast
            return a != b ? a < b : lhs.title < rhs.title
        }
        for reminder in due {
            guard let old = reminder.due else { continue }
            if let moved = moved(old, to: to, local: local) {
                moves.append(.moveReminder(reminder, to: moved))
            } else {
                skipped.append(reminder.title)
            }
        }
        return (moves, skipped)
    }

    /// `due`'s time on `to`'s day; nil when that time doesn't exist that day or happens twice.
    static func moved(_ due: ReminderDue, to day: ReminderDue, local: Calendar) -> ReminderDue? {
        guard let hour = due.hour else {
            return ReminderDue(year: day.year, month: day.month, day: day.day, timeZoneID: due.timeZoneID)
        }
        var zoned = ReminderDueRules.gregorian(local)
        if let zone = due.timeZoneID.flatMap(TimeZone.init(identifier:)) { zoned.timeZone = zone }
        let text = String(format: "%04d-%02d-%02dT%02d:%02d", day.year, day.month, day.day, hour, due.minute ?? 0)
        guard case .due(let result) = ReminderDueRules.wallClock(text, calendar: zoned) else { return nil }
        return result
    }

    private static func key(_ due: ReminderDue) -> Int { due.year * 10_000 + due.month * 100 + due.day }
}

extension VoiceToolRequest {
    /// from and to: local times (or days), to after from, at most `BulkChange.maxRangeDays` apart.
    static func parseDeleteEvents(_ args: Arguments, name: String, calendar: Calendar) -> VoiceToolRequest {
        guard let fromText = args.text("from"), let toText = args.text("to") else {
            return .invalid(name: name, reason: "give from and to")
        }
        guard case .due(let from) = ReminderDueRules.wallClock(fromText, calendar: calendar), let start = from.date(in: calendar),
              case .due(let to) = ReminderDueRules.wallClock(toText, calendar: calendar), var end = to.date(in: calendar) else {
            return .invalid(name: name, reason: "from and to must be YYYY-MM-DD or YYYY-MM-DDTHH:MM")
        }
        // A day alone as "to" means the whole of that day.
        if !to.hasTime { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
        guard end > start else { return .invalid(name: name, reason: "to must be after from") }
        guard end.timeIntervalSince(start) <= Double(BulkChange.maxRangeDays) * 86_400 else {
            return .invalid(name: name, reason: "the range can be at most \(BulkChange.maxRangeDays) days")
        }
        return .deleteCalendarEvents(VoiceTimeRange(start: start, end: end))
    }

    /// due_by and to: days (YYYY-MM-DD). `to` must be today or later.
    static func parseMoveReminders(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        guard let byText = args.text("due_by"), let toText = args.text("to") else {
            return .invalid(name: name, reason: "give due_by and to")
        }
        guard case .due(let dueBy) = ReminderDueRules.wallClock(byText, calendar: calendar), !dueBy.hasTime else {
            return .invalid(name: name, reason: "due_by is a day, YYYY-MM-DD")
        }
        switch ReminderDueRules.check(toText, now: now, calendar: calendar) {
        case .clarify(let clarification): return .needsClarification(name: name, clarification)
        case .due(let to):
            guard !to.hasTime else { return .invalid(name: name, reason: "to is a day, YYYY-MM-DD; each reminder keeps its time") }
            return .moveReminders(dueBy: dueBy, to: to)
        }
    }
}

extension VoiceToolReply {
    public static let bulkNothing = "not changed: nothing matched, so nothing changed. Tell the user."

    public static func bulkTooMany(_ count: Int) -> String {
        "not changed: \(count) items match, more than the \(BulkChange.maxItems) one card can hold. Nothing changed. Ask the user for a shorter time range."
    }

    public static let bulkDeclined = "declined: the user chose not to make these changes. Nothing changed."

    /// One line for the agent. It starts with the verb ("deleted", "moved") only when every
    /// ticked item changed and read back; "partly …" when some did; "unknown" or "failed" when
    /// none did. The ones that didn't change are named, with why.
    public static func bulkResult(_ results: [(BulkItem, BulkResult)], verb: String, skipped: [String] = []) -> String {
        let done = results.filter { $0.1 == .done }.count
        let head: String
        if done == results.count {
            head = "\(verb): all \(done) of the ticked items, each checked."
        } else if done > 0 {
            head = "partly \(verb): \(done) of \(results.count), each checked."
        } else if results.contains(where: { $0.1 == .unconfirmed }) {
            head = "unknown: none could be confirmed."
        } else {
            head = "failed: none changed."
        }
        var parts = [head]
        func names(_ result: BulkResult) -> String {
            results.filter { $0.1 == result }.map { "\"\($0.0.title)\"" }.joined(separator: ", ")
        }
        if results.contains(where: { $0.1 == .changedElsewhere }) {
            parts.append("Not changed because they changed in the meantime: \(names(.changedElsewhere)).")
        }
        if results.contains(where: { $0.1 == .unconfirmed }) { parts.append("Not confirmed, ask the user to check: \(names(.unconfirmed)).") }
        if results.contains(where: { $0.1 == .failed }) { parts.append("Failed: \(names(.failed)).") }
        if !skipped.isEmpty {
            parts.append("Left as they were (that time doesn't exist that day): \(skipped.map { "\"\($0)\"" }.joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }
}
