import Foundation

// One token per server (decision 2026-11-12-one-token-per-server), the app's half for the backend `doddy`.
//
// The Doddy account signs in once, at Supabase. Its token is traded once, at the backend's `POST /v1/session/account`, for a
// session of the backend's own for THIS iPhone: a `ds1` token of 30 days that names this iPhone's stored row, and the row's
// id (`deviceListId`), which is what the sign-out names (`DELETE /v1/web/devices/:id`, called with the iPhone's own session).
// These are the two requests, and what each answer proves; the shapes are the server's (`backend/src/accountSession.ts`,
// `docs/decisions/2026-11-14-backend-account-session.md`).
//
// Nothing here keeps anything: `BackendAccountSessions` decides what is kept, renewed and owed. No answer is read as more than
// it says: "ended" is only ever the server's own 200 with `revoked: true`, and anything that is not an answer (offline, busy,
// an unreadable reply, a route this server doesn't have) is `.unavailable`, which no caller treats as success (DOD-08).

/// A backend account session as the server handed it out.
public struct BackendSessionGrant: Equatable, Sendable {
    public let token: String
    /// The expiry the server wrote into the token, read from `expiresAt`: not an estimate.
    public let expiresAt: Date
    /// This iPhone's stored row, as `GET /v1/web/devices` lists it and `DELETE /v1/web/devices/:id` names it. Not the device id.
    public let deviceListID: String

    public init(token: String, expiresAt: Date, deviceListID: String) {
        self.token = token
        self.expiresAt = expiresAt
        self.deviceListID = deviceListID
    }
}

public enum BackendAccountSessionWire {
    /// `POST /v1/session/account`, with the Doddy account's Supabase token as the bearer and the device id as the body.
    public enum Exchange: Equatable, Sendable {
        /// 200 with an account session for the account that asked: the server made it.
        case minted(BackendSessionGrant)
        /// 401: the server doesn't accept the account's token (it ran out, or it isn't one). Nothing was made.
        case accountRefused
        /// 429: a limit (tries from this address, exchanges for this account, or iPhones on this account). Nothing was made.
        case rateLimited
        /// No session now, and nothing wrong to remember about it: a server that doesn't have the route (404, which is what a
        /// production server without a session key answers), one that isn't set up for it (503), a failure (5xx), an answer that
        /// isn't an account session for this account, or no readable answer. The caller carries on with the account's token, as
        /// before this change.
        case unavailable
    }

    /// `DELETE /v1/web/devices/:id`, with the account session itself as the bearer.
    public enum SignOut: Equatable, Sendable {
        /// 200 with `revoked: true`: the server ended this iPhone's row, so this session and any other of its tokens.
        case ended
        /// 401: the server doesn't accept this session (it was ended already, ran its 30 days, or its account is gone): nothing
        /// is left to end with it.
        case alreadyGone
        /// Offline, busy, a limit, a route or an iPhone this server doesn't know (404), or an answer that doesn't say it was
        /// done: nothing is known.
        case unavailable
    }

    public static func exchange(
        server: URL, accountID: String, accountToken: String, deviceID: String, transport: any HTTPTransport
    ) async -> Exchange {
        guard let device = UUID(uuidString: deviceID)?.uuidString.lowercased(),
              let body = try? JSONSerialization.data(withJSONObject: ["deviceId": device], options: [.sortedKeys])
        else { return .unavailable }
        let request = HTTPRequest(
            method: "POST", url: server.appendingPathComponent("v1/session/account"),
            headers: ["authorization": "Bearer \(accountToken)", "content-type": "application/json", "accept": "application/json"],
            body: body)
        guard let response = try? await transport.send(request) else { return .unavailable }
        switch response.status {
        case 200: return grant(response.body, for: accountID).map(Exchange.minted) ?? .unavailable
        case 401: return .accountRefused
        case 429: return .rateLimited
        default: return .unavailable
        }
    }

    public static func signOut(server: URL, token: String, deviceListID: String, transport: any HTTPTransport) async -> SignOut {
        // The id goes into a path: only an id.
        guard let row = UUID(uuidString: deviceListID)?.uuidString.lowercased() else { return .unavailable }
        let request = HTTPRequest(
            method: "DELETE", url: server.appendingPathComponent("v1/web/devices/\(row)"),
            headers: ["authorization": "Bearer \(token)", "accept": "application/json"], body: nil)
        guard let response = try? await transport.send(request) else { return .unavailable }
        switch response.status {
        case 200:
            let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any]
            return (json?["revoked"] as? Bool) == true ? .ended : .unavailable
        case 401: return .alreadyGone
        default: return .unavailable
        }
    }

    /// An account session for `accountID`, made well: a `ds1` token that says it is an account session (`acc`) of that very
    /// account (`sub`), an expiry, full access and a row id that is an id. Anything else is not kept, so another account's
    /// session never becomes this account's (cross-user isolation) and a path is never built from something that isn't an id.
    private static func grant(_ body: Data, for accountID: String) -> BackendSessionGrant? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let token = json["token"] as? String, token.hasPrefix("ds1."), token.count <= 2_048,
              let claims = BackendSessionToken.claims(of: token), claims.isAccountSession,
              claims.subject?.lowercased() == accountID.lowercased(),
              let expires = (json["expiresAt"] as? String).flatMap(DeviceSessionClient.parseDate),
              json["access"] as? String == "full",
              let row = (json["deviceListId"] as? String).flatMap({ UUID(uuidString: $0)?.uuidString.lowercased() })
        else { return nil }
        return BackendSessionGrant(token: token, expiresAt: expires, deviceListID: row)
    }
}
