import Foundation

// Decision 2026-11-12-voice-conversations-per-account: deleting a Doddy account also deletes its voice conversations at
// ElevenLabs, through the voice server (`POST /api/voice-auth`, action `delete-conversations`, with the Doddy account's
// token). The server deletes each conversation and reads it back; it answers counts, `deleted` and `pending`, never ids.
// What counts as confirmed is decided here, UI-free and tested on Linux, so "deleted" is said only for what the server
// confirmed (DOD-08); the app (`DoddyAccountServers.deleteAccount`, `VoiceAuthAPI.deleteConversations`) does the request.

public enum VoiceConversationErasure {
    /// One `delete-conversations` request.
    public enum Attempt: Equatable, Sendable {
        /// 200 with both counts. `pending` is what the server could not confirm gone (it is never 0 unless everything is).
        case answered(deleted: Int, pending: Int)
        /// 400 `unknown_action`: a server from before this. It recorded nothing and can delete nothing.
        case notSupported
        /// Offline, timed out, a refusal, an error, or an answer that isn't counts. Not "deleted".
        case failed
    }

    public enum Outcome: Equatable, Sendable {
        /// The server confirmed every conversation gone.
        case deleted(count: Int)
        /// Nothing was recorded or found: nothing to delete, and nothing to say.
        case nothingToDelete
        /// The server took the deletion over but could not confirm all of it. It keeps what is left recorded as owed
        /// and tries again every day, so the account deletion goes on; the final message says so and never "deleted".
        case stillDeleting(pending: Int)
        /// A server from before this: the account can still be deleted, and nothing is said about voice conversations.
        case serverCannotDelete
        /// No answer the app can trust. Nothing else is deleted and the person stays signed in, as when the messaging
        /// server doesn't confirm, so the whole deletion can be tried again (asking again is harmless).
        case notConfirmed

        public var mayContinue: Bool { self != .notConfirmed }

        /// What the final message says about voice conversations, if anything.
        public var finalLine: FinalLine? {
            switch self {
            case .deleted: .deleted
            case .stillDeleting: .stillDeleting
            case .nothingToDelete, .serverCannotDelete, .notConfirmed: nil
            }
        }
    }

    public enum FinalLine: Equatable, Sendable {
        /// "Your voice conversations were deleted."
        case deleted
        /// "Some of your voice conversations are still being deleted. Doddy's server keeps trying every day until they're gone."
        case stillDeleting
    }

    private struct Counts: Decodable {
        let deleted: Int
        let pending: Int
    }

    private struct ErrorAnswer: Decodable {
        let error: String
    }

    /// The server's answer. Only a 200 with both counts, whole numbers from 0 up, is an answer; a 400 that names
    /// `unknown_action` is a server without the action.
    public static func attempt(status: Int, body: Data) -> Attempt {
        switch status {
        case 200:
            guard let counts = try? JSONDecoder().decode(Counts.self, from: body), counts.deleted >= 0, counts.pending >= 0 else { return .failed }
            return .answered(deleted: counts.deleted, pending: counts.pending)
        case 400:
            let error = (try? JSONDecoder().decode(ErrorAnswer.self, from: body))?.error
            return error == "unknown_action" ? .notSupported : .failed
        default:
            return .failed
        }
    }

    public static func outcome(_ attempt: Attempt) -> Outcome {
        switch attempt {
        case .answered(let deleted, let pending):
            if pending > 0 { return .stillDeleting(pending: pending) }
            return deleted > 0 ? .deleted(count: deleted) : .nothingToDelete
        case .notSupported: return .serverCannotDelete
        case .failed: return .notConfirmed
        }
    }

    /// This iPhone's old per-install id (what ElevenLabs was given before the account's own user id), in the one shape
    /// the server accepts (a lower-case UUID, which is what the app makes), or nil. The server looks for conversations
    /// with it in Doddy's agents too, so the ones from before the account's id existed are deleted as well.
    public static func installUserID(_ stored: String?) -> String? {
        guard let stored, stored.utf8.count == 36, let uuid = UUID(uuidString: stored) else { return nil }
        return uuid.uuidString.lowercased()
    }

    /// The request's JSON: the action, and the install id when there is a valid one.
    public static func requestBody(installID stored: String?) -> [String: String] {
        var body = ["action": "delete-conversations"]
        if let install = installUserID(stored) { body["installUserId"] = install }
        return body
    }
}
