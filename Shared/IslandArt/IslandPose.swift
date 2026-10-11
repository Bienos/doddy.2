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

    /// The voice screen's phases, without the app's controller.
    enum Phase: Sendable {
        case connecting, listening, thinking, speaking, ended, microphoneOff, failed
    }

    /// One pose means one thing, as on the island: a failure is the facepalm, "can't hear you"
    /// (muted or no microphone) the shush, a card waiting for your tap the reach, the end the
    /// fist pump.
    static func shown(_ phase: Phase, muted: Bool, awaitingConfirmation: Bool) -> VoiceScreenArt {
        switch phase {
        case .failed: return .pose(.facepalm)
        case .microphoneOff: return .pose(.shush)
        case .ended: return .pose(.fistpump)
        default: break
        }
        if muted { return .pose(.shush) }
        if awaitingConfirmation { return .pose(.reachingHigh) }
        switch phase {
        case .connecting: return .pose(.yawnStretch)
        case .listening: return .pose(.listening)
        case .thinking: return .pose(.kneelingInspect)
        default: return .talking
        }
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
