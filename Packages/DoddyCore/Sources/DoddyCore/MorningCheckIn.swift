import Foundation

// Morning check-in (ADR-220). Off until the user turns it on. At the time they pick, a local
// notification asks "A quick look at your day?" and says nothing else, so nothing personal shows
// on the Lock Screen. A tap opens Doddy on a check-in screen built on this iPhone: today's note
// reminders and the lists with things left to do. Nothing goes to ElevenLabs until the user taps
// "Talk it through"; then the same facts go in the `{{morning_checkin}}` variable, and the agent
// reads the calendar only with its usual tool and the user's Calendar switch.

public struct MorningCheckInSettings: Equatable, Sendable {
    public var isOn: Bool
    public var hour: Int
    public var minute: Int
    public var weekdaysOnly: Bool

    public init(isOn: Bool = false, hour: Int = 8, minute: Int = 0, weekdaysOnly: Bool = false) {
        self.isOn = isOn
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.weekdaysOnly = weekdaysOnly
    }

    public static let isOnKey = "morningCheckIn.isOn"
    public static let hourKey = "morningCheckIn.hour"
    public static let minuteKey = "morningCheckIn.minute"
    public static let weekdaysOnlyKey = "morningCheckIn.weekdaysOnly"

    public static func stored(_ defaults: UserDefaults = .standard) -> MorningCheckInSettings {
        MorningCheckInSettings(
            isOn: defaults.bool(forKey: isOnKey),
            hour: defaults.object(forKey: hourKey) as? Int ?? 8,
            minute: defaults.object(forKey: minuteKey) as? Int ?? 0,
            weekdaysOnly: defaults.bool(forKey: weekdaysOnlyKey))
    }

    public func store(_ defaults: UserDefaults = .standard) {
        defaults.set(isOn, forKey: Self.isOnKey)
        defaults.set(hour, forKey: Self.hourKey)
        defaults.set(minute, forKey: Self.minuteKey)
        defaults.set(weekdaysOnly, forKey: Self.weekdaysOnlyKey)
    }
}

public enum MorningCheckIn {
    /// Every check-in request id starts with this, so Doddy can find, replace and remove its own.
    public static let notificationPrefix = "doddy.morning-checkin"

    /// One repeating request: every day, or one per weekday (Monday to Friday, 5 of iOS's 64).
    public struct Request: Equatable, Sendable {
        public let id: String
        /// Gregorian weekday (1 = Sunday) or nil for every day.
        public let weekday: Int?
        public let hour: Int
        public let minute: Int
    }

    public static func requests(_ settings: MorningCheckInSettings) -> [Request] {
        guard settings.isOn else { return [] }
        guard settings.weekdaysOnly else {
            return [Request(id: "\(notificationPrefix).daily", weekday: nil, hour: settings.hour, minute: settings.minute)]
        }
        return (2...6).map {
            Request(id: "\(notificationPrefix).weekday\($0)", weekday: $0, hour: settings.hour, minute: settings.minute)
        }
    }

    public static func isCheckIn(notificationID: String) -> Bool { notificationID.hasPrefix(notificationPrefix) }

    /// The notification says only this, in the iPhone's language (Polish or English).
    public static func title(_ language: NotificationLanguage) -> String {
        language == .polish ? "Dzień dobry" : "Good morning"
    }

    public static func body(_ language: NotificationLanguage) -> String {
        language == .polish ? "Szybki rzut oka na Twój dzień?" : "A quick look at your day?"
    }
}

/// What the check-in screen shows and, after "Talk it through", what the agent is given.
public struct MorningBriefing: Equatable, Sendable {
    public struct ReminderLine: Equatable, Sendable {
        public let memoryID: UUID
        public let time: Date
        public let text: String
    }

    public struct ListLine: Equatable, Sendable {
        public let listID: UUID
        public let name: String
        public let openCount: Int
    }

    public static let maxReminders = 6
    public static let maxLists = 5

    public let day: Date
    /// Doddy's own time reminders still ahead today, in time order.
    public let reminders: [ReminderLine]
    /// Lists with at least one open item, most open first.
    public let lists: [ListLine]

    public var isEmpty: Bool { reminders.isEmpty && lists.isEmpty }

    public static func make(
        now: Date, memories: [MemoryRecord], lists: [DoddyList], reminders: [MemoryReminder],
        calendar: Calendar = .current
    ) -> MorningBriefing {
        // The next midnight, not 24 hours on: a clock-change day has 23 or 25.
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 3600)
        let byID = Dictionary(memories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let today = reminders.compactMap { reminder -> ReminderLine? in
            guard let fire = reminder.nextFire(after: now), fire < end, let note = byID[reminder.memoryID] else { return nil }
            return ReminderLine(memoryID: note.id, time: fire, text: WidgetSnapshot.shortened(note.currentText))
        }
        .sorted { $0.time < $1.time }
        let open = lists.filter { !$0.open.isEmpty }
            .sorted { $0.open.count != $1.open.count ? $0.open.count > $1.open.count : $0.name < $1.name }
            .map { ListLine(listID: $0.id, name: WidgetSnapshot.shortened($0.name), openCount: $0.open.count) }
        return MorningBriefing(day: now, reminders: Array(today.prefix(maxReminders)), lists: Array(open.prefix(maxLists)))
    }
}

/// The `{{morning_checkin}}` variable: "none", or the facts of the briefing the user asked to
/// talk through, with what to do with them.
public enum MorningCheckInPrompt {
    public static let variableName = "morning_checkin"

    public static func render(_ briefing: MorningBriefing?, timeZone: TimeZone = .current) -> String {
        guard let briefing else { return "none" }
        let time = DateFormatter()
        time.timeZone = timeZone
        time.locale = Locale(identifier: "en_GB")
        time.dateFormat = "HH:mm"
        let day = DateFormatter()
        day.timeZone = timeZone
        day.locale = Locale(identifier: "en_GB")
        day.dateFormat = "EEEE d MMMM"
        // Reminder text and list names are the user's words: between the data markers (review C4).
        var lines: [String] = []
        if briefing.reminders.isEmpty {
            lines.append("Doddy reminders today: none.")
        } else {
            lines.append("Doddy reminders today: " + briefing.reminders.map { "\(time.string(from: $0.time)) \(ToolData.clean($0.text))" }.joined(separator: "; ") + ".")
        }
        if briefing.lists.isEmpty {
            lines.append("Lists with things left: none.")
        } else {
            lines.append("Lists with things left: " + briefing.lists.map { "\(ToolData.clean($0.name)) (\($0.openCount))" }.joined(separator: "; ") + ".")
        }
        return "The user started a morning check-in for \(day.string(from: briefing.day)).\n" + ToolData.block(lines)
    }
}
