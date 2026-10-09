import Foundation

// Swift mirror of the Doddy-owned Connected Apps API v1 (backend/src/contracts.ts).
// Both sides decode the shared fixtures in contracts/connected-apps/ so they cannot drift silently.

public enum ConnectedAppsMode: String, Codable, Sendable {
    /// Synthetic demo data from the server's mock adapter. Google Calendar is not connected.
    case mock
    case live
}

public enum ReceiptStatus: String, Codable, Sendable {
    case succeeded, failed, canceled, blocked
    case outcomeUnknown = "outcome_unknown"
}

/// Sanitized record of one connect, disconnect or read. Never contains event content.
public struct ConnectedAppReceipt: Codable, Equatable, Sendable, Identifiable {
    public enum Operation: String, Codable, Sendable { case connect, disconnect, read }

    public let operationId: UUID
    public let operation: Operation
    public let capability: String
    public let provider: String
    public let accountLabel: String?
    public let timestamp: String
    public let mode: ConnectedAppsMode
    public let status: ReceiptStatus
    public let summary: String
    public let errorCode: String?
    /// Only a reference the provider actually returned (Composio log ID); otherwise nil.
    public let providerReference: String?

    public var id: UUID { operationId }
}

public enum ConnectionStatus: String, Codable, Sendable {
    case disconnected, connecting, connected
    case permissionInsufficient = "permission_insufficient"
    case expired, error
}

public enum ConnectionReason: String, Codable, Sendable {
    case missingReadScope = "missing_read_scope"
    case grantNotReadOnly = "grant_not_read_only"
    case grantUnverifiable = "grant_unverifiable"
    case revokedOrExpired = "revoked_or_expired"
    case providerUnavailable = "provider_unavailable"
}

public enum RemoteCleanup: String, Codable, Sendable { case none, pending, failed }

public struct ConnectionAccess: Codable, Equatable, Sendable {
    public let summary: String
    public let canWrite: Bool
    public let requestedScopes: [String]
}

public struct ConnectionView: Codable, Equatable, Sendable {
    public let provider: String
    public let mode: ConnectedAppsMode
    public let status: ConnectionStatus
    public let reason: ConnectionReason?
    /// Masked calendar name reported by Google Calendar. Not a verified identity.
    public let accountLabel: String?
    public let connectedAt: String?
    public let lastCheckedAt: String?
    public let remoteCleanup: RemoteCleanup
    public let access: ConnectionAccess
}

public struct ConnectResponse: Codable, Equatable, Sendable {
    public let mode: ConnectedAppsMode
    public let attemptId: UUID
    public let nonce: String
    /// System-browser URL in live mode; nil in mock mode (the demo never shows a sign-in page).
    public let authorizationUrl: URL?
    public let callbackScheme: String
    public let expiresAt: String
}

public struct ConnectionResult: Codable, Equatable, Sendable {
    public let connection: ConnectionView
    public let receipt: ConnectedAppReceipt
}

public struct CalendarEventItem: Codable, Equatable, Sendable {
    public let title: String
    public let allDay: Bool
    /// RFC 3339 instant for timed events, YYYY-MM-DD for all-day events.
    public let start: String
    /// Exclusive end, same format as `start`.
    public let end: String
    public let isRecurring: Bool
}

public struct EventsSource: Codable, Equatable, Sendable {
    public let provider: String
    public let calendar: String
    public let label: String?
}

public struct EventsWindow: Codable, Equatable, Sendable {
    public let date: String
    public let timeZone: String
    public let start: String
    public let end: String
}

/// Transient calendar context. Shown, never stored; discarded after `expiresAt` or on disconnect.
public struct EventsResult: Codable, Equatable, Sendable {
    public let mode: ConnectedAppsMode
    public let source: EventsSource
    public let window: EventsWindow
    public let events: [CalendarEventItem]
    public let cancelledHidden: Int
    public let truncated: Bool
    public let retrievedAt: String
    public let expiresAt: String
    public let receipt: ConnectedAppReceipt
}

public struct ConnectedAppsErrorBody: Codable, Equatable, Sendable {
    public struct Detail: Codable, Equatable, Sendable {
        public let code: String
        public let message: String
        public let correlationId: String
        public let retryAfterSeconds: Int?
        public let receipt: ConnectedAppReceipt?
    }
    public let error: Detail
}

public struct ReceiptsResponse: Codable, Equatable, Sendable {
    public let receipts: [ConnectedAppReceipt]
}

// MARK: Requests

public struct EventsRequest: Codable, Equatable, Sendable {
    public let date: String
    public let timeZone: String

    public init(date: String, timeZone: String) {
        self.date = date
        self.timeZone = timeZone
    }
}

/// How the browser step ended. Encoded exactly as the server's discriminated union.
public enum CompletionResult: Equatable, Sendable {
    case callback(status: String, connectedAccountId: String?)
    case verifier(sessionUri: String)
    case canceled
    case mock(approve: Bool)
}

public struct CompleteRequest: Encodable, Equatable, Sendable {
    public let attemptId: UUID
    public let nonce: String
    public let result: CompletionResult

    public init(attemptId: UUID, nonce: String, result: CompletionResult) {
        self.attemptId = attemptId
        self.nonce = nonce
        self.result = result
    }

    private enum Keys: String, CodingKey { case attemptId, nonce, result }
    private enum ResultKeys: String, CodingKey { case kind, status, connectedAccountId, sessionUri, outcome }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(attemptId.uuidString.lowercased(), forKey: .attemptId)
        try container.encode(nonce, forKey: .nonce)
        var result = container.nestedContainer(keyedBy: ResultKeys.self, forKey: .result)
        switch self.result {
        case .callback(let status, let id):
            try result.encode("callback", forKey: .kind)
            try result.encode(status, forKey: .status)
            try result.encodeIfPresent(id, forKey: .connectedAccountId)
        case .verifier(let sessionUri):
            try result.encode("verifier", forKey: .kind)
            try result.encode(sessionUri, forKey: .sessionUri)
        case .canceled:
            try result.encode("canceled", forKey: .kind)
        case .mock(let approve):
            try result.encode("mock", forKey: .kind)
            try result.encode(approve ? "approve" : "deny", forKey: .outcome)
        }
    }
}
