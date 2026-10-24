import Foundation

/// The first `AssistantClient`: talks to the separate Doddy gateway (OpenAI), which holds the
/// provider key. Since ADR-587 the app uses `BackendAssistantClient` (Doddy's own server, Claude)
/// instead, and nothing in the app builds this one; it stays, tested, with `gateway/`, until the
/// owner decides to delete both. Nothing here logs text. Errors are the `AssistantError` taxonomy.
public struct GatewayAssistantClient: AssistantClient {
    private let configuration: GatewayConfiguration?
    private let transport: any GatewayTransport
    private let credentials: any DeviceCredentialStore
    private let now: @Sendable () -> Date
    private let requestTimeout: TimeInterval

    public init(
        configuration: GatewayConfiguration?,
        transport: any GatewayTransport,
        credentials: any DeviceCredentialStore,
        requestTimeout: TimeInterval = 35,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.credentials = credentials
        self.requestTimeout = requestTimeout
        self.now = now
    }

    public func respond(_ request: AssistantRequest) async throws -> AssistantReply {
        guard let configuration else { throw AssistantError.notConfigured }
        let body: Data
        do { body = try WireCoding.encode(WireCoding.wireRequest(from: request)) } catch { throw AssistantError.invalidRequest }

        var token = try await currentToken(configuration)
        var response = try await post(configuration, body: body, token: token)
        if response.status == 401 {
            // The token may have expired or been rotated. Register again once, then retry once.
            try await credentials.setToken(nil)
            token = try await currentToken(configuration)
            response = try await post(configuration, body: body, token: token)
        }
        return try Self.interpret(response, for: request)
    }

    // MARK: - Token

    private func currentToken(_ configuration: GatewayConfiguration) async throws -> DeviceToken {
        let host = configuration.baseURL.host
        if let token = try await credentials.token(), token.gatewayHost == host, token.expiresAt.timeIntervalSince(now()) > 60 {
            return token
        }
        guard let invite = try await credentials.inviteCode(), !invite.isEmpty else { throw AssistantError.notConfigured }
        let deviceID = try await credentials.deviceID()
        let payload = try WireCoding.encode(RegisterWireRequest(inviteCode: invite, deviceId: WireCoding.uuid(deviceID)))

        let response = try await send(GatewayHTTPRequest(
            url: configuration.endpoint("register"), method: "POST",
            headers: ["content-type": "application/json", "accept": "application/json"],
            body: payload, timeout: 15))
        guard response.status == 200 else { throw Self.error(from: response) }
        guard let decoded = try? JSONDecoder().decode(RegisterWireResponse.self, from: response.body),
              decoded.schemaVersion == 1, !decoded.token.isEmpty
        else { throw AssistantError.malformedResponse }

        let token = DeviceToken(
            value: decoded.token,
            expiresAt: Date(timeIntervalSince1970: Double(decoded.expiresAtMs) / 1000),
            gatewayHost: host)
        try await credentials.setToken(token)
        return token
    }

    // MARK: - HTTP

    private func post(_ configuration: GatewayConfiguration, body: Data, token: DeviceToken) async throws -> GatewayHTTPResponse {
        try await send(GatewayHTTPRequest(
            url: configuration.endpoint("assist"), method: "POST",
            headers: [
                "content-type": "application/json",
                "accept": "application/json",
                "authorization": "Bearer \(token.value)",
            ],
            body: body, timeout: requestTimeout))
    }

    private func send(_ request: GatewayHTTPRequest) async throws -> GatewayHTTPResponse {
        do {
            return try await transport.send(request)
        } catch {
            switch error {
            case .offline: throw AssistantError.offline
            case .timedOut: throw AssistantError.timeout
            case .cancelled: throw AssistantError.cancelled
            case .other: throw AssistantError.providerUnavailable
            }
        }
    }

    // MARK: - Decoding

    static func interpret(
        _ response: GatewayHTTPResponse, for request: AssistantRequest,
        errorMapper: (GatewayHTTPResponse) -> AssistantError = GatewayAssistantClient.error(from:)
    ) throws -> AssistantReply {
        guard response.status == 200 else { throw errorMapper(response) }
        guard let wire = try? JSONDecoder().decode(AssistWireResponse.self, from: response.body),
              wire.schemaVersion == 1,
              wire.requestId.lowercased() == WireCoding.uuid(request.requestID)
        else { throw AssistantError.malformedResponse }

        var cited: [UUID] = []
        for raw in wire.citedMemoryIDs {
            guard let id = UUID(uuidString: raw) else { throw AssistantError.invalidCitations }
            cited.append(id)
        }
        // A proposal that does not fit the limits is dropped; the answer is still shown.
        let proposal = wire.proposal.flatMap { AssistantProposal.make(kind: $0.kind, title: $0.title, request: $0.request) }
        return AssistantReply(text: wire.text, citedMemoryIDs: cited, proposal: proposal)
    }

    static func error(from response: GatewayHTTPResponse) -> AssistantError {
        let header = response.headers["retry-after"].flatMap { Int($0) }
        if let wire = try? JSONDecoder().decode(AssistWireError.self, from: response.body) {
            return AssistantError(wireCode: wire.error.code, retryAfterSeconds: wire.error.retryAfterSeconds ?? header)
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
