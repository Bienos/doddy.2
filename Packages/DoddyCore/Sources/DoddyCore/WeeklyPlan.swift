import Foundation

// The weekly plan (ADR-608; owner, 24 Oct 2026: "budujemy … potem plan na tydzień"). Off by
// default. Once a week, Monday 08:00 to start, a notification says only "Nowy tydzień · Zerknąć,
// co Cię czeka?" ("New week · Take a look at what's coming?"): no names, no counts, so nothing
// private is on the Lock Screen and nothing can be out of date by the time it arrives. Its screen
// is built when it opens, on this iPhone, from what is already here: Calendar events and Apple
// Reminders due (each only when its connection is on), Doddy's own reminders on notes, and the
// birthdays of the people the user picked. Seven days from today, day by day. Nothing is sent
// anywhere, and nothing is counted as a score.

public struct WeeklyPlanSettings: Equatable, Sendable {
    public var isOn: Bool
    /// Gregorian weekday, 1 = Sunday; Monday (2) to start.
    public var weekday: Int
    public var hour: Int
    public var minute: Int

    public init(isOn: Bool = false, weekday: Int = 2, hour: Int = 8, minute: Int = 0) {
        self.isOn = isOn
        self.weekday = min(max(weekday, 1), 7)
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public static let isOnKey = "weeklyPlan.isOn"
    public static let weekdayKey = "weeklyPlan.weekday"
    public static let hourKey = "weeklyPlan.hour"
    public static let minuteKey = "weeklyPlan.minute"

    public static func stored(_ defaults: UserDefaults = .standard) -> WeeklyPlanSettings {
        WeeklyPlanSettings(
            isOn: defaults.bool(forKey: isOnKey),
            weekday: defaults.object(forKey: weekdayKey) as? Int ?? 2,
            hour: defaults.object(forKey: hourKey) as? Int ?? 8,
            minute: defaults.object(forKey: minuteKey) as? Int ?? 0)
    }

    public func store(_ defaults: UserDefaults = .standard) {
        defaults.set(isOn, forKey: Self.isOnKey)
        defaults.set(weekday, forKey: Self.weekdayKey)
        defaults.set(hour, forKey: Self.hourKey)
        defaults.set(minute, forKey: Self.minuteKey)
    }
}

public struct WeeklyPlan: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case event, reminder, noteReminder, birthday
    }

    public struct Item: Equatable, Sendable {
        public let kind: Kind
        public let title: String
        /// When it happens; for an all-day event, a whole-day reminder or a birthday, the day's start.
        public let at: Date
        /// False for all-day events, reminders without a time and birthdays.
        public let hasTime: Bool
    }

    public struct Day: Equatable, Sendable {
        /// Start of the day, in the calendar the plan was made with.
        public let date: Date
        /// Untimed things first, then by time.
        public let items: [Item]
    }

    /// Seven days from today; days with nothing on them are kept, so the week reads as a week.
    public let days: [Day]
    /// What couldn't be read because its connection is off, so the screen can say so.
    public let calendarOff: Bool
    public let remindersOff: Bool

    public static let days = 7
    /// More than this on one day shows "and N more".
    public static let maxPerDay = 8

    public static let notificationID = "doddy.weekly-plan"

    public static func isPlan(notificationID: String) -> Bool { notificationID == Self.notificationID }

    public static func title(_ language: NotificationLanguage) -> String {
        language == .polish ? "Nowy tydzień" : "New week"
    }

    public static func body(_ language: NotificationLanguage) -> String {
        language == .polish ? "Zerknąć, co Cię czeka?" : "Take a look at what's coming?"
    }

    public var isEmpty: Bool { days.allSatisfy(\.items.isEmpty) }

    /// The week from what this iPhone has. `events` and `reminders` are nil when that connection is
    /// off. `noteReminders` pairs each of Doddy's reminders with the words to show for it (the
    /// note's text, or "A private note" when it is private). Overdue reminders are not repeated
    /// here: the plan is what's ahead.
    public static func make(
        events: [CalendarEventSummary]?, reminders: [ReminderSummary]?,
        noteReminders: [(reminder: MemoryReminder, title: String)], birthdays: [UpcomingBirthday],
        now: Date, calendar: Calendar
    ) -> WeeklyPlan {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else {
            return WeeklyPlan(days: [], calendarOff: events == nil, remindersOff: reminders == nil)
        }
        var items: [Item] = []
        for event in events ?? [] where event.end > now && event.start < end {
            // An event already under way today shows on today, at its start.
            let at = event.allDay ? calendar.startOfDay(for: max(event.start, start)) : max(event.start, start)
            items.append(Item(kind: .event, title: event.title, at: at, hasTime: !event.allDay))
        }
        for reminder in reminders ?? [] {
            guard let due = reminder.due, due >= start, due < end else { continue }
            if reminder.dueHasTime && due < now { continue }
            items.append(Item(kind: .reminder, title: reminder.title, at: due, hasTime: reminder.dueHasTime))
        }
        for (reminder, title) in noteReminders {
            for at in occurrences(of: reminder, from: now, until: end) {
                items.append(Item(kind: .noteReminder, title: title, at: at, hasTime: true))
            }
        }
        for birthday in birthdays where birthday.date >= start && birthday.date < end {
            items.append(Item(kind: .birthday, title: birthday.name, at: birthday.date, hasTime: false))
        }
        let plan = (0..<days).compactMap { offset -> Day? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let onDay = items.filter { $0.at >= day && $0.at < next }.sorted { lhs, rhs in
                if lhs.hasTime != rhs.hasTime { return !lhs.hasTime }
                if lhs.at != rhs.at { return lhs.at < rhs.at }
                return lhs.title < rhs.title
            }
            return Day(date: day, items: onDay)
        }
        return WeeklyPlan(days: plan, calendarOff: events == nil, remindersOff: reminders == nil)
    }

    /// Every time a note reminder fires from `now` until `end`: a one-off's moment, each repeat,
    /// and a snooze. Place reminders have no time and are left out.
    static func occurrences(of reminder: MemoryReminder, from now: Date, until end: Date) -> [Date] {
        guard reminder.fireAt != nil else { return [] }
        var found: [Date] = []
        var cursor = now
        while let next = reminder.nextFire(after: cursor), next < end, found.count < 40 {
            found.append(next)
            cursor = next
        }
        return found
    }
}

extension WeeklyPlan.Kind {
    /// The words shown before an item of this kind.
    public func label(_ language: NotificationLanguage) -> String {
        switch (self, language) {
        case (.event, .polish): "Kalendarz"
        case (.event, .english): "Calendar"
        case (.reminder, .polish): "Przypomnienie"
        case (.reminder, .english): "Reminder"
        case (.noteReminder, .polish): "Przypomnienie Doddy'ego"
        case (.noteReminder, .english): "Doddy's reminder"
        case (.birthday, .polish): "Urodziny"
        case (.birthday, .english): "Birthday"
        }
    }
}
