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

/// What a press says in the log about the process it ran in: was Doddy started for it, and how long did that
/// take before the press's own code began (follow-up to decision `2026-11-13-island-first`). The start timeline
/// begins when the intent's `perform()` runs, so it can't see this part: the time iOS needs to load the app
/// (libraries, `DoddyApp.init`) comes before it. Only fixed words and seconds, never anything about the person.
public struct TalkLaunchTiming: Sendable, Equatable {
    /// A process younger than this at the press was started for it, or just before it: a cold start.
    public static let freshBelow: TimeInterval = 15

    /// Seconds from the process's start to the press.
    public let processAge: Double?
    /// Seconds from the process's start to the first line of `DoddyApp.init`: iOS loading the app.
    public let beforeAppInit: Double?
    /// Seconds `DoddyApp.init` itself took.
    public let appInit: Double?

    public init(processAge: Double?, beforeAppInit: Double?, appInit: Double?) {
        self.processAge = processAge
        self.beforeAppInit = beforeAppInit
        self.appInit = appInit
    }

    /// Whether this press started the process. Nil when its age isn't known.
    public var isFreshLaunch: Bool? {
        guard let processAge, processAge.isFinite else { return nil }
        return processAge < Self.freshBelow
    }

    /// "process age 1.20 s (fresh launch) · before app init 0.60 s · app init 0.15 s". For a process that was
    /// already running, only its age: the other two belong to a launch long before this press.
    public func line() -> String {
        guard let processAge, let fresh = isFreshLaunch else { return "process age unknown" }
        var parts = ["process age \(VoiceStartTimeline.text(processAge)) (\(fresh ? "fresh launch" : "already running"))"]
        if fresh {
            if let beforeAppInit { parts.append("before app init \(VoiceStartTimeline.text(beforeAppInit))") }
            if let appInit { parts.append("app init \(VoiceStartTimeline.text(appInit))") }
        }
        return parts.joined(separator: " · ")
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
