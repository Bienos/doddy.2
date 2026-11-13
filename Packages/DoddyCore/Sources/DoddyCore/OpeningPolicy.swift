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
    /// A link opened the app (a `doddy://` address, a widget's link, the island's Show button). A link goes
    /// where it points; it never also starts a conversation. Whether one did is `LinkOpenNote`'s answer.
    public var openedByURL: Bool

    public init(
        listenOnOpen: Bool, atHome: Bool, voiceAvailable: Bool, microphoneAllowed: Bool, somethingIsOpen: Bool,
        openedByURL: Bool = false
    ) {
        self.listenOnOpen = listenOnOpen
        self.atHome = atHome
        self.voiceAvailable = voiceAvailable
        self.microphoneAllowed = microphoneAllowed
        self.somethingIsOpen = somethingIsOpen
        self.openedByURL = openedByURL
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

    /// Whether the way the app was opened leaves room for "Start listening when I open Doddy": not when a
    /// link opened it. A person who tapped a link, a widget or the island's Show button asked for that place.
    public static func shouldListen(openedByURL: Bool) -> Bool { !openedByURL }

    public static func decide(_ c: OpeningConditions, trigger: OpeningTrigger) -> OpeningDecision {
        guard c.atHome, !c.somethingIsOpen, shouldListen(openedByURL: c.openedByURL) else { return .nothing }
        if case .returned(let after) = trigger, after < replayAfter { return .nothing }
        let listen = c.listenOnOpen && c.voiceAvailable && c.microphoneAllowed
        return listen ? .listenOnly : .nothing
    }
}

/// Remembers that a link opened the app, until the next opening decision uses it. The scene hears of the link
/// (`scene(_:openURLContexts:)`, or the connection options of a cold launch) before the app is active, so the
/// note is there when `OpeningModel` decides. Used up by that decision, and a link that arrived while Doddy was
/// already in front does not suppress a much later return from the background.
public struct LinkOpenNote: Equatable, Sendable {
    /// For a return from the background: how long a link counts. It is seconds in practice (the link and the
    /// activation come together); the limit only keeps one old link from silencing a later, ordinary return.
    public static let validFor: TimeInterval = 30

    private var openedAt: Date?

    public init() {}

    public mutating func linkOpened(at now: Date) { openedAt = now }

    /// True when a link opened the app since the last decision. A cold launch takes it however long ago the
    /// link came (the welcome or a slow start can hold the decision back); a return takes it only while recent.
    /// The note is cleared either way.
    public mutating func take(for trigger: OpeningTrigger, now: Date) -> Bool {
        defer { openedAt = nil }
        guard let openedAt else { return false }
        switch trigger {
        case .coldLaunch:
            return true
        case .returned:
            // A clock that moved backwards makes the age negative: still recent.
            return now.timeIntervalSince(openedAt) <= Self.validFor
        }
    }
}
