import Foundation

/// The voice conversation and the iPhone's lock (decision 2026-11-14-voice-mute-when-protected-data-unavailable,
/// after ADR-723; DOD-08, DOD-11, ASK-01).
///
/// A conversation can go on after the iPhone locks (background audio, the island), and it holds what the agent was
/// given at the start: that cannot be taken back. With "Lock Doddy with Face ID" on, the person asked for their things
/// to stay behind Face ID, so once iOS says protected data is going away (the iPhone locks) the conversation ends: the
/// microphone closes, nothing more is sent to the agent, a card that was waiting is dropped and never runs, and nothing
/// starts again by itself on the unlock. Until the end has finished, a tool call that reaches the person's things is
/// refused in words (`ProtectedDataPolicy.reply`), never answered with an empty result.
/// With the lock off nothing changes: a conversation in a pocket goes on (ADR-577).
///
/// This type only decides. `VoiceSessionController` does what it says: one observer for iOS's two notices, one call
/// into `receive`, and `stop(.iPhoneLocked)` as the one way out. iOS announces a lock that is coming
/// (`protectedDataWillBecomeUnavailable`) but says nothing about one that was already there when a conversation
/// starts, so the start reads iOS's answer once (`sync`).
public struct ProtectedDataGuard: Equatable, Sendable {
    /// What iOS said: `UIApplication.protectedDataWillBecomeUnavailableNotification` and
    /// `protectedDataDidBecomeAvailableNotification`.
    public enum Signal: Equatable, Sendable {
        case becameUnavailable, becameAvailable
    }

    /// Where the conversation is, as the controller sees it.
    public enum Conversation: Equatable, Sendable {
        /// Idle, ended, failed or never started: nothing is open.
        case notRunning
        /// Asked to connect: the notes may already be on their way to the agent.
        case connecting
        /// Listening, thinking or speaking, muted or not, with or without a card waiting.
        case running
    }

    public enum Outcome: Equatable, Sendable {
        case nothing
        /// End the conversation now, the way End does for this reason. That closes the microphone and the agent's
        /// connection, drops any card waiting (nothing on it runs, nothing is kept as a draft) and clears every yes the
        /// person gave. It is never started again by this type.
        case end(VoiceSessionEnd)
    }

    public enum ToolDecision: Equatable, Sendable {
        case run
        /// The agent hears this text instead of a result: nothing was read, saved or changed.
        case refuse(reply: String)
    }

    /// What iOS last said, or what the start read. Never guessed.
    public private(set) var protectedDataAvailable: Bool

    public init(protectedDataAvailable: Bool = true) {
        self.protectedDataAvailable = protectedDataAvailable
    }

    /// A notice from iOS. Saying the same thing again changes nothing, so a conversation is ended at most once for one
    /// lock; unlocking never resumes or starts anything.
    public mutating func receive(_ signal: Signal, conversation: Conversation, appLockOn: Bool) -> Outcome {
        switch signal {
        case .becameAvailable:
            protectedDataAvailable = true
            return .nothing
        case .becameUnavailable:
            let wasAvailable = protectedDataAvailable
            protectedDataAvailable = false
            guard wasAvailable else { return .nothing }
            return Self.outcome(conversation: conversation, appLockOn: appLockOn)
        }
    }

    /// The start of a conversation: iOS's own answer, read once, replaces whatever was remembered (an unlock can come
    /// while nothing listens for it). A conversation that starts on a locked iPhone with the Face ID lock on ends at
    /// once, so it never holds the person's notes while locked.
    public mutating func sync(protectedDataAvailable available: Bool, conversation: Conversation, appLockOn: Bool) -> Outcome {
        protectedDataAvailable = available
        guard !available else { return .nothing }
        return Self.outcome(conversation: conversation, appLockOn: appLockOn)
    }

    /// May this tool call run now? A refusal carries the words the agent hears. Open tools (sums, Doddy's own timers)
    /// keep working, and stopping one always can (`ProtectedDataPolicy.openTools`).
    public func decide(tool: String, appLockOn: Bool) -> ToolDecision {
        ProtectedDataPolicy.allows(tool: tool, protectedDataAvailable: protectedDataAvailable, appLockOn: appLockOn)
            ? .run
            : .refuse(reply: ProtectedDataPolicy.reply)
    }

    private static func outcome(conversation: Conversation, appLockOn: Bool) -> Outcome {
        guard appLockOn else { return .nothing }
        switch conversation {
        case .notRunning: return .nothing
        case .connecting, .running: return .end(.iPhoneLocked)
        }
    }
}
