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
        let token = try VoiceTokenServer.token(status: status, body: data, retryAfter: retryAfter).get()
        // Decision 2026-11-12-voice-conversations-per-account: the server's keyed id for this account comes with the
        // token. It is kept with that token until the token is used, so the conversation starts with the user id
        // that belongs to it (`VoiceUserIDPolicy`); an answer without one leaves the install id, as before.
        VoiceTokenUserIDs.shared.remember(VoiceTokenServer.userID(fromAnswer: data), forToken: token)
        return token
    }

    /// The status, the body and the reply's Retry-After header, which says how long a 429 lasts (the
    /// message reads it in minutes, hours or "tomorrow", ADR-712).
    private func post(agent: VoiceAgentKind) async throws(VoiceTokenError) -> (Int, Data, String?) {
        // Decision 2026-11-12-one-token-per-server: signed in to a Doddy account, the voice server's own session for it
        // goes first (made once with the account's token, kept, renewed); the account's own token is what is sent when no
        // session can be had (an older server, the exchange not completing) or the session was refused twice, exactly as
        // before. A 401 for a session is forgotten and asked for once more. Any other answer, a rate limit included, is
        // read as it always was. The rules are `VoiceTokenAttempt` in DoddyCore, tested on Linux.
        let withAccount = await VoiceTokenAttempt.run(
            sessionToken: { await DoddyAccountServers.voiceSessionToken() },
            sessionRefused: { token in await DoddyAccountServers.voiceSessionRefused(token) },
            accountToken: { await DoddyAccountServers.voiceAccountToken() },
            send: { bearer in await attempt(agent: agent, bearer: bearer) })
        if let withAccount {
            let answer = try withAccount.get()
            return (answer.status, answer.body, answer.retryAfter)
        }
        // No Doddy account token of any kind (signed out, or none could be had): this iPhone's own older voice session,
        // which works whether or not the voice server takes accounts yet.
        let bearer: String
        do { bearer = try await VoiceAuthSession.shared.bearerToken() }
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
        }
        let answer = try await attempt(agent: agent, bearer: bearer).get()
        // A refused account token says nothing about the voice session, so only this path forgets it.
        if answer.status == 401 { await VoiceAuthSession.shared.serverRejectedSession() }
        return (answer.status, answer.body, answer.retryAfter)
    }

    /// One request to the token server with this bearer. A request that couldn't be made is the failure, never retried here.
    private func attempt(agent: VoiceAgentKind, bearer: String) async -> Result<VoiceTokenAnswer, VoiceTokenError> {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        if let body = agent.requestBody {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
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
            return .failure(VoiceTokenServer.loadingFailure(error))
        }
        // An answer from any other address than the one asked isn't read.
        guard BearerHost.answered(response.url, sameAs: endpoint) else { return .failure(.badResponse) }
        let http = response as? HTTPURLResponse
        return .success(VoiceTokenAnswer(status: http?.statusCode ?? 0, body: data, retryAfter: http?.value(forHTTPHeaderField: "Retry-After")))
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

    /// Before the account is deleted (decision 2026-11-12-voice-conversations-per-account): the voice server deletes the
    /// account's voice conversations at ElevenLabs, reads each one back, and answers counts. It takes the Doddy
    /// account's token, like `revokeApple`, and the install id this iPhone gave ElevenLabs before there was an account
    /// id, so older conversations go too. The status and body go to `VoiceConversationErasure`, which decides what
    /// counts as confirmed; nothing is thrown, because a failure is an answer ("not confirmed"), not an error to show.
    func deleteConversations(accountToken: String, installID: String?) async -> VoiceConversationErasure.Attempt {
        guard let endpoint = VoiceConfig.authEndpoint,
              let body = try? JSONSerialization.data(withJSONObject: VoiceConversationErasure.requestBody(installID: installID))
        else { return .failed }
        // The server works for up to about 10 seconds before it answers with what is left.
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accountToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response): (Data, URLResponse)
        // Redirects refused and the answer read only from the address asked, as for every request here that carries a token.
        do { (data, response) = try await session.data(for: request, delegate: ServerHTTPTransport.RefuseRedirects()) }
        catch { return .failed }
        guard BearerHost.answered(response.url, sameAs: endpoint),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { return .failed }
        return VoiceConversationErasure.attempt(status: status, body: data)
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
