import Foundation

// Home → Today: what is left of today in the user's own Calendar and Reminders, read on the
// iPhone, plus "before this event" nudges scheduled by iOS. Nothing here leaves the phone.

/// An incomplete reminder, as Today shows it. Title and due date only; notes are not read.
public struct ReminderSummary: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let due: Date?
    /// False for a reminder due on a day without a time.
    public let dueHasTime: Bool

    public init(id: String, title: String, due: Date?, dueHasTime: Bool) {
        self.id = id
        self.title = title
        self.due = due
        self.dueHasTime = dueHasTime
    }
}

/// What the Today card lists, chosen and ordered deterministically.
public struct TodayAgenda: Equatable, Sendable {
    public static let limit = 5

    /// Events of today not yet over: all-day ones first, then by start time.
    public let events: [CalendarEventSummary]
    /// Incomplete reminders due today or earlier, oldest due first.
    public let reminders: [ReminderSummary]
    public let moreEvents: Int
    public let moreReminders: Int

    public init(events: [CalendarEventSummary], reminders: [ReminderSummary], now: Date, calendar: Calendar, limit: Int = TodayAgenda.limit) {
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let left = events
            .filter { $0.end > now && $0.start < endOfDay }
            .sorted { ($0.allDay ? 0 : 1, $0.start, $0.title) < ($1.allDay ? 0 : 1, $1.start, $1.title) }
        let due = reminders
            .filter { reminder in reminder.due.map { $0 < endOfDay } ?? false }
            .sorted { ($0.due ?? .distantFuture, $0.title) < ($1.due ?? .distantFuture, $1.title) }
        self.events = Array(left.prefix(limit))
        self.reminders = Array(due.prefix(limit))
        moreEvents = max(0, left.count - limit)
        moreReminders = max(0, due.count - limit)
    }

    public var isEmpty: Bool { events.isEmpty && reminders.isEmpty }

    /// Overdue: a timed reminder whose time has passed, or a day-only reminder from an earlier day.
    public static func isOverdue(_ reminder: ReminderSummary, now: Date, calendar: Calendar) -> Bool {
        guard let due = reminder.due else { return false }
        return reminder.dueHasTime ? due < now : due < calendar.startOfDay(for: now)
    }
}

public enum NudgePlanError: Error, Equatable, Sendable {
    case notATimedEvent
    case leadTimeInvalid
    case fireTimeInPast
}

/// One "before this event" nudge. The identifier comes from the event and the lead time, so
/// setting the same nudge twice replaces it instead of adding a second one.
public struct EventNudgePlan: Equatable, Sendable {
    public static let leadMinuteOptions = [10, 30, 60]
    static let prefix = "doddy.nudge."

    public let eventID: String
    public let eventTitle: String
    public let eventStart: Date
    public let leadMinutes: Int
    public let fireAt: Date

    public init(event: CalendarEventSummary, leadMinutes: Int, now: Date) throws(NudgePlanError) {
        guard let id = event.id, !event.allDay else { throw .notATimedEvent }
        guard leadMinutes > 0 else { throw .leadTimeInvalid }
        let fireAt = event.start.addingTimeInterval(-Double(leadMinutes) * 60)
        guard fireAt > now else { throw .fireTimeInPast }
        eventID = id
        eventTitle = event.title
        eventStart = event.start
        self.leadMinutes = leadMinutes
        self.fireAt = fireAt
    }

    public static func identifier(eventID: String, leadMinutes: Int) -> String {
        "\(prefix)\(eventID).\(leadMinutes)"
    }

    public var identifier: String { Self.identifier(eventID: eventID, leadMinutes: leadMinutes) }

    /// The notification text, e.g. "Dentist starts in 30 minutes (14:30)."
    public func body(time: String) -> String {
        "\(eventTitle) starts \(Self.leadText(leadMinutes)) (\(time))."
    }

    public static func leadText(_ minutes: Int) -> String {
        switch minutes {
        case 60: "in 1 hour"
        case let m where m % 60 == 0: "in \(m / 60) hours"
        default: "in \(minutes) minutes"
        }
    }
}

/// A nudge as read back from iOS's pending notifications: what will actually fire.
public struct ScheduledNudge: Equatable, Sendable, Identifiable {
    public let id: String
    public let fireAt: Date?

    public init(id: String, fireAt: Date?) {
        self.id = id
        self.fireAt = fireAt
    }

    public static func isNudge(_ identifier: String) -> Bool { identifier.hasPrefix(EventNudgePlan.prefix) }

    /// The event the nudge was set for (event ids may contain dots; the lead time is last).
    public var eventID: String? {
        guard Self.isNudge(id), let dot = id.lastIndex(of: ".") else { return nil }
        let start = id.index(id.startIndex, offsetBy: EventNudgePlan.prefix.count)
        return start < dot ? String(id[start..<dot]) : nil
    }

    public var leadMinutes: Int? {
        guard eventID != nil, let dot = id.lastIndex(of: ".") else { return nil }
        return Int(id[id.index(after: dot)...])
    }

    /// nil: set for another event. false: the event moved since, so it would fire at the old time.
    public func fits(_ event: CalendarEventSummary) -> Bool? {
        guard let eventID, event.id == eventID, let leadMinutes, let fireAt else { return nil }
        let expected = event.start.addingTimeInterval(-Double(leadMinutes) * 60)
        return abs(expected.timeIntervalSince(fireAt)) < 60
    }
}
