import Foundation
@testable import DoddyCore

// The reference prototype's mock phone (`design/motion-v2/reference/engine.js`, the `ui` half and
// the per-frame checks), ported line for line so `MotionEngine` can be driven through the owner's
// 25 studies and compared with the clips' telemetry. Test-only: none of this is the app's screen.
// Units: points on a 390 × 844 canvas; time in ms.

enum RefLayout {
    static let W = 390.0, H = 844.0
    static let rail = 724.0
    static let tabX: [String: Double] = ["home": 73, "talk": 195, "memories": 317]
    static let stageY = 470.0, stageX0 = 125.0, stageX1 = 265.0, stageX = 195.0
    static let stripTop = 652.0, panelBottom = 708.0, panelOpenTop = 380.0, panelHiddenTop = 716.0
    static let composerH = 44.0, composerBottomNoStrip = 704.0, composerBottomStrip = 640.0
    static let kbH = 300.0
    static let listTop = 208.0, listBottomBase = 724.0, listInset = 108.0
    static let ruleX = 330.0
    static let detailSourceY = 300.0, detailX = 330.0
    static let draftX = 250.0
    static let sendHitX0 = 332.0, sendHitMicX0 = 288.0, micHitX0 = 332.0
    static let reviewHitX0 = 298.0
    static let zoneW = 48.0, zoneH = 108.0
}

/// One scripted finger key (the studies' `finger` arrays).
struct RefFingerKey {
    enum Kind { case down, move, up }
    enum Ease { case linear, inOut, easeIn, easeOut }
    var t: Double
    var kind: Kind
    var x = 0.0
    var y = 0.0
    var ease: Ease = .linear
}

struct RefScript {
    var timeline: [(t: Double, fn: (ReferenceMotionWorld) -> Void)] = []
    var finger: [RefFingerKey] = []
}

struct RefScene {
    var tab = "home"
    var keyboard = false
    var draft = false
    var panel = "strip"
    var introduced = false
    var typed = ""
    var scroll = 0.0
    var detail: Int?
    var badge = false
    var doddy: MotionSpot?
    var idle = 0.0
    var welcome = false
    var welcomeKind: WelcomeKind?
    var hadWelcome = false
    var glances = 0
    var glanceAt: Double?
    var breathAt: Double?
    var sitting = false
    var noSit = false
    var noEdge = false
    var gaze: MotionPoint?
    var messages = 0
}

struct RefReply {
    var delay: Double
    var text = ""
    var draft = true
    var saved = false
    var fail = false
    var savedAfter: Double?
    var draftAfter: Double?
}

final class ReferenceMotionWorld: MotionWorld {
    let engine: MotionEngine
    var now: Double { engine.now }

    // MARK: UI state (the reference's `ui`)

    var tab = "home"
    var fade: [String: Double] = ["home": 1, "talk": 0, "memories": 0]
    var draftPending = false
    var panelMode: MotionCarrier.Mode = .hidden
    let panelTop = MotionSpring(RefLayout.panelHiddenTop, response: 0.42, damping: 0.88)
    var panelPrevTop = RefLayout.panelHiddenTop
    var panelDrag: (y0: Double, f0: Double)?
    var keyboard = false
    let kbTop = MotionSpring(RefLayout.H, response: 0.28, damping: 1.0)
    let composerBase = MotionSpring(RefLayout.composerBottomNoStrip, response: 0.42, damping: 0.88)
    var detailOpen = false
    let detailX = MotionSpring(RefLayout.W, response: 0.36, damping: 1.0)
    var typed = ""
    var typingTarget = ""
    var typingTimer = 0.0
    var typeMs = 42.0
    var lastInputT = -99_999.0
    var lastTapT = -99_999.0
    var messages = 0
    var awaiting: (sentAt: Double, replyAt: Double, r: RefReply, thinkingAt: Double)?
    var nextReply: RefReply?
    var items: [(h: Double, lines: Int, hs: MotionSpring?)] = []
    var layout: [(top: Double, h: Double, bottom: Double)] = []
    var contentH = 0.0
    var scroll = RefScroll()
    var mic = false
    var bannerShow = false
    let bannerY = MotionSpring(-120, response: 0.36, damping: 0.86)
    var toast = RefToast()
    var sheetOpen = false
    let sheetY = MotionSpring(800, response: 0.42, damping: 1.0)
    var voicePhase = "idle"
    var voiceT = 0.0
    var voiceLive = false
    var badge = false
    var introduced = false
    var introUntil = 0.0
    var replyDelay = 2000.0

    // MARK: Input

    var fingerState = RefFinger()
    var hit: RefHit?

    // MARK: Metrics (the reference's `metrics` minus the DOM-only clear-zone check)

    var tabTaps: [(t: Double, tab: String, from: String, done: Double?)] = []
    var violations: [(t: Double, kind: String, detail: String)] = []
    var maxContactGap = 0.0
    var maxComposerGap = 0.0
    var listenViolations = 0
    var scaleChanges: [(t: Double, mode: String, s: Double, ok: Bool)] = []
    var frames = 0
    var lastScale = 1.4
    var drawn: [MotionSurfaceID: Double] = [:]
    var scrollChecked = false

    // MARK: Script

    var script: (start: Double, tl: [(t: Double, fn: (ReferenceMotionWorld) -> Void)], fk: [RefFingerKey], fi: Int, last: RefFingerKey?)?

    static let itemLines = [1, 1, 1, 2, 1, 2, 1, 1, 1, 1, 1, 1]

    init(settings: MotionSettings) {
        engine = MotionEngine(settings: settings)
        engine.attach(to: self)
        items = Self.itemLines.map { (104 + 22 * Double($0), $0, nil) }
        relayout()
        lastScale = settings.homeScale
    }

    // MARK: Layout helpers

    func kbProg(_ kx: Double) -> Double { MotionMath.clamp((RefLayout.H - kx) / RefLayout.kbH, 0, 1) }
    func composerBottomAt(_ base: Double, _ kx: Double) -> Double {
        MotionMath.lerp(base, min(base, RefLayout.H - RefLayout.kbH - 8), kbProg(kx))
    }
    func composerTop() -> Double { composerBottomAt(composerBase.x, kbTop.x) - RefLayout.composerH }
    func composerMaxX() -> Double { (mic ? RefLayout.sendHitMicX0 : RefLayout.sendHitX0) - 48 }
    func listBottom() -> Double { draftPending ? RefLayout.stripTop - RefLayout.listInset : RefLayout.listBottomBase }
    func listVH() -> Double { listBottom() - RefLayout.listTop }
    func relayout() {
        var y = 0.0
        layout = []
        for it in items {
            let h = it.hs?.x ?? it.h
            layout.append((y, h, y + h))
            y += h
        }
        contentH = y
    }
    func maxScroll() -> Double { max(0, contentH + RefLayout.listInset - (RefLayout.listBottomBase - RefLayout.listTop)) }
    func ruleY(_ i: Int) -> Double { RefLayout.listTop + (i < layout.count ? layout[i].bottom : 0) - scroll.y }
    func scrollAhead(_ dt: Double) -> Double {
        if dt <= 0 { return scroll.y }
        switch scroll.mode {
        case .momentum:
            let k = -log(0.998) * 1000
            return scroll.y + (scroll.v / k) * (1 - exp(-k * dt))
        case .drag: return scroll.y + scroll.vel * dt
        case .bounce, .toTop: return scroll.spring.ahead(dt)
        case .idle: return scroll.y
        }
    }
    func panelOpenness() -> Double {
        draftPending ? MotionMath.clamp((RefLayout.stripTop - panelTop.x) / (RefLayout.stripTop - RefLayout.panelOpenTop), 0, 1) : 0
    }

    // MARK: MotionWorld

    func surface(_ id: MotionSurfaceID) -> any MotionSurface { RefSurface(id: id, w: self) }

    var screenKey: String { draftPending && panelMode == .open ? "review" : tab }

    func preferredSpot(for e: MotionEngine) -> MotionSpot? {
        if draftPending, panelMode == .open { return MotionSpot(.panel, x: RefLayout.draftX) }
        if tab == "home" { return MotionSpot(.stage, x: RefLayout.stageX) }
        if tab == "talk" {
            let m = e.memory["talk"]
            return MotionSpot(.composer, x: MotionMath.clamp(m?.surface == .composer ? m!.x : RefLayout.draftX, 44, composerMaxX()))
        }
        if tab == "memories" {
            if detailOpen { return e.hiddenBehind && e.anchor != nil ? e.anchor : MotionSpot(.detail, x: RefLayout.detailX) }
            if draftPending { return MotionSpot(.panel, x: RefLayout.draftX) }
            let m = e.memory["memories"]
            return e.bestRuleSpot(prefer: m?.surface.ruleIndex, in: RefList(w: self))
        }
        return nil
    }

    func waitSpot(for e: MotionEngine) -> MotionSpot {
        if draftPending, panelMode != .open {
            return MotionSpot(.panel, x: MotionMath.clamp(RefLayout.tabX[tab]!, 40, RefLayout.reviewHitX0 - 48))
        }
        // On Talk the rail spot would stand him in front of the composer field, so he waits on the composer edge.
        if tab == "talk" { return MotionSpot(.composer, x: MotionMath.clamp(RefLayout.draftX, 44, composerMaxX())) }
        return MotionSpot(.rail, x: MotionMath.clamp(RefLayout.tabX[tab]!, 40, 350))
    }

    func isWaitSpot(_ a: MotionSpot?) -> Bool {
        guard let a else { return false }
        return a.surface == .rail || a.surface == .panel || (tab == "talk" && a.surface == .composer)
    }

    func focusPoint() -> (point: MotionPoint, label: String)? {
        switch screenKey {
        case "talk": return (MotionPoint(x: 120, y: composerTop() + 22), "composer")
        case "review": return (MotionPoint(x: 60, y: RefLayout.panelOpenTop + 112), "draft")
        case "memories":
            if detailOpen { return (MotionPoint(x: 60, y: 200), "note") }
            return (MotionPoint(x: 80, y: ruleY(0) - 100), "top item")
        default: return nil
        }
    }

    func ridingList() -> (any MotionList)? {
        if tab != "memories" || detailOpen || draftPending || sheetOpen { return nil }
        return RefList(w: self)
    }

    var isCovered: Bool { sheetOpen }
    var isOnHome: Bool { tab == "home" }
    var isOnTalk: Bool { tab == "talk" }
    var isOnMemories: Bool { tab == "memories" }
    var carrier: MotionCarrier? {
        guard draftPending else { return nil }
        return MotionCarrier(top: panelTop.x, target: panelTop.target, velocity: panelTop.v, previousTop: panelPrevTop, isDragged: panelDrag != nil, mode: panelMode)
    }
    var isTaskOpen: Bool { panelMode == .open }
    var isKeyboardUp: Bool { keyboard }
    var isVoiceLive: Bool { voiceLive }
    var lastInput: Double { lastInputT }
    var lastTap: Double { lastTapT }
    var hasWaitingStrip: Bool { draftPending && panelMode != .open }
    var hasMemoriesBadge: Bool { badge }
    var isBannerShowing: Bool { bannerShow }

    func overheadMovers(dtMs: Double) -> [MotionMover] {
        var movers: [MotionMover] = []
        if toast.active {
            movers.append(MotionMover(x0: toast.x.x, x1: toast.x.x + toast.w, y0: toast.lane, y1: toast.lane + 30, speed: abs((toast.x.x - toast.prevX) / (dtMs / 1000))))
        }
        if bannerShow || bannerY.x > -110 {
            movers.append(MotionMover(x0: 12, x1: 378, y0: 58 + bannerY.x, y1: 102 + bannerY.x, speed: abs(bannerY.v)))
        }
        return movers
    }

    func gazePoint(_ cue: MotionGazeCue) -> MotionPoint {
        switch cue {
        case .tab(let t): return MotionPoint(x: RefLayout.tabX[t] ?? 195, y: 757)
        case .draftStrip: return MotionPoint(x: 120, y: RefLayout.stripTop + 28)
        case .draftFirstLine: return MotionPoint(x: 40, y: RefLayout.panelOpenTop + 112)
        case .composerText: return MotionPoint(x: 120, y: composerTop() + 22)
        case .sentBubble: return MotionPoint(x: 320, y: composerTop() - 160)
        case .sourceLabel: return MotionPoint(x: 40 + detailX.x, y: RefLayout.detailSourceY + 18)
        case .banner: return MotionPoint(x: 195, y: 80)
        }
    }

    func startVoice() -> Bool {
        if !engine.settings.voiceFromHome { return false }
        voicePhase = "starting"
        voiceT = now
        engine.voiceStarting()
        engine.note("press and hold: voice is starting (no listening pose until capture is live)")
        return true
    }

    var voicePhaseIsStarting: Bool { voicePhase == "starting" }
    func cancelStartingVoice() { voicePhase = "idle" }

    func endVoice(_ why: String) {
        let wasLive = voiceLive || voicePhase == "starting"
        voicePhase = "idle"
        voiceLive = false
        engine.voiceEnded()
        if !wasLive { return }
        engine.note("capture ends (\(why))")
        if why == "tab change" { return }
        // Follow the conversation to Talk.
        messages += 1
        awaiting = (now, now + 1400, RefReply(delay: 1400, text: "On it.", draft: false), now + 600)
        setTab("talk")
    }

    func openTalkFromHome(tapT: Double) {
        lastTapT = tapT
        setTab("talk", tapT: tapT)
    }

    var finger: MotionFinger {
        MotionFinger(isDown: fingerState.down, x: fingerState.x, y: fingerState.y, vx: fingerState.vx, vy: fingerState.vy, moved: fingerState.moved)
    }

    // MARK: UI actions

    func setTab(_ t: String, tapT: Double? = nil) {
        if sheetOpen { return }
        if t == tab, panelMode != .open {
            engine.note("\(t) tapped again")
            return
        }
        let was = tab
        if keyboard { setKeyboard(false) }
        if panelMode == .open { setPanel(.strip, silent: true) }
        if voiceLive || voicePhase == "starting" { endVoice("tab change") }
        tab = t
        tabTaps.append((now, t, was, nil))
        if t == "memories" { badge = false }
        engine.note("tap \(t): tab content commits this frame")
        if engine.hiddenBehind, t != "memories" { engine.leftCoveredScreen() }
        engine.updateDestination(MotionReason("\(was) → \(t)", tab: t, tapT: tapT ?? now))
    }

    func setPanel(_ mode: MotionCarrier.Mode, silent: Bool = false, v: Double? = nil, noIntro: Bool = false) {
        guard draftPending else { return }
        panelMode = mode
        let target = mode == .open ? RefLayout.panelOpenTop : mode == .hidden ? RefLayout.panelHiddenTop : RefLayout.stripTop
        if engine.settings.reduceMotion {
            panelTop.snap(target)
        } else {
            panelTop.set(mode == .open ? 0.42 : 0.34, mode == .open ? 0.88 : 0.95)
            panelTop.target = target
            if let v { panelTop.v = v }
        }
        if mode == .open {
            lastInputT = now
            if keyboard { setKeyboard(false) }
        }
        if !silent {
            engine.note(mode == .open ? "review opens (panel rises)" : mode == .hidden ? "draft done: the panel clears away" : "review collapses to the strip")
            engine.updateDestination(MotionReason(mode == .open ? "review opened" : "review collapsed"))
        }
        if mode == .open, !noIntro {
            introUntil = now + 2500
            engine.after(engine.settings.reduceMotion ? 200 : 520) { [self] in tryIntro() }
        }
    }

    func setKeyboard(_ on: Bool) {
        if keyboard == on { return }
        keyboard = on
        kbTop.target = on ? RefLayout.H - RefLayout.kbH : RefLayout.H
        if on {
            lastInputT = now
            engine.note("message field focused: keyboard rises; he rides the composer")
        }
    }

    func typeText(_ text: String, _ ms: Double = 42) {
        typingTarget = text
        typingTimer = 0
        typeMs = ms
    }

    func onTypeChar() {
        lastInputT = now
        engine.userTyped()
    }

    func send(text: String? = nil, reply: RefReply? = nil) {
        messages += 1
        typed = ""
        typingTarget = ""
        var r = nextReply ?? RefReply(delay: replyDelay, text: "Here’s a message for Mateusz.", draft: true)
        if let reply { r = reply }
        nextReply = nil
        awaiting = (now, now + r.delay, r, now + 600)
        engine.userSent()
        engine.note("message sent to Doddy")
    }

    func deliverReply() {
        guard let a = awaiting else { return }
        awaiting = nil
        if a.r.fail {
            messages += 1
            engine.endThinking(failed: true)
            engine.setMood("concerned", 2400)
            engine.after(30) { [self] in engine.notice("error", MotionPoint(x: 60, y: 400), 600, mood: "concerned", moodMs: 2400) }
            engine.note("reply failed: concerned brow, eyes to the error")
            return
        }
        messages += 1
        engine.endThinking(failed: false)
        engine.after(20) { [self] in
            engine.clearReaction()
            engine.notice("reply lands", MotionPoint(x: 60, y: 400), 300)
        }
        engine.note("Doddy’s reply lands")
        if a.r.saved { engine.after(a.r.savedAfter ?? 420) { [self] in memorySaved() } }
        if a.r.draft { engine.after(a.r.draftAfter ?? 700) { [self] in createDraft() } }
    }

    func memorySaved() {
        let hs = MotionSpring(0, response: 0.34, damping: 1.0)
        hs.target = 126
        items.insert((126, 1, hs), at: 0)
        engine.rulesShifted(insertedAt: 0, by: 1)
        relayout()
        if tab != "memories" { badge = true }
        engine.notice("saved to Memories", MotionPoint(x: RefLayout.tabX["memories"]!, y: 757), 400)
        engine.note("saved to Memories (Memories tab gets a dot)")
    }

    func createDraft() {
        draftPending = true
        introduced = false
        panelTop.snap(RefLayout.panelHiddenTop)
        composerBase.target = RefLayout.composerBottomStrip
        engine.note("draft is reviewable")
        if engine.mode == .attached, engine.anchor?.surface != .panel, tab != "talk" {
            engine.notice("draft appears", MotionPoint(x: 120, y: RefLayout.stripTop + 20), 300)
        }
        setPanel(.open)
    }

    func clearDraft() {
        guard draftPending else { return }
        setPanel(.hidden)
        composerBase.target = RefLayout.composerBottomNoStrip
        engine.after(600) { [self] in
            if panelMode == .hidden {
                draftPending = false
                if engine.anchor?.surface == .panel, engine.mode == .attached { engine.updateDestination(MotionReason("panel gone")) }
            }
        }
    }

    func reviewAndSend() {
        if sheetOpen { return }
        sheetOpen = true
        sheetY.target = 0
        sheetY.set(0.42, 1.0)
        engine.look(at: MotionPoint(x: 195, y: 560), "Review & send")
        engine.note("Review & send: Apple’s composer opens and covers the app (no “sent” cue yet)")
    }

    func composerResult(_ result: String) {
        guard sheetOpen else { return }
        sheetOpen = false
        sheetY.target = 800
        sheetY.set(0.36, 1.0)
        engine.note("Apple’s composer returns: \(result)")
        engine.after(320) { [self] in
            if result == "sent" {
                engine.setMood("pleased", 900)
                engine.clearReaction()
                engine.lookAtUser()
                engine.note("sent: pleased mouth only")
                engine.after(520) { [self] in
                    clearDraft()
                    messages += 1
                }
            } else if result == "cancelled" {
                engine.look(at: MotionPoint(x: 60, y: RefLayout.panelOpenTop + 112), "draft")
                engine.note("cancelled: eyes back to the draft")
            } else {
                engine.setMood("concerned", 2200)
                engine.look(at: MotionPoint(x: 60, y: RefLayout.panelOpenTop + 112), "draft")
                engine.note("failed: concerned brow, eyes back to the draft")
            }
        }
    }

    func openDetail(_ i: Int) {
        if detailOpen || i >= items.count { return }
        detailOpen = true
        detailX.set(0.36, 1.0)
        detailX.target = 0
        engine.pagePushed()
    }

    func closeDetail() {
        guard detailOpen else { return }
        detailOpen = false
        detailX.target = RefLayout.W
        engine.pagePopped()
    }

    func setBanner(_ on: Bool) {
        if bannerShow == on { return }
        bannerShow = on
        bannerY.target = on ? 0 : -120
        engine.bannerChanged(showing: on, at: MotionPoint(x: 195, y: 80))
    }

    /// A toast that slides across just above his head (within 12 pt), then rests where told.
    func passToast(fromRight: Bool = true, restX: Double? = nil, response: Double = 0.9, hold: Double = 1400, w: Double = 150) {
        let headTop = engine.pos.y - 96 * engine.scale
        toast.w = w
        toast.lane = headTop - 8 - 30
        toast.restX = restX ?? (fromRight ? 24 : RefLayout.W - 24 - w)
        toast.exitX = fromRight ? -w - 30 : RefLayout.W + 30
        toast.active = true
        toast.phase = "in"
        toast.t = 0
        toast.x.snap(fromRight ? RefLayout.W + 20 : -w - 20)
        toast.x.set(response, 1.0)
        toast.x.target = toast.restX
        toast.prevX = toast.x.x
        toast.hold = hold
        engine.note("a toast slides \(fromRight ? "in from the right" : "in from the left") just above his head")
    }

    func setMic(_ on: Bool) {
        mic = on
        engine.note(on ? "a microphone button appears in the composer" : "the microphone button goes away")
    }

    func tryIntro() {
        if introduced || panelMode != .open || now > introUntil { return }
        if engine.canIntroduce {
            introduceDraft()
            return
        }
        engine.after(30) { [self] in tryIntro() }
    }

    func introduceDraft() {
        if introduced || panelMode != .open { return }
        if engine.introduceDraft() { introduced = true }
    }

    func editDraft() {
        engine.userEditedDraft(at: MotionPoint(x: 120, y: RefLayout.panelOpenTop + 112))
    }

    // MARK: Hit testing and the finger

    func inRect(_ x: Double, _ y: Double, _ r: [Double]) -> Bool { x >= r[0] && x <= r[2] && y >= r[1] && y <= r[3] }

    func talkHitRect() -> [Double] {
        let s = engine.settings.homeScale, zw = RefLayout.zoneW * s, zh = RefLayout.zoneH * s
        return [RefLayout.stageX - zw / 2 - 12, RefLayout.stageY - zh - 12, RefLayout.stageX + zw / 2 + 12, RefLayout.stageY + 12]
    }

    func hitTest(_ x: Double, _ y: Double) -> RefHit {
        if sheetOpen {
            if inRect(x, y, [6, 58, 100, 100]) { return RefHit(kind: "sheetCancel", tap: { [self] _ in composerResult("cancelled") }) }
            let fy = 844.0 - 360
            if inRect(x, y, [330, fy - 44, 390, fy + 8]) { return RefHit(kind: "sheetSend", tap: { [self] _ in composerResult("sent") }) }
            return RefHit(kind: "none")
        }
        if keyboard, y >= kbTop.x { return RefHit(kind: "key") }
        if y >= RefLayout.rail, y < 800 {
            let t = x < 130 ? "home" : x < 260 ? "talk" : "memories"
            return RefHit(kind: "tab", tap: { [self] tt in setTab(t, tapT: tt) })
        }
        if draftPending {
            let top = panelTop.x
            if panelMode == .open, y >= top, y <= RefLayout.panelBottom {
                let r = y - top
                if r < 30 { return RefHit(kind: "grab", drag: true, tap: { [self] _ in setPanel(.strip) }) }
                if r >= 168, r <= 218 { return RefHit(kind: "reviewSend", tap: { [self] _ in reviewAndSend() }) }
                if r >= 254, r <= 294, abs(x - 195) < 80 { return RefHit(kind: "later", tap: { [self] _ in setPanel(.strip) }) }
                if r >= 88, r <= 160 { return RefHit(kind: "draftText", tap: { [self] _ in editDraft() }, down: { [self] in editDraft() }) }
                return RefHit(kind: "panel")
            }
            if panelMode == .strip, y >= top, y <= top + 56, x >= 16, x <= 374 {
                return RefHit(kind: "strip", drag: true, tap: { [self] _ in setPanel(.open) })
            }
        }
        if tab == "memories", detailOpen, detailX.x < 40 {
            if inRect(x, y, [12, 88, 130, 124]) { return RefHit(kind: "back", tap: { [self] _ in closeDetail() }) }
            if inRect(x, y, [16, RefLayout.detailSourceY, 374, RefLayout.detailSourceY + 84]) { return RefHit(kind: "source", tap: { [self] _ in engine.playful(.trace) }) }
            if y > 84, y < 724 { return RefHit(kind: "detail") }
        }
        if tab == "home" {
            if voiceLive, inRect(x, y, [130, 588, 260, 632]) { return RefHit(kind: "stop", tap: { [self] _ in endVoice("stop tapped") }) }
            if inRect(x, y, talkHitRect()) { return RefHit(kind: "doddy") }
            return RefHit(kind: "eyes")
        }
        if tab == "talk" {
            let ct = composerTop()
            if y >= ct, y <= ct + 44, x >= 16, x <= 374 {
                if mic, x >= RefLayout.micHitX0 { return RefHit(kind: "mic", tap: { _ in }) }
                if x >= (mic ? RefLayout.sendHitMicX0 : RefLayout.sendHitX0) { return RefHit(kind: "send", tap: { [self] _ in send() }) }
                return RefHit(kind: "field", tap: { [self] _ in setKeyboard(true) })
            }
            return RefHit(kind: "none")
        }
        if tab == "memories" {
            if y >= RefLayout.listTop, y <= listBottom() { return RefHit(kind: "list") }
            return RefHit(kind: "none")
        }
        return RefHit(kind: "none")
    }

    func fingerVelocity() -> MotionPoint {
        let s = fingerState.samples
        if s.count < 2 { return .zero }
        let last = s[s.count - 1]
        var first = s[0]
        var i = s.count - 1
        while i >= 0 {
            if last.t - s[i].t >= 50 {
                first = s[i]
                break
            }
            first = s[i]
            i -= 1
        }
        let dt = (last.t - first.t) / 1000
        if dt <= 0 { return .zero }
        return MotionPoint(x: (last.x - first.x) / dt, y: (last.y - first.y) / dt)
    }

    func fingerDown(_ x: Double, _ y: Double) {
        fingerState.down = true
        fingerState.x = x
        fingerState.y = y
        fingerState.x0 = x
        fingerState.y0 = y
        fingerState.t0 = now
        fingerState.moved = false
        fingerState.samples = [(now, x, y)]
        lastInputT = now
        var t = hitTest(x, y)
        hit = t
        t.down?()
        if tab == "home", t.kind != "doddy", t.kind != "stop", !sheetOpen { engine.fingerDownElsewhereOnHome() }
        if t.kind == "doddy" { engine.homeTouchDown(x: x, y: y) }
        if t.kind == "list" { listDown() }
        if t.kind == "strip" || t.kind == "grab" {
            t.panel0 = panelTop.x
            hit = t
        }
    }

    func fingerMove(_ x: Double, _ y: Double) {
        guard fingerState.down else { return }
        fingerState.x = x
        fingerState.y = y
        fingerState.samples.append((now, x, y))
        if fingerState.samples.count > 30 { fingerState.samples.removeFirst() }
        let v = fingerVelocity()
        fingerState.vx = v.x
        fingerState.vy = v.y
        if !fingerState.moved, MotionMath.hyp(x - fingerState.x0, y - fingerState.y0) > MotionTiming.tapSlop { fingerState.moved = true }
        guard let t = hit else { return }
        if t.kind == "doddy" { engine.homeTouchMove(x: x, y: y) }
        if t.kind == "list" { listMove(y) }
        if t.kind == "strip" || t.kind == "grab", fingerState.moved { panelDragMove(y) }
    }

    func fingerUp() {
        guard fingerState.down else { return }
        let v = fingerVelocity()
        fingerState.vx = v.x
        fingerState.vy = v.y
        fingerState.down = false
        let t = hit
        hit = nil
        lastInputT = now
        engine.fingerLifted()
        guard let t else { return }
        if t.kind == "doddy" { return engine.homeTouchUp() }
        if t.kind == "list" { return listUp() }
        if t.kind == "strip" || t.kind == "grab", panelDrag != nil { return panelDragEnd() }
        if !fingerState.moved, let tap = t.tap {
            lastTapT = now
            tap(now)
        }
    }

    // MARK: Memories scrolling

    func rubber(_ d: Double, _ dim: Double) -> Double { (1 - 1 / ((d * 0.55) / dim + 1)) * dim }

    func listDown() {
        scroll.dragging = false
        if scroll.mode == .momentum || scroll.mode == .bounce || scroll.mode == .toTop {
            scroll.mode = .idle
            scroll.v = 0
        }
        scroll.d0 = scroll.y
        scroll.f0 = fingerState.y
    }

    func listMove(_ y: Double) {
        if !fingerState.moved { return }
        // The pan starts where it is recognised: content never jumps by the touch slop.
        if !scroll.dragging {
            scroll.dragging = true
            scroll.d0 = scroll.y
            scroll.f0 = y
        }
        scroll.mode = .drag
        let raw = scroll.d0 - (y - scroll.f0), mx = maxScroll(), dim = RefLayout.listBottomBase - RefLayout.listTop
        scroll.y = raw < 0 ? -rubber(-raw, dim) : raw > mx ? mx + rubber(raw - mx, dim) : raw
    }

    func listUp() {
        scroll.dragging = false
        if !fingerState.moved {
            let yC = fingerState.y - RefLayout.listTop + scroll.y
            for i in 0..<layout.count {
                let lt = layout[i].top + 66 + 22 * Double(items[i].lines)
                if yC >= lt, yC <= lt + 30, fingerState.x >= 20, fingerState.x <= 180 {
                    lastTapT = now
                    openDetail(i)
                    return
                }
            }
            return
        }
        let v = -fingerState.vy, mx = maxScroll()
        if scroll.y < 0 || scroll.y > mx {
            scroll.mode = .bounce
            scroll.spring.x = scroll.y
            scroll.spring.v = v
            scroll.spring.target = scroll.y < 0 ? 0 : mx
            scroll.spring.set(0.4, 1.0)
        } else if abs(v) > 30 {
            scroll.mode = .momentum
            scroll.v = v
        } else {
            scroll.mode = .idle
            scroll.v = 0
        }
        engine.note("scroll released at \(MotionMath.format(abs(v))) pt/s")
    }

    func stepScroll(_ dt: Double) {
        let mx = maxScroll()
        scroll.prevY = scroll.lastY ?? scroll.y
        if scroll.mode == .momentum {
            scroll.v *= pow(0.998, dt * 1000)
            scroll.y += scroll.v * dt
            if scroll.y < 0 || scroll.y > mx {
                scroll.mode = .bounce
                scroll.spring.x = scroll.y
                scroll.spring.v = scroll.v
                scroll.spring.target = scroll.y < 0 ? 0 : mx
                scroll.spring.set(0.4, 1.0)
            } else if abs(scroll.v) < 8 {
                scroll.mode = .idle
                scroll.v = 0
            }
        } else if scroll.mode == .bounce || scroll.mode == .toTop {
            scroll.spring.step(dt)
            scroll.y = scroll.spring.x
            scroll.v = scroll.spring.v
            if abs(scroll.spring.x - scroll.spring.target) < 0.05, abs(scroll.spring.v) < 2 {
                scroll.y = scroll.spring.target
                scroll.v = 0
                scroll.mode = .idle
            }
        }
        scroll.vel = dt > 0 ? (scroll.y - scroll.prevY) / dt : 0
        scroll.lastY = scroll.y
        if abs(scroll.vel) < MotionTiming.lilySettleSpeed {
            if scroll.slowSince == 0 { scroll.slowSince = now }
        } else {
            scroll.slowSince = 0
        }
        if scroll.mode == .idle, scroll.wasMoving {
            scroll.wasMoving = false
            scroll.endedAt = now
        }
        if scroll.mode != .idle { scroll.wasMoving = true }
    }

    // MARK: The panel dragged by the finger

    func panelDragMove(_ y: Double) {
        if panelDrag == nil {
            panelDrag = (panelTop.x, y)
            engine.clearReaction()
            engine.note("panel dragged: eyes on the grabber for the whole drag")
        }
        let raw = panelDrag!.y0 + (y - panelDrag!.f0)
        let top = raw < RefLayout.panelOpenTop ? RefLayout.panelOpenTop - rubber(RefLayout.panelOpenTop - raw, 300) : min(raw, RefLayout.panelHiddenTop)
        panelTop.v = fingerState.vy
        panelTop.x = top
    }

    func panelDragEnd() {
        let vy = fingerState.vy
        panelDrag = nil
        let open = vy < -700 || (panelTop.x < (RefLayout.stripTop + RefLayout.panelOpenTop) / 2 && vy < 700)
        if open {
            setPanel(.open, v: MotionMath.clamp(vy, -4000, 4000))
            engine.note("flicked open at \(MotionMath.format(abs(vy))) pt/s")
        } else {
            setPanel(.strip, v: MotionMath.clamp(vy, -4000, 4000))
        }
    }

    // MARK: Script runner and step

    func runScript(_ s: RefScript) {
        // JavaScript's sort is stable; keep equal times in their written order.
        let tl = s.timeline.enumerated().sorted { ($0.element.t, $0.offset) < ($1.element.t, $1.offset) }.map(\.element)
        let fk = s.finger.enumerated().sorted { ($0.element.t, $0.offset) < ($1.element.t, $1.offset) }.map(\.element)
        script = (now, tl, fk, 0, nil)
    }

    func scriptStep() {
        guard var sc = script else { return }
        let t = now - sc.start
        while let first = sc.tl.first, first.t <= t {
            sc.tl.removeFirst()
            script = sc
            first.fn(self)
            sc = script!
        }
        while sc.fi < sc.fk.count, sc.fk[sc.fi].t <= t {
            let k = sc.fk[sc.fi]
            sc.fi += 1
            script = sc
            switch k.kind {
            case .down: fingerDown(k.x, k.y)
            case .move: fingerMove(k.x, k.y)
            case .up: fingerUp()
            }
            sc = script!
            sc.last = k
        }
        script = sc
        if sc.fi < sc.fk.count, sc.fk[sc.fi].kind == .move, fingerState.down, let a = sc.last {
            let nx = sc.fk[sc.fi]
            let u = MotionMath.clamp((t - a.t) / max(1, nx.t - a.t), 0, 1)
            let e: Double
            switch nx.ease {
            case .linear: e = u
            case .easeOut: e = 1 - (1 - u) * (1 - u)
            case .easeIn: e = u * u
            case .inOut: e = MotionMath.smoothstep(0, 1, u)
            }
            fingerMove(MotionMath.lerp(a.x, nx.x, e), MotionMath.lerp(a.y, nx.y, e))
        }
    }

    func step(_ dtMs: Double) {
        let dt = dtMs / 1000
        engine.beginStep(dtMs)
        scriptStep()
        engine.checkHold()
        panelPrevTop = panelTop.x
        if panelDrag == nil { panelTop.step(dt) }
        kbTop.step(dt)
        composerBase.step(dt)
        detailX.step(dt)
        sheetY.step(dt)
        bannerY.step(dt)
        if !keyboard, kbTop.x > RefLayout.H - 4, kbTop.x != RefLayout.H { kbTop.snap(RefLayout.H) }
        var lay = false
        for i in items.indices {
            if let hs = items[i].hs {
                hs.step(dt)
                lay = true
                if hs.isResting { items[i].hs = nil }
            }
        }
        if lay { relayout() }
        stepScroll(dt)
        engine.stepSurfaceDips(dt)
        for k in Array(fade.keys) {
            let tgt = k == tab ? 1.0 : 0, d = dtMs / MotionTiming.uiFade
            fade[k] = tgt > fade[k]! ? min(tgt, fade[k]! + d) : max(tgt, fade[k]! - d)
        }
        for i in tabTaps.indices where tabTaps[i].done == nil && fade[tabTaps[i].tab]! >= 1 {
            tabTaps[i].done = now - tabTaps[i].t
        }
        // Typing.
        if !typingTarget.isEmpty, typed.count < typingTarget.count {
            typingTimer += dtMs
            while typingTimer > typeMs, typed.count < typingTarget.count {
                typingTimer -= typeMs
                typed = String(typingTarget.prefix(typed.count + 1))
                onTypeChar()
            }
            if typed.count >= typingTarget.count { typingTarget = "" }
        }
        engine.rearmTyping()
        // Reply timing and thinking.
        if let aw = awaiting {
            engine.waitingForReply(sentAt: aw.sentAt, thinkingAt: aw.thinkingAt, replyAt: aw.replyAt)
            if now >= aw.replyAt { deliverReply() }
        }
        // Voice capture goes live 150 ms after it starts.
        if voicePhase == "starting", now - voiceT >= 150 {
            voicePhase = "live"
            voiceLive = true
            engine.note("capture is live: microphone indicator on, listening pose")
        }
        // Toast.
        if toast.active {
            toast.prevX = toast.x.x
            toast.x.step(dt)
            toast.t += dtMs
            if toast.phase == "in", abs(toast.x.x - toast.restX) < 0.5, toast.t > 300 {
                toast.phase = "rest"
                toast.restT = now
            }
            if toast.phase == "rest", now - toast.restT > toast.hold {
                toast.phase = "out"
                toast.x.set(0.5, 1.0)
                toast.x.target = toast.exitX
            }
            if toast.phase == "out", abs(toast.x.x - toast.exitX) < 4 { toast.active = false }
        }
        engine.finishStep(dtMs)
    }

    /// One 60 Hz frame: four substeps, then the drawing's positions and the per-frame checks.
    func stepFrame() {
        let h = (1000.0 / 60.0) / 4
        for _ in 0..<4 { step(h) }
        render()
        frameCheck()
    }

    func render() {
        drawn[.stage] = RefLayout.stageY + engine.surfaceDip(.stage)
        if draftPending { drawn[.panel] = panelTop.x + engine.surfaceDip(.panel) }
        drawn[.composer] = composerTop() + engine.surfaceDip(.composer)
        for i in layout.indices {
            drawn[.rule(i)] = RefLayout.listTop + layout[i].bottom - scroll.y + engine.surfaceDip(.rule(i))
        }
        drawn[.detail] = RefLayout.detailSourceY + engine.surfaceDip(.detail)
        drawn[.rail] = RefLayout.rail + engine.surfaceDip(.rail)
    }

    func violation(_ kind: String, _ detail: String) { violations.append((now.rounded(), kind, detail)) }

    func frameCheck() {
        frames += 1
        let e = engine
        if e.mode == .attached || e.mode == .anticipate || e.mode == .shuffle, let a = e.anchor, e.opacity > 0.01, !e.hiddenBehind {
            if let y = drawn[a.surface] {
                let gap = abs(e.pos.y - y)
                if a.surface == .composer {
                    maxComposerGap = max(maxComposerGap, gap)
                    if gap > 1 { violation("contact", "composer gap \(gap)") }
                } else {
                    maxContactGap = max(maxContactGap, gap)
                    if gap > 2 { violation("contact", "\(a.surface) gap \(gap)") }
                }
            }
        }
        let sc = e.scale
        if abs(sc - lastScale) > 1e-6 {
            let ok = e.mode == .flight || e.opacity < 0.01
            scaleChanges.append((now.rounded(), e.mode.rawValue, (sc * 1000).rounded() / 1000, ok))
            if !ok { violation("scale", "changed to \(sc) while \(e.mode)") }
        }
        lastScale = sc
        if e.mode == .attached || e.mode == .shuffle, let a = e.anchor, e.opacity > 0.01 {
            let want = surface(a.surface).scale
            if abs(sc - want) > 1e-3 { violation("scale", "\(sc)× on \(a.surface)") }
        }
        if e.looksLikeListening, !voiceLive, !e.isGesturing {
            listenViolations += 1
            violation("listening", "listening pose without the microphone indicator")
        }
        if e.settings.reduceMotion {
            if e.mode == .flight || e.mode == .shuffle { violation("reduce motion", "\(e.mode) in view") }
            if abs(e.squashAmount) > 0.01 || abs(e.slideOffset) > 0.01 { violation("reduce motion", "squash or slide") }
        }
        // Scroll ends: never under the top edge, the tab bar or the strip.
        if scroll.endedAt != 0, now - scroll.endedAt > 900, !scrollChecked {
            scrollChecked = true
            if let a = e.anchor, a.surface.isRule, e.mode == .attached {
                let y = e.anchorPoint(a).y
                if y - 96 < RefLayout.listTop - 0.5 || y > listBottom() + 0.5 { violation("scroll end", "rule at \(y)") }
            }
        }
        if scroll.endedAt == 0 || now - scroll.endedAt < 900 { scrollChecked = scroll.endedAt == 0 }
    }

    // MARK: Scene setup

    func place(_ sc: RefScene) {
        tab = sc.tab
        for k in Array(fade.keys) { fade[k] = k == tab ? 1 : 0 }
        keyboard = sc.keyboard
        kbTop.snap(keyboard ? RefLayout.H - RefLayout.kbH : RefLayout.H)
        if sc.draft {
            draftPending = true
            introduced = sc.introduced
            panelMode = sc.panel == "open" ? .open : .strip
            panelTop.snap(panelMode == .open ? RefLayout.panelOpenTop : RefLayout.stripTop)
            composerBase.snap(RefLayout.composerBottomStrip)
        } else {
            draftPending = false
            panelMode = .hidden
            panelTop.snap(RefLayout.panelHiddenTop)
            composerBase.snap(RefLayout.composerBottomNoStrip)
        }
        messages = sc.messages
        typed = sc.typed
        typingTarget = ""
        scroll.y = sc.scroll
        scroll.lastY = scroll.y
        scroll.v = 0
        scroll.mode = .idle
        scroll.vel = 0
        if let d = sc.detail {
            detailOpen = true
            _ = d
            detailX.snap(0)
        }
        badge = sc.badge
        guard let spot = sc.doddy ?? preferredSpot(for: engine) else { return }
        var p = MotionEngine.Placement(spot: spot)
        p.idle = sc.idle
        p.welcome = sc.welcome
        p.welcomeKind = sc.welcomeKind
        p.hadWelcome = sc.hadWelcome
        p.glances = sc.glances
        p.glanceAt = sc.glanceAt
        p.breathAt = sc.breathAt
        p.sitting = sc.sitting
        p.noSit = sc.noSit
        p.noEdge = sc.noEdge
        p.gaze = sc.gaze
        engine.place(p, lastInputWillBe: &lastInputT, lastTapWillBe: &lastTapT)
        lastScale = engine.scale
    }

    /// The reference's `state()` at the end of a clip.
    func finalState() -> [String: Any] {
        let e = engine
        return [
            "t": now, "screen": screenKey, "tab": tab, "mode": e.mode.rawValue,
            "surface": e.anchor?.surface.description as Any, "x": ((e.pose.x) * 100).rounded() / 100, "y": (e.pos.y * 100).rounded() / 100,
            "scale": (e.scale * 1000).rounded() / 1000, "opacity": (e.opacity * 1000).rounded() / 1000,
            "activity": e.activity, "mood": e.mood, "gaze": e.gaze.label, "mic": voiceLive,
        ]
    }
}

struct RefScroll {
    enum Mode { case idle, drag, momentum, bounce, toTop }
    var y = 0.0
    var v = 0.0
    var vel = 0.0
    var mode: Mode = .idle
    let spring = MotionSpring(0, response: 0.4, damping: 1.0)
    var prevY = 0.0
    var lastY: Double?
    var slowSince = 0.0
    var d0 = 0.0
    var f0 = 0.0
    var dragging = false
    var wasMoving = false
    var endedAt = 0.0
}

struct RefToast {
    var active = false
    var phase = ""
    let x = MotionSpring(-200, response: 0.5, damping: 0.9)
    var lane = 300.0
    var w = 150.0
    var prevX = -200.0
    var t = 0.0
    var restX = 0.0
    var exitX = -200.0
    var hold = 1400.0
    var restT = 0.0
}

struct RefFinger {
    var down = false
    var x = 0.0, y = 0.0, x0 = 0.0, y0 = 0.0, t0 = 0.0
    var moved = false
    var samples: [(t: Double, x: Double, y: Double)] = []
    var vx = 0.0, vy = 0.0
}

struct RefHit {
    var kind: String
    var drag = false
    var tap: ((Double) -> Void)?
    var down: (() -> Void)?
    var panel0 = 0.0
}

/// The reference's surfaces (`S(id)` in engine.js).
struct RefSurface: MotionSurface {
    let id: MotionSurfaceID
    unowned let w: ReferenceMotionWorld

    var layer: Double {
        switch id.kind {
        case .stage, .composer, .rule: 1
        case .panel: 2
        case .rail: 2.5
        case .detail: 1.5
        }
    }

    var scale: Double { id == .stage ? w.engine.settings.homeScale : 1 }

    func top() -> Double {
        switch id.kind {
        case .stage: RefLayout.stageY
        case .composer: w.composerTop()
        case .panel: w.panelTop.x
        case .rail: RefLayout.rail
        case .detail: RefLayout.detailSourceY
        case .rule(let i): w.ruleY(i)
        }
    }

    func dx() -> Double { id == .detail ? w.detailX.x : 0 }

    func standRange() -> ClosedRange<Double> {
        switch id.kind {
        case .stage: 150...240
        case .composer: 44...w.composerMaxX()
        case .panel: w.panelMode == .open ? 40...330 : 40...(RefLayout.reviewHitX0 - 48)
        case .rail, .detail: 40...350
        case .rule: 306...340
        }
    }

    func segment() -> ClosedRange<Double> {
        switch id.kind {
        case .stage: return RefLayout.stageX0...RefLayout.stageX1
        case .composer: return 16...374
        case .panel:
            let inset = MotionMath.lerp(16, 8, w.panelOpenness())
            return inset...(RefLayout.W - inset)
        case .rail: return 0...RefLayout.W
        case .detail: return (16 + w.detailX.x)...(374 + w.detailX.x)
        case .rule: return 24...366
        }
    }

    func isVisible() -> Bool {
        switch id.kind {
        case .stage: w.tab == "home"
        case .composer: w.tab == "talk"
        case .panel: w.draftPending
        case .rail: true
        case .detail: w.tab == "memories" && w.detailOpen
        case .rule(let i): w.tab == "memories" && i < w.layout.count
        }
    }

    func pointAhead(x: Double, dt: Double) -> MotionPoint? {
        switch id.kind {
        case .panel:
            return MotionPoint(x: x, y: w.panelDrag != nil ? w.panelTop.x + w.panelTop.v * dt : w.panelTop.ahead(dt))
        case .composer:
            return MotionPoint(x: x, y: w.composerBottomAt(w.composerBase.ahead(dt), w.kbTop.ahead(dt)) - RefLayout.composerH)
        case .detail:
            return MotionPoint(x: x + w.detailX.ahead(dt), y: RefLayout.detailSourceY)
        case .rule(let i):
            return MotionPoint(x: x, y: RefLayout.listTop + (i < w.layout.count ? w.layout[i].bottom : 0) - w.scrollAhead(dt))
        default:
            return nil
        }
    }

    func predictedPoint(x: Double) -> MotionPoint? {
        switch id.kind {
        case .panel: return MotionPoint(x: x, y: w.panelTop.target)
        case .composer: return MotionPoint(x: x, y: w.composerBottomAt(w.composerBase.target, w.kbTop.target) - RefLayout.composerH)
        case .detail: return MotionPoint(x: x + w.detailX.target, y: RefLayout.detailSourceY)
        case .rule: return pointAhead(x: x, dt: 0.4)
        default: return nil
        }
    }

    func isMoving() -> Bool {
        switch id.kind {
        case .panel: return w.panelDrag != nil || abs(w.panelTop.target - w.panelTop.x) > 0.5 || abs(w.panelTop.v) > 5
        case .composer: return abs(w.kbTop.target - w.kbTop.x) > 0.5 || abs(w.composerBase.target - w.composerBase.x) > 0.5
        case .rule: return abs(w.scroll.vel) > 2
        case .detail: return abs(w.detailX.target - w.detailX.x) > 0.5
        default: return false
        }
    }

    func settleY() -> Double {
        switch id.kind {
        case .composer: w.composerBottomAt(w.composerBase.target, w.kbTop.target) - RefLayout.composerH
        case .panel: w.panelTop.target
        default: top()
        }
    }
}

/// The Memories list as the engine sees it.
struct RefList: MotionList {
    unowned let w: ReferenceMotionWorld

    var ruleCount: Int { w.layout.count }
    func ruleY(_ i: Int, ahead dt: Double) -> Double {
        dt == 0 ? w.ruleY(i) : RefLayout.listTop + w.layout[i].bottom - w.scrollAhead(dt)
    }
    var top: Double { RefLayout.listTop }
    var bottom: Double { w.listBottom() }
    var velocity: Double { w.scroll.vel }
    var isFlinging: Bool { w.scroll.mode == .momentum && abs(w.scroll.v) > MotionTiming.lilySlow }
    var isScrollingToTop: Bool { w.scroll.mode == .toTop }
    var slowSince: Double? { w.scroll.slowSince == 0 ? nil : w.scroll.slowSince }
    func isUnderFinger(_ i: Int) -> Bool {
        if !w.fingerState.down || w.tab != "memories" { return false }
        let fy = w.fingerState.y
        if fy < RefLayout.listTop || fy > w.listBottom() { return false }
        let top = i == 0 ? RefLayout.listTop - w.scroll.y : w.ruleY(i - 1), bot = w.ruleY(i)
        return fy >= top && fy <= bot
    }
    var isFingerDown: Bool { w.fingerState.down }
    var ruleX: Double { RefLayout.ruleX }
    var waitSpot: MotionSpot { MotionSpot(.rail, x: RefLayout.tabX["memories"]!) }
}
