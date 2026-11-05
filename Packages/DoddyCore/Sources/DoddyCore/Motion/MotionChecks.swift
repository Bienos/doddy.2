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
    /// When each mark was first found under his clear zone in the current stretch (-1: reported).
    private var zoneBlockedSince: [String: Double] = [:]
    private var lastOpacity = 1.0
    private var lastLandSeen = -99_999.0
    /// Below this opacity a figure isn't a visible size change (a quarter).
    static let visible = 0.25
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
            lastLandSeen = e.lastLand
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
        // Rule 13: his size changes only in the air or while he is faded out. Judged on what two
        // frames show: the engine changes the size inside a 20 ms invisible gap, so a frame longer
        // than the gap (a hitch) shows the gap's two sides back to back, each faint, and a resize
        // counts only if he is clearly visible in both. The landing step finishes the hop's own
        // size change (the flight's scale ends in the step that makes him attached), and so does
        // a carry (he is moved unseen, e.g. into Ask's composer as its cover starts up; the check
        // may run a frame or two after it, so "since the last check", not "this frame").
        let landedSinceLastCheck = e.lastLand != lastLandSeen
        let carriedSinceLastCheck = e.carries != lastCarries
        if let last = lastScale, abs(e.scale - last) > 1e-6, e.mode != .flight, !landedSinceLastCheck,
           !carriedSinceLastCheck, e.opacity > Self.visible, lastOpacity > Self.visible {
            add(t, "two sizes, one figure", "scale \(MotionMath.format(e.scale, digits: 2)) while \(e.mode.rawValue)")
        }
        lastScale = e.scale
        lastOpacity = e.opacity
        lastLandSeen = e.lastLand
        // Rule 8: his clear zone keeps 24 pt from Send and the undo bar's Undo, and off the tabs.
        // The app reports a screen's surfaces and marks one by one, so a finding needs to hold at
        // two checks in a row: a frame in which Send has moved and his spot hasn't yet is not
        // something anyone sees, while a wrong spot stays.
        var blockedNow: Set<String> = []
        if visible, e.mode == .attached, let a = e.anchor {
            let zone = MotionLayout.zone(soles: MotionPoint(x: e.pos.x, y: e.pos.y), scale: e.scale)
            var keep: [(String, Double)] = [("send", MotionLayout.sendClearance), ("undo", MotionLayout.sendClearance)]
            for tab in ["home", "memories", "settings"] { keep.append(("tab.\(tab)", 0)) }
            for (name, clearance) in keep {
                guard let r = host.scene.marks[name], host.scene.mounted.contains(Self.owner(of: name)) else { continue }
                if !MotionLayout.blocked(zone: zone, by: [r], clearance: clearance).isEmpty {
                    blockedNow.insert(name)
                    if let since = zoneBlockedSince[name] {
                        if since >= 0, t > since {
                            zoneBlockedSince[name] = -1  // reported once for this stretch
                            add(t, "clear zone", "on \(a.surface) his zone (x \(MotionMath.format(zone.minX, digits: 0))–\(MotionMath.format(zone.maxX, digits: 0)), "
                                + "y \(MotionMath.format(zone.minY, digits: 0))–\(MotionMath.format(zone.maxY, digits: 0)), scale \(MotionMath.format(e.scale, digits: 2))) "
                                + "covers \(name) (x \(MotionMath.format(r.minX, digits: 0))–\(MotionMath.format(r.maxX, digits: 0)), "
                                + "y \(MotionMath.format(r.minY, digits: 0))–\(MotionMath.format(r.maxY, digits: 0)))")
                        }
                    } else {
                        zoneBlockedSince[name] = t
                    }
                }
            }
        }
        for name in zoneBlockedSince.keys where !blockedNow.contains(name) { zoneBlockedSince[name] = nil }
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
