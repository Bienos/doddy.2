import Foundation

// Weekly tidy-up (ADR-228). Off by default. Once a week, at a time the user picks, a notification
// asks "A few minutes to tidy up Doddy?" and says nothing personal. The tidy-up screen suggests:
// notes saved twice with the same words, one-off reminders whose time passed more than a day ago
// and were never marked done, and lists where everything is ticked. Nothing is deleted, cleared
// or marked done until the user taps that one suggestion; no streaks, scores or nagging.

public struct TidyUpSettings: Equatable, Sendable {
    public var isOn: Bool
    /// Gregorian weekday, 1 = Sunday.
    public var weekday: Int
    public var hour: Int
    public var minute: Int

    public init(isOn: Bool = false, weekday: Int = 1, hour: Int = 18, minute: Int = 0) {
        self.isOn = isOn
        self.weekday = min(max(weekday, 1), 7)
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public static let isOnKey = "tidyUp.isOn"
    public static let weekdayKey = "tidyUp.weekday"
    public static let hourKey = "tidyUp.hour"
    public static let minuteKey = "tidyUp.minute"

    public static func stored(_ defaults: UserDefaults = .standard) -> TidyUpSettings {
        TidyUpSettings(
            isOn: defaults.bool(forKey: isOnKey),
            weekday: defaults.object(forKey: weekdayKey) as? Int ?? 1,
            hour: defaults.object(forKey: hourKey) as? Int ?? 18,
            minute: defaults.object(forKey: minuteKey) as? Int ?? 0)
    }

    public func store(_ defaults: UserDefaults = .standard) {
        defaults.set(isOn, forKey: Self.isOnKey)
        defaults.set(weekday, forKey: Self.weekdayKey)
        defaults.set(hour, forKey: Self.hourKey)
        defaults.set(minute, forKey: Self.minuteKey)
    }
}

public enum TidyUp {
    public static let notificationID = "doddy.tidy-up.weekly"

    public static func isTidyUp(notificationID: String) -> Bool { notificationID == Self.notificationID }

    public static func title(_ language: NotificationLanguage) -> String {
        language == .polish ? "Porządki w Doddym" : "Tidy up Doddy"
    }

    public static func body(_ language: NotificationLanguage) -> String {
        language == .polish ? "Kilka minut na porządki?" : "A few minutes to tidy up?"
    }

    /// A one-off reminder counts as forgotten once its time is this far behind.
    public static let forgottenAfter: TimeInterval = 24 * 3600

    public struct DuplicateGroup: Equatable, Sendable, Identifiable {
        /// The first saved copy, kept by default.
        public let keep: MemoryRecord
        /// Later copies with the same words.
        public let copies: [MemoryRecord]
        public var id: UUID { keep.id }
    }

    public struct Suggestions: Equatable, Sendable {
        public let duplicates: [DuplicateGroup]
        /// One-off time reminders more than a day past and never marked done.
        public let passedReminders: [MemoryReminder]
        /// Lists with at least one item where every item is ticked.
        public let finishedLists: [DoddyList]

        public var isEmpty: Bool { duplicates.isEmpty && passedReminders.isEmpty && finishedLists.isEmpty }
        public var count: Int { duplicates.count + passedReminders.count + finishedLists.count }
    }

    public static func suggestions(
        memories: [MemoryRecord], lists: [DoddyList], reminders: [MemoryReminder], now: Date
    ) -> Suggestions {
        var groups: [String: [MemoryRecord]] = [:]
        for note in memories where note.source != .sampleFixture && note.category != .list {
            let key = DuplicateNote.key(note.currentText)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(note)
        }
        let duplicates = groups.values
            .filter { $0.count > 1 }
            .map { $0.sorted { ($0.capturedAt ?? .distantPast) < ($1.capturedAt ?? .distantPast) } }
            .map { DuplicateGroup(keep: $0[0], copies: Array($0.dropFirst())) }
            .sorted { ($0.keep.capturedAt ?? .distantPast) > ($1.keep.capturedAt ?? .distantPast) }
        let known = Set(memories.map(\.id)).union(lists.map(\.id))
        let passed = reminders.filter { reminder in
            guard reminder.repeats == nil, case .time(let fireAt, _) = reminder.trigger else { return false }
            return known.contains(reminder.memoryID) && fireAt <= now.addingTimeInterval(-forgottenAfter)
        }
        .sorted { ($0.fireAt ?? .distantPast) < ($1.fireAt ?? .distantPast) }
        let finished = lists.filter { !$0.items.isEmpty && $0.open.isEmpty }
        return Suggestions(duplicates: duplicates, passedReminders: passed, finishedLists: finished)
    }
}
