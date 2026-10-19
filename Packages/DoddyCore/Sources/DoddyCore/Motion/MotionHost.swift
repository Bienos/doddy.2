import Foundation

// Motion v2, MV3 (docs/design/MOTION_V2_PLAN.md section 4, option B): the app's side of the motion
// world, without the app. The screens report what is on them (`MotionScene`: surface frames,
// which screen is up, what covers him); `MotionHost` answers the engine's questions from that and
// decides, each frame, where the app draws him: attached to the surface he stands on, in the one
// root overlay while he flies or fades, or not at all while something covers him. Pure, so the
// tab hops are tested on Linux with an iPhone-sized layout (MotionHostTests).

/// The app's screens in the motion world.
public enum MotionScreen: String, Sendable, CaseIterable {
    case home, memories, settings
    /// Ask (plan Q2: Ask's composer is "the composer").
    case talk
}

/// Where the app draws him this frame. The slot and the overlay read the same value, so the switch
/// happens in one update: never two Doddys, never zero.
public enum MotionPlacement: Equatable, Sendable {
    /// Inside the surface's own view, so the system moves him with it (scroll, keyboard, push).
    case slot(MotionSurfaceID)
    /// The root overlay: flights, fades, and crouching on a surface that has just gone.
    case overlay
    /// Not drawn: a sheet, a cover, the opening or a page is over him.
    case hidden
}

/// A page pushed on a tab's navigation stack.
public struct MotionPage: Equatable, Sendable {
    public var open: Bool
    /// The page is a note with its paper card (he may stand on it, brief: "Memories detail page").
    public var detail: Bool

    public init(open: Bool = false, detail: Bool = false) {
        self.open = open
        self.detail = detail
    }
}

/// What the screens report.
public struct MotionScene: Sendable {
    public var screen: MotionScreen = .home
    /// Each surface's last reported window frame (kept while it is off screen).
    public var frames: [MotionSurfaceID: MotionRect] = [:]
    /// The surfaces whose views are on screen now.
    public var mounted: Set<MotionSurfaceID> = []
    /// Named frames: "send", "undo", "tab.home", "tab.memories", "tab.settings", and
    /// "memories.list" (the Memories scroll view, its visible band).
    public var marks: [String: MotionRect] = [:]
    /// How many cards the Memories list shows (`rule(0)` … `rule(ruleCount - 1)`).
    public var ruleCount = 0
    /// Sheets, covers and the opening over the app.
    public var covers = 0
    public var pages: [MotionScreen: MotionPage] = [:]
    public var keyboardUp = false
    public var voiceLive = false
    public var memoriesBadge = false
    public var lastInput = -99_999.0
    public var lastTap = -99_999.0
    public var finger = MotionFinger()
    /// His size on Home's stage: 1.4×, or 1.0× at accessibility text sizes (Q12).
    public var homeScale = 1.4
    /// The Memories list's scroll (MV4).
    public var scroll = MotionScroll()

    public init() {}

    public var page: MotionPage { pages[screen] ?? MotionPage() }

    /// The screen a surface belongs to; nil for the rail and the strip, which are on every tab.
    public static func screen(of id: MotionSurfaceID) -> MotionScreen? {
        switch id.kind {
        case .stage: .home
        case .rule, .detail: .memories
        case .composer: .talk
        case .ledge(let name): name == "settings" ? .settings : .memories
        case .rail, .panel: nil
        }
    }
}

public final class MotionHost: MotionWorld {
    public let engine: MotionEngine
    public var scene = MotionScene()
    /// Off: nothing is drawn (iPad's sidebar, "Hide Doddy's pictures").
    public var isActive = true
    /// A tab tap not yet answered because the new screen hadn't reported its surfaces.
    public internal(set) var pendingTab: (screen: MotionScreen, tapT: Double)?
    /// A tap on him opens Talk (MV5 sets it; nil: nothing opens).
    public var onOpenTalk: ((Double) -> Void)?
    /// Press and hold on him starts voice if it can (MV5).
    public var onStartVoice: (() -> Bool)?
    /// The surface he was last moved off because it went away (so it is answered once).
    var relocatedFrom: MotionSpot?
    /// MV4: Ask is opening and its composer hasn't reported yet (he is unseen until it has).
    var talkPending = false
    /// The tab Ask was opened from (Home), where he goes back to as it closes.
    var returnScreen: MotionScreen = .home

    public init(settings: MotionSettings = MotionSettings()) {
        engine = MotionEngine(settings: settings)
        engine.attach(to: self)
    }

    // MARK: Driving

    /// Whether he has a place yet.
    public var isPlaced: Bool { engine.anchor != nil || engine.mode == .flight || engine.mode == .fade }

    /// Puts him on the current screen's spot at once, with no hop (the first time the app shows a
    /// screen with a surface on it). Returns false while the screen hasn't reported one.
    @discardableResult
    public func placeOnCurrentScreen(sitting: Bool = false, idleBehaviours: Bool = false) -> Bool {
        // Wait (up to `screenReportWait`) for the screen to report its own spot: at launch the
        // tab bar can report before Home's stage, and he must not start on the rail.
        let asked = placeAskedAt ?? engine.now
        placeAskedAt = asked
        guard screenHasReported() || engine.now - asked >= Self.screenReportWait else { return false }
        guard let spot = preferredSpot(for: engine), scene.frames[spot.surface] != nil else { return false }
        var p = MotionEngine.Placement(spot: spot)
        p.sitting = sitting
        // MV3: no 15 s sit and no welcome yet (MV5 turns them on).
        p.noSit = !idleBehaviours
        p.welcome = false
        var lastInput = scene.lastInput, lastTap = scene.lastTap
        engine.place(p, lastInputWillBe: &lastInput, lastTapWillBe: &lastTap)
        scene.lastInput = lastInput
        scene.lastTap = lastTap
        return true
    }

    /// A tab was tapped: the content commits in this frame, he catches up (rule 2).
    public func tabChanged(to screen: MotionScreen, tapT: Double) {
        guard screen != scene.screen else { return }
        scene.screen = screen
        scene.lastTap = tapT
        scene.lastInput = tapT
        if engine.hiddenBehind, screen != .memories { engine.leftCoveredScreen() }
        relocatedFrom = nil
        pendingTab = (screen, tapT)
    }

    /// When the app first asked to place him.
    var placeAskedAt: Double?

    /// Memories' still spots: the empty notes screen and the empty Lists screen.
    public static let memoriesLedges = ["emptyMemories", "emptyLists"]
    /// Find's "nothing found" (Q4): he comes out from behind the page and shrugs on this spot.
    public static let findLedge = "find"
    /// Find's spot appeared; he goes there once it has reported a frame.
    var findWaiting = false

    /// The undo bar appeared; he is lifted with it once it has reported its frame (MV4).
    var panelWaiting = false

    /// A surface's view appeared (the app calls this after marking it mounted).
    public func surfaceAppeared(_ id: MotionSurfaceID) {
        if id == .ledge(Self.findLedge) { findWaiting = true }
        if id == .panel { panelWaiting = true }
    }

    /// A surface's view went (the app calls this after marking it gone).
    public func surfaceGone(_ id: MotionSurfaceID) {
        if id == .panel {
            panelWaiting = false
            panelChanged(shown: false)
        }
    }

    func liftOntoPanelIfWaiting() {
        guard panelWaiting, scene.frames[.panel] != nil else { return }
        panelWaiting = false
        panelChanged(shown: true)
    }

    func goToFindIfWaiting() {
        guard findWaiting else { return }
        guard isPlaced, scene.covers == 0, pendingTab == nil, scene.screen == .memories,
              scene.page.open, !scene.page.detail else {
            if !scene.mounted.contains(.ledge(Self.findLedge)) { findWaiting = false }
            return
        }
        guard mountedFrame(.ledge(Self.findLedge)) != nil else { return }
        findWaiting = false
        // Out from behind the page he was covered by: the page itself now shows his spot.
        engine.leftCoveredScreen()
        engine.updateDestination(MotionReason("nothing found"))
    }

    /// How long a tab tap waits for the new screen to report its surfaces before he goes to the
    /// best spot known (the rail, at worst). Well inside the 484 ms a tab hop has.
    public static let screenReportWait = 60.0

    /// Whether the current screen has reported a surface of its own (its content has laid out).
    func screenHasReported() -> Bool {
        switch scene.screen {
        case .home: return scene.mounted.contains(.stage)
        case .memories:
            if scene.page.open { return scene.mounted.contains(.detail) || !scene.page.detail }
            return Self.memoriesLedges.contains { scene.mounted.contains(.ledge($0)) } || scene.mounted.contains { $0.isRule }
        case .settings: return scene.mounted.contains(.ledge("settings"))
        case .talk: return scene.mounted.contains(.composer)
        }
    }

    /// Answers a pending tab tap once the new screen has a spot for him: decided one frame after
    /// the tap at the earliest, when the new tab's content has reported where its surfaces are.
    func resolvePendingTab() {
        guard let p = pendingTab, scene.covers == 0 else { return }
        guard screenHasReported() || engine.now - p.tapT >= Self.screenReportWait else { return }
        guard isPlaced else {
            if placeOnCurrentScreen() { pendingTab = nil }
            return
        }
        guard let pref = preferredSpot(for: engine), scene.frames[pref.surface] != nil else { return }
        pendingTab = nil
        engine.updateDestination(MotionReason("tab → \(p.screen.rawValue)", tab: p.screen.rawValue, tapT: p.tapT))
    }

    /// One step of the engine, `dtMs` long (the app calls it in steps of at most ~4 ms).
    public func step(_ dtMs: Double) {
        engine.beginStep(dtMs)
        engine.stepSurfaceDips(dtMs / 1000)
        engine.finishStep(dtMs)
        // The frames his position was worked out from: a surface the system moves between two
        // steps (a scroll, the keyboard) is drawn with him already, so his drawing is placed
        // against these, not against a frame that has moved since.
        lastStepFrames = scene.frames
    }

    /// The surface frames as they were at the engine's last step.
    public private(set) var lastStepFrames: [MotionSurfaceID: MotionRect] = [:]

    /// After a frame's steps: answer a pending tab tap, and move him off a surface that went away.
    public func settle() {
        settleScroll()
        carryIntoTalkIfReady()
        liftOntoPanelIfWaiting()
        if pendingTab != nil { resolvePendingTab() }
        goToFindIfWaiting()
        relocateIfSurfaceGone()
        returnToSpotIfWaitingForNothing()
    }

    /// He stands on the rail (or the strip) with nothing to wait for (no rapid switching, no
    /// scroll) while his screen's own spot is on screen: he goes to it. A screen that reports its
    /// spot late, or a spot that comes back, gets him.
    func returnToSpotIfWaitingForNothing() {
        guard isActive, scene.covers == 0, pendingTab == nil, engine.mode == .attached, !engine.calm, !engine.scrollWait,
              let a = engine.anchor, a.surface == .rail || a.surface == .panel else { return }
        guard let pref = preferredSpot(for: engine), !isWaitSpot(pref), mountedFrame(pref.surface) != nil else { return }
        engine.updateDestination(MotionReason("his spot on this screen is here"))
    }

    func relocateIfSurfaceGone() {
        guard isActive, scene.covers == 0, pendingTab == nil, engine.mode == .attached, !engine.hiddenBehind,
              let a = engine.anchor, !scene.mounted.contains(a.surface) else {
            if let a = engine.anchor, scene.mounted.contains(a.surface) { relocatedFrom = nil }
            return
        }
        // A page pushed over his screen covers him where he stands (brief: "Covered by a page").
        if scene.page.open, MotionScene.screen(of: a.surface) == scene.screen { return }
        // Settings' row scrolled out of its Form: he went with it and comes back with it.
        if a.surface == .ledge("settings"), scene.screen == .settings { return }
        if a.isSame(as: relocatedFrom) { return }
        relocatedFrom = a
        engine.updateDestination(MotionReason("his surface went away"))
    }

    // MARK: Where the app draws him

    public var placement: MotionPlacement {
        guard isActive, scene.covers == 0, !talkPending else { return .hidden }
        if engine.mode == .flight { return .overlay }
        guard let a = engine.anchor else { return .hidden }
        if scene.mounted.contains(a.surface) { return .slot(a.surface) }
        // Standing on a surface that is off screen: covered in place (a page, a scrolled-away row),
        // unless a hop off it is starting, which the overlay shows.
        if engine.mode == .attached, pendingTab == nil { return .hidden }
        return .overlay
    }

    // MARK: Geometry helpers

    func mountedFrame(_ id: MotionSurfaceID) -> MotionRect? {
        scene.mounted.contains(id) ? scene.frames[id] : nil
    }

    /// The rail under a screen's tab (Ask is opened from Home, so it waits under Home).
    public func railSpot(_ screen: MotionScreen) -> MotionSpot {
        // While the undo bar shows, it stands over the rail: he waits on it instead (brief:
        // "the rail under the selected tab; fallback the strip").
        if let strip = mountedFrame(.panel) {
            return MotionSpot(.panel, x: MotionLayout.barSpotX(bar: strip, action: scene.marks["undo"]))
        }
        let bar = scene.frames[.rail] ?? MotionRect(x: 0, y: 724, width: 390, height: 60)
        let tab = screen == .talk ? "home" : screen.rawValue
        let center = scene.marks["tab.\(tab)"]?.midX ?? bar.midX
        return MotionSpot(.rail, x: MotionLayout.railSpotX(tabCenter: center, bar: bar))
    }

    /// The Memories list's visible band: its scroll view, and never above the first card's top
    /// edge (above it are the heading, the filters and the sort menu, which he must not cover).
    var listBand: (top: Double, bottom: Double)? {
        guard let viewport = scene.marks["memories.list"] else { return nil }
        var top = viewport.minY
        if let first = mountedFrame(.rule(0)) { top = max(top, first.minY) }
        return (top, viewport.maxY)
    }

    // MARK: MotionWorld

    public func surface(_ id: MotionSurfaceID) -> any MotionSurface { HostSurface(id: id, host: self) }

    public var screenKey: String { scene.screen.rawValue }

    public func preferredSpot(for e: MotionEngine) -> MotionSpot? {
        switch scene.screen {
        case .home:
            if let f = scene.frames[.stage] { return MotionSpot(.stage, x: MotionLayout.stageSpotX(line: f)) }
            return railSpot(.home)
        case .memories:
            let page = scene.page
            if page.open {
                if page.detail {
                    if e.hiddenBehind, let a = e.anchor { return a }
                    if let f = mountedFrame(.detail) { return MotionSpot(.detail, x: MotionLayout.detailSpotX(card: f)) }
                }
                // Find with nothing found: its spot (Q4).
                let find = MotionSurfaceID.ledge(Self.findLedge)
                if let f = mountedFrame(find) { return MotionSpot(find, x: MotionLayout.ledgeSpotX(ledge: f)) }
                // Find, or a note page still sliding in: stay if he still stands on screen.
                if let a = e.anchor, scene.mounted.contains(a.surface) { return a }
                return railSpot(.memories)
            }
            // No notes (or no lists): his spot is the empty screen's ledge (Q4).
            for name in Self.memoriesLedges {
                let ledge = MotionSurfaceID.ledge(name)
                if let f = mountedFrame(ledge) { return MotionSpot(ledge, x: MotionLayout.ledgeSpotX(ledge: f)) }
            }
            if scene.ruleCount > 0 {
                return e.bestRuleSpot(prefer: e.memory["memories"]?.surface.ruleIndex, in: HostList(host: self))
            }
            return railSpot(.memories)
        case .settings:
            if scene.page.open, let a = e.anchor, scene.mounted.contains(a.surface) { return a }
            let ledge = MotionSurfaceID.ledge("settings")
            if let f = scene.frames[ledge] { return MotionSpot(ledge, x: MotionLayout.ledgeSpotX(ledge: f)) }
            return railSpot(.settings)
        case .talk:
            if let f = scene.frames[.composer] {
                return MotionSpot(.composer, x: MotionLayout.composerSpotX(composer: f, send: scene.marks["send"]))
            }
            return railSpot(.talk)
        }
    }

    public func waitSpot(for e: MotionEngine) -> MotionSpot {
        if scene.screen == .talk, let f = scene.frames[.composer] {
            return MotionSpot(.composer, x: MotionLayout.composerSpotX(composer: f, send: scene.marks["send"]))
        }
        return railSpot(scene.screen)
    }

    public func isWaitSpot(_ spot: MotionSpot?) -> Bool {
        guard let spot else { return false }
        return spot.surface == .rail || spot.surface == .panel || (scene.screen == .talk && spot.surface == .composer)
    }

    /// His eyes' resting place. The pack has no gaze art (plan section 3), so nothing draws it.
    public func focusPoint() -> (point: MotionPoint, label: String)? { nil }

    /// The Memories list while he can ride it (MV4): lily-pad hops, or the rail while it is fast.
    public func ridingList() -> (any MotionList)? { canRideList ? HostList(host: self, riding: true) : nil }

    public var isCovered: Bool { scene.covers > 0 }
    public var isOnHome: Bool { scene.screen == .home }
    public var isOnTalk: Bool { scene.screen == .talk }
    public var isOnMemories: Bool { scene.screen == .memories }
    public var carrier: MotionCarrier? { nil }
    public var isTaskOpen: Bool { false }
    public var isKeyboardUp: Bool { scene.keyboardUp }
    public var isVoiceLive: Bool { scene.voiceLive }
    public var lastInput: Double { scene.lastInput }
    public var lastTap: Double { scene.lastTap }
    public var hasWaitingStrip: Bool { false }
    public var hasMemoriesBadge: Bool { scene.memoriesBadge }
    public var isBannerShowing: Bool { false }
    public func overheadMovers(dtMs: Double) -> [MotionMover] { [] }

    public func gazePoint(_ cue: MotionGazeCue) -> MotionPoint {
        switch cue {
        case .tab(let t):
            if let m = scene.marks["tab.\(t)"] { return MotionPoint(x: m.midX, y: m.midY) }
        case .composerText, .sentBubble:
            if let c = scene.frames[.composer] { return MotionPoint(x: c.minX + 100, y: c.minY + 22) }
        case .sourceLabel:
            if let d = scene.frames[.detail] { return MotionPoint(x: d.minX + 40, y: d.maxY - 20) }
        case .draftStrip, .draftFirstLine, .banner:
            break
        }
        return MotionPoint(x: 195, y: 400)
    }

    public func startVoice() -> Bool { onStartVoice?() ?? false }
    public var voicePhaseIsStarting: Bool { false }
    public func cancelStartingVoice() {}
    public func endVoice(_ why: String) {}
    public func openTalkFromHome(tapT: Double) { onOpenTalk?(tapT) }
    public var finger: MotionFinger { scene.finger }
}

/// One of the app's surfaces as the engine sees it.
struct HostSurface: MotionSurface {
    let id: MotionSurfaceID
    unowned let host: MotionHost

    var frame: MotionRect? { host.scene.frames[id] }

    var layer: Double {
        switch id.kind {
        case .stage, .composer, .rule, .ledge: 1
        case .detail: 1.5
        case .panel: 2
        case .rail: 2.5
        }
    }

    var scale: Double { id == .stage ? host.scene.homeScale : 1 }

    func top() -> Double { frame?.minY ?? 0 }
    func dx() -> Double { 0 }

    func standRange() -> ClosedRange<Double> {
        guard let f = frame else { return 0...0 }
        switch id.kind {
        case .stage: return MotionLayout.stageStandRange(line: f, scale: scale)
        case .rule, .detail: return MotionLayout.cardStandRange(card: f)
        case .composer: return MotionLayout.composerStandRange(composer: f, send: host.scene.marks["send"])
        case .rail: return MotionLayout.railStandRange(bar: f)
        case .panel: return MotionLayout.barStandRange(bar: f, action: host.scene.marks["undo"])
        case .ledge: return f.midX...f.midX
        }
    }

    func segment() -> ClosedRange<Double> {
        guard let f = frame else { return 0...0 }
        return f.minX...f.maxX
    }

    func isVisible() -> Bool { host.scene.mounted.contains(id) }

    /// A card scrolls with the list (MV4): where its edge will be `dt` seconds from now at the
    /// list's speed. Everything else is still between reports.
    private var listVelocity: Double? {
        guard id.isRule, host.canRideList, host.scene.scroll.isMoving else { return nil }
        return host.ridingVelocity
    }

    func pointAhead(x: Double, dt: Double) -> MotionPoint? {
        guard let v = listVelocity else { return nil }
        return MotionPoint(x: x, y: top() - v * dt)
    }

    func predictedPoint(x: Double) -> MotionPoint? { nil }
    func isMoving() -> Bool { listVelocity != nil }
    func settleY() -> Double { top() }
}

/// The Memories list as the engine sees it: its cards' edges, and its scroll (MV4).
struct HostList: MotionList {
    unowned let host: MotionHost
    /// Riding (MV4): the safe band is the scroll view's own visible band, since the content above
    /// the first card scrolls away with it. Card 0 is never a spot (the picker and filters sit
    /// right above it, where his body would be), so while riding it reads as above the band.
    /// Choosing a spot (not riding) keeps the band below the first card's top instead.
    var riding = false

    var ruleCount: Int { host.scene.ruleCount }

    func ruleY(_ i: Int, ahead dt: Double) -> Double {
        if riding, i == 0 { return -1e6 }
        if let f = host.mountedFrame(.rule(i)) { return f.minY - velocity * dt }
        // A card that isn't built (LazyVStack) is above or below the ones that are.
        guard let first = (0..<ruleCount).first(where: { host.scene.mounted.contains(.rule($0)) }) else { return 1e6 }
        return i < first ? -1e6 : 1e6
    }

    var top: Double {
        if riding, let viewport = host.scene.marks["memories.list"] { return viewport.minY }
        return host.listBand?.top ?? 1e6
    }
    var bottom: Double { host.listBand?.bottom ?? -1e6 }
    var velocity: Double { host.ridingVelocity }
    /// iOS 18: still decelerating faster than lily-pad speed. iOS 17: any move (Q10).
    var isFlinging: Bool {
        let s = host.scene.scroll
        guard s.isMoving else { return false }
        return s.measured ? s.phase == .decelerating && abs(s.velocity) > MotionTiming.lilySlow : true
    }
    /// A programmatic scroll (iOS 18's `.animating`) towards the top, such as a status bar tap.
    var isScrollingToTop: Bool {
        let s = host.scene.scroll
        return s.measured && s.phase == .animating && s.velocity < -1
    }
    var slowSince: Double? { host.scene.scroll.slowSince }
    /// Which card a finger is on isn't reported, only that one is down (iOS 18).
    func isUnderFinger(_ i: Int) -> Bool { false }
    var isFingerDown: Bool { host.scene.scroll.isFingerDown }

    var ruleX: Double {
        for i in 0..<ruleCount {
            if let f = host.mountedFrame(.rule(i)) { return MotionLayout.cardSpotX(card: f) }
        }
        return 0
    }

    var waitSpot: MotionSpot { host.railSpot(.memories) }
}
