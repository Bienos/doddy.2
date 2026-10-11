import Foundation

/// One HTTP exchange. The app supplies a URLSession-backed transport; tests supply a fake.
/// Keeping networking out of DoddyCore keeps the package testable and the guard script simple.
public struct HTTPRequest: Equatable, Sendable {
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let body: Data?
}

public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data)
}

public enum ConnectedAppsError: Error, Equatable, Sendable {
    /// No server URL or session token is configured in this build.
    case notConfigured
    case unauthenticated
    /// A safe, plain message from the server plus its code and any receipt.
    case server(code: String, message: String, retryAfterSeconds: Int?, receipt: ConnectedAppReceipt?)
    case transport(String)
    /// The response did not match the contract. Nothing is shown instead.
    case unreadableResponse

    public var receipt: ConnectedAppReceipt? {
        if case .server(_, _, _, let receipt) = self { return receipt }
        return nil
    }

    public var userMessage: String {
        switch self {
        case .notConfigured: "Connected Apps needs a Doddy server, which isn't set up in this build."
        case .unauthenticated: "Doddy's server didn't accept this device's session. Check the session token in Settings."
        case .server(_, let message, _, _): message
        case .transport: "Doddy's server couldn't be reached. Check your connection and try again."
        case .unreadableResponse: "Doddy's server sent something the app couldn't read, so nothing is shown."
        }
    }
}

/// Doddy-owned API surface the app needs. There is no generic "execute tool" call by design.
public protocol ConnectedAppsClient: Sendable {
    func status() async throws(ConnectedAppsError) -> ConnectionView
    func connect() async throws(ConnectedAppsError) -> ConnectResponse
    func complete(_ request: CompleteRequest) async throws(ConnectedAppsError) -> ConnectionResult
    func tomorrowEvents(_ request: EventsRequest) async throws(ConnectedAppsError) -> EventsResult
    func disconnect() async throws(ConnectedAppsError) -> ConnectionResult
    func receipts() async throws(ConnectedAppsError) -> [ConnectedAppReceipt]
}

public struct BackendConnectedAppsClient: ConnectedAppsClient {
    private let baseURL: URL
    private let sessionToken: @Sendable () -> String?
    private let transport: any HTTPTransport

    /// `baseURL` must be https, or http on a loopback host for local development.
    public init?(baseURL: URL, sessionToken: @escaping @Sendable () -> String?, transport: any HTTPTransport) {
        guard Self.isAllowed(baseURL) else { return nil }
        self.baseURL = baseURL
        self.sessionToken = sessionToken
        self.transport = transport
    }

    /// Same, with a token that is sent only to the server it was issued for.
    public init?(baseURL: URL, boundToken: @escaping @Sendable () -> BoundSessionToken?, transport: any HTTPTransport) {
        self.init(baseURL: baseURL, sessionToken: { boundToken()?.token(for: baseURL) }, transport: transport)
    }

    /// Plain http to this machine is for local development (the Simulator); release builds refuse
    /// it, so a bearer token never travels unencrypted from a shipped app (DOD-11).
    #if DEBUG
    public static let allowsLoopbackHTTP = true
    #else
    public static let allowsLoopbackHTTP = false
    #endif

    public static func isAllowed(_ url: URL, allowLoopbackHTTP: Bool = allowsLoopbackHTTP) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), url.query == nil else { return false }
        if scheme == "https" { return true }
        return allowLoopbackHTTP && scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    private static let path = "v1/connected-apps/google-calendar"

    public func status() async throws(ConnectedAppsError) -> ConnectionView {
        try await call("GET", Self.path, body: Optional<EventsRequest>.none)
    }

    public func connect() async throws(ConnectedAppsError) -> ConnectResponse {
        try await call("POST", "\(Self.path)/connect", body: [String: String]())
    }

    public func complete(_ request: CompleteRequest) async throws(ConnectedAppsError) -> ConnectionResult {
        try await call("POST", "\(Self.path)/complete", body: request)
    }

    public func tomorrowEvents(_ request: EventsRequest) async throws(ConnectedAppsError) -> EventsResult {
        try await call("POST", "\(Self.path)/events", body: request)
    }

    public func disconnect() async throws(ConnectedAppsError) -> ConnectionResult {
        try await call("POST", "\(Self.path)/disconnect", body: [String: String]())
    }

    public func receipts() async throws(ConnectedAppsError) -> [ConnectedAppReceipt] {
        let response: ReceiptsResponse = try await call("GET", "\(Self.path)/receipts", body: Optional<EventsRequest>.none)
        return response.receipts
    }

    private func call<Body: Encodable, Response: Decodable>(_ method: String, _ path: String, body: Body?) async throws(ConnectedAppsError) -> Response {
        guard let token = sessionToken(), !token.isEmpty else { throw .notConfigured }
        var headers = ["authorization": "Bearer \(token)", "accept": "application/json"]
        var data: Data?
        if let body {
            headers["content-type"] = "application/json"
            do { data = try JSONEncoder().encode(body) } catch { throw .transport("encoding") }
        }
        let request = HTTPRequest(method: method, url: baseURL.appendingPathComponent(path), headers: headers, body: data)
        let status: Int
        let payload: Data
        do {
            (status, payload) = try await transport.send(request)
        } catch {
            throw .transport(String(describing: type(of: error)))
        }
        return try Self.decode(status: status, data: payload)
    }

    /// Success bodies decode into the expected type; everything else into a typed error. An
    /// unreadable body is an error, never an empty result.
    public static func decode<Response: Decodable>(status: Int, data: Data) throws(ConnectedAppsError) -> Response {
        let decoder = JSONDecoder()
        if (200..<300).contains(status) {
            do { return try decoder.decode(Response.self, from: data) } catch { throw .unreadableResponse }
        }
        if status == 401 { throw .unauthenticated }
        guard let body = try? decoder.decode(ConnectedAppsErrorBody.self, from: data) else { throw .unreadableResponse }
        throw .server(code: body.error.code, message: body.error.message, retryAfterSeconds: body.error.retryAfterSeconds, receipt: body.error.receipt)
    }
}

/// A Doddy server session token together with the server that issued it. The clients send it only
/// to that server, so changing the address in Settings can't hand the token to another host (DOD-11).
public struct BoundSessionToken: Codable, Equatable, Sendable {
    public let token: String
    /// `scheme://host:port` of the server that issued the token.
    public let origin: String

    public init?(token: String, issuedBy server: URL) {
        guard !token.isEmpty, let origin = Self.origin(of: server) else { return nil }
        self.token = token
        self.origin = origin
    }

    /// The token, or nil when `server` is not the one it was issued for.
    public func token(for server: URL) -> String? {
        Self.origin(of: server) == origin ? token : nil
    }

    static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        let port = url.port ?? (scheme == "https" ? 443 : scheme == "http" ? 80 : -1)
        return "\(scheme)://\(host):\(port)"
    }
}

/// The client used when no server is configured: every call says so plainly.
public struct UnconfiguredConnectedAppsClient: ConnectedAppsClient {
    public init() {}
    public func status() async throws(ConnectedAppsError) -> ConnectionView { throw .notConfigured }
    public func connect() async throws(ConnectedAppsError) -> ConnectResponse { throw .notConfigured }
    public func complete(_ request: CompleteRequest) async throws(ConnectedAppsError) -> ConnectionResult { throw .notConfigured }
    public func tomorrowEvents(_ request: EventsRequest) async throws(ConnectedAppsError) -> EventsResult { throw .notConfigured }
    public func disconnect() async throws(ConnectedAppsError) -> ConnectionResult { throw .notConfigured }
    public func receipts() async throws(ConnectedAppsError) -> [ConnectedAppReceipt] { throw .notConfigured }
}
