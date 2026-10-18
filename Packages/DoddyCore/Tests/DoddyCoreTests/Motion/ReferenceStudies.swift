import Foundation
@testable import DoddyCore

// The owner's 25 motion studies (`design/motion-v2/reference/scripts.js`) as deterministic
// scripts over `ReferenceMotionWorld`, run the way the clips were rendered
// (`reference/stage.html`: place the scene, run the script, 60 frames a second).

struct ReferenceStudy {
    var id: String
    var duration: Double
    var reduceMotion = false
    var scene: RefScene
    var script: RefScript

    var frames: Int { Int((duration / 1000 * 60).rounded()) }

    /// Runs the study to its end and returns the world for inspection.
    func run() -> ReferenceMotionWorld {
        var settings = MotionSettings()
        settings.autoWelcome = false
        settings.reduceMotion = reduceMotion
        let w = ReferenceMotionWorld(settings: settings)
        w.place(scene)
        w.runScript(script)
        w.render()
        for _ in 0..<frames { w.stepFrame() }
        return w
    }
}

enum ReferenceStudies {
    static let tabX: [String: Double] = ["home": 73, "talk": 195, "memories": 317]
    static let tabY = 757.0

    static func tap(_ t: Double, _ x: Double, _ y: Double, _ hold: Double = 60) -> [RefFingerKey] {
        [RefFingerKey(t: t, kind: .down, x: x, y: y), RefFingerKey(t: t + hold, kind: .up)]
    }

    static func tabTap(_ t: Double, _ tab: String, _ hold: Double = 60) -> [RefFingerKey] {
        tap(t, tabX[tab]!, tabY, hold)
    }

    static func path(_ t0: Double, _ x0: Double, _ y0: Double, _ segs: [(Double, Double, Double, RefFingerKey.Ease)]) -> [RefFingerKey] {
        var out = [RefFingerKey(t: t0, kind: .down, x: x0, y: y0)]
        var t = t0
        for (dt, x, y, ease) in segs {
            t += dt
            out.append(RefFingerKey(t: t, kind: .move, x: x, y: y, ease: ease))
        }
        return out
    }

    static func up(_ t: Double) -> RefFingerKey { RefFingerKey(t: t, kind: .up) }

    static func scene(_ tab: String, _ configure: (inout RefScene) -> Void = { _ in }) -> RefScene {
        var s = RefScene()
        s.tab = tab
        configure(&s)
        return s
    }

    static func welcome(_ id: String, _ kind: WelcomeKind) -> ReferenceStudy {
        ReferenceStudy(id: id, duration: 4000, scene: scene("home") {
            $0.welcome = true
            $0.welcomeKind = kind
            $0.gaze = MotionPoint(x: -0.25, y: 0.55)
        }, script: RefScript())
    }

    /// Concatenates finger keys (keeps the type checker fast).
    static func keys(_ parts: [RefFingerKey]...) -> [RefFingerKey] { parts.flatMap { $0 } }

    static var all: [ReferenceStudy] {
        var a: [ReferenceStudy] = []
        a.append(ReferenceStudy(id: "02", duration: 5700, scene: scene("talk") { $0.messages = 2 },
                                script: RefScript(finger: keys(tabTap(500, "memories"), tabTap(2600, "talk")))))
        a.append(ReferenceStudy(id: "09a", duration: 5000, scene: scene("talk") { $0.messages = 2 },
                                script: RefScript(timeline: [(500, { $0.createDraft() })])))
        a.append(ReferenceStudy(id: "09b", duration: 4000, scene: scene("talk") {
            $0.draft = true
            $0.panel = "open"
            $0.introduced = false
            $0.messages = 2
        }, script: RefScript(timeline: [(500, { $0.introduceDraft() })], finger: tap(860, 120, 494, 80))))
        a.append(ReferenceStudy(id: "12", duration: 4600, scene: scene("memories"), script: RefScript(finger: tabTap(500, "home"))))
        a.append(ReferenceStudy(id: "14", duration: 5100, scene: scene("memories"), script: RefScript(finger: keys(tap(500, 80, 311), tap(2500, 52, 106)))))
        a.append(ReferenceStudy(id: "16", duration: 5800, scene: scene("talk") { $0.messages = 2 },
                                script: RefScript(finger: keys(tabTap(500, "memories"), tabTap(760, "home", 50), tabTap(2800, "talk", 40), tabTap(2860, "memories", 40)))))
        a.append(ReferenceStudy(id: "N1", duration: 5700, scene: scene("talk") { $0.messages = 2 },
                                script: RefScript(finger: keys(tabTap(500, "home"), tabTap(2700, "talk")))))
        let n2: [RefFingerKey] = keys(path(600, 312, 262, [(420, 86, 300, .inOut), (480, 300, 628, .inOut)]), [up(1560)], tap(2150, 196, 412, 110))
        a.append(ReferenceStudy(id: "N2", duration: 5200, scene: scene("home"), script: RefScript(finger: n2)))
        let n3a: [RefFingerKey] = path(600, 176, 356, [(260, 192, 354, .inOut), (300, 214, 357, .inOut), (360, 180, 352, .inOut), (300, 206, 355, .inOut)])
        let n3b: [RefFingerKey] = path(2700, 198, 424, [(420, 250, 432, .inOut), (320, 246, 470, .inOut), (220, 246, 470, .linear)])
        let n3c: [RefFingerKey] = path(4500, 195, 432, [(40, 195, 418, .easeIn), (50, 195, 352, .linear)])
        a.append(ReferenceStudy(id: "N3", duration: 7200, scene: scene("home"), script: RefScript(finger: keys(n3a, [up(1900)], n3b, [up(3720)], n3c, [up(4600)]))))
        a.append(ReferenceStudy(id: "N4", duration: 7200, scene: scene("home"), script: RefScript(finger: tap(600, 196, 418, 2500))))
        a.append(ReferenceStudy(id: "N5", duration: 18500, scene: scene("talk") {
            $0.draft = true
            $0.panel = "strip"
            $0.introduced = true
            $0.messages = 2
        }, script: RefScript(finger: tabTap(500, "home"))))
        a.append(welcome("N6a", .standard))
        a.append(welcome("N6b", .evening))
        a.append(welcome("N6c", .back))
        a.append(ReferenceStudy(id: "N7", duration: 5600, scene: scene("home") {
            $0.draft = true
            $0.panel = "strip"
            $0.introduced = true
        }, script: RefScript(finger: keys(tap(500, 120, 680), tap(2600, 195, 654)))))
        a.append(ReferenceStudy(id: "N8", duration: 4000, scene: scene("talk") { $0.messages = 2 },
                                script: RefScript(timeline: [(500, { $0.setMic(true) })])))
        let n9a: [RefFingerKey] = path(500, 150, 560, [(200, 150, 548, .easeIn), (520, 150, 480, .linear), (480, 150, 440, .easeOut)])
        let n9b: [RefFingerKey] = path(3200, 150, 600, [(40, 150, 588, .easeIn), (70, 150, 500, .linear)])
        a.append(ReferenceStudy(id: "N9", duration: 7600, scene: scene("memories") {
            $0.scroll = 200
            $0.doddy = MotionSpot(.rule(2), x: 330)
        }, script: RefScript(finger: keys(n9a, [up(1760)], n9b, [up(3310)]))))
        let n10: [RefFingerKey] = path(500, 120, 680, [(17, 120, 674, .linear), (17, 120, 660, .linear), (17, 120, 634, .linear), (17, 120, 594, .linear), (17, 120, 542, .linear)])
        a.append(ReferenceStudy(id: "N10", duration: 4000, scene: scene("memories") {
            $0.draft = true
            $0.panel = "strip"
            $0.introduced = true
        }, script: RefScript(finger: keys(n10, [up(585)]))))
        a.append(ReferenceStudy(id: "N11", duration: 7700, scene: scene("talk") {
            $0.keyboard = true
            $0.typed = "What time does Mum land on Saturday?"
            $0.messages = 2
        }, script: RefScript(
            timeline: [(0, { $0.nextReply = RefReply(delay: 4400, text: "Saturday at 14:20, terminal A.", draft: false) })],
            finger: tap(500, 352, 514))))
        let n12: [(t: Double, fn: (ReferenceMotionWorld) -> Void)] = [
            (500, { $0.send(text: "We have coffee on Fridays, after work.", reply: RefReply(delay: 900, text: "Got it.", draft: false, saved: true, savedAfter: 520)) }),
            (3600, { $0.setBanner(true) }),
            (5400, { $0.setBanner(false) }),
        ]
        a.append(ReferenceStudy(id: "N12", duration: 7800, scene: scene("talk") { $0.messages = 2 }, script: RefScript(timeline: n12)))
        a.append(ReferenceStudy(id: "N13", duration: 5600, scene: scene("memories") {
            $0.draft = true
            $0.panel = "strip"
            $0.introduced = true
            $0.idle = 7000
            $0.breathAt = -5200
        }, script: RefScript()))
        a.append(ReferenceStudy(id: "N14", duration: 4000, scene: scene("home") {
            $0.sitting = true
            $0.idle = 16000
        }, script: RefScript(timeline: [(500, { $0.engine.playful(.stretch) })])))
        a.append(ReferenceStudy(id: "N15", duration: 4800, scene: scene("talk") { $0.messages = 2 },
                                script: RefScript(timeline: [(500, { $0.passToast(fromRight: true, restX: 24, response: 0.95, hold: 1400) })])))
        a.append(ReferenceStudy(id: "RM", duration: 6200, reduceMotion: true, scene: scene("talk") { $0.messages = 2 },
                                script: RefScript(finger: keys(tabTap(500, "home"), tabTap(1900, "memories"), tabTap(3300, "talk"), tap(3900, 120, 682)))))
        let jTimeline: [(t: Double, fn: (ReferenceMotionWorld) -> Void)] = [
            (3600, { _ in }),
            (4300, { $0.typeText("Tell Mateusz I’m running late. Coffee is Fridays after work.", 32) }),
            (6900, { $0.nextReply = RefReply(delay: 1940, text: "I’ll draft that for Mateusz.", draft: true, saved: true, savedAfter: 450, draftAfter: 1000) }),
            (21200, { w in
                let i = w.engine.anchor?.surface.ruleIndex ?? 1
                w.fingerDown(84, w.ruleY(i) - 23)
            }),
            (21260, { $0.fingerUp() }),
        ]
        let jA: [RefFingerKey] = path(1550, 320, 252, [(400, 92, 300, .inOut), (380, 300, 610, .inOut)])
        let jB: [RefFingerKey] = path(16700, 150, 600, [(420, 150, 580, .easeIn), (600, 150, 520, .linear), (500, 150, 496, .easeOut)])
        let jC: [RefFingerKey] = path(18900, 150, 620, [(40, 150, 608, .easeIn), (70, 150, 520, .linear)])
        let jFinger: [RefFingerKey] = keys(
            jA, [up(2380)], tap(2760, 196, 414, 240), tap(3600, 120, 682), tap(7000, 352, 514), tap(12600, 195, 573),
            tap(13900, 359, 466), tabTap(15500, "memories"), jB, [up(18270)], jC, [up(19010)], tap(22700, 52, 106), tabTap(23600, "home"))
        a.append(ReferenceStudy(id: "J", duration: 30000, scene: scene("home") {
            $0.welcome = true
            $0.gaze = MotionPoint(x: -0.25, y: 0.55)
        }, script: RefScript(timeline: jTimeline, finger: jFinger)))
        return a
    }
}
