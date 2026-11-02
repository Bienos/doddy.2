import Foundation

/// Doddy's beat on the Dynamic Island while he talks and Doddy is not the app on screen (owner,
/// 30 Oct 2026, ADR-683: "pulse around Dynamic Island outside app like it is on Home").
///
/// A Live Activity can't run an animation of its own: iOS draws it again only when the app sends
/// an update. So while he talks, the app sends one small number every `interval`: how loud his
/// voice was over that stretch, as a step from 0 (quiet between words) to `maxStep` (his loudest).
/// The island swells and eases with each step. That is a beat about every 0.6 s, not Home's 30
/// frames a second.
///
/// The number comes from the loudness of the audio Doddy plays (ADR-655), never the microphone,
/// and never what he says. It stays on the iPhone: the island is updated locally, with no push.
public struct IslandVoiceBeat: Sendable {
    /// How often the app sends a beat while he talks off screen. Each one is a Live Activity
    /// update, so this is also how often the widget is drawn again.
    public static let interval: TimeInterval = 0.6
    /// The loudest step. Steps run from 0 to this.
    public static let maxStep = 4
    /// Below this level the beat is 0: a pause between his words.
    static let quietBelow = 0.08

    /// The step sent last, or nil before the first beat.
    public private(set) var last: Int?

    public init() {}

    /// The step for a beat whose loudest level (0 to 1) was `peak`. While he is audible it is
    /// never the step sent just before, so a long, evenly loud sentence still moves the island:
    /// a repeat goes one step up, or one down from the top.
    public mutating func next(peak: Double) -> Int {
        var step = Self.step(peak: peak)
        if step > 0, step == last {
            step = step == Self.maxStep ? step - 1 : step + 1
        }
        last = step
        return step
    }

    /// He stopped talking or Doddy came on screen.
    public mutating func reset() {
        last = nil
    }

    /// 0 for a pause, then 1 to `maxStep` spread evenly over the levels above it.
    static func step(peak: Double) -> Int {
        guard peak.isFinite, peak >= quietBelow else { return 0 }
        let scaled = (min(1, peak) - quietBelow) / (1 - quietBelow)
        return 1 + min(maxStep - 1, Int(scaled * Double(maxStep)))
    }
}

extension SpeechPulse {
    /// The loudest the made-up pulse gets between `start` and `end` (seconds after he started
    /// speaking), looked at every 20 ms. For a beat that stands for a stretch of time (ADR-683)
    /// when there is no audio track to measure.
    public static func peak(from start: TimeInterval, to end: TimeInterval) -> Double {
        guard start.isFinite, end.isFinite else { return 0 }
        let from = max(0, start)
        guard end >= from else { return 0 }
        var best = level(at: end)
        var t = from
        while t < end {
            best = max(best, level(at: t))
            t += 0.02
        }
        return best
    }
}
