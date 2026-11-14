import Foundation

/// When the first sound of Doddy's voice arrived after a press (decision `2026-11-14-first-audible-sound`).
///
/// The log already says when the voice provider reports that he started speaking
/// (`voice first speaking event after start`), and that event can come before anything plays. This
/// watches the loudness of the audio his track hands the app instead (`AgentVoiceMeter`, one level
/// per buffer, the same numbers that draw the island's lines) and notes when sound first came, so a
/// phone log can tell the two apart.
///
/// What it is, and isn't:
/// - It is the first buffer of sound **handed to the output**, found from its loudness. It is not heard
///   at the ear: the iPhone's own output delay (`AVAudioSession.outputLatency`, a Bluetooth headset has
///   more) comes on top, and the app logs that beside it.
/// - The meter starts listening when his audio track appears, on the first speaking event, so a sound
///   that began before that can't be seen. `listeningFrom` says when the meter's first buffer came: a
///   `sound` equal to it means the sound was already playing and "no earlier than this" is all that is known.
/// - The threshold and the length are chosen, not measured on a device (they sit between a decoded
///   line's hiss and speech, `VoiceAudibleOnsetTests`); read the first logged starts before trusting
///   a number to a tenth of a second.
///
/// Plain Swift in DoddyCore: only seconds in and out, no audio, no words. Every time is a reading of one
/// monotonic clock in seconds (`ProcessInfo.systemUptime` in the app), so a changed wall clock can't skew it.
/// Used by the iPhone app; the Watch and Mac apps (paused) don't use it.
public struct VoiceAudibleOnset: Sendable, Equatable {
    /// Seconds after the press, both measured from the same press.
    public struct Result: Sendable, Equatable {
        /// To the first buffer of the run of sound that lasted.
        public let sound: Double
        /// To the first buffer of any kind the meter saw after the press.
        public let listeningFrom: Double

        public init(sound: Double, listeningFrom: Double) {
            self.sound = sound
            self.listeningFrom = listeningFrom
        }

        /// "first sound 2.84 s · listening from 2.79 s · output latency 0.05 s": fixed words and seconds
        /// only. An output latency that isn't a number is left out rather than written as 0.
        public func line(outputLatency: Double? = nil) -> String {
            var parts = ["first sound \(VoiceStartTimeline.text(sound))", "listening from \(VoiceStartTimeline.text(listeningFrom))"]
            if let outputLatency, outputLatency.isFinite {
                parts.append("output latency \(VoiceStartTimeline.text(outputLatency))")
            }
            return parts.joined(separator: " · ")
        }
    }

    /// A buffer's level (`VoiceLevel.level(rms:)`, 0 to 1) at or above this is sound: about -42 dB, well
    /// above the hiss of a decoded line (-65 dB gives 0) and well below speech (-25 dB gives 0.66).
    public static let defaultThreshold = 0.2
    /// The sound must last this many seconds in a row, so one click at the start of a stream isn't a voice.
    public static let defaultSustain = 0.04
    /// A press with no sound after this many seconds is dropped, so a start that never opened a
    /// conversation can't time the next one that has no press of its own.
    public static let maxWait = 60.0

    public let threshold: Double
    public let sustain: Double
    /// Set once, when the sound is found; nil until then.
    public private(set) var result: Result?

    private var startedAt: Double?
    private var firstBufferAt: Double?
    private var runStartedAt: Double?
    private var runSeconds = 0.0

    public init(threshold: Double = VoiceAudibleOnset.defaultThreshold, sustain: Double = VoiceAudibleOnset.defaultSustain) {
        self.threshold = threshold
        self.sustain = sustain
    }

    /// A press is waiting for its sound: begun, not found, not expired.
    public var isWatching: Bool { startedAt != nil && result == nil }

    /// A press (Home's tap, the Action Button) that is about to start a conversation. Forgets the last result.
    /// A time that isn't a number is no press at all.
    public mutating func begin(at startedAt: Double) {
        reset()
        guard startedAt.isFinite else { return }
        self.startedAt = startedAt
    }

    /// Nothing is watched until the next press.
    public mutating func reset() {
        startedAt = nil
        firstBufferAt = nil
        runStartedAt = nil
        runSeconds = 0
        result = nil
    }

    /// One buffer of his audio: its level, how long it lasted, and when it arrived. Returns the result the
    /// one time the sound is found, and nil every other time. A buffer with no length, or a time that isn't
    /// a number, is ignored; a level that isn't a number is silence.
    @discardableResult
    public mutating func push(level: Double, seconds: Double, at now: Double) -> Result? {
        guard let startedAt, result == nil, now.isFinite, seconds.isFinite, seconds > 0 else { return nil }
        if now - startedAt > Self.maxWait {
            reset()
            return nil
        }
        let first = firstBufferAt ?? now
        firstBufferAt = first
        guard level.isFinite, level >= threshold else {
            runStartedAt = nil
            runSeconds = 0
            return nil
        }
        let began = runStartedAt ?? now
        runStartedAt = began
        runSeconds += seconds
        // Ten-millisecond buffers add up to 0.04 only to within rounding: allow for it.
        guard runSeconds + 1e-9 >= sustain else { return nil }
        let found = Result(sound: Self.clamped(began - startedAt), listeningFrom: Self.clamped(first - startedAt))
        result = found
        return found
    }

    private static func clamped(_ seconds: Double) -> Double {
        seconds.isFinite ? max(0, seconds) : 0
    }
}
