import Foundation

/// When a conversation nobody is speaking in ends by itself (owner, 15 Nov 2026: "there is something that
/// captures voice all the time and using credits … find it and fix it"; decision
/// `2026-11-15-quiet-conversations-hang-up`).
///
/// Why: until now a conversation stayed open until End, Doddy's `end_call`, or ElevenLabs' own 10-minute cap.
/// The live agents never hang up on silence (`silence_end_call_timeout` is -1), and ElevenLabs bills every
/// minute a conversation is open, silence included. After Doddy opened Maps, or the phone was put down, the
/// microphone stayed open in the background and heard whatever was around it (14 Nov, 02:19: open 4 min 39 s,
/// the person's last real request at 0:02, then a television's English at 1:20).
///
/// The rule: a conversation ends once nothing has happened in it for the limit of its situation. Something
/// happening is a line from either side or the conversation's state changing (Doddy starts or stops speaking or
/// working). While Doddy speaks or works on an answer, or the person records a long turn, the clock waits, up to
/// `busyCeiling`, so a state that never ends can't keep the microphone open either.
///
/// Pure rules on a steady clock (seconds, e.g. system uptime): `VoiceSessionController` feeds it and ends the
/// conversation as `VoiceSessionEnd.quiet`.
public struct VoiceQuietWatch: Equatable, Sendable {
    /// What the conversation is doing when the watch looks.
    public struct Situation: Equatable, Sendable {
        /// Doddy is speaking or working on an answer (a tool running, "Working on it…"), or the person is
        /// recording a long turn ("Listen until I finish").
        public var busy: Bool
        /// Doddy is the app on screen. False in the background: after Doddy opened another app, with the
        /// screen locked, or for a conversation started from the island over another app.
        public var onScreen: Bool
        /// Translator mode: waiting in silence until someone speaks is its job.
        public var translating: Bool
        /// A card waits for the person's tap or yes; they may be reading it.
        public var cardWaiting: Bool

        public init(busy: Bool, onScreen: Bool, translating: Bool, cardWaiting: Bool) {
            self.busy = busy
            self.onScreen = onScreen
            self.translating = translating
            self.cardWaiting = cardWaiting
        }
    }

    /// Doddy on screen, nothing waiting: a minute is long enough to think of the next question.
    public static let onScreenLimit: TimeInterval = 60
    /// Doddy in the background: nobody is looking at him, and the microphone hears the room.
    public static let backgroundLimit: TimeInterval = 30
    /// Translator mode, on screen or not (owner, 15 Nov 2026: "give 45s translator"); the live translator
    /// agent's `silence_end_call_timeout` is the same 45 s.
    public static let translatorLimit: TimeInterval = 45
    /// A card waiting for a tap: the person may be reading it.
    public static let patientLimit: TimeInterval = 120
    /// The longest Doddy speaking or working holds the clock with nothing else happening.
    public static let busyCeiling: TimeInterval = 300
    /// The longest gap between two looks, so a change of situation (Doddy leaving the screen) counts within
    /// a few seconds.
    public static let lookEvery: TimeInterval = 5

    /// The quiet limit for `situation`: a card waiting first, then translator mode, then the screen.
    public static func limit(for situation: Situation) -> TimeInterval {
        if situation.cardWaiting { return patientLimit }
        if situation.translating { return translatorLimit }
        return situation.onScreen ? onScreenLimit : backgroundLimit
    }

    public enum Decision: Equatable, Sendable {
        /// Look again this many seconds from now.
        case lookAgain(after: TimeInterval)
        /// Quiet for the whole limit: end the conversation.
        case end(quietFor: TimeInterval)
    }

    /// The last time something happened: a line, or the conversation's state changing.
    public private(set) var lastActivity: Double
    /// The last look that found Doddy busy; the quiet time starts after it.
    public private(set) var lastBusy: Double?

    public init(startedAt: Double) {
        lastActivity = startedAt
    }

    /// Something happened. A time earlier than the last one changes nothing.
    public mutating func activity(at time: Double) {
        lastActivity = max(lastActivity, time)
    }

    public mutating func look(at now: Double, situation: Situation) -> Decision {
        if situation.busy {
            let heldFor = now - lastActivity
            if heldFor >= Self.busyCeiling { return .end(quietFor: heldFor) }
            lastBusy = now
            return .lookAgain(after: min(Self.lookEvery, Self.busyCeiling - heldFor))
        }
        let quietSince = max(lastActivity, lastBusy ?? lastActivity)
        let quiet = now - quietSince
        let limit = Self.limit(for: situation)
        if quiet >= limit { return .end(quietFor: quiet) }
        return .lookAgain(after: min(Self.lookEvery, limit - quiet))
    }
}
