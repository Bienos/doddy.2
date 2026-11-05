import Foundation

/// How loud Doddy's voice is, as a number for Home's island extension (ADR-655). The app
/// listens to the loudness of the audio he plays, a number per buffer, kept in memory for a
/// moment; the sound itself is never stored or sent anywhere.
public enum VoiceLevel {
    /// 0 to 1 from the root-mean-square of a buffer of samples scaled to -1...1: -50 dB (a quiet
    /// room) is 0 and -12 dB (loud speech) is 1.
    public static func level(rms: Double) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels + 50) / 38))
    }
}

/// Follows a raw level the way a level meter does: up quickly, down slowly, so the lines jump
/// with each word and ease away between them.
public struct VoiceLevelSmoother: Sendable {
    public private(set) var value = 0.0

    /// About how long it takes to follow a rise and a fall, in seconds.
    static let attack = 0.025
    static let release = 0.16

    public init() {}

    /// Takes the raw level of a buffer that lasted `seconds`, and returns the level to show.
    @discardableResult
    public mutating func push(_ raw: Double, seconds: Double) -> Double {
        let target = raw.isFinite ? min(1, max(0, raw)) : 0
        let tau = target > value ? Self.attack : Self.release
        let step = 1 - exp(-max(0, seconds.isFinite ? seconds : 0) / tau)
        value += (target - value) * step
        return value
    }

    public mutating func reset() {
        value = 0
    }
}
