import DoddyCore
import Foundation
import os

/// Fetches a short-lived ElevenLabs credential from DODDY's server. It sends a DODDY
/// session bearer, never an owner/provider key or conversation content.
struct VoiceTokenClient: Sendable {
    let endpoint: URL
    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "voice-audio")
    /// ElevenLabs conversation token. Sends no body for the main agent (ElevenLabs is the only voice, 9 Nov 2026);
    /// translating asks for its own agent, which has no tools (decision 2026-11-12-translator-agent).
    func fetchToken(agent: VoiceAgentKind = .main) async throws(VoiceTokenError) -> String {
        // How long the token server took, on the "voice-audio" log with the start's other stages
        // (decision 2026-11-10-voice-start-timing): seconds only.
        let began = ProcessInfo.processInfo.systemUptime
        defer {
            let took = VoiceStartTimeline.text(ProcessInfo.processInfo.systemUptime - began)
            Self.log.notice("voice token request took \(took, privacy: .public)")
        }
        let (status, data, retryAfter) = try await post(agent: agent)
        return try VoiceTokenServer.token(status: status, body: data, retryAfter: retryAfter).get()
    }

    /// The status, the body and the reply's Retry-After header, which says how long a 429 lasts (the
    /// message reads it in minutes, hours or "tomorrow", ADR-712).
    private func post(agent: VoiceAgentKind) async throws(VoiceTokenError) -> (Int, Data, String?) {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        if let body = agent.requestBody {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        var accessToken: String?
        // Decision 2026-11-08-required-account: the Doddy account's token, unless this iPhone still has its
        // own voice session (that one works whether or not the voice server takes accounts yet).
        let accountToken = await DoddyAccountServers.voiceAccountToken()
        if let accountToken { accessToken = accountToken }
        else { do { accessToken = try await VoiceAuthSession.shared.bearerToken() }
        catch let error as VoiceAuthFailure {
            switch error {
            case .offline: throw .offline
            case .sessionExpired: throw .sessionExpired
            case .serverNotConfigured: throw .serverNotConfigured
            case .rejected, .badResponse: throw .badResponse
            // Only a failed sign-in leaves this behind, and then no session is saved: a new sign-in is what's needed.
            case .tooManySignIns: throw .sessionExpired
            }
        } catch {
            throw .badResponse
        } }
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        // One ephemeral session per fetch, as before, but released when it is done (review H11):
        // a URLSession that is never invalidated is never freed.
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        do {
            // Redirects are refused, as for the messaging server, so the bearer token never follows one
            // (decision 2026-11-12-local-data-owner).
            (data, response) = try await session.data(for: request, delegate: ServerHTTPTransport.RefuseRedirects())
        } catch {
            // Only a missing or lost connection is "offline"; a cancelled request, a timeout and a
            // refused secure connection each say what happened (ADR-681).
            throw VoiceTokenServer.loadingFailure(error)
        }
        // An answer from any other address than the one asked isn't read.
        guard BearerHost.answered(response.url, sameAs: endpoint) else { throw .badResponse }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // A refused account token says nothing about the voice session, so that one is left alone.
        if status == 401, accountToken == nil { await VoiceAuthSession.shared.serverRejectedSession() }
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

    // Decision 2026-11-09-apple-revoke-for-doddy-accounts: a Doddy account (not a voice session) that
    // signed in with Apple. Both take the Doddy account's access token as the bearer.

    /// Right after that sign-in: the server keeps Apple's token, sealed, so deleting the account can end
    /// Sign in with Apple. True only when the server kept it; the account works either way.
    func linkApple(accountToken: String, identityToken: String, rawNonce: String, authorizationCode: String) async throws -> Bool {
        let reply: AppleLinkReply = try await post(
            ["action": "apple-link", "identityToken": identityToken, "rawNonce": rawNonce, "authorizationCode": authorizationCode],
            bearer: accountToken)
        return reply.linked
    }

    /// Before the account is deleted: the server tells Apple to end the link. True only when Apple said yes.
    func revokeApple(accountToken: String) async throws -> Bool {
        let reply: AppleRevokeReply = try await post(["action": "apple-revoke"], bearer: accountToken)
        return reply.appleRevoked
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
        // Redirects refused and the answer read only from the address asked, as for the token above
        // (decision 2026-11-12-local-data-owner): these requests carry a session or account token.
        do { (data, response) = try await session.data(for: request, delegate: ServerHTTPTransport.RefuseRedirects()) }
        catch { throw VoiceAuthFailure.offline }
        guard BearerHost.answered(response.url, sameAs: endpoint) else { throw VoiceAuthFailure.badResponse }
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
private struct AppleLinkReply: Decodable { let linked: Bool }
private struct AppleRevokeReply: Decodable { let appleRevoked: Bool }
