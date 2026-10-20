import Foundation

/// "Whole Doddy" (ADR-264): Doddy's whole body on the voice island, one pose per state (and on
/// the read-aloud island, the Lock Screen card and the voice screen, ADR-299). The
/// poses are the owner's DODDY-Numbered-Video-Assets-v01 pack (01-transparent-poses), as
/// downscaled copies in the image sets `WholeDoddy_<rawValue>` of the app and widget catalogs
/// (docs/design/UPLOADED_MEMORY_ASSETS.md). Each picture is 2:3 with transparent edges.
enum IslandPose: String, CaseIterable, Sendable {
    case yawnStretch = "yawn_stretch", listening, kneelingInspect = "kneeling_inspect", shrug, shush, facepalm
    case crosslegged, leaning, reachingHigh = "reaching_high", fistpump, tiptoe
    /// The greeting (ADR-290): frame 4 of the pack's wave strip, cut out by
    /// tools/whole_doddy/cut_wave.py (the only pose not from 01-transparent-poses).
    case wave
    /// Reading a note aloud (ADR-299): lying on his front with a book.
    case bellyReading = "belly_reading"
    /// The focus timer (ADR-313): dribbling, busy with one thing.
    case basketballDribble = "basketball_dribble"
    /// Breathing (ADR-313): balancing on one leg.
    case onelegBalance = "oneleg_balance"
    /// "Pause all connections" is on (ADR-323): crouching, lying low.
    case sneakyCrouch = "sneaky_crouch"
    /// Notes hidden from widgets or the watch (ADR-331): turned away, not looking. Frame 5 of
    /// the pack's turn strip (018), cut like the other strip frames.
    case turnedAway = "turned_away"

    var assetName: String { "WholeDoddy_\(rawValue)" }

    /// The figure's box in the picture, as fractions of its width and height, so the drawing
    /// can stand on the island's floor at the largest size that fits.
    var figure: IslandRect {
        // Measured from the alpha channel at 400 × 600 (pixels with alpha above 24).
        let box: (Double, Double, Double, Double) = switch self {
        case .yawnStretch: (52, 61, 356, 545)
        case .listening: (88, 67, 335, 534)
        case .kneelingInspect: (35, 97, 364, 479)
        case .shrug: (21, 56, 381, 557)
        case .shush: (92, 33, 317, 584)
        case .facepalm: (118, 64, 320, 533)
        case .crosslegged: (88, 90, 315, 512)
        case .leaning: (36, 73, 355, 529)
        case .reachingHigh: (68, 30, 365, 569)
        case .fistpump: (100, 49, 346, 562)
        case .tiptoe: (26, 78, 374, 529)
        case .wave: (58, 100, 341, 548)
        case .bellyReading: (17, 196, 384, 413)
        case .basketballDribble: (34, 83, 375, 467)
        case .onelegBalance: (10, 78, 389, 531)
        case .sneakyCrouch: (77, 89, 338, 524)
        case .turnedAway: (112, 118, 287, 564)
        }
        return IslandRect(x: box.0 / 400, y: box.1 / 600, width: (box.2 - box.0) / 400, height: (box.3 - box.1) / 600)
    }

    /// The pose whose face compact and minimal show: at 24 pt only a face reads, and only four
    /// poses show it clearly. Eyes closed (from the stretch) while Doddy waits or is paused.
    var facePose: IslandPose {
        switch self {
        case .listening: .listening
        case .shush: .shush
        case .crosslegged, .leaning: .yawnStretch
        default: .crosslegged
        }
    }

    /// Where the head is in a face pose: its centre as fractions of width and height, and its
    /// diameter as a fraction of the width. Nil for poses not used as a face.
    var head: (x: Double, y: Double, diameter: Double)? {
        switch self {
        case .listening: (205.0 / 400, 152.0 / 600, 172.0 / 400)
        case .shush: (203.0 / 400, 140.0 / 600, 190.0 / 400)
        case .yawnStretch: (201.0 / 400, 212.0 / 600, 160.0 / 400)
        case .crosslegged: (200.0 / 400, 179.0 / 600, 196.0 / 400)
        default: nil
        }
    }
}

/// What the in-app voice screen draws (ADR-299): the island's pose for the same moment, except
/// while Doddy speaks, when the six frames of the pack's talking strip (020) play in turn.
/// Kept here, beside the poses, so the mapping is checked on any machine with Swift.
enum VoiceScreenArt: Hashable, Sendable {
    case pose(IslandPose)
    case talking
    /// A looping strip (ADR-313): walking while connecting, running while a plan runs.
    case motion(DoddyMotion)

    /// The voice screen's phases, without the app's controller.
    enum Phase: Sendable {
        case connecting, listening, thinking, speaking, ended, microphoneOff, failed
    }

    /// One pose means one thing, as on the island: a failure is the facepalm, "can't hear you"
    /// (muted or no microphone) the shush, a card waiting for your tap the reach, the end the
    /// fist pump.
    /// In the app Doddy can move, so getting there is a walk (the island, which can't animate,
    /// keeps the stretch) and a running plan is a run (ADR-313).
    static func shown(_ phase: Phase, muted: Bool, awaitingConfirmation: Bool, planRunning: Bool = false) -> VoiceScreenArt {
        switch phase {
        case .failed: return .pose(.facepalm)
        case .microphoneOff: return .pose(.shush)
        case .ended: return .pose(.fistpump)
        default: break
        }
        if muted { return .pose(.shush) }
        if awaitingConfirmation { return .pose(.reachingHigh) }
        switch phase {
        case .connecting: return .motion(.walk)
        case .speaking: return .talking
        default: break
        }
        // Between his lines, while the steps of a plan run.
        if planRunning { return .motion(.run) }
        return phase == .thinking ? .pose(.kneelingInspect) : .pose(.listening)
    }

    static let talkingFrameCount = 6
    /// Seconds each talking frame shows.
    static let talkingFrameDuration = 0.18
    /// One box for all six frames (the union of their figures at 400 × 600), so he stays put.
    static let talkingFigure = IslandRect(x: 36.0 / 400, y: 99.0 / 600, width: 332.0 / 400, height: 449.0 / 600)

    /// `VoiceDoddy_talking_1` ... `_6`, cut from the strip by tools/whole_doddy/cut_frames.py.
    static func talkingAssetName(_ frame: Int) -> String { "VoiceDoddy_talking_\(frame)" }

    /// The frame (1 ... 6) shown at a moment, looping.
    static func talkingFrame(at seconds: TimeInterval) -> Int {
        let step = Int((max(0, seconds) / talkingFrameDuration).rounded(.down))
        return step % talkingFrameCount + 1
    }
}

/// Doddy moving (ADR-313): strips from the owner's pack, cut by tools/whole_doddy/cut_frames.py
/// --shared, so every frame has the same scale and ground. Image sets `DoddyMotion_<strip>_<n>`
/// in the app catalog. A strip either loops or plays once and stays on its last frame.
enum DoddyMotion: String, CaseIterable, Hashable, Sendable {
    /// 012: eight steps, looping. The voice screen while connecting.
    case walk
    /// 014: six strides, looping. The voice screen while a plan runs.
    case run
    /// 015: crouch, jump, land, stand. Once, when the last thing on a list is ticked.
    case jump
    /// 018, frames 1–3: Doddy turns side-on. Once when an entry is undone in What Doddy did
    /// (ADR-323); otherwise its last frame stands still as the "undone" mark.
    case turn
    /// 019: a burst, a star jump, a crouch, a wave. Once, when a note is saved.
    case pop
    /// 013: four breaths, standing. Once on Home, then he sits.
    case idle
    /// 017: he sits down on a box (ADR-323). Once on Home after the idle breaths; then he stays
    /// on the box for that launch.
    case sit
    /// 016: hand up, open, waving (ADR-380). Once: Home's first visit of a morning, the morning
    /// check-in and other hellos; then it rests on the open-hand wave.
    case wave

    /// The frames the app ships, in order.
    var frames: [Int] {
        switch self {
        case .walk: Array(1...8)
        case .run: Array(1...6)
        case .jump: Array(1...5)
        case .turn: Array(1...3)
        case .pop: Array(1...4)
        case .idle: Array(1...4)
        case .sit: Array(1...5)
        case .wave: Array(1...5)
        }
    }

    var loops: Bool { self == .walk || self == .run }

    /// Seconds per frame.
    var frameDuration: Double {
        switch self {
        case .walk: 0.12
        case .run: 0.09
        case .jump, .pop: 0.12
        case .turn: 0.16
        case .idle: 0.3
        case .sit: 0.22
        case .wave: 0.14
        }
    }

    /// Seconds a once-only strip takes before it rests on its last frame.
    var duration: Double { Double(frames.count) * frameDuration }

    func assetName(_ frame: Int) -> String { "DoddyMotion_\(rawValue)_\(frame)" }

    /// One box for all of a strip's frames (their union at 400 × 600), so he doesn't jump.
    var figure: IslandRect {
        let box: (Double, Double, Double, Double) = switch self {
        case .walk: (75, 123, 325, 564)
        case .run: (38, 144, 361, 564)
        case .jump: (40, 117, 359, 564)
        case .turn: (103, 115, 298, 564)
        case .pop: (34, 142, 365, 579)
        case .idle: (97, 112, 303, 564)
        case .sit: (37, 123, 362, 564)
        case .wave: (53, 117, 347, 564)
        }
        return IslandRect(x: box.0 / 400, y: box.1 / 600, width: (box.2 - box.0) / 400, height: (box.3 - box.1) / 600)
    }

    /// The frame shown `seconds` after the strip started: looping, or held on the last frame.
    /// With Reduce Motion the app shows `stillFrame` instead.
    func frame(at seconds: TimeInterval) -> Int {
        let step = Int((max(0, seconds) / frameDuration).rounded(.down))
        return loops ? frames[step % frames.count] : frames[min(step, frames.count - 1)]
    }

    /// The one frame shown with Reduce Motion: where a once-only strip ends, a loop's first.
    var stillFrame: Int { loops ? frames[0] : frames[frames.count - 1] }
}

/// The pack's storyboards, played as cross-faded panels (ADR-299, ADR-380). Panels are cropped
/// from the pack only (`tools/whole_doddy/cut_panels.py`, `cut_storyboards.py`).
enum PanelStory: String, CaseIterable, Hashable, Sendable {
    /// 038: a notebook's page turns and Doddy waves. No screen shows it now (the welcome's `StorybookView`
    /// was removed, 20 Oct); the preview gallery does.
    case page
    /// 037: Doddy steps out of a phone onto the desk. The Back Tap guide.
    case phone
    /// 039: Doddy draws a door and walks through. The Face ID lock.
    case door
    /// 040: an ink drop, a splash, Doddy in a real street. No screen shows it now ("What I can do"
    /// was removed, 20 Oct); the Xcode preview gallery still does.
    case ink
    /// 041: keys found under a cushion. No screen shows it now; the preview gallery does.
    case keys

    var panelCount: Int { self == .keys ? 6 : 4 }

    func assetName(_ panel: Int) -> String {
        self == .page ? "Storybook_page_\(panel)" : "Story_\(rawValue)_\(panel)"
    }

    /// Seconds each panel holds before the next fades in.
    var hold: Double { self == .page ? 1.1 : 0.9 }
}
