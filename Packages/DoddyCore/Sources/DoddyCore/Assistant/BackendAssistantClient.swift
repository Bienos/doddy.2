import Foundation

/// How Ask Doddy gets a session on Doddy's server (ADR-563, ADR-587). The app implements it with the
/// device session in the Keychain; the tests with a script.
public struct AssistantSession: Sendable {
    /// The session token for the server, after signing this iPhone in if it has none. Nil: it
    /// couldn't (offline, or the server refused).
    public let token: @Sendable () async -> String?
    /// After the server refused the token: forget it, sign in again, return the new one.
    public let renewed: @Sendable () async -> String?

    public init(token: @escaping @Sendable () async -> String?, renewed: @escaping @Sendable () async -> String?) {
        self.token = token
        self.renewed = renewed
    }
}

/// The real `AssistantClient` (ADR-587): typed questions go to Doddy's own server, `POST /v1/assist`,
/// which answers with Claude using the server's key. Same request and reply as the old gateway
/// (`AssistantWire.swift`), so the checks around it (consent, grounding, citation check) are
/// unchanged. There is no gateway address and no invite code: this iPhone signs itself in
/// (`DeviceSession`), and every iPhone may ask. Nothing here logs text.
public struct BackendAssistantClient: AssistantClient {
    private let baseURL: URL?
    private let session: AssistantSession
    private let transport: any GatewayTransport
    private let requestTimeout: TimeInterval

    /// `baseURL`: Doddy's server (https, or http on this device for development). Nil: this build
    /// has no server, and every question says so.
    public init(baseURL: URL?, session: AssistantSession, transport: any GatewayTransport, requestTimeout: TimeInterval = 35) {
        self.baseURL = baseURL
        self.session = session
        self.transport = transport
        self.requestTimeout = requestTimeout
    }

    public func respond(_ request: AssistantRequest) async throws -> AssistantReply {
        guard let baseURL, BackendConnectedAppsClient.isAllowed(baseURL) else { throw AssistantError.notConfigured }
        let body: Data
        do { body = try WireCoding.encode(WireCoding.wireRequest(from: request)) } catch { throw AssistantError.invalidRequest }

        guard let token = await session.token() else { throw AssistantError.notAuthorized }
        var response = try await post(baseURL, body: body, token: token)
        if response.status == 401 {
            // Expired, or the server's key changed: sign in again once, then ask once more.
            guard let fresh = await session.renewed() else { throw AssistantError.notAuthorized }
            response = try await post(baseURL, body: body, token: fresh)
        }
        return try GatewayAssistantClient.interpret(response, for: request, errorMapper: Self.error(from:))
    }

    private func post(_ baseURL: URL, body: Data, token: String) async throws -> GatewayHTTPResponse {
        do {
            return try await transport.send(GatewayHTTPRequest(
                url: baseURL.appendingPathComponent("v1/assist"), method: "POST",
                headers: [
                    "content-type": "application/json",
                    "accept": "application/json",
                    "authorization": "Bearer \(token)",
                ],
                body: body, timeout: requestTimeout))
        } catch {
            switch error {
            case .offline: throw AssistantError.offline
            case .timedOut: throw AssistantError.timeout
            case .cancelled: throw AssistantError.cancelled
            case .other: throw AssistantError.providerUnavailable
            }
        }
    }

    /// The server's error body is `{"error":{"code","message","correlationId","retryAfterSeconds"?}}`.
    static func error(from response: GatewayHTTPResponse) -> AssistantError {
        struct Body: Decodable {
            struct Detail: Decodable {
                let code: String
                let retryAfterSeconds: Int?
            }
            let error: Detail
        }
        let header = response.headers["retry-after"].flatMap { Int($0) }
        if let body = try? JSONDecoder().decode(Body.self, from: response.body) {
            return AssistantError(backendCode: body.error.code, retryAfterSeconds: body.error.retryAfterSeconds ?? header)
        }
        switch response.status {
        case 401: return .notAuthorized
        case 429: return .rateLimited(retryAfterSeconds: header)
        case 400, 413: return .invalidRequest
        case 504: return .timeout
        default: return .providerUnavailable
        }
    }
}
