import Foundation

// What a voice conversation does when iOS takes its audio away (ADR-584). A phone call, an alarm or
// Siri interrupts the audio session; neither voice SDK reacts to that, so before this rule the
// conversation stayed "listening" with a microphone that heard nothing, and the one-conversation
// gate sent every tap on Doddy back to it. Now a short interruption (a declined call, Siri) is
// resumed in place, and anything longer ends the conversation as a drop: the microphone, the island
// and the pill are freed, and the next conversation is told it was cut off. Plain Swift for the
// Linux tests; VoiceSessionController follows it.

public enum VoiceInterruptionPolicy {
    /// How long iOS may hold the audio before the conversation is ended rather than resumed. Long
    /// enough to decline a call or dismiss Siri, short enough that nobody comes back to a deaf Doddy.
    public static let resumeGraceSeconds: TimeInterval = 10

    public enum Decision: Equatable, Sendable {
        /// Nothing to do.
        case ignore
        /// iOS has the audio: say so and wait (at most `resumeGraceSeconds`).
        case markPaused
        /// iOS gave the audio back in time: activate the audio session again and carry on.
        case resume
        /// End the conversation as `VoiceSessionEnd.dropped(.audioInterrupted)`.
        case endAsDrop
    }

    /// iOS took the audio (the audio session's interruption "began").
    public static func began(isLive: Bool) -> Decision {
        isLive ? .markPaused : .ignore
    }

    /// iOS says the interruption is over (`.ended`). `pausedSince` is when `.began` arrived, or nil
    /// if it never did. `shouldResume` is iOS's `.shouldResume` option: without it iOS is saying the
    /// audio shouldn't simply start again.
    public static func ended(pausedSince: Date?, shouldResume: Bool, now: Date, isLive: Bool) -> Decision {
        guard isLive, let pausedSince else { return .ignore }
        guard shouldResume, now.timeIntervalSince(pausedSince) <= resumeGraceSeconds else { return .endAsDrop }
        return .resume
    }

    /// A check while still paused: on a timer after `.began`, and when Doddy comes back to the
    /// front. iOS doesn't promise an `.ended` at all, so a pause past the grace time ends the
    /// conversation whether or not one arrives.
    public static func stillPaused(pausedSince: Date?, now: Date, isLive: Bool) -> Decision {
        guard isLive, let pausedSince else { return .ignore }
        return now.timeIntervalSince(pausedSince) > resumeGraceSeconds ? .endAsDrop : .ignore
    }

    /// iOS restarted its media services: every audio object the conversation had is gone.
    public static func mediaServicesReset(isLive: Bool) -> Decision {
        isLive ? .endAsDrop : .ignore
    }
}
