import Foundation

/// Who sets up the audio session for a voice conversation (decision
/// `2026-11-12-action-button-audio-and-island`). Platforms: iPhone.
///
/// LiveKit, under the ElevenLabs SDK, sets the session up itself when its audio engine starts. Since
/// LiveKit 2.17 that is a session that doesn't mix with other apps, and it switches it on. iOS refuses
/// to switch on such a session while the app is in the background, which is where the Action Button
/// starts a conversation without opening Doddy. So for that start Doddy takes the session itself,
/// mixable, inside the intent (a "hold"), and LiveKit leaves it as it is until that conversation is
/// over. Every other start leaves the session to LiveKit, as before.
///
/// One hold at a time, like conversations (ADR-496). A hold left over from an earlier conversation
/// never decides for a newer one: the newer start drops it, and its late release changes nothing.
public struct ConversationAudioHolds: Sendable {
    /// One conversation's hold on the session.
    public struct Hold: Equatable, Sendable {
        public let id: Int
    }

    /// The hold in force, or nil when LiveKit sets the session up.
    public private(set) var current: Hold?
    private var issued = 0

    public init() {}

    /// Doddy has just taken the session itself, mixable, for a start without opening the app. From
    /// now until `release`, LiveKit must not set it up.
    public mutating func take() -> Hold {
        issued &+= 1
        let hold = Hold(id: issued)
        current = hold
        return hold
    }

    /// Right before a conversation connects. True when LiveKit sets the session up itself: every
    /// start except the one whose hold is in force. A start without a hold drops one left over from an
    /// earlier conversation, so that one can't keep LiveKit off.
    public mutating func liveKitSetsUpSession(for hold: Hold?) -> Bool {
        if let hold, hold == current { return false }
        current = nil
        return true
    }

    /// The conversation that took `hold` is over. True when that hold was the one in force: LiveKit
    /// gets the session back, and Doddy switches it off if nothing else uses it. False for no hold,
    /// or one that a newer conversation has replaced, which must not touch the session it now uses.
    public mutating func release(_ hold: Hold?) -> Bool {
        guard let hold, hold == current else { return false }
        current = nil
        return true
    }
}
