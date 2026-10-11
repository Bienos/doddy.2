import Foundation

// Timers and alarms in the action status model (ADR-292, extends ADR-291). Like reminders and
// events, a timer or alarm Doddy couldn't confirm is checked before it is tried again, so asking
// again never sets a second one; "set" still comes only from the iPhone listing it afterwards.
//  - Alarms are for a time of day, so the same alarm twice is never wanted: Doddy always looks
//    at its own alarms first.
//  - Timers are for a length of time, and two identical timers can be wanted on purpose. Doddy
//    looks for a running copy only when an earlier try of the same timer is unconfirmed
//    (ActionRetry said checkFirst), and only for one started since that try.
// Plain Swift for the Linux tests. The iPhone side: DeviceConnections (timers) and
// AlarmScheduler (alarms).

// MARK: Timers

public enum TimerIdempotency {
    static let prefix = "doddy.timer."

    /// Same label (normalized) and length: the same timer.
    public static func key(_ draft: TimerDraft) -> String {
        "t1-" + ReminderIdempotency.fnv(ReminderIdempotency.normalizedTitle(draft.label ?? "") + "\u{1F}" + String(draft.seconds))
    }

    /// The notification's identifier carries the key, so a later look can tell which timer it is.
    public static func identifier(key: String, id: UUID) -> String { "\(prefix)\(key).\(id.uuidString)" }

    /// The key in a Doddy timer identifier; nil for timers set before ADR-292 and anything else.
    public static func key(fromIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(prefix) else { return nil }
        let rest = identifier.dropFirst(prefix.count)
        guard let dot = rest.firstIndex(of: "."), rest.hasPrefix("t1-") else { return nil }
        return String(rest[..<dot])
    }
}

/// A Doddy timer the iPhone still has waiting to ring.
public struct PendingTimer: Equatable, Sendable {
    public let identifier: String
    public let firesAt: Date

    public init(identifier: String, firesAt: Date) {
        self.identifier = identifier
        self.firesAt = firesAt
    }
}

/// The iPhone's timers, as starting one needs them. `DeviceConnections` implements it with
/// notifications; the tests use a fake.
@MainActor
public protocol TimerWriter: AnyObject {
    /// Doddy's timers still waiting to ring.
    func pendingTimers() async -> [PendingTimer]
    /// Schedules the timer under exactly this identifier. A throw does not prove nothing was scheduled.
    func scheduleTimer(_ draft: TimerDraft, identifier: String) async throws
}

public enum TimerStartOutcome: Equatable, Sendable {
    case started(PendingTimer)
    /// The earlier unconfirmed try is running after all; nothing new was started.
    case alreadyRunning(PendingTimer)
    /// Not started: the schedule failed and a fresh look shows it isn't waiting.
    case notStarted(String)
    /// Scheduled, or maybe, but the iPhone didn't list it afterwards.
    case unknown

    /// The iPhone was asked to schedule one.
    public var attemptedWrite: Bool {
        switch self {
        case .started, .notStarted, .unknown: true
        case .alreadyRunning: false
        }
    }
}

public enum TimerStartAction {
    /// `uncheckedSince`: when the earlier unconfirmed try of this timer was made, from
    /// `ActionRetryDecision.uncheckedSince`. Nil means start it, as asked.
    @MainActor
    public static func start(_ draft: TimerDraft, with writer: some TimerWriter, uncheckedSince since: Date?) async -> TimerStartOutcome {
        let key = TimerIdempotency.key(draft)
        if let since {
            // A copy started at or after that try rings at least `seconds` after it (5 s slack).
            let earliest = since.addingTimeInterval(TimeInterval(draft.seconds) - 5)
            let running = await writer.pendingTimers()
                .filter { TimerIdempotency.key(fromIdentifier: $0.identifier) == key && $0.firesAt >= earliest }
                .min { $0.firesAt < $1.firesAt }
            if let running { return .alreadyRunning(running) }
        }
        let identifier = TimerIdempotency.identifier(key: key, id: UUID())
        do {
            try await writer.scheduleTimer(draft, identifier: identifier)
        } catch {
            // It may still have gone in: look before answering.
            if let found = await writer.pendingTimers().first(where: { $0.identifier == identifier }) { return .started(found) }
            return .notStarted(describe(error, or: "The timer couldn't be set."))
        }
        guard let found = await writer.pendingTimers().first(where: { $0.identifier == identifier }) else { return .unknown }
        return .started(found)
    }
}

// MARK: Alarms

public enum AlarmIdempotency {
    /// Same label (normalized), time, and day or repeat: the same alarm.
    public static func key(_ draft: AlarmDraft) -> String {
        let when = draft.repeats.map { "\(draft.clock) \($0.rawValue)" } ?? draft.first.localText
        return "a1-" + ReminderIdempotency.fnv(ReminderIdempotency.normalizedTitle(draft.label ?? "") + "\u{1F}" + when)
    }

    /// The alarm Doddy already has that is this one: the same key, or for an alarm set before
    /// ADR-292 (no key), the same time, day and label as remembered.
    public static func existing(for draft: AlarmDraft, in alarms: [AlarmEntry]) -> AlarmEntry? {
        let key = key(draft)
        if let keyed = alarms.first(where: { $0.key == key }) { return keyed }
        return alarms.first { $0.key == nil && $0.summary == draft.summary && $0.label == draft.label }
    }
}

public enum AlarmScheduleAttempt: Equatable, Sendable {
    case scheduled
    /// iOS older than 26: no AlarmKit. Nothing was set.
    case needsNewerIOS
    /// The user said no to alarms. Nothing was set.
    case notAllowed
}

/// The iPhone's alarms, as setting one needs them. `AlarmScheduler` implements it with AlarmKit;
/// the tests use a fake.
@MainActor
public protocol AlarmWriter: AnyObject {
    /// Doddy's alarms the iPhone still lists, with what Doddy remembered about each.
    func alarms() -> [AlarmEntry]
    /// Every alarm id the iPhone lists for Doddy.
    func scheduledAlarmIDs() -> Set<UUID>
    /// Sets the alarm under exactly this id. A throw does not prove nothing was set.
    func scheduleAlarm(_ draft: AlarmDraft, id: UUID) async throws -> AlarmScheduleAttempt
    /// Keeps Doddy's note of an alarm (time, label, key), so it can be named and found later.
    func remember(_ alarm: AlarmEntry)
    func forget(_ id: UUID)
}

public enum AlarmSetOutcome: Equatable, Sendable {
    case set(AlarmEntry)
    /// The same alarm was already set (an earlier tap or an unconfirmed try); nothing new was set.
    case alreadySet(AlarmEntry)
    case notSet(String)
    case needsNewerIOS
    case notAllowed
    /// Set, or maybe, but the iPhone didn't list it afterwards.
    case unknown
    case needsClarification(ReminderClarification)

    /// The iPhone was asked to set one.
    public var attemptedWrite: Bool {
        switch self {
        case .set, .notSet, .unknown: true
        case .alreadySet, .needsNewerIOS, .notAllowed, .needsClarification: false
        }
    }
}

public enum AlarmSetAction {
    /// Runs after the user tapped Set alarm. Looks first, so asking again never sets a second
    /// one, and says "set" only when the iPhone lists it.
    @MainActor
    public static func set(_ draft: AlarmDraft, with writer: some AlarmWriter, now: Date) async -> AlarmSetOutcome {
        // A one-off time may have passed while the card waited.
        if draft.repeats == nil, let late = ReminderDueRules.passed(draft.first, now: now) { return .needsClarification(late) }
        if let same = AlarmIdempotency.existing(for: draft, in: writer.alarms()) { return .alreadySet(same) }

        let entry = AlarmEntry(
            id: UUID(), clock: draft.clock, label: draft.label, summary: draft.summary, key: AlarmIdempotency.key(draft))
        // Noted before it is set: if the iPhone lists it only later, a retry still finds it.
        writer.remember(entry)
        let attempt: AlarmScheduleAttempt
        do {
            attempt = try await writer.scheduleAlarm(draft, id: entry.id)
        } catch {
            if writer.scheduledAlarmIDs().contains(entry.id) { return .set(entry) }
            writer.forget(entry.id)
            return .notSet(describe(error, or: "The alarm couldn't be set."))
        }
        switch attempt {
        case .needsNewerIOS:
            writer.forget(entry.id)
            return .needsNewerIOS
        case .notAllowed:
            writer.forget(entry.id)
            return .notAllowed
        case .scheduled:
            return writer.scheduledAlarmIDs().contains(entry.id) ? .set(entry) : .unknown
        }
    }
}

private func describe(_ error: Error, or fallback: String) -> String {
    if let described = (error as? LocalizedError)?.errorDescription, !described.isEmpty { return described }
    return fallback
}

// MARK: Replies, receipts, keys

extension ActionRetryDecision {
    /// When the earlier unconfirmed try was made; nil unless Doddy must check first.
    public var uncheckedSince: Date? {
        if case .checkFirst(let since) = self { return since }
        return nil
    }
}

extension VoiceToolReply {
    public static func timer(_ outcome: TimerStartOutcome, draft: TimerDraft, calendar: Calendar) -> String {
        switch outcome {
        case .started(let timer):
            return timerAdded(draft, endsAt: timer.firesAt, calendar: calendar)
        case .alreadyRunning(let timer):
            let what = draft.label.map { "\"\($0)\", " } ?? ""
            return "added: timer \(what)\(durationText(draft.seconds)) was already running from the earlier try and rings at \(localText(timer.firesAt, hasTime: true, calendar: calendar)), so Doddy did not start a second one."
        case .notStarted(let reason):
            return "failed: \(reason) Nothing was set."
        case .unknown:
            return "unknown: the iPhone didn't confirm the timer. It may not be running. Tell the user. If they ask to try again, call \(VoiceToolName.setTimer) again: Doddy checks for it first and will not start a second one."
        }
    }

    public static func alarm(_ outcome: AlarmSetOutcome) -> String {
        switch outcome {
        case .set(let alarm), .alreadySet(let alarm):
            let what = alarm.label.map { "\"\($0)\" " } ?? ""
            if case .alreadySet = outcome {
                return "added: alarm \(what)at \(alarm.summary) was already set, so Doddy did not set a second one."
            }
            return "added: alarm \(what)at \(alarm.summary). It rings even in Silent mode or a Focus. Checked."
        case .notSet(let reason): return "failed: \(reason) Nothing was set."
        case .needsNewerIOS: return alarmNeedsNewerIOS
        case .notAllowed: return alarmNotAllowed
        case .unknown:
            return "unknown: the iPhone didn't confirm the alarm. It may not be set. Tell the user. If they ask to try again, call \(VoiceToolName.setAlarm) again: Doddy checks its alarms first and will not set a second one."
        case .needsClarification(let question): return clarification(question, tool: VoiceToolName.setAlarm)
        }
    }
}

extension ActivityReceipt {
    /// From a timer the iPhone lists as waiting.
    public init(timer: PendingTimer, draft: TimerDraft, calendar: Calendar, readAt: Date) {
        self.init(
            app: .timers, externalID: timer.identifier,
            lines: (draft.label.map { ["“\($0)”"] } ?? []) + [
                VoiceToolReply.durationText(draft.seconds),
                "Rings at \(VoiceToolReply.localText(timer.firesAt, hasTime: true, calendar: calendar))",
            ],
            readAt: readAt)
    }

    /// From an alarm the iPhone lists.
    public init(alarm: AlarmEntry, readAt: Date) {
        self.init(
            app: .timers, externalID: alarm.id.uuidString,
            lines: (alarm.label.map { ["“\($0)”"] } ?? []) + ["Alarm \(alarm.summary)"], readAt: readAt)
    }
}
