import Foundation

// Connections (V4a): things on this iPhone that Doddy may use once the user connects them.
// A connection is "Connected" only after a real read succeeded; reads may run automatically
// once connected, writes always go through a proposal → confirmation → verified receipt.
// See docs/research/CONNECTIONS_AND_PROACTIVE_DODDY_2026-10.md §3.

public enum ConnectionKind: String, CaseIterable, Codable, Sendable {
    case calendar, reminders, contacts
}

/// What iOS reports for a permission. Mirrors EventKit/Contacts statuses without importing them.
public enum SystemAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    /// EventKit write-only: can add items, cannot read them back (so cannot verify).
    case writeOnly
    case fullAccess

    public var allowsReading: Bool { self == .fullAccess }
    public var allowsWriting: Bool { self == .fullAccess || self == .writeOnly }
}

/// Proof that a real read succeeded after authorization.
public struct ConnectionVerification: Equatable, Sendable {
    public let verifiedAt: Date
    /// Human-readable evidence, e.g. "read 4 calendars and 3 events".
    public let evidence: String

    public init(verifiedAt: Date, evidence: String) {
        self.verifiedAt = verifiedAt
        self.evidence = evidence
    }
}

public enum ConnectionStatus: Equatable, Sendable {
    /// The user has not switched this connection on in Doddy.
    case off
    /// Switched on, iOS has not been asked yet.
    case notConnected
    /// iOS permission denied or restricted; only the Settings app can change it.
    case denied
    /// Permission granted but no successful read yet (or write-only access).
    case authorizedUnverified
    case connected(ConnectionVerification)
    case error(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Session state of one connection. `status` is derived, never stored: "Connected" cannot be
/// claimed without `enabled`, a reading authorization and a verification.
public struct ConnectionState: Equatable, Sendable {
    public let kind: ConnectionKind
    /// The user's in-app switch ("Doddy may use Calendar"). Off by default.
    public var enabled: Bool
    public var authorization: SystemAuthorization
    public var verification: ConnectionVerification?
    public var lastError: String?

    public init(
        kind: ConnectionKind, enabled: Bool = false, authorization: SystemAuthorization = .notDetermined,
        verification: ConnectionVerification? = nil, lastError: String? = nil
    ) {
        self.kind = kind
        self.enabled = enabled
        self.authorization = authorization
        self.verification = verification
        self.lastError = lastError
    }

    public var status: ConnectionStatus {
        guard enabled else { return .off }
        switch authorization {
        case .notDetermined: return .notConnected
        case .denied, .restricted: return .denied
        case .writeOnly, .fullAccess:
            if let lastError { return .error(lastError) }
            guard let verification else { return .authorizedUnverified }
            return .connected(verification)
        }
    }

    /// Reads are allowed only for a verified, full-access connection.
    public var canRead: Bool { status.isConnected && authorization.allowsReading }
    public var canWrite: Bool { enabled && authorization.allowsWriting && lastError == nil }
}

// MARK: Calendar

public struct CalendarInfo: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let allowsWrites: Bool

    public init(id: String, title: String, allowsWrites: Bool) {
        self.id = id
        self.title = title
        self.allowsWrites = allowsWrites
    }
}

public struct CalendarEvent: Equatable, Sendable, Identifiable {
    public let id: String
    public let calendarTitle: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?

    public init(id: String, calendarTitle: String, title: String, start: Date, end: Date, isAllDay: Bool, location: String? = nil) {
        self.id = id
        self.calendarTitle = calendarTitle
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
    }
}

public enum ConnectionDraftError: Error, Equatable, Sendable {
    case emptyTitle
    case endBeforeStart
}

/// A validated request to add an event. Nothing is written until the user confirms it.
public struct EventDraft: Equatable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
    public let notes: String?

    public init(title: String, start: Date, end: Date? = nil, isAllDay: Bool = false, location: String? = nil, notes: String? = nil) throws(ConnectionDraftError) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyTitle }
        let resolvedEnd = end ?? start.addingTimeInterval(isAllDay ? 0 : 3600)
        guard resolvedEnd >= start else { throw .endBeforeStart }
        self.title = trimmed
        self.start = start
        self.end = resolvedEnd
        self.isAllDay = isAllDay
        self.location = location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.notes = notes?.nilIfEmpty
    }
}

// MARK: Reminders

public struct ReminderDraft: Equatable, Sendable {
    public let title: String
    public let due: Date?
    /// False for a due *day* without a time: no alarm is set in that case.
    public let dueIncludesTime: Bool
    public let notes: String?

    public init(title: String, due: Date? = nil, dueIncludesTime: Bool = true, notes: String? = nil) throws(ConnectionDraftError) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyTitle }
        self.title = trimmed
        self.due = due
        self.dueIncludesTime = due == nil ? false : dueIncludesTime
        self.notes = notes?.nilIfEmpty
    }
}

public struct ReminderItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let due: Date?
    public let dueIncludesTime: Bool
    public let listTitle: String

    public init(id: String, title: String, due: Date?, dueIncludesTime: Bool, listTitle: String) {
        self.id = id
        self.title = title
        self.due = due
        self.dueIncludesTime = due == nil ? false : dueIncludesTime
        self.listTitle = listTitle
    }
}

// MARK: Contacts

public struct ContactMatch: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let phoneNumbers: [String]
    public let emailAddresses: [String]

    public init(id: String, displayName: String, phoneNumbers: [String], emailAddresses: [String]) {
        self.id = id
        self.displayName = displayName
        self.phoneNumbers = phoneNumbers
        self.emailAddresses = emailAddresses
    }
}

// MARK: Ports

public enum ConnectionError: Error, Equatable, Sendable {
    case notAuthorized(ConnectionKind)
    /// The write was sent but the item could not be read back. Outcome is unknown, not failed.
    case unverified(ConnectionKind)
    case noWritableCalendar
    case failed(String)
}

public protocol CalendarGateway: Sendable {
    func authorization() -> SystemAuthorization
    func requestAccess() async throws -> SystemAuthorization
    func calendars() async throws -> [CalendarInfo]
    func events(from start: Date, to end: Date) async throws -> [CalendarEvent]
    /// Returns only after the saved event was read back by its identifier.
    func createEvent(_ draft: EventDraft) async throws -> CalendarEvent
}

public protocol RemindersGateway: Sendable {
    func authorization() -> SystemAuthorization
    func requestAccess() async throws -> SystemAuthorization
    /// Titles of the reminder lists; used as the verified read after connecting.
    func listTitles() async throws -> [String]
    /// Incomplete reminders, optionally only those due before `dueBefore`.
    func incompleteReminders(dueBefore: Date?) async throws -> [ReminderItem]
    /// Returns only after the saved reminder was read back by its identifier.
    func createReminder(_ draft: ReminderDraft) async throws -> ReminderItem
}

public protocol ContactsGateway: Sendable {
    func authorization() -> SystemAuthorization
    func requestAccess() async throws -> SystemAuthorization
    /// Number of contact accounts (containers); this verified read reads no person's details.
    func accountCount() async throws -> Int
    func lookup(name: String) async throws -> [ContactMatch]
}

public struct UnavailableCalendarGateway: CalendarGateway {
    public init() {}
    public func authorization() -> SystemAuthorization { .notDetermined }
    public func requestAccess() async throws -> SystemAuthorization { throw DoddyError.capabilityUnavailable(.calendar) }
    public func calendars() async throws -> [CalendarInfo] { throw DoddyError.capabilityUnavailable(.calendar) }
    public func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { throw DoddyError.capabilityUnavailable(.calendar) }
    public func createEvent(_ draft: EventDraft) async throws -> CalendarEvent { throw DoddyError.capabilityUnavailable(.calendar) }
}

public struct UnavailableRemindersGateway: RemindersGateway {
    public init() {}
    public func authorization() -> SystemAuthorization { .notDetermined }
    public func requestAccess() async throws -> SystemAuthorization { throw DoddyError.capabilityUnavailable(.reminders) }
    public func listTitles() async throws -> [String] { throw DoddyError.capabilityUnavailable(.reminders) }
    public func incompleteReminders(dueBefore: Date?) async throws -> [ReminderItem] { throw DoddyError.capabilityUnavailable(.reminders) }
    public func createReminder(_ draft: ReminderDraft) async throws -> ReminderItem { throw DoddyError.capabilityUnavailable(.reminders) }
}

public struct UnavailableContactsGateway: ContactsGateway {
    public init() {}
    public func authorization() -> SystemAuthorization { .notDetermined }
    public func requestAccess() async throws -> SystemAuthorization { throw DoddyError.capabilityUnavailable(.contacts) }
    public func accountCount() async throws -> Int { throw DoddyError.capabilityUnavailable(.contacts) }
    public func lookup(name: String) async throws -> [ContactMatch] { throw DoddyError.capabilityUnavailable(.contacts) }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
