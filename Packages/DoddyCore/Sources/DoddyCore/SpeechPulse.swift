import Foundation

/// An imitation of how loud Doddy sounds while he talks (ADR-654), for the island extension on
/// Home. The app has no loudness for his voice: only the provider's real "speaking" state. So the
/// pulse is made up from a clock: one burst about every 0.42 s, a little uneven, one burst in
/// eight left out as a breath. It says nothing about what he says, and it is the same every time
/// from the same start. Bursts are at least 0.34 s apart, so it never pulses more than three
/// times a second.
public enum SpeechPulse {
    static let period: TimeInterval = 0.42
    static let width: TimeInterval = 0.34
    static let jitter: TimeInterval = 0.04
    static let breathEvery = 8

    /// 0 to 1, `time` seconds after he started speaking.
    public static func level(at time: TimeInterval) -> Double {
        guard time.isFinite, time >= 0 else { return 0 }
        let slot = Int(time / period)
        var best = 0.0
        for k in max(0, slot - 1)...(slot + 1) {
            guard let burst = burst(k) else { continue }
            let x = (time - burst.onset) / width
            if x >= 0, x <= 1 {
                best = max(best, burst.amplitude * pow(sin(Double.pi * x), 1.4))
            }
        }
        return min(1, best)
    }

    /// The `k`th burst: when it starts and how strong it is. Nil for a breath.
    static func burst(_ k: Int) -> (onset: TimeInterval, amplitude: Double)? {
        if k % breathEvery == breathEvery - 1 { return nil }
        let shift = unit(k, salt: 1) * 2 - 1
        let amplitude = 0.65 + 0.35 * unit(k, salt: 2)
        return (Double(k) * period + shift * jitter, amplitude)
    }

    /// A repeatable number from 0 to 1 for a burst and a purpose.
    static func unit(_ k: Int, salt: UInt64) -> Double {
        var x = (UInt64(truncatingIfNeeded: k) &+ salt) &* 0x9E37_79B9_7F4A_7C15
        x ^= x >> 29
        x = x &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 32
        return Double(x % 10_000) / 9_999
    }
}

/// The spring the island extension widens and narrows with (ADR-654). SwiftUI can't hand a
/// frame-by-frame animated value to a `Canvas`, so the extension asks for the value itself.
public enum IslandSpring {
    /// Where the value is `elapsed` seconds after it was told to go from `from` to `to`. A damping
    /// under 1 overshoots a little and settles, which is the pop.
    public static func value(
        from: Double, to: Double, elapsed: TimeInterval, response: Double = 0.5, damping: Double = 0.7
    ) -> Double {
        guard elapsed > 0 else { return from }
        guard response > 0 else { return to }
        let omega = 2 * Double.pi / response
        let delta = from - to
        if damping >= 1 {
            return to + delta * (1 + omega * elapsed) * exp(-omega * elapsed)
        }
        let omegaD = omega * (1 - damping * damping).squareRoot()
        let decay = exp(-damping * omega * elapsed)
        return to + delta * decay * (cos(omegaD * elapsed) + damping * omega / omegaD * sin(omegaD * elapsed))
    }
}
