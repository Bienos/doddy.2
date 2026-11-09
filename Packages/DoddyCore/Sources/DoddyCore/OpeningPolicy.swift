import Foundation

// Whether an explicitly enabled listen-on-open preference starts a conversation when the app is
// opened (ADR-225). The first-launch basketball opening that shared these rules was removed with
// its v1.3 art (decision 2026-11-09-remove-old-design-leftovers); the welcome (ADR-598) is the
// first launch now. The app reads its settings and state into `OpeningConditions`; this decides;
// the app acts.
// Listening on open is the user's own switch (off by default), and it never opens the microphone
// silently: the conversation screen comes up, says "Listening" from real session events, and iOS
// shows its microphone indicator. It starts by itself only once iOS has allowed the microphone, so
// the first microphone question always follows the user's own tap on Talk to Doddy, never an app
// launch (ADR-325).

public struct OpeningConditions: Equatable, Sendable {
    /// Settings → Voice → "Start listening when I open Doddy". Off unless turned on.
    public var listenOnOpen: Bool
    /// First-use onboarding is finished and Home is what the user sees.
    public var atHome: Bool
    public var voiceAvailable: Bool
    /// iOS has allowed the microphone. Not yet asked counts as no: the question would pop up the
    /// moment the app opens. Refused: a conversation would open straight into "Microphone is off".
    public var microphoneAllowed: Bool
    /// A conversation, the Back Tap guide, a shared draft or a Find request is already up.
    public var somethingIsOpen: Bool

    public init(listenOnOpen: Bool, atHome: Bool, voiceAvailable: Bool, microphoneAllowed: Bool, somethingIsOpen: Bool) {
        self.listenOnOpen = listenOnOpen
        self.atHome = atHome
        self.voiceAvailable = voiceAvailable
        self.microphoneAllowed = microphoneAllowed
        self.somethingIsOpen = somethingIsOpen
    }
}

/// Why the app is being looked at now.
public enum OpeningTrigger: Equatable, Sendable {
    case coldLaunch
    /// Back from the background after this long.
    case returned(after: TimeInterval)
}

public enum OpeningDecision: Equatable, Sendable {
    case nothing
    /// The conversation opens by itself.
    case listenOnly

    public var listens: Bool { self == .listenOnly }
}

public enum OpeningPolicy {
    /// A quick switch to another app and back is not a new return for the explicit listen-on-open option.
    public static let replayAfter: TimeInterval = 5 * 60

    public static func decide(_ c: OpeningConditions, trigger: OpeningTrigger) -> OpeningDecision {
        guard c.atHome, !c.somethingIsOpen else { return .nothing }
        if case .returned(let after) = trigger, after < replayAfter { return .nothing }
        let listen = c.listenOnOpen && c.voiceAvailable && c.microphoneAllowed
        return listen ? .listenOnly : .nothing
    }
}
