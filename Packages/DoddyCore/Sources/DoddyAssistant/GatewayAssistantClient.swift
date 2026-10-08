import DoddyCore
import Foundation

public struct GatewayConfiguration: Sendable {
    /// e.g. https://<project>.supabase.co/functions/v1/assistant
    public let baseURL: URL
    public let locale: String

    public init(baseURL: URL, locale: String = "en") {
        self.baseURL = baseURL
        self.locale = locale
    }
}

/// Talks to the Doddy gateway (gateway/README.md). Holds no provider key: the gateway does.
///
/// - Sends only the user's text and the explicitly selected, recall-eligible memories.
/// - Re-verifies citations: any cited id that was not sent makes the reply `invalidCitations`.
/// - Registers an anonymous device token on first use and retries once after a 401.
public actor GatewayAssistantClient: AssistantClient {
    public static let maxMemories = 5
    private static let maxTextScalars = MemoryLimits.maxTextLength

    private let configuration: GatewayConfiguration
    private let transport: any HTTPTransport
    private let tokenStore: any DeviceTokenStore
    private let makeRequestID: @Sendable () -> UUID
    private var registration: Task<String, any Error>?

    public init(
        configuration: GatewayConfiguration,
        transport: any HTTPTransport,
        tokenStore: any DeviceTokenStore,
        makeRequestID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.tokenStore = tokenStore
        self.makeRequestID = makeRequestID
    }

    public func respond(_ request: AssistantRequest) async throws -> AssistantReply {
        let memories = request.groundingMemories.filter { $0.record.source.isEligibleForPersonalRecall }
        let text = request.userText
        guard !text.allSatisfy(\.isWhitespace),
              text.unicodeScalars.count <= Self.maxTextScalars,
              memories.count <= Self.maxMemories
        else { throw AssistantError.invalidRequest }

        let sentIDs = Set(memories.map(\.memoryID))
        let body: Data
        do {
            body = try JSONEncoder().encode(ChatBody(
                requestId: makeRequestID().uuidString,
                sessionId: request.sessionID.uuidString,
                taskType: memories.isEmpty ? "chat" : "recall",
                locale: configuration.locale,
                turns: [.init(role: "user", text: text)],
                memories: memories.map {
                    .init(id: $0.memoryID.uuidString, currentText: $0.record.currentText, source: $0.record.source.rawValue)
                }))
        } catch { throw AssistantError.invalidRequest }

        do {
            return try await attempt(body: body, sentIDs: sentIDs)
        } catch AssistantError.notAuthorized {
            // The stored token was rejected (e.g. the gateway forgot it): register again, once.
            await tokenStore.clear()
            return try await attempt(body: body, sentIDs: sentIDs)
        }
    }

    // MARK: - Steps

    private func attempt(body: Data, sentIDs: Set<UUID>) async throws -> AssistantReply {
        try Task.checkCancellation()
        let token = try await ensureToken()
        let response = try await send(HTTPRequest(
            url: configuration.baseURL.appendingPathComponent("chat"),
            method: "POST",
            headers: ["content-type": "application/json", "authorization": "Bearer \(token)"],
            body: body))
        guard response.status == 200 else { throw failure(for: response) }
        guard let reply = try? JSONDecoder().decode(ChatReply.self, from: response.body),
              !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw AssistantError.malformedResponse }

        var cited: [UUID] = []
        for raw in reply.citedMemoryIds {
            guard let id = UUID(uuidString: raw), sentIDs.contains(id) else { throw AssistantError.invalidCitations }
            if !cited.contains(id) { cited.append(id) }
        }
        if reply.invalidCitations == true { throw AssistantError.invalidCitations }
        return AssistantReply(text: reply.text, citedMemoryIDs: cited)
    }

    private func ensureToken() async throws -> String {
        if let existing = await tokenStore.token() { return existing }
        if let inFlight = registration { return try await inFlight.value }
        let task = Task { try await self.register() }
        registration = task
        defer { registration = nil }
        return try await task.value
    }

    private func register() async throws -> String {
        let response = try await send(HTTPRequest(
            url: configuration.baseURL.appendingPathComponent("register"), method: "POST"))
        guard response.status == 200 else { throw failure(for: response) }
        guard let decoded = try? JSONDecoder().decode(RegisterReply.self, from: response.body),
              !decoded.deviceToken.isEmpty
        else { throw AssistantError.malformedResponse }
        do { try await tokenStore.save(decoded.deviceToken) } catch { throw AssistantError.providerUnavailable }
        return decoded.deviceToken
    }

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch is CancellationError {
            throw AssistantError.cancelled
        } catch let error as TransportError {
            throw error == .offline ? AssistantError.offline : AssistantError.timeout
        } catch {
            throw AssistantError.providerUnavailable
        }
    }

    private func failure(for response: HTTPResponse) -> AssistantError {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: response.body),
           let mapped = AssistantError(gatewayCode: envelope.error) {
            return mapped
        }
        switch response.status {
        case 401: return .notAuthorized
        case 429: return .rateLimited
        case 400: return .invalidRequest
        case 408, 504: return .timeout
        default: return .providerUnavailable
        }
    }

    // MARK: - Wire format (gateway/README.md)

    private struct ChatBody: Encodable {
        struct Turn: Encodable { let role: String; let text: String }
        struct Memory: Encodable { let id: String; let currentText: String; let source: String }
        let requestId: String
        let sessionId: String
        let taskType: String
        let locale: String
        let turns: [Turn]
        let memories: [Memory]
    }

    private struct ChatReply: Decodable {
        let text: String
        let citedMemoryIds: [String]
        let invalidCitations: Bool?
    }

    private struct RegisterReply: Decodable { let deviceToken: String }
    private struct ErrorEnvelope: Decodable { let error: String }
}
