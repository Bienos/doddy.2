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

    public static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), url.query == nil else { return false }
        if scheme == "https" { return true }
        return scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
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
