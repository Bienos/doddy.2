import Foundation

// One token per server (decision 2026-11-12-one-token-per-server): which token a request to `/api/voice-token` carries
// while a Doddy account is signed in. The server accepts both kinds this release, so the move can't break anyone:
// 1. this server's own session token, when the account has one (`VoiceAccountSessions`);
// 2. the account's Supabase token, exactly as before this change, when no session can be had (an older server that
//    answers 400 `unknown_action`, the exchange not completing) or when the session was refused twice.
// A refused session (401) is forgotten and asked for again once. Any other answer, a rate limit included, is the
// caller's to read as it always was: the account counts the same under either token, so a second try would only count again.

/// What the token server answered: the status, the body and the Retry-After header (read for a 429, ADR-712).
public struct VoiceTokenAnswer: Equatable, Sendable {
    public let status: Int
    public let body: Data
    public let retryAfter: String?

    public init(status: Int, body: Data, retryAfter: String?) {
        self.status = status
        self.body = body
        self.retryAfter = retryAfter
    }
}

public enum VoiceTokenAttempt {
    /// Sends the request with the right token and returns what came back, or nil when there is no Doddy-account token of
    /// any kind to send (signed out, or no token could be had): the caller then uses this iPhone's own older voice
    /// session, as before.
    /// - `sessionToken`: the voice server's own access token for the account, or nil when none can be had now.
    /// - `sessionRefused`: this session token was refused by the voice server (401): forget it.
    /// - `accountToken`: the Doddy account's Supabase token, the fallback.
    /// - `send`: the request, with the token as the bearer. A request that couldn't be made is a failure and is returned as
    ///   it is, never retried with another token.
    public static func run(
        sessionToken: @Sendable () async -> String?,
        sessionRefused: @Sendable (String) async -> Void,
        accountToken: @Sendable () async -> String?,
        send: @Sendable (String) async -> Result<VoiceTokenAnswer, VoiceTokenError>
    ) async -> Result<VoiceTokenAnswer, VoiceTokenError>? {
        // At most two sessions are tried: the one in hand, and one made after it was refused.
        for _ in 0..<2 {
            guard let token = await sessionToken() else { break }
            let result = await send(token)
            guard case .success(let answer) = result, answer.status == 401 else { return result }
            await sessionRefused(token)
        }
        guard let token = await accountToken() else { return nil }
        return await send(token)
    }
}
