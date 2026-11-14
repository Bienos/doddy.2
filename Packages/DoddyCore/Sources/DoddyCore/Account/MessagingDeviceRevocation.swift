import Foundation

// Security audit 2026-11-09, finding 1. Signing out used to delete only this iPhone's own copy of its
// messaging-server token. The server still knew the token (and this iPhone's push address), so a copied
// token kept working and the account's private notifications kept coming. Signing out now also asks the
// server to forget this iPhone (`DELETE /v1/device`, which ends the token and the push binding together).
//
// Signing out must not wait for a network, so the two are kept apart, and the difference is never hidden:
// - signed out here: immediate, the token leaves the Keychain slot the app uses;
// - revoked at the server: confirmed only when the server said so. Until then the token waits in a
//   separate slot, used for nothing but this request, and the request is tried again (at launch, at the
//   next sign-in, and after each sign-out) until it is answered. It never restores a session.

/// Where tokens still owed a revocation are kept: the Keychain (this device only) in the app, memory in tests.
public protocol PendingRevocationStore: Sendable {
    func load() -> [String]
    /// False when it couldn't be kept.
    func save(_ tokens: [String]) -> Bool
}

public enum DeviceRevocation: Equatable, Sendable {
    /// The server ended this iPhone's token and push binding, or no longer knew the token (an earlier try got
    /// through, or the server removed it): either way it is gone.
    case revoked
    /// The server won't end this one (an iPhone that is not the sign-in of a Doddy account): a retry would
    /// get the same answer, and there is nothing of an account to protect.
    case notNeeded
    /// Offline, busy or broken: nothing is known. Tried again later.
    case retryLater
}

extension DoddyAccountLink {
    /// `DELETE /v1/device` on the messaging server, with the token to end as the bearer.
    public static func revokeMessagingDevice(server: URL, deviceToken: String, transport: any HTTPTransport) async -> DeviceRevocation {
        // Same shape the server accepts; anything else could never be a token of its.
        guard deviceToken.count == 43, deviceToken.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return .notNeeded }
        let request = HTTPRequest(
            method: "DELETE", url: server.appendingPathComponent("v1/device"),
            headers: ["authorization": "Bearer \(deviceToken)", "accept": "application/json"], body: nil)
        guard let response = try? await transport.send(request) else { return .retryLater }
        switch response.status {
        case 204, 401: return .revoked
        case 409: return .notNeeded
        default: return .retryLater   // 429, 5xx, 404 from a server that doesn't have the route yet, anything else
        }
    }
}

/// Tokens whose revocation is owed, and the retrying of it. All on the main actor, so a token added while
/// a retry is on its way is never lost: the list is read and written only between the awaits.
@MainActor
public final class PendingDeviceRevocations {
    /// More than this many are never kept (a person signing out many times offline): the oldest give way.
    public static let maxKept = 5

    private let store: any PendingRevocationStore
    private let transport: any HTTPTransport

    public init(store: any PendingRevocationStore, transport: any HTTPTransport) {
        self.store = store
        self.transport = transport
    }

    public var count: Int { store.load().count }

    /// Writes the token down as owed. False when the iPhone couldn't keep it (then the caller tries once, now).
    @discardableResult
    public func add(_ token: String) -> Bool {
        var tokens = store.load().filter { $0 != token }
        tokens.append(token)
        if tokens.count > Self.maxKept { tokens.removeFirst(tokens.count - Self.maxKept) }
        return store.save(tokens)
    }

    /// Asks the server about each owed token; those it answered (revoked, or not needed) are removed.
    /// Returns how many are still owed. Safe to call whenever and as often as wanted.
    @discardableResult
    public func retry(server: URL) async -> Int {
        for token in store.load() {
            let outcome = await DoddyAccountLink.revokeMessagingDevice(server: server, deviceToken: token, transport: transport)
            guard outcome != .retryLater else { continue }
            // Read again: another add or retry may have changed the list while this request was on its way.
            _ = store.save(store.load().filter { $0 != token })
        }
        return store.load().count
    }

    /// Owed first, then tried now. When the token couldn't even be written down, it is tried once anyway.
    public func revoke(_ token: String, server: URL) async {
        if add(token) {
            await retry(server: server)
        } else {
            _ = await DoddyAccountLink.revokeMessagingDevice(server: server, deviceToken: token, transport: transport)
        }
    }
}
