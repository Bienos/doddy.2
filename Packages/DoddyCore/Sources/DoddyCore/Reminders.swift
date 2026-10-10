import Foundation

// Apple Reminders as the first real action (repo M4). EventKit itself lives in the app
// (DoddyApp/Features/Reminders); this file holds everything that can be tested without it.

/// What the user approves for a reminder. The due time is stored with its UTC offset and time
/// zone, so the approval screen shows exactly the moment that will be written.
public struct ReminderSpec: Equatable, Sendable {
    public let title: String
    public let due: Date?
    public let timeZone: TimeZone
    public let list: ReminderList

    public static let maxTitleLength = 500

    public init(title: String, due: Date?, timeZone: TimeZone, list: ReminderList) {
        self.title = title
        self.due = due
        self.timeZone = timeZone
        self.list = list
    }

    /// Reads a reminder payload back. Fails on anything that isn't a well-formed reminder.
    public init(payload: ActionPayload) throws {
        guard payload.type == .createReminder,
              let title = payload.value(for: "title"),
              let listID = payload.value(for: "listID")
        else { throw ActionPayloadError.missingField("title") }
        var due: Date?
        var timeZone = TimeZone(identifier: "UTC")!
        if let dueText = payload.value(for: "due") {
            guard let zoneID = payload.value(for: "timeZone"), let zone = TimeZone(identifier: zoneID),
                  let date = Self.formatter(zone).date(from: dueText)
            else { throw ActionPayloadError.missingField("due") }
            due = date
            timeZone = zone
        }
        self.init(title: title, due: due, timeZone: timeZone, list: ReminderList(id: listID, title: payload.target))
    }

    /// "2026-10-11T18:00:00+02:00": whole seconds, offset of `timeZone`.
    public static func isoString(_ date: Date, in timeZone: TimeZone) -> String {
        formatter(timeZone).string(from: date)
    }

    static func formatter(_ timeZone: TimeZone) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter
    }
}

public struct ReminderList: Equatable, Hashable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

extension ActionPayload {
    /// Fields: title, optional due (ISO 8601 with offset) + timeZone, listID. Target = list name.
    public static func reminder(_ spec: ReminderSpec) throws -> ActionPayload {
        let title = try validated(spec.title, key: "title", limit: ReminderSpec.maxTitleLength)
        let listTitle = try validated(spec.list.title, key: "list", limit: maxTargetLength)
        let listID = try validated(spec.list.id, key: "list", limit: maxTargetLength)
        var fields = [Field(key: "title", label: "Reminder", value: title)]
        if let due = spec.due {
            fields.append(Field(key: "due", label: "When", value: ReminderSpec.isoString(due, in: spec.timeZone)))
            fields.append(Field(key: "timeZone", label: "Time zone", value: spec.timeZone.identifier))
        }
        fields.append(Field(key: "listID", label: "List ID", value: listID))
        return ActionPayload(type: .createReminder, target: listTitle, fields: fields)
    }
}

public enum RemindersAuthorization: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

/// What gets written. The marker lets Doddy find its own reminder again to verify or reconcile.
public struct ReminderWrite: Equatable, Sendable {
    public let title: String
    public let due: Date?
    public let timeZone: TimeZone
    public let listID: String
    public let markerURL: URL
    public let markerNote: String
}

/// Marks each reminder with the action's idempotency key, in its URL and its notes.
public enum RemindersMarker {
    public static func url(for key: UUID) -> URL {
        URL(string: "doddy://action/\(key.uuidString)")!
    }

    public static func note(for key: UUID) -> String {
        "Added by Doddy after you approved it. Ref: \(key.uuidString)"
    }

    /// True when a reminder's URL or notes carry this reference (either survives user edits to the other).
    public static func matches(url: URL?, notes: String?, reference: UUID) -> Bool {
        url == Self.url(for: reference) || (notes?.contains("Ref: \(reference.uuidString)") ?? false)
    }
}

public enum RemindersClientError: Error, Equatable, Sendable {
    case listMissing
    case accessDenied
    case lookupFailed
}

/// The slice of EventKit Doddy uses. Implemented in the app by `EventKitRemindersClient`.
public protocol RemindersClient: Sendable {
    func authorization() async -> RemindersAuthorization
    /// Shows the iOS permission prompt (only when not determined). Returns whether access is granted.
    func requestAccess() async throws -> Bool
    func defaultList() async -> ReminderList?
    func list(id: String) async -> ReminderList?
    /// Saves and commits one reminder; returns its EventKit identifier.
    func create(_ write: ReminderWrite) async throws -> String
    /// Identifier of the reminder carrying `reference`, or nil if none exists.
    func findReminder(reference: UUID) async throws -> String?
}

/// Real Apple Reminders writes through the ledger. "Confirmed" only after the reminder is found
/// again by its marker; a failed save is checked the same way before it is called failed.
public struct RemindersActionAdapter: ActionAdapter {
    public let client: any RemindersClient

    public init(client: any RemindersClient) {
        self.client = client
    }

    public var connectorID: String { "apple-reminders" }
    public var isSimulation: Bool { false }
    public func supports(_ type: ActionType) -> Bool { type == .createReminder }

    public func readiness(for type: ActionType) async -> ActionReadiness {
        switch await client.authorization() {
        case .granted: .ready
        case .notDetermined: .notReady("Doddy needs access to Reminders first. Nothing was added.")
        case .denied: .notReady("Reminders access is off for Doddy. Turn it on in Settings to add this. Nothing was added.")
        case .restricted: .notReady("Reminders access is restricted on this iPhone. Nothing was added.")
        }
    }

    public func execute(_ request: ActionExecutionRequest) async throws -> ActionProviderResult {
        let spec: ReminderSpec
        do {
            spec = try ReminderSpec(payload: request.payload)
        } catch {
            return .failed(reason: "The reminder details were incomplete. Nothing was added.")
        }
        // Checked again at execution time: access can be revoked after approval.
        guard await client.authorization() == .granted else {
            return .failed(reason: "Reminders access is off. Nothing was added.")
        }
        // An earlier attempt with this key may already have written it.
        if let existing = try await client.findReminder(reference: request.idempotencyKey) {
            return .confirmed(providerReference: existing)
        }
        guard await client.list(id: spec.list.id) != nil else {
            return .failed(reason: "The list “\(spec.list.title)” no longer exists. Nothing was added.")
        }
        let write = ReminderWrite(
            title: spec.title, due: spec.due, timeZone: spec.timeZone, listID: spec.list.id,
            markerURL: RemindersMarker.url(for: request.idempotencyKey),
            markerNote: RemindersMarker.note(for: request.idempotencyKey))
        do {
            let identifier = try await client.create(write)
            guard try await client.findReminder(reference: request.idempotencyKey) == identifier else {
                return .unknown(reason: "Saved, but the reminder couldn't be found again")
            }
            return .confirmed(providerReference: identifier)
        } catch {
            // The save failed; look before saying it didn't happen.
            if let found = try await client.findReminder(reference: request.idempotencyKey) {
                return .confirmed(providerReference: found)
            }
            return .failed(reason: "Reminders didn't save it. Nothing was added.")
        }
    }

    public func status(idempotencyKey: UUID) async throws -> ActionProviderResult {
        guard await client.authorization() == .granted else {
            return .unknown(reason: "Can't check without Reminders access")
        }
        if let found = try await client.findReminder(reference: idempotencyKey) {
            return .confirmed(providerReference: found)
        }
        return .failed(reason: "No reminder from this action exists in Reminders")
    }
}
