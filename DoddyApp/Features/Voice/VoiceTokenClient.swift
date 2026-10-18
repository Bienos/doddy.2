import DoddyCore
import Foundation

/// Fetches a short-lived, provider-scoped credential from DODDY's server. It sends a DODDY
/// session bearer, never an owner/provider key or conversation content.
/// For the OpenAI voice (ADR-265) the body also names the provider and the model (ADR-442).
/// The voice account's own calls to the same server (`VoiceAuthAPI`) are below (ADR-483).
struct VoiceTokenClient: Sendable {
    let endpoint: URL
    /// ElevenLabs conversation token. Sends no body, exactly as before ADR-265.
    func fetchToken() async throws(VoiceTokenError) -> String {
        let (status, data) = try await post(VoiceTokenServer.requestBody(for: .elevenLabs))
        return try VoiceTokenServer.token(status: status, body: data).get()
    }

    /// OpenAI Realtime client secret for the chosen model.
    func fetchOpenAIGrant(model: OpenAIRealtimeModel) async throws(VoiceTokenError) -> OpenAIRealtimeGrant {
        let (status, data) = try await post(VoiceTokenServer.requestBody(for: .openAIRealtime, model: model))
        return try VoiceTokenServer.openAIGrant(status: status, body: data).get()
    }

    /// The owner's Picovoice AccessKey for "Hey Doddy" (ADR-328). Starts no conversation.
    func fetchWakeWordKey() async throws(VoiceTokenError) -> String {
        let (status, data) = try await post(VoiceTokenServer.wakeWordKeyRequestBody)
        return try VoiceTokenServer.wakeWordKey(status: status, body: data).get()
    }

    private func post(_ body: Data?) async throws(VoiceTokenError) -> (Int, Data) {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        let accessToken: String
        do { accessToken = try await VoiceAuthSession.shared.bearerToken() }
        catch let error as VoiceAuthFailure {
            switch error {
            case .offline: throw .offline
            case .sessionExpired: throw .sessionExpired
            case .serverNotConfigured: throw .serverNotConfigured
            case .rejected, .badResponse: throw .badResponse
            }
        } catch { throw .badResponse }
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        // One ephemeral session per fetch, as before, but released when it is done (review H11):
        // a URLSession that is never invalidated is never freed.
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { await VoiceAuthSession.shared.serverRejectedSession() }
        return (status, data)
    }
}

/// The DODDY voice account's calls to the same token server (`/api/voice-auth`): exchange
/// Apple's identity token for a session, refresh it, sign out, delete the account. Kept in this
/// file so the app's own networking stays in the files the capability guard allows (ADR-483).
struct VoiceSessionReply: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

actor VoiceAuthAPI {
    static let shared = VoiceAuthAPI()

    func signIn(_ identityToken: String, rawNonce: String, provider: String) async throws -> VoiceSessionReply {
        try await post(["action": "sign-in", "identityToken": identityToken, "rawNonce": rawNonce, "provider": provider])
    }

    func refresh(_ refreshToken: String) async throws -> VoiceSessionReply {
        try await post(["action": "refresh", "refreshToken": refreshToken])
    }

    func signOut(_ accessToken: String) async throws {
        let _: EmptyReply = try await post(["action": "sign-out"], bearer: accessToken)
    }

    func deleteAccount(_ accessToken: String) async throws {
        let _: EmptyReply = try await post(["action": "delete-account"], bearer: accessToken)
    }

    private func post<T: Decodable>(_ body: [String: Any], bearer: String? = nil) async throws -> T {
        guard let endpoint = VoiceConfig.authEndpoint else { throw VoiceAuthFailure.serverNotConfigured }
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response): (Data, URLResponse)
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        do { (data, response) = try await session.data(for: request) }
        catch { throw VoiceAuthFailure.offline }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw VoiceAuthFailure.badResponse }
        guard (200..<300).contains(status) else {
            if status == 401 { throw VoiceAuthFailure.sessionExpired }
            if status == 404 || status == 500 || status == 503 { throw VoiceAuthFailure.serverNotConfigured }
            throw VoiceAuthFailure.rejected
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else { throw VoiceAuthFailure.badResponse }
        return decoded
    }
}

private struct EmptyReply: Decodable {}
