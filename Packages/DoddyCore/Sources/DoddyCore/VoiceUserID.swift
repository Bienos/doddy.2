import Foundation

// Decision 2026-11-12-voice-conversations-per-account: deleting a Doddy account also deletes its voice conversations at
// ElevenLabs. The voice server answers a token request with `{ token, userId }`; `userId` is a keyed hash of the Doddy
// account, which the app gives ElevenLabs as the conversation's user, so the server can find the account's
// conversations by listing them. This file is the app's side of that, UI-free and tested on Linux.

/// Which user id a voice conversation starts with at ElevenLabs.
public enum VoiceUserIDPolicy {
    /// The server's account id when it sent one this app accepts; otherwise this iPhone's own random id, as before
    /// (a server that predates the field sends none, and conversations from then on are found by the install id,
    /// which the app also hands the server once when the account is deleted: `VoiceConversationErasure`).
    public static func userID(server: String?, install: String) -> String {
        accepted(server) ?? install
    }

    /// The server's id when it is 16 to 128 characters of letters, digits, `_` and `-` (the server makes 32 hex
    /// characters), otherwise nil. Nothing else is passed on to ElevenLabs as a user id, whatever a reply held.
    public static func accepted(_ serverUserID: String?) -> String? {
        guard let id = serverUserID, (16...128).contains(id.utf8.count) else { return nil }
        let allowed = id.utf8.allSatisfy { byte in
            (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) || byte == 0x5F || byte == 0x2D
        }
        return allowed ? id : nil
    }
}

extension VoiceTokenServer {
    /// The `userId` of a token answer, or nil when it has none or none the app accepts.
    public static func userID(fromAnswer body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return VoiceUserIDPolicy.accepted(json["userId"] as? String)
    }
}

/// The `userId` each token came with, kept until that token is used, so the conversation that uses it starts with
/// the id that belongs to it and not with another account's (the token shelf holds one token ahead of a start, and the
/// start reads it much later). Held in memory only, a handful at most, each taken once; nothing is logged.
public final class VoiceTokenUserIDs: @unchecked Sendable {
    public static let shared = VoiceTokenUserIDs()

    private let lock = NSLock()
    private var entries: [(token: String, userID: String)] = []
    private let capacity: Int

    public init(capacity: Int = 8) { self.capacity = max(1, capacity) }

    /// Keeps `userID` for `token`; a later call for the same token replaces it, and nil (an answer without one)
    /// leaves nothing for it.
    public func remember(_ userID: String?, forToken token: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll { $0.token == token }
        guard let userID, !token.isEmpty else { return }
        entries.append((token: token, userID: userID))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    /// The id that came with `token`, once.
    public func take(forToken token: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = entries.firstIndex(where: { $0.token == token }) else { return nil }
        return entries.remove(at: index).userID
    }

    /// Sign-out, an account change, Pause all: nothing held survives (as the token shelf's `clear`).
    public func forget() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
