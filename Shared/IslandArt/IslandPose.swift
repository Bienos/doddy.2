import Foundation

/// "Whole Doddy" (ADR-264): Doddy's whole body on the voice island, one pose per state. The
/// poses are the owner's DODDY-Numbered-Video-Assets-v01 pack (01-transparent-poses), as
/// downscaled copies in the image sets `WholeDoddy_<rawValue>` of the app and widget catalogs
/// (docs/design/UPLOADED_MEMORY_ASSETS.md). Each picture is 2:3 with transparent edges.
enum IslandPose: String, CaseIterable, Sendable {
    case yawnStretch = "yawn_stretch", listening, kneelingInspect = "kneeling_inspect", shrug, shush, facepalm
    case crosslegged, leaning, reachingHigh = "reaching_high", fistpump, tiptoe
    /// The greeting (ADR-268): frame 4 of the pack's wave strip, cut out by
    /// tools/whole_doddy/cut_wave.py (the only pose not from 01-transparent-poses).
    case wave

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
