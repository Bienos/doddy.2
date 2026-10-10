import Foundation

// Morning brief (ADR-212): the day at a glance, once a day, when the user turns it on.
// Built on the iPhone from what Home → Today already reads (Calendar and Reminders, only with
// their Connections switches on) and Doddy's own note reminders. Nothing is sent anywhere.
// The daily notification says only that the brief is ready: no titles or notes on the Lock Screen.
// Wording is plain and neutral: counts and times, no pressure, no praise, no guessing.

/// When the brief appears. Off unless the user turns it on.
public struct MorningBriefSchedule: Equatable, Sendable {
    public static let defaultHour = 7
    public static let defaultMinute = 30
    /// How long after its time the brief stays at the top of Home (never past the end of the day).
    public static let showingHours = 5

    public var isOn: Bool
    public let hour: Int
    public let minute: Int

    /// Out-of-range values fall back to the default time.
    public init(isOn: Bool, hour: Int = defaultHour, minute: Int = defaultMinute) {
        self.isOn = isOn
        let valid = (0...23).contains(hour) && (0...59).contains(minute)
        self.hour = valid ? hour : Self.defaultHour
        self.minute = valid ? minute : Self.defaultMinute
    }

    /// Today's brief time in `calendar`'s zone.
    public func start(on now: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
    }

    /// Whether Home shows the brief now: on, from its time for `showingHours` (until midnight at
    /// the latest), and not already closed today.
    public func isShowing(now: Date, dismissedDay: String?, calendar: Calendar) -> Bool {
        guard isOn, dismissedDay != Self.dayKey(now, calendar: calendar),
              let start = start(on: now, calendar: calendar) else { return false }
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let end = min(start.addingTimeInterval(Double(Self.showingHours) * 3600), endOfDay)
        return now >= start && now < end
    }

    /// "2026-10-10" in `calendar`'s zone: which day the user closed the brief.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// The daily local notification. Same text every day, so nothing personal is on the Lock Screen
/// and nothing has to be worked out in the background.
public enum MorningBriefNotification {
    public static let identifier = "doddy.brief.daily"
    public static let title = "Morning brief"
    public static let body = "Your day at a glance is ready in Doddy."

    public static func isBrief(_ identifier: String) -> Bool { identifier == Self.identifier }
}

/// A note reminder that fires later today, with the note's current words.
public struct BriefNoteReminder: Equatable, Sendable {
    public let fireAt: Date
    public let noteText: String

    public init(fireAt: Date, noteText: String) {
        self.fireAt = fireAt
        self.noteText = noteText
    }
}

/// What the brief could read.
public enum BriefSource: Equatable, Sendable {
    /// Calendar and/or Reminders were read (each `nil` when its switch is off or iOS blocks it).
    case agenda(TodayAgenda, calendarRead: Bool, remindersRead: Bool)
    /// Calendar and Reminders are both off or blocked.
    case notConnected
    /// Settings → Pause all is on.
    case paused
}

public struct MorningBrief: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case greeting, events, reminders, noteReminders, notice
    }

    public struct Line: Equatable, Sendable {
        public let kind: Kind
        public let text: String
    }

    public let lines: [Line]

    /// Everything in one paragraph, for reading aloud.
    public var spokenText: String { lines.map(\.text).joined(separator: " ") }

    static let namedItems = 3

    /// `timeText` formats a time of day ("10:00"); the app passes the user's locale.
    public static func compose(
        source: BriefSource, noteReminders: [BriefNoteReminder], name: String?,
        now: Date, calendar: Calendar, timeText: (Date) -> String
    ) -> MorningBrief {
        var lines: [Line] = []
        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(Line(kind: .greeting, text: (cleanName?.isEmpty == false) ? "Good morning, \(cleanName!)." : "Good morning."))

        switch source {
        case .paused:
            lines.append(Line(kind: .notice, text: "Connections are paused, so your calendar and reminders aren't in this brief."))
        case .notConnected:
            lines.append(Line(kind: .notice, text: "Calendar and Reminders are off in Settings, Connections, so they aren't in this brief."))
        case .agenda(let agenda, let calendarRead, let remindersRead):
            if calendarRead { lines.append(Line(kind: .events, text: eventsText(agenda, timeText: timeText))) }
            if remindersRead { lines.append(Line(kind: .reminders, text: remindersText(agenda, now: now, calendar: calendar))) }
            if !calendarRead { lines.append(Line(kind: .notice, text: "Calendar is off, so events aren't in this brief.")) }
            if !remindersRead { lines.append(Line(kind: .notice, text: "Reminders is off, so your reminders aren't in this brief.")) }
        }

        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let later = noteReminders
            .filter { $0.fireAt >= now && $0.fireAt < endOfDay }
            .sorted { ($0.fireAt, $0.noteText) < ($1.fireAt, $1.noteText) }
        if !later.isEmpty {
            let shown = later.prefix(namedItems).map { "at \(timeText($0.fireAt)), “\(clip($0.noteText))”" }
            let more = later.count > namedItems ? ", and \(later.count - namedItems) more" : ""
            lines.append(Line(
                kind: .noteReminders,
                text: "\(later.count == 1 ? "A note reminder" : "\(later.count) note reminders") today: \(list(Array(shown)))\(more)."))
        }

        return MorningBrief(lines: lines)
    }

    static func eventsText(_ agenda: TodayAgenda, timeText: (Date) -> String) -> String {
        let total = agenda.events.count + agenda.moreEvents
        guard total > 0 else { return "No events left in your calendar today." }
        let allDay = agenda.events.filter(\.allDay)
        let timed = agenda.events.filter { !$0.allDay }
        var parts: [String] = []
        if !allDay.isEmpty {
            parts.append("all day, \(list(allDay.prefix(namedItems).map { clip($0.title) }))")
        }
        if let first = timed.first {
            if timed.count == 1 {
                parts.append("\(clip(first.title)) at \(timeText(first.start))")
            } else {
                parts.append("first \(clip(first.title)) at \(timeText(first.start))")
            }
        }
        let count = total == 1 ? "One event left today" : "\(total) events left today"
        return parts.isEmpty ? "\(count)." : "\(count): \(parts.joined(separator: "; "))."
    }

    static func remindersText(_ agenda: TodayAgenda, now: Date, calendar: Calendar) -> String {
        let total = agenda.reminders.count + agenda.moreReminders
        guard total > 0 else { return "No reminders due today." }
        let earlier = agenda.reminders.filter { TodayAgenda.isOverdue($0, now: now, calendar: calendar) && !isToday($0, now: now, calendar: calendar) }
        let names = agenda.reminders.prefix(namedItems).map { clip($0.title) }
        let more = total > names.count ? ", and \(total - names.count) more" : ""
        var text = "\(total == 1 ? "One reminder" : "\(total) reminders") due: \(list(Array(names)))\(more)."
        if !earlier.isEmpty {
            text += earlier.count == 1 ? " One is from an earlier day." : " \(earlier.count) are from earlier days."
        }
        return text
    }

    private static func isToday(_ reminder: ReminderSummary, now: Date, calendar: Calendar) -> Bool {
        reminder.due.map { calendar.isDate($0, inSameDayAs: now) } ?? false
    }

    /// "A", "A and B", "A, B and C".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }

    /// Long titles and notes are shortened for the brief only (the note itself is never changed).
    static func clip(_ text: String, max: Int = 80) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > max ? String(flat.prefix(max - 1)) + "…" : flat
    }
}
