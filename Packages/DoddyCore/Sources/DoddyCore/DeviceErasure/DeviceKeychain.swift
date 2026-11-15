import Foundation

// The Keychain side of "Erase everything on this iPhone". Every item Doddy keeps is a generic password under a
// service name `com.bienos.doddy2.<name>`, all marked "this device only" (not backed up, not synced). The app lists
// what the Keychain holds for it and asks this table what to do with each service; a service the table doesn't know is
// erased, so one added later can't be forgotten. UI-free: the app does the `SecItem` calls.
//
// Kept while the person stays signed in (`DeviceErasureScope.keepSignIn`): the sign-in itself and what ties this iPhone
// to Doddy's servers. Erasing them would sign the person out and cut the iPhone off from the copies Doddy's servers keep
// for it, with no way to delete them (the account deletion needs them). Signing out and deleting the account are their
// own steps; after the account was deleted (`afterAccountDeleted`) they go too.

public enum DeviceKeychain {
    public enum Role: String, Sendable {
        /// A key the person pasted in. Always erased.
        case personalKey
        /// Something no build writes any more. Always erased.
        case retired
        /// The signed-in account (or the older voice account). Kept while signed in.
        case signIn
        /// The token or id Doddy's servers know this iPhone by. Kept while signed in.
        case serverTie
    }

    public struct Service: Equatable, Sendable {
        public let name: String
        public let role: Role
        /// What the service holds, for the doc and the tests.
        public let holds: String
    }

    public static let services: [Service] = [
        Service(name: "com.bienos.doddy2.account-keys", role: .personalKey, holds: "The inFakt API key the person pasted in."),
        Service(name: "com.bienos.doddy2.gateway", role: .retired, holds: "Device id, invite code and token of the old assistant gateway; no build writes them."),
        Service(name: "com.bienos.doddy2.voice-access-code", role: .retired, holds: "The old tester access code; removed at launch, listed so a leftover is erased."),
        Service(name: "com.bienos.doddy2.doddy-account", role: .signIn, holds: "The signed-in Doddy account's session (tokens and who it is)."),
        Service(name: "com.bienos.doddy2.voice-session", role: .signIn, holds: "The older voice account's session (Sign in with Apple at the voice server)."),
        Service(name: "com.bienos.doddy2.voice-account-session", role: .signIn, holds: "The voice server's own session for the signed-in Doddy account (its two tokens and which account they belong to)."),
        Service(name: "com.bienos.doddy2.voice-account-session-owed", role: .serverTie, holds: "Voice-server sessions this iPhone signed out of that the server hasn't yet confirmed it ended; used for nothing but that one request."),
        Service(name: "com.bienos.doddy2.backend-account-session", role: .signIn, holds: "The backend's own session for the signed-in Doddy account (its token, when it ends, which stored iPhone it is, and which account and server it belongs to)."),
        Service(name: "com.bienos.doddy2.backend-account-session-owed", role: .serverTie, holds: "Backend sessions this iPhone signed out of that the backend hasn't yet confirmed it ended; used for nothing but that one request."),
        Service(name: "com.bienos.doddy2.connected-apps", role: .serverTie, holds: "The session token for Doddy's backend (a device session, or the account's token or the backend's own session for it): whichever token the backend clients send."),
        Service(name: "com.bienos.doddy2.server", role: .serverTie, holds: "The device token for Doddy's messaging server."),
        Service(name: "com.bienos.doddy2.server.pending-revocation", role: .serverTie, holds: "Device tokens of messaging-server sessions this iPhone signed out of that the server hasn't yet confirmed it ended; used for nothing but that one request."),
        Service(name: "com.bienos.doddy2.device", role: .serverTie, holds: "This iPhone's random device id, which mints backend sessions."),
    ]

    /// True when the service's items should be erased in `scope`. Unknown services are erased.
    public static func shouldErase(service: String, scope: DeviceErasureScope) -> Bool {
        guard let known = services.first(where: { $0.name == service }) else { return true }
        switch known.role {
        case .personalKey, .retired: return true
        case .signIn, .serverTie: return !scope.keepsSignIn
        }
    }

    /// The store that erases and reads back this service: the sign-in and server ties (`keychainServerHandles`), or
    /// everything else (`keychainPersonalKeys`, also for a service the table doesn't know).
    public static func store(for service: String) -> DeviceStoreID {
        switch services.first(where: { $0.name == service })?.role {
        case .signIn?, .serverTie?: .keychainServerHandles
        case .personalKey?, .retired?, nil: .keychainPersonalKeys
        }
    }

    /// The services that stay in `scope`, for the line that tells the person what was kept.
    public static func keptServices(scope: DeviceErasureScope) -> [String] {
        services.map(\.name).filter { !shouldErase(service: $0, scope: scope) }
    }
}
