import Foundation

// Whether the one-time first-launch opening plays, and whether an explicitly enabled
// listen-on-open preference starts a conversation on a later return (ADR-225).
// The app reads its settings and state into `OpeningConditions`; this decides; the app acts.
// Listening on open is the user's own switch (off by default), and it never
// opens the microphone silently: the conversation screen comes up, says "Listening" from real
// session events, and iOS shows its microphone indicator. It starts by itself only once iOS has
// allowed the microphone, so the first microphone question always follows the user's own tap on
// Talk to Doddy, never an app launch (ADR-325).

public struct OpeningConditions: Equatable, Sendable {
    /// Legacy Settings → Appearance preference, retained so an older opt-out is respected.
    public var sceneOn: Bool
    /// Settings → Voice → "Start listening when I open Doddy". On unless turned off.
    public var listenOnOpen: Bool
    /// Settings → "Hide character artwork": there is no Doddy to show.
    public var characterArtHidden: Bool
    public var reduceMotion: Bool
    /// An animation gives a VoiceOver user only a delay; the greeting is spoken by Doddy anyway when a conversation starts.
    public var voiceOverRunning: Bool
    /// First-use onboarding is finished and Home is what the user sees.
    public var atHome: Bool
    public var voiceAvailable: Bool
    /// iOS has allowed the microphone. Not yet asked counts as no: the question would pop up the
    /// moment the app opens. Refused: a conversation would open straight into "Microphone is off".
    public var microphoneAllowed: Bool
    /// A conversation, the Back Tap guide, a shared draft or a Find request is already up.
    public var somethingIsOpen: Bool
    /// True only for a new installation before the introductory opening has been shown or skipped.
    public var firstLaunchIntroPending: Bool

    public init(
        sceneOn: Bool, listenOnOpen: Bool, characterArtHidden: Bool, reduceMotion: Bool,
        voiceOverRunning: Bool, atHome: Bool, voiceAvailable: Bool, microphoneAllowed: Bool,
        somethingIsOpen: Bool, firstLaunchIntroPending: Bool = false
    ) {
        self.sceneOn = sceneOn
        self.listenOnOpen = listenOnOpen
        self.characterArtHidden = characterArtHidden
        self.reduceMotion = reduceMotion
        self.voiceOverRunning = voiceOverRunning
        self.atHome = atHome
        self.voiceAvailable = voiceAvailable
        self.microphoneAllowed = microphoneAllowed
        self.somethingIsOpen = somethingIsOpen
        self.firstLaunchIntroPending = firstLaunchIntroPending
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
    /// Play the opening (the still picture under Reduce Motion); `thenListen` is always false for this intro.
    case scene(reducedMotion: Bool, thenListen: Bool)
    /// No opening, but the conversation opens by itself.
    case listenOnly

    public var playsScene: Bool {
        if case .scene = self { return true }
        return false
    }

    public var listens: Bool {
        switch self {
        case .nothing: false
        case .scene(_, let thenListen): thenListen
        case .listenOnly: true
        }
    }
}

public enum OpeningPolicy {
    /// A quick switch to another app and back is not a new return for the explicit listen-on-open option.
    public static let replayAfter: TimeInterval = 5 * 60

    public static func decide(_ c: OpeningConditions, trigger: OpeningTrigger) -> OpeningDecision {
        guard c.atHome, !c.somethingIsOpen else { return .nothing }
        if c.firstLaunchIntroPending {
            guard case .coldLaunch = trigger else { return .nothing }
            let scene = c.sceneOn && !c.characterArtHidden && !c.voiceOverRunning
            // The first-run animation never opens voice or asks for a permission.
            return scene ? .scene(reducedMotion: c.reduceMotion, thenListen: false) : .nothing
        }
        if case .returned(let after) = trigger, after < replayAfter { return .nothing }
        let listen = c.listenOnOpen && c.voiceAvailable && c.microphoneAllowed
        if listen { return .listenOnly }
        return .nothing
    }
}
