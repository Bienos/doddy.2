import Foundation

/// A stopwatch that counts up (ADR-621; owner, 24 Oct 2026: "stoper"). Doddy's timers count down
/// (`set_timer`, `FocusSession`); this one has no end. Pure timing rules, so they are tested on
/// Linux; the app keeps one on this iPhone, shows it on the Lock Screen and in the island, and
/// never sends a notification for it (nothing ends). It measures time and claims nothing else.
public struct Stopwatch: Codable, Equatable, Sendable, Identifiable {
    public enum State: Equatable, Sendable {
        case running
        case paused
        case stopped
    }

    /// The optional line is shown on the Lock Screen and island, so it is kept short.
    public static let maxLabelLength = 40
    /// A stopwatch left running is stopped at this reading: a day is plenty, and the island's
    /// numerals have room for it.
    public static let maxElapsed: TimeInterval = 24 * 3_600

    public let id: UUID
    /// What the user said, trimmed; nil when empty.
    public let label: String?
    public let startedAt: Date
    /// Time counted before the current run (before the last pause).
    public private(set) var accumulated: TimeInterval
    /// When the current run began; nil while paused or stopped.
    public private(set) var runningSince: Date?
    /// When it was stopped; nil until then.
    public private(set) var stoppedAt: Date?

    public init(label: String?, now: Date, id: UUID = UUID()) {
        self.id = id
        self.label = Self.cleanLabel(label)
        startedAt = now
        accumulated = 0
        runningSince = now
        stoppedAt = nil
    }

    public static func cleanLabel(_ text: String?) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).joined(separator: " ")
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLabelLength))
    }

    public var state: State {
        if stoppedAt != nil { return .stopped }
        return runningSince != nil ? .running : .paused
    }

    public var isRunning: Bool { state == .running }
    public var isPaused: Bool { state == .paused }
    public var isOver: Bool { state == .stopped }

    /// Time counted so far. Never negative (a clock set back counts nothing), never past `maxElapsed`.
    public func elapsed(at now: Date) -> TimeInterval {
        let running = runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return min(Self.maxElapsed, max(0, accumulated + running))
    }

    /// The moment a counting-up clock would have started to show the time so far: what the Lock
    /// Screen's self-ticking text needs. It does not change while running, so the Live Activity
    /// is updated only on a pause or resume. Nil unless it is running.
    public var countsFrom: Date? {
        runningSince?.addingTimeInterval(-accumulated)
    }

    public mutating func pause(at now: Date) {
        guard isRunning else { return }
        accumulated = elapsed(at: now)
        runningSince = nil
    }

    public mutating func resume(at now: Date) {
        guard isPaused else { return }
        runningSince = now
    }

    public mutating func stop(at now: Date) {
        guard !isOver else { return }
        accumulated = elapsed(at: now)
        runningSince = nil
        stoppedAt = now
    }

    /// Stops a stopwatch left running until it reached `maxElapsed`, at that moment. True when it
    /// changed.
    @discardableResult
    public mutating func stopIfAtLimit(at now: Date) -> Bool {
        guard isRunning, elapsed(at: now) >= Self.maxElapsed, let since = runningSince else { return false }
        let limitReachedAt = since.addingTimeInterval(Self.maxElapsed - accumulated)
        stop(at: limitReachedAt)
        return true
    }

    /// "0:07", "12:07", "1:02:07": minutes and seconds, hours only when there are some.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3_600, minutes = (total % 3_600) / 60, rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// A reading in words, for what Doddy says: "12 minutes 7 seconds" / "12 minut 7 sekund".
    public static func spoken(_ seconds: TimeInterval, polish: Bool) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3_600, minutes = (total % 3_600) / 60, rest = total % 60
        var parts: [String] = []
        if polish {
            if hours > 0 { parts.append("\(hours) \(plural(hours, "godzina", "godziny", "godzin"))") }
            if minutes > 0 { parts.append("\(minutes) \(plural(minutes, "minuta", "minuty", "minut"))") }
            if rest > 0 || parts.isEmpty { parts.append("\(rest) \(plural(rest, "sekunda", "sekundy", "sekund"))") }
        } else {
            if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hour" : "hours")") }
            if minutes > 0 { parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")") }
            if rest > 0 || parts.isEmpty { parts.append("\(rest) \(rest == 1 ? "second" : "seconds")") }
        }
        return parts.joined(separator: " ")
    }

    private static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        if n == 1 { return one }
        let lastTwo = n % 100, last = n % 10
        return (2...4).contains(last) && !(12...14).contains(lastTwo) ? few : many
    }
}
