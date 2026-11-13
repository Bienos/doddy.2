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

/// The island comes first (owner, 13 Nov 2026: the Action Button should show the island at once, "zależy mi na
/// szybkości"; decision `2026-11-13-island-first`). A press puts the island up, as "Connecting…", as soon as the
/// checks that need nothing but the iPhone have passed, before it waits for the notes store, the profile, the
/// conversation's own set-up, the audio session, the token and the connect. Those used to run before the island
/// was asked for. The island never says Doddy listens before he does: the waves come with the provider's events.
public enum TalkIslandFirst {
    /// What happens to the island the press put up, once the start has handed back, failed, been refused or
    /// been cancelled.
    public enum Afterwards: Equatable, Sendable {
        /// A conversation is connecting or live: it shows itself on that island now, and ends it itself.
        case leave
        /// Nothing took it over: it goes at once, so a refused or cancelled press leaves no "Connecting…" island.
        case end
    }

    /// - Parameters:
    ///   - shownByPress: this press asked for the island (it was not already up) and iOS put it up.
    ///   - conversationLive: a conversation is connecting or live now (this press's, or one started meanwhile).
    public static func afterwards(shownByPress: Bool, conversationLive: Bool) -> Afterwards {
        guard shownByPress, !conversationLive else { return .leave }
        return .end
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
