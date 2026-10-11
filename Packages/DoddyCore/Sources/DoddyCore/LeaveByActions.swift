import Foundation

// "Remind me when to leave" in the action status model (extends ADR-319/320 to ADR-335's tool).
// Two reminders to leave for the same place at the same time are never wanted, so Doddy always
// looks first, as for alarms: one of its pending leave reminders with the same key counts as
// already set. A new one is scheduled under an identifier that carries the key, and is "set"
// only when iOS lists it; after an error, a listed one still counts as set. There is no 3-try
// stop: it would ask the user to look for the reminder, and a waiting one shows nowhere.

public enum LeaveByIdempotency {
    static let prefix = "doddy.leaveBy."

    /// Same place (normalized), arrival minute and way of travel: the same reminder. The spare
    /// minutes don't change which trip it is.
    public static func key(_ request: LeaveByRequest) -> String {
        let minute = Int((request.arriveBy.timeIntervalSince1970 / 60).rounded(.down))
        return "l1-" + ReminderIdempotency.fnv(
            ReminderIdempotency.normalizedTitle(request.place) + "\u{1F}" + String(minute) + "\u{1F}" + request.mode.rawValue)
    }

    public static func identifier(key: String, id: UUID) -> String { "\(prefix)\(key).\(id.uuidString)" }

    /// The key in a Doddy leave identifier; nil for ones set before this and anything else.
    public static func key(fromIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(prefix) else { return nil }
        let rest = identifier.dropFirst(prefix.count)
        guard let dot = rest.firstIndex(of: "."), rest.hasPrefix("l1-") else { return nil }
        return String(rest[..<dot])
    }
}

/// A Doddy leave reminder the iPhone still has waiting.
public struct PendingLeaveBy: Equatable, Sendable {
    public let identifier: String
    /// When iOS will show it, as iOS lists it.
    public let firesAt: Date?

    public init(identifier: String, firesAt: Date?) {
        self.identifier = identifier
        self.firesAt = firesAt
    }
}

/// The iPhone's notifications, as a leave reminder needs them. `LeaveByScheduler` implements it;
/// the tests use a fake.
@MainActor
public protocol LeaveByWriter: AnyObject {
    /// Asks once if iOS hasn't asked yet; false when notifications are off for Doddy.
    func notificationsAllowed() async -> Bool
    /// Doddy's leave reminders still waiting.
    func pendingLeaveBys() async -> [PendingLeaveBy]
    /// Schedules it under exactly this identifier. A throw does not prove nothing was scheduled.
    func scheduleLeaveBy(_ plan: LeaveByPlan, identifier: String) async throws
}

public enum LeaveBySetOutcome: Equatable, Sendable {
    case set(PendingLeaveBy)
    /// The same reminder was already waiting (an earlier try); nothing new was set.
    case alreadySet(PendingLeaveBy)
    case notAllowed
    /// Not set: the schedule failed and a fresh look shows it isn't waiting.
    case notSet
    /// Scheduled, or maybe, but the iPhone didn't list it afterwards.
    case unknown

    /// The iPhone was asked to schedule one.
    public var attemptedWrite: Bool {
        switch self {
        case .set, .notSet, .unknown: true
        case .alreadySet, .notAllowed: false
        }
    }
}

public enum LeaveBySetAction {
    @MainActor
    public static func set(_ plan: LeaveByPlan, with writer: some LeaveByWriter) async -> LeaveBySetOutcome {
        guard await writer.notificationsAllowed() else { return .notAllowed }
        let key = LeaveByIdempotency.key(plan.request)
        if let same = await writer.pendingLeaveBys().first(where: { LeaveByIdempotency.key(fromIdentifier: $0.identifier) == key }) {
            return .alreadySet(same)
        }
        let identifier = LeaveByIdempotency.identifier(key: key, id: UUID())
        do {
            try await writer.scheduleLeaveBy(plan, identifier: identifier)
        } catch {
            // It may still have gone in: look before answering.
            if let found = await writer.pendingLeaveBys().first(where: { $0.identifier == identifier }) { return .set(found) }
            return .notSet
        }
        guard let found = await writer.pendingLeaveBys().first(where: { $0.identifier == identifier }) else { return .unknown }
        return .set(found)
    }
}

extension VoiceToolReply {
    public static func leaveBy(_ outcome: LeaveBySetOutcome, plan: LeaveByPlan, calendar: Calendar) -> String {
        switch outcome {
        case .set: return leaveBySet(plan, calendar: calendar)
        case .alreadySet:
            return "added: a reminder to leave at \(LeaveBy.clock(plan.leaveAt, calendar: calendar)) for \(plan.placeName) was already set, so Doddy did not set a second one."
        case .notAllowed: return leaveByNotAllowed
        case .notSet: return leaveByFailed
        case .unknown:
            return "unknown: the iPhone didn't confirm the reminder to leave. It may not be set. Tell the user. If they ask to try again, call \(VoiceToolName.remindWhenToLeave) again: Doddy checks for it first and will not set a second one."
        }
    }
}

extension ActivityReceipt {
    /// From a leave reminder the iPhone lists: when it shows, where to, and the arrival time.
    public init(leaveBy pending: PendingLeaveBy, plan: LeaveByPlan, calendar: Calendar, readAt: Date) {
        let at = pending.firesAt ?? plan.leaveAt
        self.init(
            app: .maps, externalID: pending.identifier,
            lines: [
                "Leave at \(LeaveBy.clock(at, calendar: calendar)), \(LeaveBy.day(at, calendar: calendar))",
                "Place: \(plan.placeName)",
                "Arrive by \(LeaveBy.clock(plan.request.arriveBy, calendar: calendar))",
            ],
            readAt: readAt)
    }
}
