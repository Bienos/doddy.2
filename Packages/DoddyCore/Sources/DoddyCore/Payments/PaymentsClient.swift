import Foundation

public enum PaymentsError: Error, Equatable, Sendable {
    /// No server URL or session token is configured in this build.
    case notConfigured
    case unauthenticated
    /// A plain, safe message from the server, with its code.
    case server(code: String, message: String, retryAfterSeconds: Int?)
    /// The request may or may not have reached the server.
    case transport(String)
    /// The response did not match the contract. Nothing is shown instead.
    case unreadableResponse

    public var code: String? {
        if case .server(let code, _, _) = self { return code }
        return nil
    }

    public var userMessage: String {
        switch self {
        case .notConfigured: "Payments need a Doddy server, which isn't set up in this build."
        case .unauthenticated: "Doddy's server didn't accept this device's session. Check the session token in Settings."
        case .server(_, let message, _): message
        case .transport: "Doddy's server couldn't be reached. Check your connection."
        case .unreadableResponse: "Doddy's server sent an answer the app couldn't read."
        }
    }
}

/// Doddy-owned API surface for purchases (ADR-530). There is no call that takes a provider, an
/// amount to charge later or a URL to fetch: the server keeps the purchase the card showed and
/// charges exactly that, once.
public protocol PaymentsClient: Sendable {
    func prepare(_ request: PreparePurchaseRequest) async throws(PaymentsError) -> PurchasePrepareResult
    /// Native purchases only. Uses up the card's approval.
    func pay(purchaseId: UUID, approvalId: UUID, payment: PurchasePayment) async throws(PaymentsError) -> PurchaseResult
    /// Re-read from Stripe by the server while paying, waiting for the bank or unsure.
    func status(purchaseId: UUID) async throws(PaymentsError) -> PurchaseResult
    func cancel(purchaseId: UUID) async throws(PaymentsError) -> PurchaseResult
    /// Checkout purchases only. Uses up the card's approval and returns the page to open.
    func handoff(purchaseId: UUID, approvalId: UUID) async throws(PaymentsError) -> HandoffResult
    /// After a hand-off: the user's own answer, recorded as theirs.
    func report(purchaseId: UUID, paid: Bool) async throws(PaymentsError) -> PurchaseResult
    func list() async throws(PaymentsError) -> [PurchaseView]
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

    public func prepare(_ request: PreparePurchaseRequest) async throws(PaymentsError) -> PurchasePrepareResult {
        try await call("POST", "v1/purchases/prepare", body: request)
    }

    public func pay(purchaseId: UUID, approvalId: UUID, payment: PurchasePayment) async throws(PaymentsError) -> PurchaseResult {
        try await call("POST", "v1/purchases/pay", body: PayRequestBody(purchaseId: purchaseId, approvalId: approvalId, payment: payment))
    }

    public func status(purchaseId: UUID) async throws(PaymentsError) -> PurchaseResult {
        try await call("POST", "v1/purchases/status", body: PurchaseIDBody(purchaseId))
    }

    public func cancel(purchaseId: UUID) async throws(PaymentsError) -> PurchaseResult {
        try await call("POST", "v1/purchases/cancel", body: PurchaseIDBody(purchaseId))
    }

    public func handoff(purchaseId: UUID, approvalId: UUID) async throws(PaymentsError) -> HandoffResult {
        try await call("POST", "v1/purchases/handoff", body: HandoffBody(purchaseId: purchaseId, approvalId: approvalId))
    }

    public func report(purchaseId: UUID, paid: Bool) async throws(PaymentsError) -> PurchaseResult {
        try await call("POST", "v1/purchases/report", body: ReportBody(purchaseId: purchaseId, paid: paid))
    }

    public func list() async throws(PaymentsError) -> [PurchaseView] {
        let response: PurchasesList = try await call("GET", "v1/purchases", body: Optional<PurchaseIDBody>.none)
        return response.purchases
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
        guard let body = try? decoder.decode(ErrorBody.self, from: data) else { throw .unreadableResponse }
        throw .server(code: body.error.code, message: body.error.message, retryAfterSeconds: body.error.retryAfterSeconds)
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable {
            let code: String
            let message: String
            let retryAfterSeconds: Int?
        }
        let error: Detail
    }
}

/// The client used when no server is configured: every call says so plainly.
public struct UnconfiguredPaymentsClient: PaymentsClient {
    public init() {}
    public func prepare(_ request: PreparePurchaseRequest) async throws(PaymentsError) -> PurchasePrepareResult { throw .notConfigured }
    public func pay(purchaseId: UUID, approvalId: UUID, payment: PurchasePayment) async throws(PaymentsError) -> PurchaseResult { throw .notConfigured }
    public func status(purchaseId: UUID) async throws(PaymentsError) -> PurchaseResult { throw .notConfigured }
    public func cancel(purchaseId: UUID) async throws(PaymentsError) -> PurchaseResult { throw .notConfigured }
    public func handoff(purchaseId: UUID, approvalId: UUID) async throws(PaymentsError) -> HandoffResult { throw .notConfigured }
    public func report(purchaseId: UUID, paid: Bool) async throws(PaymentsError) -> PurchaseResult { throw .notConfigured }
    public func list() async throws(PaymentsError) -> [PurchaseView] { throw .notConfigured }
}
