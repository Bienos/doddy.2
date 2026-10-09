import Foundation

// Local "before this event" nudges (V4a). Scheduled on the iPhone with UserNotifications;
// no server is involved. A nudge counts as scheduled only after the pending request was read
// back from the notification centre.

public enum NudgeAuthorization: Equatable, Sendable {
    case notDetermined, denied, authorized
}

public enum NudgePlanError: Error, Equatable, Sendable {
    case leadTimeInvalid
    case fireTimeInPast
}

public enum NudgeError: Error, Equatable, Sendable {
    /// Notifications are off for Doddy in iOS Settings.
    case notAuthorized
    /// iOS accepted the request but it was not in the pending list afterwards.
    case unverified
}

/// Deterministic plan for one nudge. The identifier is derived from the event and lead time,
/// so scheduling the same nudge twice replaces it instead of duplicating it.
public struct EventNudgePlan: Equatable, Sendable {
    public static let leadMinuteOptions = [10, 30, 60]

    public let eventID: String
    public let eventTitle: String
    public let eventStart: Date
    public let leadMinutes: Int
    public let fireAt: Date

    public init(event: CalendarEvent, leadMinutes: Int, now: Date) throws(NudgePlanError) {
        guard leadMinutes > 0 else { throw .leadTimeInvalid }
        let fireAt = event.start.addingTimeInterval(-Double(leadMinutes) * 60)
        guard fireAt > now else { throw .fireTimeInPast }
        self.eventID = event.id
        self.eventTitle = event.title
        self.eventStart = event.start
        self.leadMinutes = leadMinutes
        self.fireAt = fireAt
    }

    public static func identifier(eventID: String, leadMinutes: Int) -> String {
        "nudge.event.\(eventID).\(leadMinutes)"
    }

    public var identifier: String { Self.identifier(eventID: eventID, leadMinutes: leadMinutes) }

    public var notificationTitle: String { "Doddy" }

    public var notificationBody: String {
        "\(eventTitle) starts \(Self.leadText(leadMinutes)) (\(eventStart.formatted(date: .omitted, time: .shortened)))."
    }

    public static func leadText(_ minutes: Int) -> String {
        switch minutes {
        case 60: "in 1 hour"
        case let m where m % 60 == 0: "in \(m / 60) hours"
        default: "in \(minutes) minutes"
        }
    }
}

/// A nudge read back from the notification centre (what will actually fire).
public struct ScheduledNudge: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    public let fireAt: Date?

    public init(id: String, title: String, body: String, fireAt: Date?) {
        self.id = id
        self.title = title
        self.body = body
        self.fireAt = fireAt
    }

    private static let eventPrefix = "nudge.event."

    /// Event identifier encoded in the nudge identifier, if it is an event nudge.
    public var eventID: String? {
        guard id.hasPrefix(Self.eventPrefix), let dot = id.lastIndex(of: ".") else { return nil }
        let start = id.index(id.startIndex, offsetBy: Self.eventPrefix.count)
        guard start < dot else { return nil }
        return String(id[start..<dot])
    }

    /// Lead time encoded in the nudge identifier, if it is an event nudge.
    public var leadMinutes: Int? {
        guard eventID != nil, let dot = id.lastIndex(of: ".") else { return nil }
        return Int(id[id.index(after: dot)...])
    }

    /// Whether this nudge still fits the event it was set for; `nil` if it is for another event.
    public func matches(_ event: CalendarEvent) -> Bool? {
        guard event.id == eventID, let leadMinutes, let fireAt else { return nil }
        let expected = event.start.addingTimeInterval(-Double(leadMinutes) * 60)
        return abs(expected.timeIntervalSince(fireAt)) < 60
    }
}

public protocol NudgeScheduler: Sendable {
    func authorization() async -> NudgeAuthorization
    func requestAuthorization() async throws -> NudgeAuthorization
    /// Returns only after the request was read back from the pending list.
    func schedule(_ plan: EventNudgePlan) async throws -> ScheduledNudge
    func pending() async throws -> [ScheduledNudge]
    func cancel(id: String) async throws
}

public struct UnavailableNudgeScheduler: NudgeScheduler {
    public init() {}
    public func authorization() async -> NudgeAuthorization { .notDetermined }
    public func requestAuthorization() async throws -> NudgeAuthorization { throw DoddyError.capabilityUnavailable(.localNudges) }
    public func schedule(_ plan: EventNudgePlan) async throws -> ScheduledNudge { throw DoddyError.capabilityUnavailable(.localNudges) }
    public func pending() async throws -> [ScheduledNudge] { throw DoddyError.capabilityUnavailable(.localNudges) }
    public func cancel(id: String) async throws { throw DoddyError.capabilityUnavailable(.localNudges) }
}
