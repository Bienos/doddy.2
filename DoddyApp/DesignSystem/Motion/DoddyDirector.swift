import DoddyCore
import Foundation
import Observation

/// What the drawing of him needs this frame: the picture and its transforms (`MotionArt`), and
/// where (window points), how big and how visible.
struct DoddyFigure: Equatable {
    var art: MotionArt
    /// His soles' centre in window points.
    var x: Double
    var y: Double
    var scale: Double
    var opacity: Double
    /// In a slot: his soles relative to the surface's top edge centre, worked out from the same
    /// frame the engine used. Relative, so it stays right while the system moves the surface
    /// (a scroll, the keyboard) between his frames.
    var slotDX = 0.0
    var slotDY = 0.0
}

/// The clock the director runs on: a display link while he moves, asleep (or a timer) while he
/// is still. The app supplies a CADisplayLink one (`DoddyClock`).
@MainActor
protocol DoddyClockDriving: AnyObject {
    /// Ticks every frame from now on.
    func run()
    /// No more frames; one tick at `uptime` (seconds, the clock's own time base) if not nil.
    func sleep(until uptime: Double?)
}

/// The one persistent Doddy's director (motion v2, docs/design/MOTION_V2_PLAN.md section 4,
/// option B). It owns the one `MotionEngine` (through `MotionHost`, which answers the engine's
/// questions about the screen), keeps the registry of the surfaces the screens report (MV2), and
/// publishes where he is drawn: attached to the surface he stands on (`.slot`), in the root
/// overlay while he flies or fades (`.overlay`), or not at all while something covers him. The
/// slots and the overlay read the same `placement`, so a hand-off happens in one SwiftUI update.
///
/// UI-free on purpose (Foundation, Observation, DoddyCore), so `scripts/typecheck_app_logic.sh`
/// compiles it on Linux. Frames change on every scroll frame, so they are not observed.
@MainActor
@Observable
final class DoddyDirector {
    static let shared = DoddyDirector()

    /// The motion world is on: an iPhone-sized layout (Q13, iPad keeps today's pictures) with
    /// Doddy's pictures shown. Off, the screens keep no room for him and nothing draws him.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            host.isActive = isActive
            poke()
        }
    }

    // MARK: Published every frame he moves (the only state the drawing observes)

    /// Where he is drawn.
    private(set) var placement: MotionPlacement = .hidden
    /// What is drawn; nil when nothing is.
    private(set) var figure: DoddyFigure?
    /// Where the root overlay is in the window (it fills the window, so normally 0, 0).
    private(set) var overlayOrigin = MotionPoint.zero

    func overlayMoved(to origin: MotionPoint) {
        if origin != overlayOrigin { overlayOrigin = origin }
    }

    // MARK: The engine and the screen's reports

    let host: MotionHost
    var engine: MotionEngine { host.engine }
    @ObservationIgnored weak var clock: (any DoddyClockDriving)?
    /// The time now, in seconds, on the clock's time base (CACurrentMediaTime in the app).
    @ObservationIgnored var now: () -> Double = { ProcessInfo.processInfo.systemUptime }

    /// The last window frame each surface reported (kept while it is off screen).
    @ObservationIgnored private(set) var frames: [MotionSurfaceID: MotionRect] = [:]
    /// How many views report each surface right now. On screen: more than zero.
    @ObservationIgnored private var mountCount: [MotionSurfaceID: Int] = [:]
    /// Named frames: "send", "undo", "tab.home", "memories.list" …
    @ObservationIgnored private(set) var marks: [String: MotionRect] = [:]
    /// The Memories cards in the order shown: `rule(i)` is the card of `ruleIDs[i]`.
    @ObservationIgnored private(set) var ruleIDs: [UUID] = []
    /// Sheets and covers up now, by the token of the view that presents them.
    @ObservationIgnored private var coverTokens: Set<UUID> = []
    /// Screens showing a problem whose own picture of him was left out (Q4: he does the pose).
    @ObservationIgnored private var problems = 0
    /// Every drawing of him that is on screen now, by the token of the view that draws it, and
    /// where and since when (for the one-Doddy check: a view that appears twice is still one).
    @ObservationIgnored private(set) var drawings: [UUID: (spot: String, since: Double)] = [:]
    /// How many drawings of him are on screen (for the one-Doddy check).
    var drawnCount: Int { drawings.count }
    /// The DEBUG checks (MV3), run every frame in debug builds.
    @ObservationIgnored private(set) var checks = MotionChecks()
    /// Frames ticked since launch (the annotated mode's frame counter).
    @ObservationIgnored private(set) var frameCount = 0

    @ObservationIgnored private var lastTime: Double?
    /// DEBUG evidence (MV6): flights seen since launch, for the annotated mode's label.
    @ObservationIgnored private(set) var flightsSeen = 0
    @ObservationIgnored private var lastMode: MotionEngine.Mode = .attached
    @ObservationIgnored private var asleep = true
    /// Steps of at most this long (ms): four per 60 Hz frame, as the reference engine runs.
    static let substep = 1000.0 / 240
    /// A tick later than this after the last one (a hitch, the app coming back) isn't replayed.
    static let longestFrame = 100.0

    init() {
        var settings = MotionSettings()
        // MV5: breaths, the 15 s sit, the daily welcome and the playful moment are on; the welcome
        // is armed per day by `appBecameActive`. Low Power Mode comes from the device (DoddyClock).
        settings.autoWelcome = false
        host = MotionHost(settings: settings)
        host.isActive = false
        host.behaviours = true
        // A tap or a hold on him opens the voice screen (Q2); a hold can't start capture on Home
        // (plan section 5), so it acts as a tap.
        host.onOpenTalk = { [weak self] _ in self?.onTalk?() }
        host.onStartVoice = { false }
    }

    /// Opens the voice screen, as Home's "Talk to Doddy" button does (set by RootView).
    @ObservationIgnored var onTalk: (() -> Void)?

    // MARK: Reports from the screens (MV2)

    func surfaceMoved(_ id: MotionSurfaceID, to frame: MotionRect) {
        let old = frames[id]
        frames[id] = frame
        host.scene.frames[id] = frame
        // iOS 17 (Q10): no scroll measurements, so the first card on screen moving by itself (same
        // size) says the list scrolled. On iOS 18 the scroll view reports it (`listScrolled`).
        if !host.scene.scroll.measured, case .rule(let i) = id.kind, let old, isMounted(id),
           abs(old.height - frame.height) < 0.5, abs(old.width - frame.width) < 0.5,
           !(0..<i).contains(where: { isMounted(.rule($0)) }) {
            catchUp()
            host.cardsMoved(by: frame.minY - old.minY)
            poke()
        }
    }

    func surfaceAppeared(_ id: MotionSurfaceID) {
        mountCount[id, default: 0] += 1
        host.scene.mounted.insert(id)
        host.surfaceAppeared(id)
        poke()
    }

    func surfaceGone(_ id: MotionSurfaceID) {
        let n = (mountCount[id] ?? 0) - 1
        mountCount[id] = n > 0 ? n : nil
        if n <= 0 {
            catchUp()
            host.scene.mounted.remove(id)
            host.surfaceGone(id)
        }
        poke()
    }

    func markMoved(_ name: String, to frame: MotionRect) {
        marks[name] = frame
        host.scene.marks[name] = frame
    }

    /// The Memories list shows these notes, in this order. If his card moved (a note saved above
    /// it, one deleted), his rule number follows it.
    func cardsShown(_ ids: [UUID]) {
        let old = ruleIDs
        ruleIDs = ids
        host.scene.ruleCount = ids.count
        for id in Array(frames.keys) {
            if let i = id.ruleIndex, i >= ids.count {
                frames[id] = nil
                host.scene.frames[id] = nil
            }
        }
        if let i = engine.anchor?.surface.ruleIndex, i < old.count, let j = ids.firstIndex(of: old[i]), j != i {
            engine.rulesShifted(insertedAt: min(i, j), by: j - i)
        }
        poke()
    }

    // MARK: Reading

    func isMounted(_ id: MotionSurfaceID) -> Bool { mountCount[id] != nil }

    /// The surface's frame if its view is on screen now.
    func frame(of id: MotionSurfaceID) -> MotionRect? {
        isMounted(id) ? frames[id] : nil
    }

    // MARK: What the app tells him

    /// A tab button was tapped: called in the same action that changes the tab, so the surfaces of
    /// the screen that is leaving are treated as gone in this very update, and he crouches in the
    /// overlay where he stood (never zero Doddys while the tab content commits).
    func tabTapped(_ screen: MotionScreen) {
        guard screen != host.scene.screen else { return }
        catchUp()
        let leaving = host.scene.screen
        for id in host.scene.mounted where MotionScene.screen(of: id) == leaving {
            host.scene.mounted.remove(id)
        }
        host.tabChanged(to: screen, tapT: engine.now)
        publish()
        clock?.run()
    }

    /// The tab changed some other way (a link, a shortcut): the same, without a tap to answer.
    func screenChanged(_ screen: MotionScreen) {
        tabTapped(screen)
    }

    /// A page was pushed or popped on a tab (a note, Find, a Settings page).
    func pageChanged(on screen: MotionScreen, open: Bool, detail: Bool) {
        let was = host.scene.pages[screen] ?? MotionPage()
        let page = MotionPage(open: open, detail: detail)
        guard page != was else { return }
        catchUp()
        host.scene.pages[screen] = page
        if screen == .memories, host.scene.screen == .memories {
            if open, !was.open {
                // On a card he stays and the page covers him; elsewhere he goes to the note's spot.
                if engine.anchor?.surface.isRule == true || detail { engine.pagePushed() }
            } else if !open, was.open {
                engine.pagePopped()
            }
        }
        poke()
    }

    /// A sheet or cover starts or ends (`token` names the view that presents it). He is hidden in
    /// the frame it starts (plan, MV3: "every cover and sheet hides him in the frame it starts").
    func cover(_ token: UUID, isUp: Bool) {
        let changed = isUp ? coverTokens.insert(token).inserted : coverTokens.remove(token) != nil
        guard changed else { return }
        catchUp()
        host.scene.covers = coverTokens.count
        poke()
    }

    /// A problem view whose picture of him was left out appeared or went (he does the facepalm on
    /// his spot instead, Q4).
    func problemShown(_ shown: Bool) {
        problems = max(0, problems + (shown ? 1 : -1))
        poke()
    }

    // MARK: Riding (MV4)

    /// iOS 18: the Memories list's content offset (pt).
    func listScrolled(to offset: Double) {
        catchUp()
        host.listScrolled(to: offset)
        poke()
    }

    /// iOS 18: the Memories list's scroll phase.
    func listPhaseChanged(_ phase: MotionScroll.Phase) {
        catchUp()
        host.listPhaseChanged(phase)
        poke()
    }

    /// Ask opened (its cover starts up): he comes up with it, on its composer (Q2).
    func askOpened() {
        catchUp()
        host.talkOpened()
        poke()
    }

    /// Ask is closing: he is back on Home's stage, under its cover until it has gone.
    func askClosing() {
        guard host.scene.screen == .talk else { return }
        catchUp()
        host.talkClosing()
        poke()
    }

    // MARK: Behaviours (MV5)

    /// A finger on him on Home (his touch area), in window points.
    func touchDown(x: Double, y: Double) {
        catchUp()
        host.touchDown(x: x, y: y)
        poke()
    }

    func touchMoved(x: Double, y: Double, vx: Double, vy: Double) {
        catchUp()
        host.touchMoved(x: x, y: y, vx: vx, vy: vy)
        poke()
    }

    func touchUp(vx: Double, vy: Double) {
        catchUp()
        host.touchUp(vx: vx, vy: vy)
        poke()
    }

    /// Ask is waiting for its reply (thinking from 600 ms), or it came.
    func askSending(_ sending: Bool, failed: Bool) {
        catchUp()
        host.askSending(sending, failed: failed)
        poke()
    }

    /// A conversation's microphone is live and capturing (the session's real `.listening` phase).
    func voiceListening(_ live: Bool) {
        guard host.scene.voiceLive != live else { return }
        catchUp()
        host.voiceListening(live)
        poke()
    }

    /// Low Power Mode: no breaths, no glances.
    func setLowPower(_ on: Bool) {
        guard engine.settings.lowPower != on else { return }
        engine.settings.lowPower = on
        poke()
    }

    /// The day his welcome last played (shared with Home's morning wave, ADR-380, so the two never
    /// both play) and when Doddy was last opened, on this iPhone only. Neither is a note.
    static let welcomeDayKey = "home.lastWaveDay"
    static let lastVisitKey = "motion.lastVisit"

    /// When Doddy was last opened before this visit (read from `lastVisitKey` once per launch).
    @ObservationIgnored private var visitBefore: Date?
    @ObservationIgnored private var visitLoaded = false

    /// The app came to the front (or the motion world came on while it is): arms today's welcome
    /// if it hasn't played (after three days away, with a hop in place first), then remembers
    /// this visit. Safe to call more than once.
    func appBecameActive(now date: Date = Date(), defaults: UserDefaults = .standard) {
        if !visitLoaded {
            visitLoaded = true
            visitBefore = (defaults.object(forKey: Self.lastVisitKey) as? Double).map(Date.init(timeIntervalSince1970:))
        }
        // Only while he is drawn: with the motion world off (iPad's sidebar) Home's own morning
        // wave (ADR-380) keeps the day.
        if isActive {
            if let welcome = MotionWelcome.decide(now: date, lastWelcomeDay: defaults.string(forKey: Self.welcomeDayKey),
                                                  lastVisit: visitBefore) {
                defaults.set(welcome.day, forKey: Self.welcomeDayKey)
                catchUp()
                if host.isPlaced { host.newDay(welcome: welcome.kind) } else { host.welcomeToday = welcome.kind }
            }
            visitBefore = date
        }
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastVisitKey)
        poke()
    }

    /// The keyboard is up or down (playful moments wait while it is up).
    func keyboardChanged(up: Bool) {
        guard host.scene.keyboardUp != up else { return }
        host.scene.keyboardUp = up
        poke()
    }

    func setReduceMotion(_ on: Bool) {
        guard engine.settings.reduceMotion != on else { return }
        catchUp()
        engine.setReduceMotion(on)
        poke()
    }

    /// Q12: 1.4× on Home, 1.0× at accessibility text sizes (the change happens while he is unseen).
    func setHomeScale(_ scale: Double) {
        guard host.scene.homeScale != scale else { return }
        catchUp()
        host.scene.homeScale = scale
        engine.homeScaleChanged(scale)
        poke()
    }

    /// A drawing of him appeared or went (the one-Doddy check counts them).
    func drawingAppeared(_ token: UUID, in spot: String) { drawings[token] = (spot, now()) }
    func drawingGone(_ token: UUID) { drawings[token] = nil }
    /// Where each drawing is and how long it has been there, for a finding's text.
    var drawingsDescription: String {
        let t = now()
        return drawings.values.sorted { $0.since < $1.since }
            .map { "\($0.spot) \(String(format: "%.1f", t - $0.since)) s" }.joined(separator: ", ")
    }

    // MARK: The clock

    /// Something changed: look again now, and keep the frames coming until he is still.
    func poke() {
        catchUp()
        afterSteps()
    }

    /// One frame from the clock, at `time` (seconds).
    func tick(at time: Double) {
        advance(to: time)
        afterSteps()
    }

    /// Brings the engine's clock up to now before an event is handed to it.
    private func catchUp() {
        advance(to: now())
    }

    private func advance(to time: Double) {
        guard let last = lastTime else {
            lastTime = time
            return
        }
        guard time > last else { return }
        lastTime = time
        var dt = (time - last) * 1000
        if asleep {
            // He was still: the whole quiet stretch is one step (nothing was moving in it).
            asleep = false
            host.step(min(dt, 600_000))
            return
        }
        dt = min(dt, Self.longestFrame)
        while dt > 1e-6 {
            let d = min(dt, Self.substep)
            host.step(d)
            dt -= d
        }
    }

    private func afterSteps() {
        if isActive, !host.isPlaced { host.placeOnCurrentScreen() }
        host.settle()
        publish()
        frameCount += 1
        #if DEBUG
        if isActive { checks.check(host, drawn: drawnCount, drawnWhere: drawingsDescription) }
        // MV6 evidence: how many hops took to the air (none under Reduce Motion: fades only).
        if engine.mode == .flight, lastMode != .flight { flightsSeen += 1 }
        lastMode = engine.mode
        #endif
        guard let last = lastTime else { return }
        if !isActive || (host.isPlaced && engine.isStill && host.pendingTab == nil && !host.wantsFrames) {
            asleep = true
            let next = [engine.nextDue, host.nextDue].compactMap { $0 }.min()
            let due = isActive ? next.map { last + max(0.05, ($0 - engine.now) / 1000) } : nil
            clock?.sleep(until: due)
        } else {
            clock?.run()
        }
    }

    /// The pose a still screen asks for instead of standing: cross-legged on an empty list's spot,
    /// the facepalm while a problem is shown (Q4: he does the pose on his spot).
    private var stillPose: String? {
        guard engine.mode == .attached, let a = engine.anchor else { return nil }
        if case .ledge(let name) = a.surface.kind {
            if MotionHost.memoriesLedges.contains(name) { return "crosslegged" }
            if name == MotionHost.findLedge { return "shrug" }
        }
        // A problem view on his screen (Q4: he does its pose where he stands).
        if problems > 0 { return "facepalm" }
        return nil
    }

    private func publish() {
        let p = host.placement
        if p != placement { placement = p }
        let f: DoddyFigure?
        if p == .hidden {
            f = nil
        } else {
            let pose = engine.pose
            var figure = DoddyFigure(art: MotionArt.choose(engine, still: stillPose), x: pose.x, y: pose.y,
                                     scale: pose.scale, opacity: pose.opacity)
            if case .slot(let id) = p, let frame = host.lastStepFrames[id] ?? host.scene.frames[id] {
                figure.slotDX = pose.x - frame.midX
                figure.slotDY = pose.y - frame.minY
                // In a slot only the offsets are drawn: leaving his window position out keeps a
                // scroll (which moves it every frame) from redrawing him while the system moves
                // him anyway.
                figure.x = 0
                figure.y = 0
            }
            f = figure
        }
        if f != figure { figure = f }
    }
}
