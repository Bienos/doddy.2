import Foundation

// Whether the opening plays, and whether a conversation starts by itself afterwards (ADR-207).
// The app reads its settings and state into `OpeningConditions`; this decides; the app acts.
// Listening on open is the user's own switch (on by default, owner decision), and it never
// opens the microphone silently: the conversation screen comes up, says "Listening" from real
// session events, and iOS shows its microphone indicator.

public struct OpeningConditions: Equatable, Sendable {
    /// Settings → Appearance → "Doddy's opening". On unless turned off.
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
    /// iOS refuses the microphone: a conversation would open straight into "Microphone is off" every time.
    public var microphoneDenied: Bool
    /// A conversation, the Back Tap guide, a shared draft or a Find request is already up.
    public var somethingIsOpen: Bool

    public init(
        sceneOn: Bool, listenOnOpen: Bool, characterArtHidden: Bool, reduceMotion: Bool,
        voiceOverRunning: Bool, atHome: Bool, voiceAvailable: Bool, microphoneDenied: Bool,
        somethingIsOpen: Bool
    ) {
        self.sceneOn = sceneOn
        self.listenOnOpen = listenOnOpen
        self.characterArtHidden = characterArtHidden
        self.reduceMotion = reduceMotion
        self.voiceOverRunning = voiceOverRunning
        self.atHome = atHome
        self.voiceAvailable = voiceAvailable
        self.microphoneDenied = microphoneDenied
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
    /// Play the opening (the still picture under Reduce Motion), then open the conversation if `thenListen`.
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
    /// A quick switch to another app and back is not "opening Doddy": the opening (and listening)
    /// play again only after this long away.
    public static let replayAfter: TimeInterval = 5 * 60

    public static func decide(_ c: OpeningConditions, trigger: OpeningTrigger) -> OpeningDecision {
        guard c.atHome, !c.somethingIsOpen else { return .nothing }
        if case .returned(let after) = trigger, after < replayAfter { return .nothing }
        let scene = c.sceneOn && !c.characterArtHidden && !c.voiceOverRunning
        let listen = c.listenOnOpen && c.voiceAvailable && !c.microphoneDenied
        if scene { return .scene(reducedMotion: c.reduceMotion, thenListen: listen) }
        if listen { return .listenOnly }
        return .nothing
    }
}
