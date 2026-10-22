import Foundation

// The first-launch welcome, "One morning in Warsaw" (ADR-579): five swipeable chapters that show
// what Doddy does, and a sign-in sheet at the bottom. Everything here is pure maths and rules
// (no UI, no strings), so it is tested on Linux. The drawing is `DoddyApp/Features/Welcome`.
//
// Honest by construction: the chapters are scripted demonstrations. Nothing here saves, sends,
// looks up or signs in anything.

/// The owner's pose pictures the welcome uses (`WholeDoddy_<pose>` image sets, unchanged).
public enum WelcomePose: String, CaseIterable, Sendable {
    case wave, bellyReading, shrug, fistpump, basketballDribble

    /// The image set in the app's asset catalog.
    public var assetName: String {
        switch self {
        case .wave: "WholeDoddy_wave"
        case .bellyReading: "WholeDoddy_belly_reading"
        case .shrug: "WholeDoddy_shrug"
        case .fistpump: "WholeDoddy_fistpump"
        case .basketballDribble: "WholeDoddy_basketball_dribble"
        }
    }

    /// Where the lowest ink is, as a fraction of the picture's height (measured on the supplied
    /// art). Standing him on the ground line means placing the picture so this fraction lands on it.
    public var soleFraction: Double {
        switch self {
        case .wave: 0.916
        case .bellyReading: 0.689
        case .shrug: 0.929
        case .fistpump: 0.936
        case .basketballDribble: 0.778
        }
    }
}

/// The five chapters, in order.
public enum WelcomeChapter: Int, CaseIterable, Sendable, Identifiable {
    case castleSquare, notes, reminder, plan, pocket

    public var id: Int { rawValue }

    public var pose: WelcomePose {
        switch self {
        case .castleSquare: .wave
        case .notes: .bellyReading
        case .reminder: .shrug
        case .plan: .fistpump
        case .pocket: .basketballDribble
        }
    }

    public static var count: Int { allCases.count }
}

/// What the scroll position means for the picture. `progress` is the page position in page units:
/// 0 is the first chapter centred, 4 the last. Everything is a pure function of it, so the picture
/// follows the finger 1:1 and can be grabbed and reversed at any moment.
public enum WelcomeFlow {
    /// The Warsaw line drifts this fraction as fast as the pages (parallax).
    public static let parallaxFactor = 0.45
    /// How high he hops, in points, at the middle of a page change.
    public static let hopHeight = 34.0
    /// How far the chapter text slides, in points per page of distance (depth against the page).
    public static let textSlide = 46.0

    public static var lastPage: Int { WelcomeChapter.count - 1 }

    /// Keeps a scroll position inside the five pages.
    public static func clamped(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), Double(lastPage))
    }

    /// The page the position is nearest to.
    public static func page(at progress: Double) -> Int {
        Int(clamped(progress).rounded())
    }

    /// 1 while the chapter's pose is shown, 0 when another is. A quick swap in the middle of a
    /// page change (from 40% to 60% of the way), where he is highest in the hop.
    public static func poseOpacity(chapter: Int, progress: Double) -> Double {
        let distance = abs(Double(chapter) - clamped(progress))
        return unit(0.5 + (0.5 - distance) * 5)
    }

    /// The chapter text's opacity: full on its page, gone before the next one is half in.
    public static func textOpacity(chapter: Int, progress: Double) -> Double {
        let distance = abs(Double(chapter) - clamped(progress))
        return unit(1 - distance * 1.25)
    }

    /// The chapter text's extra slide: towards the side it comes from, so it moves faster than its page.
    public static func textOffset(chapter: Int, progress: Double) -> Double {
        (Double(chapter) - clamped(progress)) * textSlide
    }

    /// 0 on a page, 1 half way between two: his hop. Zero at both ends, so he never hops on the spot.
    public static func hop(progress: Double) -> Double {
        let p = clamped(progress)
        return sin((p - p.rounded(.down)) * .pi)
    }

    /// His lean while he hops, in degrees: one way for the first half of a page change, the other for the second.
    public static func tilt(progress: Double) -> Double {
        let p = clamped(progress)
        return sin((p - p.rounded(.down)) * 2 * .pi) * -4
    }

    /// How far the ground line has moved, in points (1:1 with the pages).
    public static func groundOffset(progress: Double, pageWidth: Double) -> Double {
        -clamped(progress) * pageWidth
    }

    /// How far the Warsaw line has moved, in points.
    public static func skylineOffset(progress: Double, pageWidth: Double) -> Double {
        groundOffset(progress: progress, pageWidth: pageWidth) * parallaxFactor
    }

    private static func unit(_ value: Double) -> Double { min(max(value, 0), 1) }
}

/// Whether the welcome shows. One rule, so it is tested.
public enum WelcomeRule {
    /// - Parameters:
    ///   - seen: the person has been through it (or skipped it) on this installation.
    ///   - firstInstallation: a genuinely new installation (`ProfileStore.isFirstInstallation`).
    ///     Someone updating from an older version is not surprised with it.
    ///   - replayRequested: Settings › "Show the welcome again".
    ///   - override: a UI-test launch argument (`-welcome 1` forces it, `-welcome 0` skips it).
    public static func shouldShow(seen: Bool, firstInstallation: Bool, replayRequested: Bool, override: Bool?) -> Bool {
        if let override { return override }
        if replayRequested { return true }
        return firstInstallation && !seen
    }
}

/// Time inside one chapter's scene, in seconds since the chapter became current. Scenes read these
/// instead of running timers, so a swipe can end any scene at once and nothing blocks input.
public enum WelcomeTimeline {
    /// 0 before `start`, 1 after `start + duration`, linear between.
    public static func fraction(_ elapsed: Double, start: Double, duration: Double) -> Double {
        guard duration > 0 else { return elapsed >= start ? 1 : 0 }
        return min(max((elapsed - start) / duration, 0), 1)
    }

    /// A gentle slow-down towards the end, for things that arrive.
    public static func easeOut(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return 1 - (1 - x) * (1 - x) * (1 - x)
    }

    /// The first part of `text`, as if typed: whole characters only.
    public static func typed(_ text: String, elapsed: Double, start: Double, duration: Double) -> String {
        let count = text.count
        let shown = Int((fraction(elapsed, start: start, duration: duration) * Double(count)).rounded(.down))
        return String(text.prefix(min(max(shown, 0), count)))
    }

    /// 0...1: how far a pecking bird's head is down at time `t`. Two quick pecks every 3.6 s.
    public static func peck(_ t: Double) -> Double {
        let phase = (t.truncatingRemainder(dividingBy: 3.6) + 3.6).truncatingRemainder(dividingBy: 3.6) / 3.6
        func bump(_ from: Double, _ to: Double) -> Double {
            guard phase >= from, phase <= to else { return 0 }
            return sin((phase - from) / (to - from) * .pi)
        }
        return max(bump(0.62, 0.70), bump(0.78, 0.86))
    }
}
