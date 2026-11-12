import Foundation

/// Rules for the start of a conversation from the Action Button, a control or Back Tap, kept here so
/// they are tested on Linux (decision `2026-11-10-action-button-start`). Platforms: iPhone.

/// Whether a start has to restore the voice login over the network before it checks the account gate.
public enum TalkStartAccount {
    /// The gate (`hasVoiceAccess`) is passed by a Doddy account alone, and the token request takes
    /// that account's token (refreshing it itself), so a signed-in Doddy account needs no restore: it
    /// used to run on every press. Only an older voice session that is not signed in yet, or whose
    /// access token is about to run out, is restored.
    /// - Parameters:
    ///   - accountSignedIn: a Doddy account is signed in on this iPhone.
    ///   - voiceSessionSecondsLeft: the older voice session's access token life left, nil when that
    ///     session is not signed in.
    public static func needsRestore(accountSignedIn: Bool, voiceSessionSecondsLeft: TimeInterval?) -> Bool {
        if accountSignedIn { return false }
        guard let voiceSessionSecondsLeft else { return true }
        return voiceSessionSecondsLeft <= 30
    }
}

/// When the Action Button's intent may return. A background intent has a short time budget, so it
/// must not wait for the token request and the ElevenLabs connect (up to 10 s): it waits only until
/// the checks are done and the island and audio session are up, or the start has already ended.
public enum TalkStartHandoff {
    public enum Decision: Equatable, Sendable {
        case keepWaiting
        /// Return now; the connection carries on in the background and ends the island if it fails.
        case handBack
        /// The start already ended (refused, failed or finished): report it as before.
        case report
        /// No island/audio session within the budget: cancel this start and offer the app.
        case timedOut
    }

    /// The longest the intent waits for the island and the audio session.
    public static let maxWait: TimeInterval = 4

    public static func decide(islandReady: Bool, startEnded: Bool, waited: TimeInterval) -> Decision {
        if startEnded { return .report }
        if islandReady { return .handBack }
        if waited >= maxWait { return .timedOut }
        return .keepWaiting
    }
}
