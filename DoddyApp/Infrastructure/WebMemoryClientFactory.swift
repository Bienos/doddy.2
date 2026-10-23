import DoddyCore
import Foundation

/// Builds the client for keeping notes and conversations on Doddy's server (ADR-595), on the same
/// server and session as Doddy on the web (`WebLinkClientFactory`, ADR-585). Nil when the build has no server.
enum WebMemoryClientFactory {
    static func make() -> (any WebMemoryClient)? {
        // The token is used only with the server that issued it (`BoundSessionToken`).
        guard let url = DeviceSession.serverURL(), KeychainSessionStore.read()?.token(for: url) != nil else { return nil }
        return BackendWebMemoryClient(baseURL: url, boundToken: { KeychainSessionStore.read() }, transport: URLSessionTransport.shared)
    }

    /// The client, after signing this iPhone in if it has no session yet.
    static func ready() async -> (any WebMemoryClient)? {
        guard let url = DeviceSession.serverURL() else { return nil }
        await DeviceSession.ensure(server: url)
        return make()
    }

    /// After the server said `unauthenticated`: a fresh device session, then the client again.
    static func renewed() async -> (any WebMemoryClient)? {
        guard let url = DeviceSession.serverURL(), await DeviceSession.renew(server: url) else { return nil }
        return make()
    }
}
