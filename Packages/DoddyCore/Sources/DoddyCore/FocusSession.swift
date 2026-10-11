import Foundation

/// A focus timer (owner choice 2026-10-10: presets plus an optional line you type; ADR-241).
/// Pure timing rules, so they are tested on Linux; the app schedules the "time's up"
/// notification and the Live Activity from them. Nothing here claims the user focused.
public struct FocusSession: Codable, Equatable, Sendable {
    public enum State: Codable, Equatable, Sendable {
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
        /// The time ran out (`at` is when it was due, not when the app noticed).
        case finished(at: Date)
        case stopped(at: Date)
    }

    /// Minutes offered on the start screen (the board's example is 25).
    public static let presetMinutes = [15, 25, 45]
    /// The optional line is shown on the Lock Screen and island, so it is kept short.
    public static let maxLabelLength = 60

    public let id: UUID
    public let duration: TimeInterval
    /// What the user typed, trimmed; nil when empty.
    public let label: String?
    public let startedAt: Date
    public private(set) var state: State

    public init(minutes: Int, label: String?, now: Date, id: UUID = UUID()) {
        let clamped = min(max(minutes, 1), 180)
        self.id = id
        duration = TimeInterval(clamped * 60)
        self.label = Self.cleanLabel(label)
        startedAt = now
        state = .running(endsAt: now.addingTimeInterval(TimeInterval(clamped * 60)))
    }

    public static func cleanLabel(_ text: String?) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).joined(separator: " ")
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLabelLength))
    }

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

    /// Share of the time still left, 1 at the start and 0 at the end.
    public func fractionLeft(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, remaining(at: now) / duration))
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

    /// Marks a running session finished once its end has passed. Returns true when it changed.
    @discardableResult
    public mutating func finishIfDue(at now: Date) -> Bool {
        guard case .running(let end) = state, end <= now else { return false }
        state = .finished(at: end)
        return true
    }
}

/// A short guided breathing exercise (owner choice 2026-10-10: in the app; ADR-242). In 4 s,
/// out 6 s, for 1, 2 or 3 minutes. The phase is worked out from the clock, so the screen can
/// redraw at any moment and stay right; the island shows only the time left, because it can't
/// switch phases while the app is not running.
public struct BreathingSession: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case breatheIn, breatheOut
    }

    public static let presetMinutes = [1, 2, 3]
    public static let inhale: TimeInterval = 4
    public static let exhale: TimeInterval = 6
    public static var cycle: TimeInterval { inhale + exhale }

    public let startedAt: Date
    public let duration: TimeInterval

    public init(minutes: Int, now: Date) {
        startedAt = now
        duration = TimeInterval(min(max(minutes, 1), 10) * 60)
    }

    public var endsAt: Date { startedAt.addingTimeInterval(duration) }

    public func isOver(at now: Date) -> Bool { now >= endsAt }

    public func remaining(at now: Date) -> TimeInterval { max(0, endsAt.timeIntervalSince(now)) }

    /// The phase at `now`, how far through it (0…1) and the seconds left in it.
    public func phase(at now: Date) -> (phase: Phase, progress: Double, secondsLeft: TimeInterval) {
        let elapsed = min(max(0, now.timeIntervalSince(startedAt)), duration)
        let inCycle = elapsed.truncatingRemainder(dividingBy: Self.cycle)
        if inCycle < Self.inhale {
            return (.breatheIn, inCycle / Self.inhale, Self.inhale - inCycle)
        }
        let out = inCycle - Self.inhale
        return (.breatheOut, out / Self.exhale, Self.exhale - out)
    }

    /// Completed in/out cycles so far.
    public func cyclesDone(at now: Date) -> Int {
        let elapsed = min(max(0, now.timeIntervalSince(startedAt)), duration)
        return Int(elapsed / Self.cycle)
    }
}
