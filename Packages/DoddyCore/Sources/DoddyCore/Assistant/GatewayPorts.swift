import Foundation

// Ports for the gateway client. The real HTTP transport and the Keychain store live in the app
// target, so this package stays free of networking and platform code and its tests run on Linux.

public struct GatewayHTTPRequest: Equatable, Sendable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data?
    public let timeout: TimeInterval

    public init(url: URL, method: String, headers: [String: String], body: Data?, timeout: TimeInterval) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct GatewayHTTPResponse: Equatable, Sendable {
    public let status: Int
    /// Header names lower-cased.
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public enum TransportFailure: Error, Equatable, Sendable {
    case offline
    case timedOut
    case cancelled
    case other
}

public protocol GatewayTransport: Sendable {
    func send(_ request: GatewayHTTPRequest) async throws(TransportFailure) -> GatewayHTTPResponse
}

public struct DeviceToken: Equatable, Sendable {
    public let value: String
    public let expiresAt: Date
    /// The gateway host that issued it. A token is never sent to a different host (for example after the
    /// address is changed in Settings).
    public let gatewayHost: String?

    public init(value: String, expiresAt: Date, gatewayHost: String? = nil) {
        self.value = value
        self.expiresAt = expiresAt
        self.gatewayHost = gatewayHost
    }
}

/// Holds the random device id, the invite code and the short-lived token. No account, no profile.
/// The app implements this on the Keychain; deleting the app removes it.
public protocol DeviceCredentialStore: Sendable {
    /// A random id, created and kept on first use. It identifies this install to the gateway, nothing else.
    func deviceID() async throws -> UUID
    func inviteCode() async throws -> String?
    func setInviteCode(_ code: String?) async throws
    func token() async throws -> DeviceToken?
    func setToken(_ token: DeviceToken?) async throws
}

public actor InMemoryCredentialStore: DeviceCredentialStore {
    private var id: UUID?
    private var invite: String?
    private var stored: DeviceToken?

    public init(inviteCode: String? = nil, deviceID: UUID? = nil) {
        invite = inviteCode
        id = deviceID
    }

    public func deviceID() -> UUID {
        if let id { return id }
        let created = UUID()
        id = created
        return created
    }

    public func inviteCode() -> String? { invite }
    public func setInviteCode(_ code: String?) { invite = code }
    public func token() -> DeviceToken? { stored }
    public func setToken(_ token: DeviceToken?) { stored = token }
}

/// Where the gateway lives. Only plain https addresses are accepted.
public struct GatewayConfiguration: Equatable, Sendable {
    public let baseURL: URL

    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host, host.contains("."),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.url != nil
        else { return nil }
        var normalised = components
        while normalised.path.hasSuffix("/") { normalised.path.removeLast() }
        guard let base = normalised.url else { return nil }
        self.baseURL = base
    }

    func endpoint(_ name: String) -> URL { baseURL.appendingPathComponent("api").appendingPathComponent(name) }
}
