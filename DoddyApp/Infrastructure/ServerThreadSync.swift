import DoddyCore
import Foundation

/// The Messages copy for Doddy Web (owner, 28 Oct 2026: "sync always on"), on the same server and session as the
/// Files list. With no session for that server (this iPhone has never signed in to it) nothing is sent and no
/// sign-in is started just to send: there is no web account to show it to. A refused session is renewed once.
///
/// NOT COMPILED here (needs the app target); the client and the snapshot are tested in DoddyCore.
struct ServerThreadSync: ThreadSyncClient {
    func send(_ snapshot: ThreadSync.Snapshot) async throws(WebLinkError) {
        try await withClient { client throws(WebLinkError) in try await client.send(snapshot) }
    }

    func deleteAll() async throws(WebLinkError) {
        try await withClient { client throws(WebLinkError) in try await client.deleteAll() }
    }

    /// Whether this iPhone has a session for Doddy's server, so there can be a copy at all.
    static var isAvailable: Bool { client() != nil }

    private func withClient(_ work: (BackendThreadSyncClient) async throws(WebLinkError) -> Void) async throws(WebLinkError) {
        guard let client = Self.client() else { throw .notConfigured }
        do {
            try await work(client)
        } catch .unauthenticated {
            guard let url = DeviceSession.serverURL(), await DeviceSession.renew(server: url), let renewed = Self.client() else { throw .unauthenticated }
            try await work(renewed)
        }
    }

    private static func client() -> BackendThreadSyncClient? {
        // The token is used only with the server that issued it (`BoundSessionToken`).
        guard let url = DeviceSession.serverURL(), KeychainSessionStore.read()?.token(for: url) != nil else { return nil }
        return BackendThreadSyncClient(baseURL: url, boundToken: { KeychainSessionStore.read() }, transport: URLSessionTransport.shared)
    }
}
