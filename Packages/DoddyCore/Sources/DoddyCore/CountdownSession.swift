import Foundation

/// A plain countdown (ADR-337): a kitchen timer ("pasta, 10 minutes", by voice or from Home) or
/// a short wind-down before sleep. Pure timing rules, tested on Linux; the app schedules the
/// "done" notification and the Live Activity from them, the same way as the focus timer
/// (`FocusSession`). Nothing here claims the user cooked or slept.
public struct CountdownSession: Codable, Equatable, Sendable {
    public enum Purpose: String, Codable, Equatable, Sendable {
        /// A kitchen or any other timer, with an optional label ("Pasta").
        case timer
        /// A quiet countdown before bed; made for StandBy. No label.
        case windDown
    }

    public enum State: Codable, Equatable, Sendable {
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
        /// The time ran out (`at` is when it was due, not when the app noticed).
        case finished(at: Date)
        case stopped(at: Date)
    }

    /// Minutes offered on the Home screen's timer; voice can ask for any length.
    public static let timerPresetMinutes = [3, 5, 10, 15]
    public static let windDownPresetMinutes = [5, 10, 15, 20]
    public static let minSeconds = 5
    public static let maxSeconds = 24 * 3600
    /// The label shows on the Lock Screen and island, so it is kept short.
    public static let maxLabelLength = 40

    public let id: UUID
    public let purpose: Purpose
    public let duration: TimeInterval
    /// What the user said or typed, trimmed; nil when empty. Never set for a wind-down.
    public let label: String?
    public let startedAt: Date
    public private(set) var state: State

    public init(seconds: Int, purpose: Purpose, label: String?, now: Date, id: UUID = UUID()) {
        let clamped = min(max(seconds, Self.minSeconds), Self.maxSeconds)
        self.id = id
        self.purpose = purpose
        duration = TimeInterval(clamped)
        self.label = purpose == .windDown ? nil : Self.cleanLabel(label)
        startedAt = now
        state = .running(endsAt: now.addingTimeInterval(TimeInterval(clamped)))
    }

    public static func cleanLabel(_ text: String?) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).joined(separator: " ")
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLabelLength))
    }

    /// The "done" notification's identifier: one per countdown, so Stop can cancel exactly it.
    public var notificationID: String { "doddy.countdown.\(id.uuidString)" }

    public static func isCountdown(notificationID: String) -> Bool { notificationID.hasPrefix("doddy.countdown.") }

    public var isRunning: Bool { if case .running = state { true } else { false } }
    public var isPaused: Bool { if case .paused = state { true } else { false } }
    public var isOver: Bool {
        switch state {
        case .finished, .stopped: true
        default: false
        }
    }

    public var endsAt: Date? { if case .running(let end) = state { end } else { nil } }

    public func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .running(let end): max(0, end.timeIntervalSince(now))
        case .paused(let left): left
        case .finished, .stopped: 0
        }
    }

    public mutating func pause(at now: Date) {
        guard case .running(let end) = state else { return }
        let left = end.timeIntervalSince(now)
        state = left > 0 ? .paused(remaining: left) : .finished(at: end)
    }

    public mutating func resume(at now: Date) {
        guard case .paused(let left) = state else { return }
        state = .running(endsAt: now.addingTimeInterval(left))
    }

    public mutating func stop(at now: Date) {
        guard !isOver else { return }
        if case .running(let end) = state, end <= now {
            state = .finished(at: end)
        } else {
            state = .stopped(at: now)
        }
    }

    /// Marks a running countdown finished once its end has passed. Returns true when it changed.
    @discardableResult
    public mutating func finishIfDue(at now: Date) -> Bool {
        guard case .running(let end) = state, end <= now else { return false }
        state = .finished(at: end)
        return true
    }

    /// "10 min", "1 h 30 min" or "45 s": the length as the screens and the island say it.
    public static func lengthText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return m > 0 ? "\(h) h \(m) min" : "\(h) h" }
        if m > 0 { return s > 0 && m < 5 ? "\(m) min \(s) s" : "\(m) min" }
        return "\(s) s"
    }

    /// The notification's words when the time runs out. English and Polish, like the other
    /// notifications (ADR-213). The label is the user's own words.
    public static func doneTitle(_ purpose: Purpose, _ language: NotificationLanguage) -> String {
        switch (purpose, language) {
        case (.timer, .english): "Timer done"
        case (.timer, .polish): "Minutnik: koniec"
        case (.windDown, .english): "Wind-down over"
        case (.windDown, .polish): "Wyciszenie dobiegło końca"
        }
    }

    public static func doneBody(_ purpose: Purpose, label: String?, _ language: NotificationLanguage) -> String {
        if purpose == .timer, let label { return label }
        switch (purpose, language) {
        case (.timer, .english): return "Your timer is done."
        case (.timer, .polish): return "Czas minął."
        case (.windDown, .english): return "Time to put the phone down."
        case (.windDown, .polish): return "Pora odłożyć telefon."
        }
    }
}
