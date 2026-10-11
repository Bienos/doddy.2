import Foundation

/// "A thought is ready for review" (ADR-342): an opt-in, once-a-day passive notification that
/// brings back one note the user saved a while ago. Which note, and when, are decided here with
/// plain rules, so they are tested on Linux. The notification never carries the note's words;
/// opening it shows the note in Doddy. Nothing is scored and nothing is sent anywhere.
public struct ThoughtReviewSettings: Equatable, Sendable {
    public var isOn: Bool
    public var hour: Int
    public var minute: Int

    public init(isOn: Bool = false, hour: Int = 19, minute: Int = 30) {
        self.isOn = isOn
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public static let isOnKey = "thoughtReview.isOn"
    public static let hourKey = "thoughtReview.hour"
    public static let minuteKey = "thoughtReview.minute"

    public static func stored(_ defaults: UserDefaults = .standard) -> ThoughtReviewSettings {
        ThoughtReviewSettings(
            isOn: defaults.bool(forKey: isOnKey),
            hour: defaults.object(forKey: hourKey) as? Int ?? 19,
            minute: defaults.object(forKey: minuteKey) as? Int ?? 30)
    }

    public func store(_ defaults: UserDefaults = .standard) {
        defaults.set(isOn, forKey: Self.isOnKey)
        defaults.set(hour, forKey: Self.hourKey)
        defaults.set(minute, forKey: Self.minuteKey)
    }
}

/// When each note was last opened from a review notification. Only ids and dates, kept in
/// UserDefaults as JSON; entries for deleted notes are dropped when the schedule is rebuilt.
public struct ThoughtReviewLog: Codable, Equatable, Sendable {
    public static let storageKey = "thoughtReview.log"

    public private(set) var reviewed: [UUID: Date]

    public init(reviewed: [UUID: Date] = [:]) {
        self.reviewed = reviewed
    }

    public mutating func mark(_ id: UUID, at date: Date) {
        reviewed[id] = date
    }

    /// Drops notes that are gone, so the log can't grow past the notes that exist.
    public mutating func keepOnly(_ ids: Set<UUID>) {
        reviewed = reviewed.filter { ids.contains($0.key) }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(self)
    }

    public static func decoded(_ data: Data?) -> ThoughtReviewLog {
        guard let data else { return ThoughtReviewLog() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? decoder.decode(ThoughtReviewLog.self, from: data)) ?? ThoughtReviewLog()
    }
}

public enum ThoughtReview {
    public static let notificationID = "doddy.thought-review"
    public static let categoryID = "DODDY_THOUGHT_REVIEW"
    public static let memoryIDKey = "memoryID"
    /// A note is first offered a week after it was saved, then again a month after each review.
    public static let firstAfterDays = 7
    public static let againAfterDays = 30

    public static func isReview(notificationID: String) -> Bool { notificationID == Self.notificationID }

    public static func title(_ language: NotificationLanguage) -> String {
        switch language {
        case .english: "A thought is ready for review"
        case .polish: "Jedna myśl czeka na powtórkę"
        }
    }

    /// No note words: the note opens in Doddy, where the user is.
    public static func body(_ language: NotificationLanguage) -> String {
        switch language {
        case .english: "Open Doddy to read it again. Nothing else happens."
        case .polish: "Otwórz Doddy, żeby ją przeczytać jeszcze raz. Nic więcej się nie dzieje."
        }
    }

    public static func openAction(_ language: NotificationLanguage) -> String {
        switch language {
        case .english: "Open the note"
        case .polish: "Otwórz notatkę"
        }
    }

    /// The one note due for a review at `now`, or nil when none is: a note (never a list) saved
    /// at least `firstAfterDays` ago that was never reviewed, newest such first, so a note comes
    /// back about a week after it was saved; otherwise the note reviewed longest ago, once
    /// `againAfterDays` have passed since. Deterministic: the same input picks the same note.
    public static func due(memories: [MemoryRecord], log: ThoughtReviewLog, now: Date) -> MemoryRecord? {
        let firstCutoff = now.addingTimeInterval(-Double(firstAfterDays) * 86_400)
        let againCutoff = now.addingTimeInterval(-Double(againAfterDays) * 86_400)
        let notes = memories.filter { $0.category != .list }
        let fresh = notes
            .filter { log.reviewed[$0.id] == nil }
            .filter { ($0.capturedAt ?? .distantFuture) <= firstCutoff }
            .sorted { ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
        if let next = fresh.first { return next }
        return notes
            .compactMap { note in log.reviewed[note.id].map { (note, $0) } }
            .filter { $0.1 <= againCutoff }
            .sorted { $0.1 < $1.1 }
            .first?.0
    }

    /// The next moment the chosen clock time comes round, strictly after `now`.
    public static func nextFire(after now: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        guard let today = calendar.date(from: parts) else { return now.addingTimeInterval(86_400) }
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    }
}
