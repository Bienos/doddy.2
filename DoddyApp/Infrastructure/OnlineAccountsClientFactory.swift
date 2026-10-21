import DoddyCore
import Foundation

/// Builds the online-accounts client (web search, Claude, Gmail and the other accounts).
///
/// The server is the one built into the app (`DoddyServerURL`, ADR-563) unless Settings' development
/// field names another. The session token is in the Keychain, bound to the server that issued it.
/// `ready()` signs the phone in first when there is no token yet, so nobody has to paste one.
/// `make()` returns nil when either is missing, so callers say "not set up" instead of pretending.
enum OnlineAccountsClientFactory {
    static func make() -> (any OnlineAccountsClient)? {
        // The token is used only with the server that issued it (`BoundSessionToken`).
        guard let url = DeviceSession.serverURL(), KeychainSessionStore.read()?.token(for: url) != nil else { return nil }
        return BackendOnlineAccountsClient(
            baseURL: url, boundToken: { KeychainSessionStore.read() }, transport: URLSessionTransport.shared)
    }

    /// The client, after signing this iPhone in if it has no session yet (ADR-563).
    static func ready() async -> (any OnlineAccountsClient)? {
        guard let url = DeviceSession.serverURL() else { return nil }
        await DeviceSession.ensure(server: url)
        return make()
    }

    /// After the server said `unauthenticated`: a fresh device session, then the client again.
    static func renewed() async -> (any OnlineAccountsClient)? {
        guard let url = DeviceSession.serverURL(), await DeviceSession.renew(server: url) else { return nil }
        return make()
    }
}
