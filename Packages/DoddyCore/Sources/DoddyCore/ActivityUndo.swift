import Foundation

// Undo in "What Doddy did" (ADR-255). For a day after Doddy added or changed an event or a
// reminder, its row offers Undo. Undo only ever reverses what Doddy itself did:
//  - an event or reminder Doddy added is removed, and only if it still looks exactly as Doddy
//    left it (same title and time; a reminder still open and carrying Doddy's marker);
//  - an event Doddy moved or renamed goes back to how it was, only if it still looks as Doddy left it;
//  - a reminder Doddy re-timed gets its old due back, and one Doddy ticked off is opened again.
// Anything changed since, by the user or another app, is left alone and the row says so. The user
// confirms on a sheet that names exactly what will happen. Afterwards Calendar or Reminders is read
// back; "Undone" is shown only when the read-back agrees, otherwise "not sure". Nothing here runs
// from the voice agent: Undo is a button the user taps.

/// What Doddy needs to put things back. Kept with the activity entry on this iPhone only.
public enum ActivityUndo: Codable, Equatable, Sendable {
    /// `eventID` is the event's identifier on this iPhone, read back right after Doddy saved it.
    case addedEvent(eventID: String, event: CalendarEventSummary)
    /// Found again by Doddy's marker key, among open reminders only.
    case addedReminder(key: String, title: String, due: ReminderDue?)
    case changedEvent(EventChangePlan)
    /// `oldDue` is the due before Doddy's change. `markedDone` is true when Doddy ticked it off
    /// (then the due was not changed).
    case changedReminder(id: String, title: String, oldDue: ReminderDue?, newDue: ReminderDue?, markedDone: Bool)

    /// Undo is offered for this long after the change.
    public static let window: TimeInterval = 24 * 3_600

    public var app: ActivityApp {
        switch self {
        case .addedEvent, .changedEvent: .calendar
        case .addedReminder, .changedReminder: .reminders
        }
    }

    /// The switch in Settings, Connections that Undo needs, like the change it reverses.
    public var connection: VoiceConnection {
        switch self {
        case .addedEvent, .changedEvent: .calendar
        case .addedReminder, .changedReminder: .reminders
        }
    }

    /// Why Undo can't run now, checked at the tap before anything is read or written. Nil when it can.
    public func blocked(pauseAll: Bool, connectionOn: Bool) -> String? {
        if pauseAll { return "Connections are paused in Settings." }
        if !connectionOn { return "\(connection.title) is off in Settings, Connections." }
        return nil
    }

    /// The question on the confirmation sheet.
    public var question: String {
        switch self {
        case .addedEvent(_, let event): "Remove “\(event.title)” from Calendar?"
        case .addedReminder(_, let title, _): "Remove “\(title)” from Reminders?"
        case .changedEvent(let plan): "Put “\(plan.before.title)” back?"
        case .changedReminder(_, let title, _, _, let markedDone):
            markedDone ? "Mark “\(title)” not done?" : "Put back the due of “\(title)”?"
        }
    }

    /// Exactly what will happen, shown under the question.
    public func explanation(calendar: Calendar) -> String {
        switch self {
        case .addedEvent(_, let event):
            return "Doddy added this event for \(Self.when(event, calendar: calendar)). Only this event is removed, and only if it hasn't changed since."
        case .addedReminder(_, _, let due):
            return "Doddy added this reminder (due: \(ReminderText.due(due))). Only this reminder is removed, and only if it is still open and hasn't changed since."
        case .changedEvent(let plan):
            let rename = plan.before.title != plan.after.title ? " and its name goes back from “\(plan.after.title)”" : ""
            return "It moves back to \(Self.when(plan.before, calendar: calendar)) from \(Self.when(plan.after, calendar: calendar))\(rename). Only if it hasn't changed since."
        case .changedReminder(_, _, let oldDue, let newDue, let markedDone):
            if markedDone { return "Doddy marked it done. It becomes an open reminder again, only if nothing else changed it since." }
            return "Due goes back to \(ReminderText.due(oldDue)) from \(ReminderText.due(newDue)). Only if it hasn't changed since."
        }
    }

    /// The confirming button.
    public var buttonTitle: String {
        switch self {
        case .addedEvent, .addedReminder: "Remove"
        case .changedEvent: "Put back"
        case .changedReminder(_, _, _, _, let markedDone): markedDone ? "Mark not done" : "Put back"
        }
    }

    /// Undo for a reminder Doddy just added: only when Doddy wrote it and read it back, never
    /// when it was already there (then it is the user's) or Doddy isn't sure.
    public static func addedReminder(_ outcome: ReminderOutcome, draft: ReminderDraft) -> ActivityUndo? {
        guard case .added = outcome else { return nil }
        return .addedReminder(key: ReminderWrite(draft).key, title: draft.title, due: draft.due)
    }

    /// The plan that moves an event back. The event is found by its current occurrence (Doddy's
    /// "after"), which must still look exactly like that; it then becomes Doddy's "before".
    public static func reversed(_ plan: EventChangePlan) -> EventChangePlan {
        let item = plan.before.id.flatMap(CalendarEventSummary.itemID(fromOccurrence:))
        let now = CalendarEventSummary(
            id: item.map { CalendarEventSummary.occurrenceID(itemID: $0, start: plan.after.start) },
            title: plan.after.title, start: plan.after.start, end: plan.after.end, allDay: plan.after.allDay)
        let back = CalendarEventSummary(
            id: plan.before.id, title: plan.before.title, start: plan.before.start, end: plan.before.end, allDay: plan.before.allDay)
        return EventChangePlan(before: now, after: back)
    }

    /// An event Doddy added still looks exactly as Doddy left it (title, times, all-day).
    public static func unchanged(_ found: CalendarEventSummary, since added: CalendarEventSummary) -> Bool {
        found.title == added.title && found.start == added.start && found.end == added.end && found.allDay == added.allDay
    }

    /// A reminder Doddy added is still open, still carries Doddy's marker, and has the same title and due.
    public static func unchanged(_ found: ReminderSnapshot, key: String, title: String, due: ReminderDue?) -> Bool {
        !found.isCompleted && ReminderIdempotency.key(fromMarker: found.markerURL) == key
            && found.title == title && EventChange.sameDue(found.due, due)
    }

    /// The one open reminder carrying Doddy's marker for `key`. Nil when there is none or several.
    public static func addedReminder(key: String, in reminders: [ReminderSnapshot]) -> ReminderSnapshot? {
        let found = reminders.filter { !$0.isCompleted && ReminderIdempotency.key(fromMarker: $0.markerURL) == key }
        return found.count == 1 ? found[0] : nil
    }

    /// A reminder Doddy changed still looks exactly as Doddy left it.
    public static func unchangedSinceChange(_ found: ReminderSnapshot, title: String, newDue: ReminderDue?, oldDue: ReminderDue?, markedDone: Bool) -> Bool {
        guard found.title == title else { return false }
        if markedDone { return found.isCompleted && EventChange.sameDue(found.due, oldDue) }
        return !found.isCompleted && EventChange.sameDue(found.due, newDue)
    }

    private static func when(_ event: CalendarEventSummary, calendar: Calendar) -> String {
        event.allDay
            ? "\(VoiceToolReply.localText(event.start, hasTime: false, calendar: calendar)) (all day)"
            : VoiceToolReply.localText(event.start, hasTime: true, calendar: calendar)
    }
}

/// What happened when the user tapped Undo.
public enum UndoResult: Equatable, Sendable {
    /// Reversed, and the read-back agrees.
    case undone
    /// It no longer looks as Doddy left it. Nothing was written.
    case leftAlone
    /// Nothing was written (no permission, the switch is off, Pause all, or the write failed and a
    /// fresh look shows it unchanged). The user can try again.
    case notDone(String)
    /// Written, or maybe written, but the read-back didn't agree. Not offered again.
    case notSure
}

/// Recorded on the entry after the user tapped Undo.
public enum UndoState: Codable, Equatable, Sendable {
    case undone(Date)
    case leftAlone(Date)
    case notDone(Date)
    case notSure(Date)

    public var at: Date {
        switch self {
        case .undone(let date), .leftAlone(let date), .notDone(let date), .notSure(let date): date
        }
    }
}

extension CalendarEventSummary {
    /// One id per occurrence: repeating events share one item identifier, so the start time is
    /// added. The iPhone's `DeviceConnections` builds every id with this, so they always agree.
    public static func occurrenceID(itemID: String, start: Date) -> String {
        "\(itemID)@\(Int(start.timeIntervalSince1970))"
    }

    /// The item identifier inside an occurrence id. Nil when the id isn't one.
    public static func itemID(fromOccurrence id: String) -> String? {
        guard let at = id.lastIndex(of: "@"), at != id.startIndex,
              Int(id[id.index(after: at)...]) != nil else { return nil }
        return String(id[..<at])
    }
}

extension ActivityEntry {
    /// The row offers Undo: Doddy did it and checked, it can be put back, the user hasn't
    /// already undone it (or Doddy isn't unsure about an earlier try), and it was within a day.
    public func canUndo(now: Date) -> Bool {
        guard outcome == .done, undo != nil else { return false }
        switch undoState {
        case nil, .notDone?: break
        case .undone?, .leftAlone?, .notSure?: return false
        }
        let age = now.timeIntervalSince(at)
        return age >= 0 && age < ActivityUndo.window
    }

    /// "Calendar · Done", or "Calendar · Undone" once the user has undone it.
    public var statusText: String {
        if case .undone? = undoState { return "\(app.title) · Undone" }
        return "\(app.title) · \(outcome.text)"
    }
}

extension ActivityLog {
    /// The entry after the user tapped Undo. "Undone" only when the read-back agreed.
    public static func undid(_ entry: ActivityEntry, result: UndoResult, at date: Date) -> ActivityEntry {
        var updated = entry
        let where_ = entry.app.title
        switch result {
        case .undone:
            updated.undoState = .undone(date)
            updated.note = "You undid this. Checked in \(where_)."
        case .leftAlone:
            updated.undoState = .leftAlone(date)
            updated.note = "Not undone: it changed in \(where_) since Doddy did this, so Doddy left it alone."
        case .notDone(let reason):
            updated.undoState = .notDone(date)
            updated.note = "Not undone: \(reason) Nothing changed."
        case .notSure:
            updated.undoState = .notSure(date)
            updated.note = "Doddy couldn't confirm the undo. Check \(where_) before trying again."
        }
        return updated
    }
}

// MARK: "Undo that" by voice (ADR-258)

extension VoiceToolName {
    public static let undoLast = "undo_last"
}

extension ActivityUndo {
    /// The newest change from this conversation that can still be undone. Never one from an
    /// earlier conversation: "undo that" means what was just done.
    public static func latest(in entries: [ActivityEntry], since start: Date, now: Date) -> ActivityEntry? {
        entries.filter { $0.at >= start && $0.canUndo(now: now) }.max { $0.at < $1.at }
    }
}

extension VoiceToolReply {
    public static let nothingToUndo = "nothing to undo: Doddy hasn't added or changed anything in Calendar or Reminders in this conversation that can still be undone. Nothing changed. Older changes can be undone in Settings, What Doddy did."
    public static let undoDeclined = "declined: the user chose to keep it. Nothing changed."

    /// What the agent hears after the user tapped the undo card. "undone" only after the read-back.
    public static func undo(_ result: UndoResult, _ undo: ActivityUndo) -> String {
        let place = undo.app.title
        switch result {
        case .undone:
            switch undo {
            case .addedEvent(_, let event): return "undone: \"\(event.title)\" was removed from Calendar. Checked."
            case .addedReminder(_, let title, _): return "undone: \"\(title)\" was removed from Reminders. Checked."
            case .changedEvent(let plan): return "undone: \"\(plan.before.title)\" is back as it was. Checked in Calendar."
            case .changedReminder(_, let title, _, _, let markedDone):
                return markedDone
                    ? "undone: \"\(title)\" is open again in Reminders. Checked."
                    : "undone: \"\(title)\" has its old due back. Checked in Reminders."
            }
        case .leftAlone:
            return "not undone: it changed in \(place) since Doddy did it, so Doddy left it alone. Nothing changed."
        case .notDone(let reason):
            return "failed: not undone. \(reason) Nothing changed."
        case .notSure:
            return "unknown: Doddy couldn't confirm the undo. Ask the user to check \(place) before trying again."
        }
    }
}

