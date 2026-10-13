import Foundation

// Linux check for the island drawing data (scripts/check_island_art.sh): every path in every
// board parses, every number is finite, and each drawing stays inside its view box. With
// `--svg <dir>` it also redraws each drawing from the parsed commands as SVG, so the result
// can be compared by eye with the owner's originals.

@main
struct IslandArtCheck {
    static func main() {
        let args = CommandLine.arguments
        // scripts/check_island_art.sh checks each of these has an image set in both catalogs.
        if args.contains("--pose-assets") {
            for pose in IslandPose.allCases { print(pose.assetName) }
            return
        }
        // ...and the round faces compact and minimal draw, one per face pose, in both catalogs.
        if args.contains("--face-assets") {
            for name in Set(IslandPose.allCases.map(\.faceAssetName)).sorted() { print(name) }
            return
        }
        // ...and the voice screen's talking frames (ADR-299) and the strips (ADR-313), app catalog only.
        if args.contains("--story-assets") {
            for story in PanelStory.allCases {
                for panel in 1...story.panelCount { print(story.assetName(panel)) }
            }
            return
        }
        if args.contains("--talking-assets") {
            for frame in 1...VoiceScreenArt.talkingFrameCount { print(VoiceScreenArt.talkingAssetName(frame)) }
            for motion in DoddyMotion.allCases {
                for frame in motion.frames { print(motion.assetName(frame)) }
            }
            return
        }
        let svgDir = args.firstIndex(of: "--svg").map { args[$0 + 1] }
        var failures = 0
        var drawings = 0
        for board in IslandBoard.allCases {
            for scenario in 0...1 {
                for (presentation, name) in [(IslandPresentation.expanded, "expanded"), (.compact, "compact"), (.minimal, "minimal")] {
                    let art = IslandBoardArt.art(board, scenario: scenario, presentation)
                    drawings += 1
                    failures += check(art, label: "\(board.rawValue)-\(scenario)-\(name)")
                    if let svgDir {
                        let svg = render(art)
                        try? svg.write(toFile: "\(svgDir)/\(board.rawValue)-\(scenario)-\(name).svg", atomically: true, encoding: .utf8)
                    }
                }
            }
        }
        for face in [IslandFace.listening, .speaking, .thinking, .calm, .proud, .focused] {
            for d in [face.brow, face.mouth] where IslandPathParser.parse(d) == nil {
                print("FAIL: face \(face) path does not parse: \(d)")
                failures += 1
            }
        }
        // Orange becomes grey when Doddy can't hear you.
        let lean = IslandBoardArt.art(.leanIn, scenario: 0, .expanded)
        if lean.primitives(live: false).contains(where: { $0.paint.stroke == IslandColor.orange || $0.paint.fill == IslandColor.orange }) {
            print("FAIL: orange left in a drawing that is not live"); failures += 1
        }
        if lean.primitives(live: true, showsHands: false).count >= lean.primitives(live: true).count {
            print("FAIL: hands not removed"); failures += 1
        }
        failures += IslandSceneChecks.run()
        failures += IslandSceneChecks.wholeDoddy()
        failures += IslandSceneChecks.voiceScreen()
        if failures > 0 {
            print("FAIL: \(failures) problem(s) in \(drawings) drawings")
            exit(1)
        }
        print("PASS: \(drawings) island drawings parse and fit their view boxes; scene checks pass")
    }

    static func walk(_ art: IslandArt, _ body: (IslandPrimitive) -> Void) {
        for p in art.primitives(live: true) { body(p) }
    }

    static func check(_ art: IslandArt, label: String) -> Int {
        var failures = 0
        func checkElements(_ elements: [IslandArtElement]) {
            for element in elements {
                switch element {
                case .path(let d, _):
                    if IslandPathParser.parse(d) == nil { print("FAIL: \(label): path does not parse: \(d)"); failures += 1 }
                case .group(_, _, _, _, let children):
                    checkElements(children)
                default: break
                }
            }
        }
        checkElements(art.elements)
        let vb = art.viewBox
        walk(art) { p in
            for (x, y) in points(p) {
                let ax = p.x + p.scale * x, ay = p.y + p.scale * y
                guard ax.isFinite, ay.isFinite else { print("FAIL: \(label): non-finite point"); failures += 1; return }
                // Curves' control points may sit a little outside what is drawn.
                let slack = 6.0
                if ax < vb.x - slack || ax > vb.x + vb.width + slack || ay < vb.y - slack || ay > vb.y + vb.height + slack {
                    print("FAIL: \(label): point (\(ax), \(ay)) outside view box \(vb)"); failures += 1; return
                }
            }
        }
        return failures
    }

    static func points(_ p: IslandPrimitive) -> [(Double, Double)] {
        switch p.geometry {
        case .ellipse(let cx, let cy, let rx, let ry): return [(cx - rx, cy - ry), (cx + rx, cy + ry)]
        case .rect(let x, let y, let w, let h, _): return [(x, y), (x + w, y + h)]
        case .path(let commands):
            return commands.flatMap { c -> [(Double, Double)] in
                switch c {
                case .move(let x, let y), .line(let x, let y): return [(x, y)]
                case .quad(_, _, let x, let y): return [(x, y)]
                case .cubic(_, _, _, _, let x, let y): return [(x, y)]
                case .close: return []
                }
            }
        }
    }

    static func hex(_ v: UInt32?) -> String { v.map { String(format: "#%06X", $0) } ?? "none" }

    static func render(_ art: IslandArt) -> String {
        let vb = art.viewBox
        var s = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(vb.width * 4)\" height=\"\(vb.height * 4)\" viewBox=\"\(vb.x) \(vb.y) \(vb.width) \(vb.height)\"><rect x=\"\(vb.x)\" y=\"\(vb.y)\" width=\"\(vb.width)\" height=\"\(vb.height)\" fill=\"#080808\"/>"
        walk(art) { p in
            let style = "fill=\"\(hex(p.paint.fill))\" stroke=\"\(hex(p.paint.stroke))\" stroke-width=\"\(p.paint.width)\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
            let t = "transform=\"translate(\(p.x) \(p.y)) scale(\(p.scale))\""
            switch p.geometry {
            case .ellipse(let cx, let cy, let rx, let ry):
                s += "<ellipse cx=\"\(cx)\" cy=\"\(cy)\" rx=\"\(rx)\" ry=\"\(ry)\" \(t) \(style)/>"
            case .rect(let x, let y, let w, let h, let r):
                s += "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(w)\" height=\"\(h)\" rx=\"\(r)\" \(t) \(style)/>"
            case .path(let commands):
                let d = commands.map { c -> String in
                    switch c {
                    case .move(let x, let y): return "M\(x) \(y)"
                    case .line(let x, let y): return "L\(x) \(y)"
                    case .quad(let cx, let cy, let x, let y): return "Q\(cx) \(cy) \(x) \(y)"
                    case .cubic(let a, let b, let c, let d, let x, let y): return "C\(a) \(b) \(c) \(d) \(x) \(y)"
                    case .close: return "Z"
                    }
                }.joined(separator: " ")
                s += "<path d=\"\(d)\" \(t) \(style)/>"
            }
        }
        return s + "</svg>"
    }
}
