import Foundation

public enum PaymentsError: Error, Equatable, Sendable {
    /// No server URL or session token is configured in this build.
    case notConfigured
    case unauthenticated
    case server(code: String, message: String, retryAfterSeconds: Int?, receipt: PaymentReceipt?)
    case transport(String)
    /// The response did not match the contract. Nothing is shown instead.
    case unreadableResponse

    public var receipt: PaymentReceipt? {
        if case .server(_, _, _, let receipt) = self { return receipt }
        return nil
    }

    public var code: String? {
        if case .server(let code, _, _, _) = self { return code }
        return nil
    }

    public var userMessage: String {
        switch self {
        case .notConfigured: "Payments need a Doddy server, which isn't set up in this build."
        case .unauthenticated: "Doddy's server didn't accept this device's session. Check the session token in Settings."
        case .server(_, let message, _, _): message
        case .transport: "Doddy's server couldn't be reached. Check your connection and try again."
        case .unreadableResponse: "Doddy's server sent something the app couldn't read."
        }
    }

    /// Error codes the server only uses when it refused before doing anything, so no payment can have
    /// been sent. Anything else, with no receipt to say otherwise, might have happened.
    private static let neverAttempted: Set<String> = [
        "unauthenticated", "invalid_request", "not_found", "payload_too_large", "capability_disabled",
        "rate_limited", "quota_exceeded", "busy", "live_not_configured",
    ]

    /// After the server was asked to pay: could the payment have gone through? True unless the server
    /// itself said it did nothing. Used to choose "unconfirmed" (never "try again") over "failed".
    public var mightHaveBeenPaid: Bool {
        switch self {
        case .notConfigured, .unauthenticated:
            // Refused before a request was made, or the server turned the session away.
            return false
        case .transport, .unreadableResponse:
            // The request may have reached the server and finished without our hearing about it.
            return true
        case .server(let code, _, _, let receipt):
            if let receipt {
                switch receipt.status {
                case .blocked, .failed, .canceled: return false
                case .outcomeUnknown, .succeeded: return true
                }
            }
            return !Self.neverAttempted.contains(code)
        }
    }
}

/// Doddy-owned payments API. The app can ask for exactly four things: the status, the person's own
/// switch, the terms for one page, and (with an approval) to pay that page. There is no call that
/// takes an amount, a recipient or a wallet: the server decides everything but the page.
public protocol PaymentsClient: Sendable {
    func status() async throws(PaymentsError) -> PaymentStatus
    func setSwitch(enabled: Bool) async throws(PaymentsError) -> PaymentSwitchResult
    /// Shows exactly what would be paid and returns a single-use approval for those terms. Pays nothing.
    func prepare(url: String) async throws(PaymentsError) -> PaymentPrepared
    /// Pays once. Never call it twice for one approval, and never retry it: see `PaymentsError.mightHaveBeenPaid`.
    /// `confirmAmount` is what the person typed, sent only when the terms asked for it.
    func pay(url: String, approvalId: UUID, confirmAmount: String?) async throws(PaymentsError) -> PaymentResult
    func receipts() async throws(PaymentsError) -> [PaymentReceipt]
}

public struct BackendPaymentsClient: PaymentsClient {
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

    public func status() async throws(PaymentsError) -> PaymentStatus {
        try await call("GET", "v1/payments", body: Optional<NoBody>.none)
    }

    public func setSwitch(enabled: Bool) async throws(PaymentsError) -> PaymentSwitchResult {
        try await call("PUT", "v1/payments/switch", body: SwitchBody(enabled: enabled))
    }

    public func prepare(url: String) async throws(PaymentsError) -> PaymentPrepared {
        try await call("POST", "v1/payments/prepare", body: PrepareBody(url: url))
    }

    public func pay(url: String, approvalId: UUID, confirmAmount: String?) async throws(PaymentsError) -> PaymentResult {
        try await call("POST", "v1/payments/pay", body: PayBody(url: url, approvalId: approvalId.uuidString.lowercased(), confirmAmount: confirmAmount))
    }

    public func receipts() async throws(PaymentsError) -> [PaymentReceipt] {
        let response: PaymentReceiptsResponse = try await call("GET", "v1/payments/receipts", body: Optional<NoBody>.none)
        return response.receipts
    }

    struct NoBody: Encodable, Equatable {}

    struct SwitchBody: Encodable, Equatable {
        let enabled: Bool
    }

    struct PrepareBody: Encodable, Equatable {
        let url: String
    }

    struct PayBody: Encodable, Equatable {
        let url: String
        let approvalId: String
        /// Omitted from the JSON when nil.
        let confirmAmount: String?
    }

    private func call<Body: Encodable, Response: Decodable>(_ method: String, _ path: String, body: Body?) async throws(PaymentsError) -> Response {
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
    public static func decode<Response: Decodable>(status: Int, data: Data) throws(PaymentsError) -> Response {
        let decoder = JSONDecoder()
        if (200..<300).contains(status) {
            do { return try decoder.decode(Response.self, from: data) } catch { throw .unreadableResponse }
        }
        if status == 401 { throw .unauthenticated }
        guard let body = try? decoder.decode(PaymentErrorBody.self, from: data) else { throw .unreadableResponse }
        throw .server(code: body.error.code, message: body.error.message, retryAfterSeconds: body.error.retryAfterSeconds, receipt: body.error.receipt)
    }
}

/// The client used when no server is configured: every call says so plainly.
public struct UnconfiguredPaymentsClient: PaymentsClient {
    public init() {}
    public func status() async throws(PaymentsError) -> PaymentStatus { throw .notConfigured }
    public func setSwitch(enabled: Bool) async throws(PaymentsError) -> PaymentSwitchResult { throw .notConfigured }
    public func prepare(url: String) async throws(PaymentsError) -> PaymentPrepared { throw .notConfigured }
    public func pay(url: String, approvalId: UUID, confirmAmount: String?) async throws(PaymentsError) -> PaymentResult { throw .notConfigured }
    public func receipts() async throws(PaymentsError) -> [PaymentReceipt] { throw .notConfigured }
}
