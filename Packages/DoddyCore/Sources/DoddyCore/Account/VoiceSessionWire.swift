import Foundation

// One token per server (decision 2026-11-12-one-token-per-server), the app's half for the voice server.
//
// The Doddy account signs in once, at Supabase. Its token is traded once, at the voice server's
// `POST /api/voice-auth` action `account-session`, for a session of that server's own: a 10-minute access token and a
// rotating 30-day refresh token, bound to the account. The same endpoint renews it (`refresh`) and ends it (`sign-out`),
// as it does for an older Apple voice account. These are the three requests, and what each answer proves; the shapes
// are the server's (`server/voice-token/README.md`, "One token per server"; `test/account-session.test.js`).
//
// Nothing here keeps anything: `VoiceAccountSessions` decides what is kept, renewed and owed. No answer is read as more
// than it says: "ended" is only ever the server's own 200, and anything that is not an answer (offline, busy, an
// unreadable reply) is `.unavailable`, which no caller treats as success (DOD-08).

/// What the voice server hands out: the session's two tokens and how long the access token lasts (seconds).
public struct VoiceSessionTokens: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int

    public init(accessToken: String, refreshToken: String, expiresIn: Int) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
    }
}

public enum VoiceSessionWire {
    /// `account-session`, with the Doddy account's access token as the bearer.
    public enum Exchange: Equatable, Sendable {
        /// 200 with a session: the server made it.
        case minted(VoiceSessionTokens)
        /// 401: the server doesn't accept the account's token (it ran out, or it isn't one). Nothing was made.
        case accountRefused
        /// No session now, and nothing wrong to remember about it: an older server that doesn't know the action
        /// (400 `unknown_action`), a limit (429), the server or its keys busy (503), any other status, or no
        /// readable answer. The caller carries on with the account's token, as before this change.
        case unavailable
    }

    /// `refresh`, with the refresh token in the body. It works once: the answer carries the next one.
    public enum Refresh: Equatable, Sendable {
        case rotated(VoiceSessionTokens)
        /// 401: the server no longer knows this refresh token (the session ended, ran its 30 days, or the token was
        /// already used). The session is gone; asking again with the same token never helps.
        case refused
        /// Offline, busy, or not a readable answer: nothing is known, and the token is unchanged.
        case unavailable
    }

    /// `sign-out`, with the session's access token as the bearer.
    public enum SignOut: Equatable, Sendable {
        /// 200: the server ended the session.
        case ended
        /// 401: the server doesn't know the session (it already ended, or its access token ran out): nothing is left
        /// to end with this token.
        case alreadyGone
        case unavailable
    }

    public static func exchange(endpoint: URL, accountToken: String, transport: any HTTPTransport) async -> Exchange {
        guard let response = await post(endpoint, ["action": "account-session"], bearer: accountToken, transport) else { return .unavailable }
        switch response.status {
        case 200: return tokens(response.body).map(Exchange.minted) ?? .unavailable
        case 401: return .accountRefused
        default: return .unavailable
        }
    }

    public static func refresh(endpoint: URL, refreshToken: String, transport: any HTTPTransport) async -> Refresh {
        guard let response = await post(endpoint, ["action": "refresh", "refreshToken": refreshToken], bearer: nil, transport) else {
            return .unavailable
        }
        switch response.status {
        case 200: return tokens(response.body).map(Refresh.rotated) ?? .unavailable
        case 401: return .refused
        default: return .unavailable
        }
    }

    public static func signOut(endpoint: URL, accessToken: String, transport: any HTTPTransport) async -> SignOut {
        guard let response = await post(endpoint, ["action": "sign-out"], bearer: accessToken, transport) else { return .unavailable }
        switch response.status {
        case 200: return .ended
        case 401: return .alreadyGone
        default: return .unavailable
        }
    }

    // MARK: Plumbing

    private static func post(_ endpoint: URL, _ body: [String: String], bearer: String?, _ transport: any HTTPTransport) async -> (status: Int, body: Data)? {
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return nil }
        var headers = ["content-type": "application/json", "accept": "application/json"]
        if let bearer { headers["authorization"] = "Bearer \(bearer)" }
        return try? await transport.send(HTTPRequest(method: "POST", url: endpoint, headers: headers, body: data))
    }

    /// A session reply: both tokens, not empty, and an access token that lasts (the server's is 600 seconds).
    private static func tokens(_ body: Data) -> VoiceSessionTokens? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let access = json["accessToken"] as? String, !access.isEmpty,
              let refresh = json["refreshToken"] as? String, !refresh.isEmpty,
              let lifetime = json["expiresIn"] as? Int, lifetime > 0
        else { return nil }
        return VoiceSessionTokens(accessToken: access, refreshToken: refresh, expiresIn: lifetime)
    }
}
