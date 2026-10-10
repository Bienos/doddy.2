import Foundation

// M4: one reliable action, Apple Reminders (docs/architecture/TOOLS_AND_ACTIONS.md).
// A proposal authorises nothing. The user reviews and confirms on screen; the pending state is
// stored before the external write; success is claimed only after reading the reminder back.

/// A due date in the user's own time zone. `hour == nil` means a date without a time.
public struct ReminderDue: Equatable, Hashable, Sendable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int?
    public let minute: Int?
    public let timeZoneID: String

    public init(year: Int, month: Int, day: Int, hour: Int? = nil, minute: Int? = nil, timeZoneID: String) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.timeZoneID = timeZoneID
    }

    public init(date: Date, includesTime: Bool, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!,
                  hour: includesTime ? c.hour : nil, minute: includesTime ? c.minute : nil, timeZoneID: timeZone.identifier)
    }

    public var hasTime: Bool { hour != nil }

    /// Same due as confirmed? Date-only reminders compare by calendar day (Reminders may drop
    /// their time zone); timed ones by the actual instant.
    public static func same(_ a: ReminderDue?, _ b: ReminderDue?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?):
            guard a.hasTime == b.hasTime else { return false }
            if !a.hasTime { return (a.year, a.month, a.day) == (b.year, b.month, b.day) }
            guard let x = a.instant, let y = b.instant else { return false }
            return x == y
        default: return false
        }
    }

    public var timeZone: TimeZone? { TimeZone(identifier: timeZoneID) }

    public var dateComponents: DateComponents {
        DateComponents(timeZone: timeZone, year: year, month: month, day: day, hour: hour, minute: minute)
    }

    /// The instant it falls due (start of day for date-only), or nil if the date doesn't exist.
    public var instant: Date? {
        guard let tz = timeZone else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        var c = DateComponents(year: year, month: month, day: day, hour: hour ?? 0, minute: minute ?? 0)
        c.calendar = calendar
        guard c.isValidDate(in: calendar), let date = calendar.date(from: c) else { return nil }
        // Rejects times skipped by a DST change (the calendar would silently move them).
        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard back.year == year, back.month == month, back.day == day,
              back.hour == (hour ?? 0), back.minute == (minute ?? 0) else { return nil }
        return date
    }
}

public enum ReminderDueParse: Equatable, Sendable {
    case none
    case due(ReminderDue)
    /// Shown to the user, who must pick the date on screen. Never guessed.
    case needsClarification(String)
}

public enum ReminderDueInput {
    /// Accepts only a local date ("2026-10-11") or a local date and time ("2026-10-11T17:30").
    /// Anything else (words, offsets, "Z", impossible or past dates) needs the user to choose.
    public static func parse(_ text: String?, timeZoneID: String, now: Date) -> ReminderDueParse {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return .none }
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::\d{2})?)?$"#
        guard let match = raw.range(of: pattern, options: .regularExpression), match == raw.startIndex..<raw.endIndex else {
            return .needsClarification("Please choose the date and time.")
        }
        let digits = raw.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        let due = ReminderDue(
            year: digits[0], month: digits[1], day: digits[2],
            hour: digits.count >= 5 ? digits[3] : nil, minute: digits.count >= 5 ? digits[4] : nil,
            timeZoneID: timeZoneID)
        guard let tz = due.timeZone, let instant = due.instant else {
            return .needsClarification("That date or time doesn't exist. Please choose it.")
        }
        let passed = due.hasTime ? instant <= now : instant < startOfDay(now, in: tz)
        if passed { return .needsClarification("That time has already passed. Please choose a new one.") }
        return .due(due)
    }

    private static func startOfDay(_ date: Date, in tz: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        return calendar.startOfDay(for: date)
    }
}

public struct ReminderPayload: Equatable, Sendable, Codable {
    public var title: String
    public var notes: String?
    public var due: ReminderDue?
    /// Apple Reminders list (calendar) identifier; nil = the user's default list.
    public var listID: String?

    public init(title: String, notes: String? = nil, due: ReminderDue? = nil, listID: String? = nil) {
        self.title = title
        self.notes = notes
        self.due = due
        self.listID = listID
    }

    public static let maxTitle = 300

    /// Stable JSON (sorted keys) stored with the action, so the confirmed payload is the one written.
    public func canonicalJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

public enum ActionState: String, Codable, Sendable, CaseIterable {
    case drafted
    case needsClarification = "needs_clarification"
    case readyForConfirmation = "ready_for_confirmation"
    case userConfirmed = "user_confirmed"
    case pendingExternalWrite = "pending_external_write"
    case verifiedSucceeded = "verified_succeeded"
    case verifiedFailed = "verified_failed"
    case unknownOutcome = "unknown_outcome"

    /// The allowed edges of the state machine. Anything else is a bug and is refused.
    public func canMove(to next: ActionState) -> Bool {
        switch (self, next) {
        case (.drafted, .needsClarification), (.drafted, .readyForConfirmation),
             (.needsClarification, .readyForConfirmation),
             (.readyForConfirmation, .needsClarification), (.readyForConfirmation, .userConfirmed),
             (.userConfirmed, .pendingExternalWrite), (.userConfirmed, .verifiedFailed),
             (.pendingExternalWrite, .verifiedSucceeded), (.pendingExternalWrite, .verifiedFailed),
             (.pendingExternalWrite, .unknownOutcome),
             (.unknownOutcome, .verifiedSucceeded), (.unknownOutcome, .pendingExternalWrite),
             (.unknownOutcome, .unknownOutcome),
             // Retry is allowed only from a failure where nothing was written.
             (.verifiedFailed, .userConfirmed):
            return true
        default:
            return false
        }
    }
}

public struct ReminderAction: Equatable, Sendable, Identifiable {
    public let operationID: UUID
    public private(set) var state: ActionState
    public var payload: ReminderPayload
    public private(set) var externalID: String?
    public private(set) var errorCode: String?
    public let sourceMemoryID: UUID?
    public let createdAt: Date
    public private(set) var updatedAt: Date
    public private(set) var verifiedAt: Date?

    public var id: UUID { operationID }

    public init(operationID: UUID, state: ActionState, payload: ReminderPayload, externalID: String? = nil,
                errorCode: String? = nil, sourceMemoryID: UUID? = nil, createdAt: Date, updatedAt: Date, verifiedAt: Date? = nil) {
        self.operationID = operationID
        self.state = state
        self.payload = payload
        self.externalID = externalID
        self.errorCode = errorCode
        self.sourceMemoryID = sourceMemoryID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.verifiedAt = verifiedAt
    }

    /// Marker stored on the Apple reminder (its URL field) to find it again after a crash.
    public var marker: URL { URL(string: "doddy://reminder/\(operationID.uuidString.lowercased())")! }

    public mutating func move(to next: ActionState, at date: Date, externalID: String? = nil, errorCode: String? = nil) throws {
        guard state.canMove(to: next) else { throw ReminderError.invalidTransition(from: state, to: next) }
        state = next
        updatedAt = date
        self.errorCode = errorCode
        if let externalID { self.externalID = externalID }
        if next == .verifiedSucceeded { verifiedAt = date }
    }
}

public enum ReminderError: Error, Equatable, Sendable {
    case emptyTitle
    case titleTooLong
    case dueInvalid(String)
    case invalidTransition(from: ActionState, to: ActionState)
    case notFound
}

public enum RemindersAccess: Equatable, Sendable {
    case granted, denied, notDetermined
}

/// What Apple Reminders holds for a reminder, read back after writing.
public struct ExternalReminder: Equatable, Sendable {
    public let id: String
    public let title: String
    public let due: ReminderDue?
    public let listTitle: String

    public init(id: String, title: String, due: ReminderDue?, listTitle: String) {
        self.id = id
        self.title = title
        self.due = due
        self.listTitle = listTitle
    }
}

/// The app's EventKit adapter implements this; tests use a fake.
public protocol ReminderGateway: Sendable {
    func access() async -> RemindersAccess
    /// Shows the system prompt (only when the user is creating a reminder).
    func requestAccess() async throws -> Bool
    func create(_ payload: ReminderPayload, marker: URL) async throws -> String
    func fetch(id: String) async throws -> ExternalReminder?
    func find(marker: URL) async throws -> ExternalReminder?
}

/// Durable record of reminder actions (SQLite in the app).
public protocol ReminderActionStore: Sendable {
    func get(_ operationID: UUID) async throws -> ReminderAction?
    /// Inserts or replaces the row; returns only after the write is committed and read back.
    func put(_ action: ReminderAction) async throws
    func recent(limit: Int) async throws -> [ReminderAction]
    func inStates(_ states: [ActionState]) async throws -> [ReminderAction]
}

public struct UnavailableReminderGateway: ReminderGateway {
    public init() {}
    public func access() async -> RemindersAccess { .denied }
    public func requestAccess() async throws -> Bool { false }
    public func create(_ payload: ReminderPayload, marker: URL) async throws -> String { throw DoddyError.capabilityUnavailable(.reminders) }
    public func fetch(id: String) async throws -> ExternalReminder? { throw DoddyError.capabilityUnavailable(.reminders) }
    public func find(marker: URL) async throws -> ExternalReminder? { throw DoddyError.capabilityUnavailable(.reminders) }
}

/// Runs the confirmed reminder write: store pending → write → read back → record the verified result.
public struct ReminderExecutor: Sendable {
    private let store: any ReminderActionStore
    private let gateway: any ReminderGateway
    private let now: @Sendable () -> Date

    public init(store: any ReminderActionStore, gateway: any ReminderGateway, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.gateway = gateway
        self.now = now
    }

    public static func validate(_ payload: ReminderPayload, now: Date) throws(ReminderError) {
        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw .emptyTitle }
        guard title.count <= ReminderPayload.maxTitle else { throw .titleTooLong }
        if let due = payload.due {
            guard let instant = due.instant else { throw .dueInvalid("That date or time doesn't exist.") }
            if due.hasTime && instant <= now { throw .dueInvalid("That time has already passed.") }
        }
    }

    /// Called only after the user tapped "Create" on the review screen.
    public func confirmAndCreate(_ payload: ReminderPayload, operationID: UUID, sourceMemoryID: UUID? = nil) async throws -> ReminderAction {
        let date = now()
        try Self.validate(payload, now: date)
        var action: ReminderAction
        if var existing = try await store.get(operationID) {
            switch existing.state {
            case .verifiedSucceeded:
                return existing // already done: never write twice
            case .pendingExternalWrite, .unknownOutcome:
                return try await reconcile(existing, createIfMissing: true)
            case .verifiedFailed:
                existing.payload = payload
                try existing.move(to: .userConfirmed, at: date)
                action = existing
            default:
                throw ReminderError.invalidTransition(from: existing.state, to: .userConfirmed)
            }
        } else {
            action = ReminderAction(operationID: operationID, state: .readyForConfirmation, payload: payload,
                                    sourceMemoryID: sourceMemoryID, createdAt: date, updatedAt: date)
            try action.move(to: .userConfirmed, at: date)
        }
        try await store.put(action)

        // Permission is checked at execution time; denial keeps the draft and says so.
        var access = await gateway.access()
        if access == .notDetermined { access = (try? await gateway.requestAccess()) == true ? .granted : .denied }
        guard access == .granted else {
            try action.move(to: .verifiedFailed, at: now(), errorCode: "permission_denied")
            try await store.put(action)
            return action
        }
        return try await write(action)
    }

    /// For actions left in pending or unknown: look for the reminder by its marker first.
    public func reconcile(_ action: ReminderAction, createIfMissing: Bool) async throws -> ReminderAction {
        var action = action
        let found: ExternalReminder?
        do {
            found = try await gateway.find(marker: action.marker)
        } catch {
            if action.state != .unknownOutcome { try action.move(to: .unknownOutcome, at: now(), errorCode: "reconcile_failed") }
            try await store.put(action)
            return action
        }
        if let found {
            try action.move(to: .verifiedSucceeded, at: now(), externalID: found.id)
            try await store.put(action)
            return action
        }
        guard createIfMissing else {
            if action.state != .unknownOutcome { try action.move(to: .unknownOutcome, at: now(), errorCode: "not_found") }
            try await store.put(action)
            return action
        }
        if action.state == .pendingExternalWrite { try action.move(to: .unknownOutcome, at: now(), errorCode: "not_found") }
        return try await write(action)
    }

    /// At launch: finish or reconcile anything a crash or kill interrupted.
    public func recoverInterrupted() async throws -> [ReminderAction] {
        var out: [ReminderAction] = []
        for var action in try await store.inStates([.userConfirmed, .pendingExternalWrite]) {
            if action.state == .userConfirmed {
                // The pending state is stored before any write, so nothing was written.
                try action.move(to: .verifiedFailed, at: now(), errorCode: "interrupted_before_write")
                try await store.put(action)
                out.append(action)
            } else {
                out.append(try await reconcile(action, createIfMissing: false))
            }
        }
        return out
    }

    private func write(_ action: ReminderAction) async throws -> ReminderAction {
        var action = action
        try action.move(to: .pendingExternalWrite, at: now())
        try await store.put(action) // stored before the external call
        let externalID: String
        do {
            externalID = try await gateway.create(action.payload, marker: action.marker)
        } catch {
            // The write may or may not have happened: check before calling it failed.
            if let found = try? await gateway.find(marker: action.marker) {
                try action.move(to: .verifiedSucceeded, at: now(), externalID: found.id)
            } else {
                try action.move(to: .unknownOutcome, at: now(), errorCode: "write_error")
            }
            try await store.put(action)
            return action
        }
        // Read it back: success only when Reminders really holds what the user confirmed.
        let stored = try? await gateway.fetch(id: externalID)
        if let stored, stored.title == action.payload.title, ReminderDue.same(stored.due, action.payload.due) {
            try action.move(to: .verifiedSucceeded, at: now(), externalID: externalID)
        } else {
            try action.move(to: .unknownOutcome, at: now(), externalID: externalID,
                            errorCode: stored == nil ? "not_found_after_write" : "mismatch_after_write")
        }
        try await store.put(action)
        return action
    }
}

/// User-facing words for each final state. They say only what was verified.
public enum ReminderCopy {
    public static func status(_ action: ReminderAction) -> String {
        switch action.state {
        case .verifiedSucceeded: "Added to Apple Reminders"
        case .verifiedFailed where action.errorCode == "permission_denied":
            "Not added: Doddy doesn't have access to Reminders. Allow it in iOS Settings, then try again."
        case .verifiedFailed where action.errorCode == "interrupted_before_write":
            "Not added: Doddy was closed before writing it. Try again."
        case .verifiedFailed: "Not added to Reminders."
        case .unknownOutcome:
            "Not sure it was added. Doddy didn't find it in Reminders. Check again, or add it once more."
        case .pendingExternalWrite, .userConfirmed: "Adding…"
        case .drafted, .needsClarification, .readyForConfirmation: "Not created yet"
        }
    }
}
