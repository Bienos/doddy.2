import Foundation

public enum OnlineAccountsError: Error, Equatable, Sendable {
    /// No server URL or session token is configured in this build.
    case notConfigured
    case unauthenticated
    case server(code: String, message: String, retryAfterSeconds: Int?, receipt: OnlineToolReceipt?)
    case transport(String)
    /// The response did not match the contract. Nothing is shown instead.
    case unreadableResponse

    public var receipt: OnlineToolReceipt? {
        if case .server(_, _, _, let receipt) = self { return receipt }
        return nil
    }

    public var code: String? {
        if case .server(let code, _, _, _) = self { return code }
        return nil
    }

    public var userMessage: String {
        switch self {
        case .notConfigured: "Online accounts need a Doddy server, which isn't set up in this build."
        case .unauthenticated: "Doddy's server didn't accept this device's session. Check the session token in Settings."
        case .server(_, let message, _, _): message
        case .transport: "Doddy's server couldn't be reached. Check your connection and try again."
        case .unreadableResponse: "Doddy's server sent something the app couldn't read, so nothing is shown."
        }
    }
}

/// Doddy-owned API surface for online accounts. There is no generic "run any tool" call by design:
/// a tool is one of a fixed list, and the server decides everything else.
public protocol OnlineAccountsClient: Sendable {
    func catalog() async throws(OnlineAccountsError) -> ToolsCatalog
    func connect(toolkit: String) async throws(OnlineAccountsError) -> ConnectResponse
    func complete(toolkit: String, _ request: CompleteRequest) async throws(OnlineAccountsError) -> ToolkitResult
    func disconnect(toolkit: String) async throws(OnlineAccountsError) -> ToolkitResult
    func setSwitch(tool: String, enabled: Bool) async throws(OnlineAccountsError) -> ToolkitResult
    /// Every tool (ASK-01, ADR-483): asks the server for the card and a single-use approval for
    /// exactly these arguments. For a read nothing is read; `run` refuses without the approval.
    func prepare(_ call: CloudToolCall) async throws(OnlineAccountsError) -> PrepareResult
    func run(_ call: CloudToolCall, timeZone: String, approvalId: UUID?) async throws(OnlineAccountsError) -> RunResult
    func receipts() async throws(OnlineAccountsError) -> [OnlineToolReceipt]
}

public struct BackendOnlineAccountsClient: OnlineAccountsClient {
    private let baseURL: URL
    private let sessionToken: @Sendable () -> String?
    private let transport: any HTTPTransport

    /// `baseURL` must be https, or http on a loopback host for local development.
    public init?(baseURL: URL, sessionToken: @escaping @Sendable () -> String?, transport: any HTTPTransport) {
        guard BackendConnectedAppsClient.isAllowed(baseURL) else { return nil }
        self.baseURL = baseURL
        self.sessionToken = sessionToken
        self.transport = transport
    }

    /// Same, with a token that is sent only to the server it was issued for.
    public init?(baseURL: URL, boundToken: @escaping @Sendable () -> BoundSessionToken?, transport: any HTTPTransport) {
        self.init(baseURL: baseURL, sessionToken: { boundToken()?.token(for: baseURL) }, transport: transport)
    }

    public func catalog() async throws(OnlineAccountsError) -> ToolsCatalog {
        try await call("GET", "v1/tools", body: Optional<JSONValue>.none)
    }

    public func connect(toolkit: String) async throws(OnlineAccountsError) -> ConnectResponse {
        try await call("POST", "v1/tools/\(toolkit)/connect", body: [String: String]())
    }

    public func complete(toolkit: String, _ request: CompleteRequest) async throws(OnlineAccountsError) -> ToolkitResult {
        try await call("POST", "v1/tools/\(toolkit)/complete", body: request)
    }

    public func disconnect(toolkit: String) async throws(OnlineAccountsError) -> ToolkitResult {
        try await call("POST", "v1/tools/\(toolkit)/disconnect", body: [String: String]())
    }

    public func setSwitch(tool: String, enabled: Bool) async throws(OnlineAccountsError) -> ToolkitResult {
        try await call("PUT", "v1/tools/switch", body: SwitchBody(tool: tool, enabled: enabled))
    }

    public func prepare(_ call: CloudToolCall) async throws(OnlineAccountsError) -> PrepareResult {
        try await self.call("POST", "v1/tools/prepare", body: PrepareBody(tool: call.name, arguments: call.arguments))
    }

    public func run(_ call: CloudToolCall, timeZone: String, approvalId: UUID?) async throws(OnlineAccountsError) -> RunResult {
        try await self.call(
            "POST", "v1/tools/run",
            body: RunBody(tool: call.name, arguments: call.arguments, timeZone: timeZone, approvalId: approvalId?.uuidString.lowercased()))
    }

    public func receipts() async throws(OnlineAccountsError) -> [OnlineToolReceipt] {
        let response: OnlineReceiptsResponse = try await call("GET", "v1/tools/receipts", body: Optional<JSONValue>.none)
        return response.receipts
    }

    struct SwitchBody: Encodable, Equatable {
        let tool: String
        let enabled: Bool
    }

    struct PrepareBody: Encodable, Equatable {
        let tool: String
        let arguments: [String: JSONValue]
    }

    struct RunBody: Encodable, Equatable {
        let tool: String
        let arguments: [String: JSONValue]
        let timeZone: String
        let approvalId: String?
    }

    private func call<Body: Encodable, Response: Decodable>(_ method: String, _ path: String, body: Body?) async throws(OnlineAccountsError) -> Response {
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
    public static func decode<Response: Decodable>(status: Int, data: Data) throws(OnlineAccountsError) -> Response {
        let decoder = JSONDecoder()
        if (200..<300).contains(status) {
            do { return try decoder.decode(Response.self, from: data) } catch { throw .unreadableResponse }
        }
        if status == 401 { throw .unauthenticated }
        guard let body = try? decoder.decode(OnlineErrorBody.self, from: data) else { throw .unreadableResponse }
        throw .server(code: body.error.code, message: body.error.message, retryAfterSeconds: body.error.retryAfterSeconds, receipt: body.error.receipt)
    }
}

/// The client used when no server is configured: every call says so plainly.
public struct UnconfiguredOnlineAccountsClient: OnlineAccountsClient {
    public init() {}
    public func catalog() async throws(OnlineAccountsError) -> ToolsCatalog { throw .notConfigured }
    public func connect(toolkit: String) async throws(OnlineAccountsError) -> ConnectResponse { throw .notConfigured }
    public func complete(toolkit: String, _ request: CompleteRequest) async throws(OnlineAccountsError) -> ToolkitResult { throw .notConfigured }
    public func disconnect(toolkit: String) async throws(OnlineAccountsError) -> ToolkitResult { throw .notConfigured }
    public func setSwitch(tool: String, enabled: Bool) async throws(OnlineAccountsError) -> ToolkitResult { throw .notConfigured }
    public func prepare(_ call: CloudToolCall) async throws(OnlineAccountsError) -> PrepareResult { throw .notConfigured }
    public func run(_ call: CloudToolCall, timeZone: String, approvalId: UUID?) async throws(OnlineAccountsError) -> RunResult { throw .notConfigured }
    public func receipts() async throws(OnlineAccountsError) -> [OnlineToolReceipt] { throw .notConfigured }
}
