import Foundation

// The weekly look-back (ADR-306). Off by default. Once a week, on the day and at the time the
// user picks (Sunday 19:00 to start, an hour after the tidy-up; ADR-310), a notification says only "Your week with Doddy". Its screen
// is built on this iPhone from what is already here: the notes saved in the last seven days, list
// items ticked off, changes Doddy made and checked ("What Doddy did", done only), and, if Calendar
// or Reminders are on in Connections, what is coming up in the next seven days. Counts and the
// user's own words only: no streaks, no scores, no comparison with other weeks, no nudge to do
// more. Nothing is sent anywhere.

public struct WeeklyLookBackSettings: Equatable, Sendable {
    public var isOn: Bool
    /// Gregorian weekday, 1 = Sunday.
    public var weekday: Int
    public var hour: Int
    public var minute: Int

    public init(isOn: Bool = false, weekday: Int = 1, hour: Int = 19, minute: Int = 0) {
        self.isOn = isOn
        self.weekday = min(max(weekday, 1), 7)
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public static let isOnKey = "weeklyLookBack.isOn"
    public static let weekdayKey = "weeklyLookBack.weekday"
    public static let hourKey = "weeklyLookBack.hour"
    public static let minuteKey = "weeklyLookBack.minute"

    public static func stored(_ defaults: UserDefaults = .standard) -> WeeklyLookBackSettings {
        WeeklyLookBackSettings(
            isOn: defaults.bool(forKey: isOnKey),
            weekday: defaults.object(forKey: weekdayKey) as? Int ?? 1,
            hour: defaults.object(forKey: hourKey) as? Int ?? 19,
            minute: defaults.object(forKey: minuteKey) as? Int ?? 0)
    }

    public func store(_ defaults: UserDefaults = .standard) {
        defaults.set(isOn, forKey: Self.isOnKey)
        defaults.set(weekday, forKey: Self.weekdayKey)
        defaults.set(hour, forKey: Self.hourKey)
        defaults.set(minute, forKey: Self.minuteKey)
    }
}

public struct WeeklyLookBack: Equatable, Sendable {
    /// Notes saved in the last seven days, newest first, at most `maxNotes` shown.
    public let notes: [String]
    public let noteCount: Int
    /// List items ticked off in the last seven days.
    public let ticked: Int
    /// Changes Doddy made and checked, by app (only `done` rows), most first.
    public let doneByApp: [(app: ActivityApp, count: Int)]
    /// Next seven days. Nil: that connection is off, so nothing was read.
    public let upcomingEvents: [CalendarEventSummary]?
    public let remindersDue: Int?

    public static let maxNotes = 5
    public static let maxEvents = 5
    public static let days = 7

    public static let notificationID = "doddy.weekly-lookback"

    public static func isLookBack(notificationID: String) -> Bool { notificationID == Self.notificationID }

    public static func title(_ language: NotificationLanguage) -> String {
        language == .polish ? "Twój tydzień z Doddym" : "Your week with Doddy"
    }

    public static func body(_ language: NotificationLanguage) -> String {
        language == .polish ? "Krótkie podsumowanie, gdy zechcesz." : "A short look back, when you like."
    }

    public static func == (lhs: WeeklyLookBack, rhs: WeeklyLookBack) -> Bool {
        lhs.notes == rhs.notes && lhs.noteCount == rhs.noteCount && lhs.ticked == rhs.ticked
            && lhs.doneByApp.map(\.app) == rhs.doneByApp.map(\.app) && lhs.doneByApp.map(\.count) == rhs.doneByApp.map(\.count)
            && lhs.upcomingEvents == rhs.upcomingEvents && lhs.remindersDue == rhs.remindersDue
    }

    /// Everything shown, from what this iPhone already has. `events` and `remindersDue` are nil
    /// when that connection is off.
    public static func make(
        notes: [MemoryRecord], lists: [DoddyList], activity: [ActivityEntry],
        events: [CalendarEventSummary]?, remindersDue: Int?, now: Date
    ) -> WeeklyLookBack {
        let since = now.addingTimeInterval(-Double(days) * 86_400)
        let until = now.addingTimeInterval(Double(days) * 86_400)
        let recent = notes
            .filter { $0.category != .list && ($0.capturedAt ?? .distantPast) >= since && ($0.capturedAt ?? .distantFuture) <= now }
            .sorted { ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
        let ticked = lists.flatMap(\.items).filter { item in
            guard let done = item.doneAt else { return false }
            return done >= since && done <= now
        }.count
        var counts: [ActivityApp: Int] = [:]
        // An undone change (or one whose undo may have run) doesn't count as done.
        for entry in activity where entry.outcome == .done && entry.at >= since && entry.at <= now && !Self.wasUndone(entry) {
            counts[entry.app, default: 0] += 1
        }
        let byApp = counts.map { (app: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.app.rawValue < $1.app.rawValue }
        let upcoming = events.map { found in
            Array(found.filter { $0.start >= now && $0.start < until }.sorted { $0.start < $1.start }.prefix(maxEvents))
        }
        return WeeklyLookBack(
            notes: recent.prefix(maxNotes).map(\.currentText), noteCount: recent.count, ticked: ticked,
            doneByApp: byApp, upcomingEvents: upcoming, remindersDue: remindersDue)
    }

    static func wasUndone(_ entry: ActivityEntry) -> Bool {
        switch entry.undoState {
        case .undone, .notSure: true
        case .leftAlone, .notDone, nil: false
        }
    }

    /// Nothing happened and nothing is known to be coming: the screen says so plainly.
    public var isQuiet: Bool {
        noteCount == 0 && ticked == 0 && doneByApp.isEmpty && (upcomingEvents ?? []).isEmpty && (remindersDue ?? 0) == 0
    }
}
