import Foundation

// Today's own add and edit (owner, 13 Nov 2026: "Dzisiaj — fajne te przypomnienia, ale zero edycji"):
// a reminder typed on the Today screen goes to the default Reminders list, and one tapped there can get a
// new title, day and time, and notes, or be deleted. These are the rules with no screen in them. The iPhone
// side is `TodayModel` and `DeviceConnections.editReminder`; adding goes through `ReminderAction.add`, which
// looks first and reads back like every other reminder Doddy adds.

/// What the Today screen's reminder sheet checks before anything is written.
public enum ReminderForm {
    public enum TitleCheck: Equatable, Sendable {
        /// The title as it will be saved.
        case ok(String)
        case empty
        case tooLong
    }

    public enum NotesCheck: Equatable, Sendable {
        /// The notes as they will be saved; nil for none.
        case ok(String?)
        case tooLong
    }

    /// Spaces at the ends are dropped and line breaks become spaces; nothing else is changed.
    public static func checkTitle(_ raw: String) -> TitleCheck {
        let oneLine = raw.split(whereSeparator: \.isNewline).joined(separator: " ")
        let trimmed = oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard trimmed.count <= ReminderDetails.maxTitleLength else { return .tooLong }
        return .ok(trimmed)
    }

    /// Notes left exactly as they were read stay exactly so (no write just for trimming them); otherwise
    /// spaces at the ends are dropped, and empty means no notes.
    public static func checkNotes(_ raw: String, original: String?) -> NotesCheck {
        if raw == (original ?? "") { return .ok(original) }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= ReminderDetails.maxReplacedNotesLength else { return .tooLong }
        return .ok(trimmed.isEmpty ? nil : trimmed)
    }

    /// The due for a day picked on screen, with its time or without: wall-clock fields in the iPhone's
    /// time zone, read as Gregorian (as every `ReminderDue` is), so an iPhone set to another calendar
    /// doesn't shift the year. A day without a time keeps no hour or minute.
    public static func due(from date: Date, hasTime: Bool, calendar: Calendar) -> ReminderDue {
        let gregorian = ReminderDueRules.gregorian(calendar)
        let parts = gregorian.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return ReminderDue(
            year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1,
            hour: hasTime ? (parts.hour ?? 0) : nil, minute: hasTime ? (parts.minute ?? 0) : nil,
            timeZoneID: gregorian.timeZone.identifier)
    }

    /// Where the pickers start for a new reminder: the next full hour.
    public static func suggestedDue(now: Date, calendar: Calendar) -> Date {
        let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? now
    }

    /// Where the pickers start for a reminder that has a due: its moment on this iPhone's clock.
    public static func pickerDate(for due: ReminderDue?, local: Calendar, otherwise: Date) -> Date {
        due.flatMap { EventChange.moment($0, local: local) } ?? otherwise
    }
}

/// A change to an open reminder from the Today screen: its title, notes and due (nil for none), all three
/// as the sheet shows them, written in one save.
public struct ReminderEdit: Equatable, Sendable {
    public let title: String
    public let notes: String?
    public let due: ReminderDue?

    public init(title: String, notes: String?, due: ReminderDue?) {
        self.title = title
        self.notes = notes
        self.due = due
    }

    /// The reminder already reads like this: nothing to write.
    public func changesNothing(_ reminder: ReminderSnapshot) -> Bool {
        reminder.title == title && (reminder.notes ?? "") == (notes ?? "") && EventChange.sameDue(reminder.due, due)
    }

    /// The reminder read back from Reminders shows this change: still open, same title, notes and due.
    public func confirms(_ back: ReminderSnapshot) -> Bool {
        !back.isCompleted && changesNothing(back)
    }

    /// The due moves (or goes): the alarm set for the old due has to move with it.
    public func movesDue(from reminder: ReminderSnapshot) -> Bool {
        !EventChange.sameDue(reminder.due, due)
    }
}

/// The Calendar app at a moment: `calshow:` and the seconds since 1 January 2001, the address Calendar
/// itself answers. Apple doesn't document it, so the screen says so when the app didn't open.
public enum CalendarAppLink {
    public static func url(at date: Date) -> URL? {
        let seconds = date.timeIntervalSinceReferenceDate
        guard seconds.isFinite, abs(seconds) < 1e12 else { return nil }
        return URL(string: "calshow:\(Int(seconds.rounded(.down)))")
    }
}
