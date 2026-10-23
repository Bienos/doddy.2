import Foundation

/// The `AssistantClient` behind Messages (ADR-585, ADR-586): asks Doddy's messaging server, which asks Claude.
/// The wire is the gateway's (`AssistantWire`), so the reply is read by the same code (`GatewayAssistantClient`),
/// and the account is the anonymous device account every other server feature uses: no invite code, no key on
/// the iPhone. Nothing here logs text. Every error is an `AssistantError`.
public struct ServerAssistantClient: AssistantClient {
    private let server: DoddyServerClient?
    private let requestTimeout: TimeInterval

    /// - Parameter server: nil when this build has no messaging server address.
    /// - Parameter requestTimeout: a little over the server's own 45 s limit, so the server's "timeout" answer arrives first.
    public init(server: DoddyServerClient?, requestTimeout: TimeInterval = 50) {
        self.server = server
        self.requestTimeout = requestTimeout
    }

    public func respond(_ request: AssistantRequest) async throws -> AssistantReply {
        guard let server else { throw AssistantError.notConfigured }
        let body: Data
        do { body = try WireCoding.encode(WireCoding.wireRequest(from: request)) } catch { throw AssistantError.invalidRequest }

        var retriedAccount = false
        while true {
            do {
                let response = try await server.askAssistant(body, timeout: requestTimeout)
                return try GatewayAssistantClient.interpret(
                    GatewayHTTPResponse(status: response.status, body: response.body), for: request)
            } catch let error as AssistantError {
                throw error
            } catch ServerError.accountMissing where !retriedAccount {
                // The server no longer knows this device and the token was removed: the next call makes a
                // new anonymous account. Try once more with it.
                retriedAccount = true
            } catch is DoddyServerClient.OutcomeUnknown {
                // It may have reached the server but no answer came back, or the person stopped it. Not
                // retried here: sending it again is the person's choice (DOD-11).
                throw Task.isCancelled ? AssistantError.cancelled : AssistantError.timeout
            } catch let error as ServerError {
                throw Task.isCancelled ? AssistantError.cancelled : Self.map(error)
            } catch {
                throw Task.isCancelled || error is CancellationError ? AssistantError.cancelled : AssistantError.providerUnavailable
            }
        }
    }

    static func map(_ error: ServerError) -> AssistantError {
        switch error {
        case .offline: .offline
        case .accountMissing: .notAuthorized
        case .rateLimited: .rateLimited(retryAfterSeconds: nil)
        case .notConfigured: .notConfigured
        case .invalidRequest: .invalidRequest
        default: .providerUnavailable
        }
    }
}

extension DoddyServerClient {
    /// Messages (ADR-586). Returns the server's answer as it is. `startsSomething` makes a request that may have
    /// reached the server without an answer coming back `OutcomeUnknown`, never "offline".
    func askAssistant(_ body: Data, timeout: TimeInterval) async throws -> ServerResponse {
        try await authorized(.post, "/v1/assistant/ask", body: body, startsSomething: true, timeout: timeout)
    }
}
