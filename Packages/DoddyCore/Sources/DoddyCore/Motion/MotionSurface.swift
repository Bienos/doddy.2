import Foundation

// Motion v2 (MV1): what the engine knows about the screen. Doddy only ever stands on a surface:
// an edge the host app reports (the plan's surface map, section 1). The engine never reads
// views; the host answers these protocols from its own layout, and the golden tests answer them
// from the reference prototype's layout (`design/motion-v2/reference/engine.js`).

/// Which edge he is on. The names follow the owner's brief and reference engine; the plan's
/// section 1 maps them onto this app (stage: Home's art; composer: Ask's composer; rail: the
/// tab bar's top edge; panel: a bar that rises and falls under him, the undo bar in this app;
/// detail: the note page's card; rule: the n-th row edge of a scrolling list).
public struct MotionSurfaceID: Hashable, Sendable, CustomStringConvertible {
    public enum Kind: Hashable, Sendable {
        case stage, composer, panel, rail, detail
        case rule(Int)
    }

    public var kind: Kind

    public init(_ kind: Kind) { self.kind = kind }

    public static let stage = MotionSurfaceID(.stage)
    public static let composer = MotionSurfaceID(.composer)
    public static let panel = MotionSurfaceID(.panel)
    public static let rail = MotionSurfaceID(.rail)
    public static let detail = MotionSurfaceID(.detail)
    public static func rule(_ i: Int) -> MotionSurfaceID { MotionSurfaceID(.rule(i)) }

    /// The row index for a list rule, nil otherwise.
    public var ruleIndex: Int? {
        if case .rule(let i) = kind { return i }
        return nil
    }

    public var isRule: Bool { ruleIndex != nil }

    public var description: String {
        switch kind {
        case .stage: "stage"
        case .composer: "composer"
        case .panel: "panel"
        case .rail: "rail"
        case .detail: "detail"
        case .rule(let i): "rule:\(i)"
        }
    }
}

/// A place to stand: a surface and the x of his soles' centre on it.
public struct MotionSpot: Equatable, Sendable {
    public var surface: MotionSurfaceID
    public var x: Double

    public init(_ surface: MotionSurfaceID, x: Double) {
        self.surface = surface
        self.x = x
    }

    /// Same surface and within 6 pt: the reference's `sameAnchor`.
    public func isSame(as other: MotionSpot?) -> Bool {
        guard let other else { return false }
        return surface == other.surface && abs(x - other.x) < 6
    }
}

/// One surface's live geometry, in window points.
public protocol MotionSurface {
    var id: MotionSurfaceID { get }
    /// Drawing order; he flies just above the higher of the two surfaces.
    var layer: Double { get }
    /// His size on it: 1.4 on Home's stage, 1 elsewhere (rule 13).
    var scale: Double { get }
    /// The edge's y now.
    func top() -> Double
    /// Horizontal offset of the whole surface (a page sliding in), added to a spot's x.
    func dx() -> Double
    /// The x range his soles may stand in without breaking a clear zone.
    func standRange() -> ClosedRange<Double>
    /// The edge's visible extent (for the debug overlay).
    func segment() -> ClosedRange<Double>
    func isVisible() -> Bool
    /// Where a spot on this surface will be `dt` seconds from now, if the surface knows its
    /// own motion (a spring, a scroll, the keyboard). Nil: it isn't moving by itself, so the
    /// spot is where it is now.
    func pointAhead(x: Double, dt: Double) -> MotionPoint?
    /// Where a spot will come to rest, if it is moving. Nil: the same as now.
    func predictedPoint(x: Double) -> MotionPoint?
    /// Whether the surface is moving under him right now.
    func isMoving() -> Bool
    /// The y the edge will settle at (its target), for the "is it about to move away" test.
    func settleY() -> Double
}

/// A scrolling list of rules (Memories' rows), when one is on screen.
public protocol MotionList {
    var ruleCount: Int { get }
    /// Rule i's y `dt` seconds from now (0: now), following the scroll's own physics.
    func ruleY(_ i: Int, ahead dt: Double) -> Double
    /// The list's visible band.
    var top: Double { get }
    var bottom: Double { get }
    /// The scroll's measured velocity (pt/s, content moving up is positive).
    var velocity: Double { get }
    /// A fling still faster than lily-pad speed.
    var isFlinging: Bool { get }
    /// A programmatic scroll to the top.
    var isScrollingToTop: Bool { get }
    /// When the scroll last became slower than `MotionTiming.lilySettleSpeed` (nil if it isn't).
    var slowSince: Double? { get }
    /// Whether a finger is on row i (he never lands on a touched row).
    func isUnderFinger(_ i: Int) -> Bool
    var isFingerDown: Bool { get }
    /// His x on any rule (the right end, in the clear gutter).
    var ruleX: Double { get }
    /// Where he waits while the list moves too fast: the rail under this tab.
    var waitSpot: MotionSpot { get }
}

/// What the engine asks of the screen around him. The host (the app's director, or the golden
/// tests' reference world) answers from its own state; nothing here is a view.
public protocol MotionWorld: AnyObject {
    func surface(_ id: MotionSurfaceID) -> any MotionSurface
    /// The screen in the reference's terms: "home", "talk", "memories" or "review". Used for his
    /// per-screen spot memory and focus.
    var screenKey: String { get }
    /// Where he should be on the current screen (his spot, or the spot he remembered).
    func preferredSpot(for engine: MotionEngine) -> MotionSpot?
    /// Where he waits during rapid switching (calm mode).
    func waitSpot(for engine: MotionEngine) -> MotionSpot
    func isWaitSpot(_ spot: MotionSpot?) -> Bool
    /// What his eyes rest on when he attends to the screen (nil: you).
    func focusPoint() -> (point: MotionPoint, label: String)?
    /// The list on screen, if he can ride it right now (nil otherwise).
    func ridingList() -> (any MotionList)?
    /// A sheet or cover hides the app: he doesn't move.
    var isCovered: Bool { get }
    var isOnHome: Bool { get }
    var isOnTalk: Bool { get }
    var isOnMemories: Bool { get }
    /// A bar that rises and falls (the reference's draft panel) and its spring, if shown.
    var carrier: MotionCarrier? { get }
    /// Whether a review-like task is open, the keyboard is up or voice capture is live
    /// (playful moments wait), and when the user last touched or tapped.
    var isTaskOpen: Bool { get }
    var isKeyboardUp: Bool { get }
    var isVoiceLive: Bool { get }
    var lastInput: Double { get }
    var lastTap: Double { get }
    /// Home glances: a waiting draft strip, a new-memory dot.
    var hasWaitingStrip: Bool { get }
    var hasMemoriesBadge: Bool { get }
    /// An offline banner (or similar status bar) is showing.
    var isBannerShowing: Bool { get }
    /// Things moving just above his head (a toast, a banner), for ducking.
    func overheadMovers(dtMs: Double) -> [MotionMover]
    /// Gaze targets the engine names but the host lays out.
    func gazePoint(_ cue: MotionGazeCue) -> MotionPoint
    /// Hold to talk on Home: start voice (false if it can't start here).
    func startVoice() -> Bool
    var voicePhaseIsStarting: Bool { get }
    func cancelStartingVoice()
    func endVoice(_ why: String)
    /// A tap on him: Talk opens.
    func openTalkFromHome(tapT: Double)
    /// Where the finger is, for gaze that follows it.
    var finger: MotionFinger { get }
}

/// The carrier bar: its edge now, where it is heading, its speed and last frame's edge.
public struct MotionCarrier: Sendable {
    public var top: Double
    public var target: Double
    public var velocity: Double
    public var previousTop: Double
    public var isDragged: Bool
    public var mode: Mode

    public enum Mode: Sendable {
        /// Fully open: a task such as review.
        case open
        /// A resting strip above the rail.
        case strip
        /// Going away.
        case hidden
    }

    public init(top: Double, target: Double, velocity: Double, previousTop: Double, isDragged: Bool, mode: Mode) {
        self.top = top
        self.target = target
        self.velocity = velocity
        self.previousTop = previousTop
        self.isDragged = isDragged
        self.mode = mode
    }
}

/// Something sliding past above him.
public struct MotionMover: Sendable {
    public var x0, x1, y0, y1: Double
    /// Its speed in pt/s.
    public var speed: Double

    public init(x0: Double, x1: Double, y0: Double, y1: Double, speed: Double) {
        self.x0 = x0
        self.x1 = x1
        self.y0 = y0
        self.y1 = y1
        self.speed = speed
    }
}

public struct MotionFinger: Sendable {
    public var isDown: Bool
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    public var moved: Bool

    public init(isDown: Bool = false, x: Double = 0, y: Double = 0, vx: Double = 0, vy: Double = 0, moved: Bool = false) {
        self.isDown = isDown
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.moved = moved
    }
}

/// Places his eyes go that only the host can lay out.
public enum MotionGazeCue: Sendable, Equatable {
    case tab(String)
    case draftStrip
    case draftFirstLine
    case composerText
    case sentBubble
    case sourceLabel
    case banner
}

/// Why he is moving: shown in the log and kept with each hop's record.
public struct MotionReason: Sendable {
    public var why: String
    /// The tab whose tap caused it; tab hops are capped to land by 484 ms after the tap.
    public var tab: String?
    public var tapT: Double?

    public init(_ why: String, tab: String? = nil, tapT: Double? = nil) {
        self.why = why
        self.tab = tab
        self.tapT = tapT
    }
}
