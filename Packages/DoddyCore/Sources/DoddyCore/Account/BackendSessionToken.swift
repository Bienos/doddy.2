import Foundation

// One token per server (decision 2026-11-12-one-token-per-server), the app's half for the backend `doddy`.
//
// Two `ds1.` tokens can sit in this iPhone's Keychain for the backend: the earlier DEVICE session (the iPhone's own, minted
// from its device id at `POST /v1/session/device`) and the ACCOUNT session (`POST /v1/session/account`, which the backend
// signs the same way and marks with the claim `acc`). The link routes (`/v1/account/link-device/start` and `/undo`) need
// the earlier device session and refuse an account session with a 401 (decision 2026-11-14-backend-account-session, rule 9).
// "Starts with `ds1.`" therefore no longer says which one a stored token is; this says, from what the token itself claims
// and from what the app holds as its account session.

public enum BackendSessionToken {
    /// What a `ds1` token claims about itself. The signature is the server's to check; the app only reads which kind it is.
    struct Claims: Equatable {
        /// `sub`: the Doddy account for an account session, the iPhone's own id for a device session.
        let subject: String?
        /// `acc`: set by the backend on an account session only.
        let isAccountSession: Bool
    }

    /// The claims of a `ds1.<claims>.<signature>` token, or nil when it isn't one or its claims can't be read.
    static func claims(of token: String) -> Claims? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "ds1", let data = base64URLDecoded(String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let account = (json["acc"] as? Int) == 1 || (json["acc"] as? Bool) == true
        return Claims(subject: json["sub"] as? String, isAccountSession: account)
    }

    /// True when the token says it is an account session (`acc`).
    public static func isAccountSession(_ token: String) -> Bool {
        claims(of: token)?.isAccountSession ?? false
    }

    /// The token the link routes may be sent: this iPhone's EARLIER DEVICE SESSION found among what is stored for the backend,
    /// or nil. Never an account session: not one the token says it is, and not the one the app holds as its account session
    /// (`accountSession`), whatever its claims say. Not a Supabase token either, which is what the app saves in the same
    /// place after the link. A token whose claims can't be read is taken as before this change, because the backend's own
    /// account sessions always can be read. The same length limit as the link calls.
    public static func earlierDeviceSession(stored: String?, accountSession: String?) -> String? {
        guard let stored, stored.hasPrefix("ds1."), stored.count <= 2_048 else { return nil }
        if let accountSession, stored == accountSession { return nil }
        if isAccountSession(stored) { return nil }
        return stored
    }

    private static func base64URLDecoded(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
