import DoddyCore
import Foundation

/// Builds the client for Logbook (ADR-602), on the same server and session as Doddy on the web and the
/// notes kept there (`WebMemoryClientFactory`). With a Doddy account, the session is the account's token
/// once the backend takes the account (`DoddyAccountServers`). Nil when the build has no server.
enum LogbookClientFactory {
    static func make() -> (any LogbookClient)? {
        // The token is used only with the server that issued it (`BoundSessionToken`).
        guard let url = DeviceSession.serverURL(), KeychainSessionStore.read()?.token(for: url) != nil else { return nil }
        return BackendLogbookClient(baseURL: url, boundToken: { KeychainSessionStore.read() }, transport: URLSessionTransport.shared)
    }

    /// The client, after signing this iPhone in if it has no session yet.
    static func ready() async -> (any LogbookClient)? {
        guard let url = DeviceSession.serverURL() else { return nil }
        await DeviceSession.ensure(server: url)
        return make()
    }

    /// After the server said `unauthenticated`: a fresh session, then the client again.
    static func renewed() async -> (any LogbookClient)? {
        guard let url = DeviceSession.serverURL(), await DeviceSession.renew(server: url) else { return nil }
        return make()
    }
}
