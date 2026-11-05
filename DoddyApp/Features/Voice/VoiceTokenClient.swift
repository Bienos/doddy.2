import DoddyCore
import Foundation

/// Fetches a short-lived, provider-scoped credential from DODDY's server. It sends a DODDY
/// session bearer, never an owner/provider key or conversation content.
/// For the OpenAI voice (ADR-265) the body also names the provider and the model (ADR-442).
struct VoiceTokenClient: Sendable {
    let endpoint: URL
    /// ElevenLabs conversation token. Sends no body, exactly as before ADR-265.
    func fetchToken() async throws(VoiceTokenError) -> String {
        let (status, data, retryAfter) = try await post(VoiceTokenServer.requestBody(for: .elevenLabs))
        return try VoiceTokenServer.token(status: status, body: data, retryAfter: retryAfter).get()
    }

    /// OpenAI Realtime client secret for the chosen model.
    func fetchOpenAIGrant(model: OpenAIRealtimeModel) async throws(VoiceTokenError) -> OpenAIRealtimeGrant {
        // A Debug build may go without a voice account (ADR-726); the server decides whether to allow it.
        let (status, data, retryAfter) = try await post(
            VoiceTokenServer.requestBody(for: .openAIRealtime, model: model), anonymousAllowed: VoiceConfig.openAIWithoutAccount)
        return try VoiceTokenServer.openAIGrant(status: status, body: data, retryAfter: retryAfter).get()
    }

    /// The status, the body and the reply's Retry-After header, which says how long a 429 lasts (the
    /// message reads it in minutes, hours or "tomorrow", ADR-712).
    private func post(_ body: Data?, anonymousAllowed: Bool = false) async throws(VoiceTokenError) -> (Int, Data, String?) {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        let accessToken: String?
        do { accessToken = try await VoiceAuthSession.shared.bearerToken() }
        catch let error as VoiceAuthFailure {
            if anonymousAllowed {
                // No session: ask without one. The server refuses with 401 unless it allows this (ADR-726).
                accessToken = nil
            } else {
                switch error {
                case .offline: throw .offline
                case .sessionExpired: throw .sessionExpired
                case .serverNotConfigured: throw .serverNotConfigured
                case .rejected, .badResponse: throw .badResponse
                // Only a failed sign-in leaves this behind, and then no session is saved: a new sign-in is what's needed.
                case .tooManySignIns: throw .sessionExpired
                }
            }
        } catch {
            if anonymousAllowed { accessToken = nil } else { throw .badResponse }
        }
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
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
            // Only a missing or lost connection is "offline"; a cancelled request, a timeout and a
            // refused secure connection each say what happened (ADR-681).
            throw VoiceTokenServer.loadingFailure(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, !anonymousAllowed { await VoiceAuthSession.shared.serverRejectedSession() }
        return (status, data, (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After"))
    }
}

/// DODDY's own session with the voice token server: Apple sign-in, refresh, sign-out and account
/// deletion (commit 754e5d6). It lives here, beside the provider-token requests to the same
/// server, so the app's networking stays in the files the capability guard allows (ADR-494).
actor VoiceAuthAPI {
    static let shared = VoiceAuthAPI()

    /// `authorizationCode` is Apple's one-time code from the same sign-in. The server swaps it for
    /// the token it needs to revoke Sign in with Apple when the account is deleted (ADR-524).
    func signIn(_ identityToken: String, rawNonce: String, authorizationCode: String? = nil,
                provider: String) async throws -> VoiceSessionReply {
        var body: [String: Any] = ["action": "sign-in", "identityToken": identityToken, "rawNonce": rawNonce, "provider": provider]
        if let authorizationCode, !authorizationCode.isEmpty { body["authorizationCode"] = authorizationCode }
        return try await post(body)
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
            // A 429 on a sign-in is the server's limit per caller address, not Apple's token failing to
            // verify (ADR-712); DoddyCore reads the status and the Retry-After header.
            let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
            switch VoiceAuthStatus.failure(status: status, action: body["action"] as? String ?? "", retryAfter: retryAfter) {
            case .sessionExpired: throw VoiceAuthFailure.sessionExpired
            case .serverNotConfigured: throw VoiceAuthFailure.serverNotConfigured
            case .tooManySignIns(let seconds): throw VoiceAuthFailure.tooManySignIns(retryAfterSeconds: seconds)
            case .rejected: throw VoiceAuthFailure.rejected
            }
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else { throw VoiceAuthFailure.badResponse }
        return decoded
    }
}

private struct EmptyReply: Decodable {}
