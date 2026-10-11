import Foundation

// Evening wrap-up (ADR-256). Off by default. Once a day, at a time the user picks, a notification
// asks "Anything to move to tomorrow?" and says nothing personal. Its screen lists the open
// reminders in the iPhone's Reminders app that are due today or earlier (read on this iPhone,
// only with Reminders on in Connections). None is ticked to start with; the user ticks the ones
// to move and taps Move. Each one keeps its time and moves to tomorrow, only if it still looks as
// shown, and is read back (the same checked change as ADR-229). Nothing is sent anywhere.

public struct EveningWrapUpSettings: Equatable, Sendable {
    public var isOn: Bool
    public var hour: Int
    public var minute: Int

    public init(isOn: Bool = false, hour: Int = 21, minute: Int = 0) {
        self.isOn = isOn
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public static let isOnKey = "eveningWrapUp.isOn"
    public static let hourKey = "eveningWrapUp.hour"
    public static let minuteKey = "eveningWrapUp.minute"

    public static func stored(_ defaults: UserDefaults = .standard) -> EveningWrapUpSettings {
        EveningWrapUpSettings(
            isOn: defaults.bool(forKey: isOnKey),
            hour: defaults.object(forKey: hourKey) as? Int ?? 21,
            minute: defaults.object(forKey: minuteKey) as? Int ?? 0)
    }

    public func store(_ defaults: UserDefaults = .standard) {
        defaults.set(isOn, forKey: Self.isOnKey)
        defaults.set(hour, forKey: Self.hourKey)
        defaults.set(minute, forKey: Self.minuteKey)
    }
}

public enum EveningWrapUp {
    public static let notificationID = "doddy.evening-wrapup.daily"
    /// At most this many reminders on the screen, oldest due first.
    public static let maxShown = 30

    public static func isWrapUp(notificationID: String) -> Bool { notificationID == Self.notificationID }

    public static func title(_ language: NotificationLanguage) -> String {
        language == .polish ? "Dobry wieczór" : "Good evening"
    }

    public static func body(_ language: NotificationLanguage) -> String {
        language == .polish ? "Coś przenieść na jutro?" : "Anything to move to tomorrow?"
    }

    /// Open reminders due today or earlier, oldest first. Reminders without a due aren't offered:
    /// moving them would give them a date they never had.
    public static func movable(_ reminders: [ReminderSnapshot], now: Date, local: Calendar) -> [ReminderSnapshot] {
        let today = ReminderDueRules.gregorian(local).dateComponents([.year, .month, .day], from: now)
        let todayKey = (today.year ?? 0) * 10_000 + (today.month ?? 0) * 100 + (today.day ?? 0)
        return reminders
            .filter { reminder in
                guard !reminder.isCompleted, let due = reminder.due else { return false }
                return due.year * 10_000 + due.month * 100 + due.day <= todayKey
            }
            .sorted { lhs, rhs in
                let left = lhs.due.flatMap { EventChange.moment($0, local: local) } ?? .distantPast
                let right = rhs.due.flatMap { EventChange.moment($0, local: local) } ?? .distantPast
                return left != right ? left < right : lhs.title < rhs.title
            }
            .prefix(maxShown)
            .map { $0 }
    }

    /// The same time tomorrow, or tomorrow for a day without a time. "Tomorrow" is the day after
    /// `now`, so a reminder overdue since last week also lands tomorrow. Nil when that time
    /// doesn't exist tomorrow or happens twice (the clocks change): the screen says so instead.
    public static func tomorrow(_ due: ReminderDue, now: Date, local: Calendar) -> ReminderDue? {
        let calendar = ReminderDueRules.gregorian(local)
        guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
        let day = calendar.dateComponents([.year, .month, .day], from: next)
        guard let year = day.year, let month = day.month, let dayOfMonth = day.day else { return nil }
        guard let hour = due.hour else {
            return ReminderDue(year: year, month: month, day: dayOfMonth, timeZoneID: due.timeZoneID)
        }
        var zoned = calendar
        if let zone = due.timeZoneID.flatMap(TimeZone.init(identifier:)) { zoned.timeZone = zone }
        let text = String(format: "%04d-%02d-%02dT%02d:%02d", year, month, dayOfMonth, hour, due.minute ?? 0)
        guard case .due(let moved) = ReminderDueRules.wallClock(text, calendar: zoned) else { return nil }
        return moved
    }
}
