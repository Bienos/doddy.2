import Foundation

// Motion v2, MV3: the plan's DEBUG checks, run by the app every frame in debug builds (and shown
// by the annotated mode). Each is one of the brief's acceptance checks, measured on the real
// screen instead of the reference's mock: one Doddy, his soles on his edge, size changing only in
// the air or unseen, his clear zone kept, and no listening pose without a live microphone.

public struct MotionChecks: Sendable {
    public struct Violation: Equatable, Sendable {
        public var t: Double
        public var rule: String
        public var detail: String
    }

    /// Everything found so far (the newest last), and how many in all.
    public private(set) var violations: [Violation] = []
    public private(set) var count = 0
    private var lastScale: Double?
    private var doubleSeen = false
    private var lastCarries = 0
    /// The newest finding in words (the annotated mode shows it).
    public var lastDetail: String { violations.last.map { "\($0.rule): \($0.detail)" } ?? "" }
    /// Keep the list short; the count keeps going.
    public static let kept = 50

    public init() {}

    mutating func add(_ t: Double, _ rule: String, _ detail: String) {
        count += 1
        violations.append(Violation(t: t.rounded(), rule: rule, detail: detail))
        if violations.count > Self.kept { violations.removeFirst() }
    }

    /// One frame. `drawn` is how many drawings of him the screen has on it now, `drawnWhere` says
    /// where each is (for the finding's text).
    public mutating func check(_ host: MotionHost, drawn: Int, drawnWhere: String = "") {
        let e = host.engine
        let t = e.now
        // Before he has a place there is nothing to check (his default size isn't a size he has).
        guard host.isPlaced else {
            lastScale = nil
            doubleSeen = false
            lastCarries = e.carries
            return
        }
        defer { lastCarries = e.carries }
        let visible = host.placement != .hidden && e.opacity > 0.01
        // Rule 1: one Doddy, never two. SwiftUI adds the new drawing and removes the old one in
        // one update, so two are counted only if they are still there at the next check.
        if drawn > 1 {
            if doubleSeen { add(t, "one Doddy", "\(drawn) drawings on screen" + (drawnWhere.isEmpty ? "" : ": \(drawnWhere)")) }
            doubleSeen = true
        } else {
            doubleSeen = false
        }
        // Rule 4: soles on a real edge, within 2 pt (1 pt on the composer). Against the edge the
        // engine stood on at its last step: the system moves a slot's edge between his frames, and
        // his drawing moves with it (it is offset by the dip alone, `DoddyFigure.slotDY`).
        if visible, case .slot(let id) = host.placement, e.mode != .flight, !e.hiddenBehind,
           let frame = host.lastStepFrames[id] ?? host.scene.frames[id] {
            let gap = abs(e.pos.y - (frame.minY + e.surfaceDip(id)))
            let limit = id == .composer ? 1.0 : 2.0
            if gap > limit { add(t, "feet on something real", "\(id) gap \(MotionMath.format(gap, digits: 1)) pt") }
        }
        // Rule 13: his size changes only in the air or while he is faded out (or when he was carried
        // unseen since the last check, e.g. into Ask's composer as its cover starts up; the check
        // may run a frame or two after the carry, so "since the last check", not "this frame").
        let carriedSinceLastCheck = e.carries != lastCarries
        if let last = lastScale, abs(e.scale - last) > 1e-6, e.mode != .flight, e.opacity > 0.01, !carriedSinceLastCheck {
            add(t, "two sizes, one figure", "scale \(MotionMath.format(e.scale, digits: 2)) while \(e.mode.rawValue)")
        }
        lastScale = e.scale
        // Rule 8: his clear zone keeps 24 pt from Send and the undo bar's Undo, and off the tabs.
        if visible, e.mode == .attached, let a = e.anchor {
            let zone = MotionLayout.zone(soles: MotionPoint(x: e.pos.x, y: e.pos.y), scale: e.scale)
            var keep: [(String, Double)] = [("send", MotionLayout.sendClearance), ("undo", MotionLayout.sendClearance)]
            for tab in ["home", "memories", "settings"] { keep.append(("tab.\(tab)", 0)) }
            for (name, clearance) in keep {
                guard let r = host.scene.marks[name], host.scene.mounted.contains(Self.owner(of: name)) else { continue }
                if !MotionLayout.blocked(zone: zone, by: [r], clearance: clearance).isEmpty {
                    add(t, "clear zone", "on \(a.surface) his zone covers \(name)")
                }
            }
        }
        // Rule 10: no listening pose unless the microphone is live.
        if visible, e.pose.listening, !host.scene.voiceLive { add(t, "honest always", "listening without a live microphone") }
    }

    /// The surface a mark sits on, so a mark from a screen that is gone isn't checked.
    static func owner(of mark: String) -> MotionSurfaceID {
        switch mark {
        case "send": .composer
        case "undo": .panel
        default: .rail
        }
    }
}
