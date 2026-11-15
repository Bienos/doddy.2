import Foundation

/// How long Doddy's voice kept coming out after the person interrupted him (decision
/// `2026-11-15-conversation-core-and-corrections`; research "Human Conversation Intelligence" of 15 Nov 2026,
/// report 10, "interrupt-to-silence").
///
/// What it measures, and what it doesn't:
/// - From the provider's interruption event reaching the phone to the last buffer of his voice handed to the output
///   after it (`AgentVoiceMeter`, the same loudness numbers as `VoiceAudibleOnset`). It is **not** from the moment the
///   person started speaking: the provider decides that it was an interruption first, and the app has no speech
///   detection of its own, so that part is not in the number and is written as such in the line.
/// - It is sound handed to the output, not heard at the ear: the iPhone's output delay comes on top.
/// - The voice counts as stopped once a quiet stretch of `quietSeconds` follows; the time is when the last loud buffer
///   came. Already quiet when the event came: 0. Still loud after `maxWait`: the line says so instead of a number.
/// - The threshold is `VoiceAudibleOnset.defaultThreshold`, chosen, not measured on a device.
///
/// Plain Swift: seconds and levels in, seconds and fixed words out; no audio, no words. One monotonic clock
/// (`ProcessInfo.systemUptime` in the app). Used by the iPhone app; the Watch and Mac apps (paused) don't use it.
public struct VoiceInterruptSilence: Sendable, Equatable {
    public enum Result: Sendable, Equatable {
        /// Seconds from the interruption event to the last loud buffer after it (0: already quiet).
        case stopped(Double)
        /// Still sound `maxWait` seconds after the event.
        case stillSounding

        /// "interruption to silence 0.18 s (from the provider's interruption event; the person's own start is not
        /// measured)": fixed words and seconds only.
        public var line: String {
            switch self {
            case .stopped(let seconds):
                "interruption to silence \(VoiceStartTimeline.text(seconds)) (from the provider's interruption event; the person's own start is not measured)"
            case .stillSounding:
                "interruption to silence not reached in \(VoiceStartTimeline.text(VoiceInterruptSilence.maxWait)) (from the provider's interruption event)"
            }
        }
    }

    /// A quiet stretch this long after the last loud buffer means the voice has stopped.
    public static let quietSeconds = 0.3
    /// Give up after this long.
    public static let maxWait = 5.0

    public let threshold: Double
    public private(set) var result: Result?

    private var interruptedAt: Double?
    private var lastLoudAt: Double?
    private var quietRun = 0.0

    public init(threshold: Double = VoiceAudibleOnset.defaultThreshold) {
        self.threshold = threshold
    }

    public var isWatching: Bool { interruptedAt != nil && result == nil }

    /// The provider's interruption event reached the phone. A second one while watching starts again from it.
    public mutating func begin(at now: Double) {
        reset()
        guard now.isFinite else { return }
        interruptedAt = now
    }

    public mutating func reset() {
        interruptedAt = nil
        lastLoudAt = nil
        quietRun = 0
        result = nil
    }

    /// One buffer of his audio. Returns the result the one time it is settled, nil every other time.
    @discardableResult
    public mutating func push(level: Double, seconds: Double, at now: Double) -> Result? {
        guard let interruptedAt, result == nil, now.isFinite, seconds.isFinite, seconds > 0 else { return nil }
        if level.isFinite, level >= threshold {
            lastLoudAt = now
            quietRun = 0
        } else {
            quietRun += seconds
        }
        if quietRun + 1e-9 >= Self.quietSeconds {
            let stoppedAt = lastLoudAt ?? interruptedAt
            result = .stopped(max(0, stoppedAt - interruptedAt))
            return result
        }
        return check(at: now)
    }

    /// No buffer may come once his track goes quiet: the app also looks after `quietSeconds` and at `maxWait`.
    @discardableResult
    public mutating func check(at now: Double) -> Result? {
        guard let interruptedAt, result == nil, now.isFinite else { return nil }
        let lastSound = lastLoudAt ?? interruptedAt
        if now - interruptedAt >= Self.maxWait, now - lastSound < Self.quietSeconds {
            result = .stillSounding
            return result
        }
        if now - lastSound >= Self.quietSeconds {
            result = .stopped(max(0, lastSound - interruptedAt))
            return result
        }
        return nil
    }
}
