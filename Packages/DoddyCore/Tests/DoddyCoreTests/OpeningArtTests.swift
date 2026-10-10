import XCTest
@testable import DoddyCore

final class OpeningArtTests: XCTestCase {
    /// The supplied drawings, as the app bundles them.
    private static let assets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("design/interface-v1.2/assets")

    private func drawing(_ name: String) throws -> DoddyDrawing {
        let url = Self.assets.appendingPathComponent("doddy-pose-basketball-\(name)-light-v1.3-r1.svg")
        return try SVGPoseReader.read(try String(contentsOf: url, encoding: .utf8))
    }

    func testEverySuppliedPoseReadsCompletely() throws {
        for name in ["dribble", "gather", "shot", "follow-through"] {
            let d = try drawing(name)
            XCTAssertEqual(d.size, 512)
            XCTAssertGreaterThan(d.strokes.count, 15, name)
            XCTAssertTrue(d.contains(group: "head-contour"), name)
            XCTAssertTrue(d.contains(group: "eyes"), name)
            XCTAssertTrue(d.strokes.allSatisfy { $0.stroke != nil || $0.fill != nil }, name)
            // Every coordinate lands inside the square.
            for stroke in d.strokes {
                for command in stroke.commands {
                    for (x, y) in points(command) {
                        XCTAssertTrue((-20...532).contains(x) && (-20...532).contains(y), "\(name): \(command)")
                    }
                }
            }
        }
    }

    func testTheBallIsItsOwnGroupAndTheFollowThroughHasNone() throws {
        for name in ["dribble", "gather", "shot"] {
            let d = try drawing(name)
            XCTAssertTrue(d.contains(group: "basketball"), name)
            XCTAssertFalse(d.without(group: "basketball").contains(group: "basketball"))
            XCTAssertTrue(d.strokes.contains { $0.fill == .orange }, name)
            XCTAssertFalse(d.without(group: "basketball").strokes.contains { $0.fill == .orange }, name)
        }
        XCTAssertFalse(try drawing("follow-through").contains(group: "basketball"))
    }

    func testTheBallSitsWhereTheOpeningExpectsIt() throws {
        // The measured spots in OpeningLayout came from the rendered PNGs; the vector ball must agree.
        for (name, pose) in [("dribble", OpeningPose.dribble), ("gather", .gather), ("shot", .shot)] {
            let ball = try drawing(name).strokes.filter { $0.groups.contains("basketball") }
            let xs = ball.flatMap { $0.commands.flatMap(points).map(\.0) }
            let ys = ball.flatMap { $0.commands.flatMap(points).map(\.1) }
            let cx = (xs.min()! + xs.max()!) / 2 / 512, cy = (ys.min()! + ys.max()!) / 2 / 512
            let art = try XCTUnwrap(OpeningLayout.ballInArt(pose))
            XCTAssertEqual(cx, art.centerX, accuracy: 0.012, name)
            XCTAssertEqual(cy, art.centerY, accuracy: 0.012, name)
        }
    }

    func testLimbsComeBeforeTheFace() throws {
        let d = try drawing("dribble")
        let index: (String) -> Int? = { id in d.strokes.firstIndex { $0.groups.contains(id) } }
        XCTAssertLessThan(try XCTUnwrap(index("body-spine")), try XCTUnwrap(index("head-contour")))
        XCTAssertLessThan(try XCTUnwrap(index("head-contour")), try XCTUnwrap(index("eyes")))
    }

    func testTransformsAreAppliedRightToLeft() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <g id="root"><g transform="translate(10 20) scale(2) rotate(90)"><g id="inner">
        <path d="M1,0 L2,0" fill="none" stroke="#171715" stroke-width="3"/>
        </g></g></g></svg>
        """
        let d = try SVGPoseReader.read(svg)
        XCTAssertEqual(d.size, 100)
        XCTAssertEqual(d.strokes.count, 1)
        let s = d.strokes[0]
        XCTAssertEqual(s.groups, ["root", "inner"])
        XCTAssertEqual(s.lineWidth, 6, accuracy: 1e-9, "scaled by the group")
        XCTAssertEqual(s.stroke, .ink)
        XCTAssertNil(s.fill)
        // (1,0) rotated 90° → (0,1), scaled → (0,2), translated → (10,22).
        guard case .move(let x, let y) = s.commands[0] else { return XCTFail("\(s.commands)") }
        XCTAssertEqual(x, 10, accuracy: 1e-9)
        XCTAssertEqual(y, 22, accuracy: 1e-9)
        guard case .line(let x2, let y2) = s.commands[1] else { return XCTFail("\(s.commands)") }
        XCTAssertEqual(x2, 10, accuracy: 1e-9)
        XCTAssertEqual(y2, 24, accuracy: 1e-9)
    }

    func testRotationAboutAPointKeepsThatPointStill() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
        <g transform="translate(5 5) rotate(90 10 10)"><path d="M10,10 L20,10" fill="none" stroke="#171715"/></g>
        </svg>
        """
        let s = try SVGPoseReader.read(svg).strokes[0]
        guard case .move(let x, let y) = s.commands[0], case .line(let x2, let y2) = s.commands[1] else { return XCTFail() }
        XCTAssertEqual(x, 15, accuracy: 1e-9); XCTAssertEqual(y, 15, accuracy: 1e-9)
        // (20,10) turned 90° about (10,10) → (10,20), then moved by (5,5).
        XCTAssertEqual(x2, 15, accuracy: 1e-9); XCTAssertEqual(y2, 25, accuracy: 1e-9)
    }

    func testPathsCirclesAndRepeatsAreRead() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <path d="M0 0 L1 1 2 2 Q3 3 4 4 C5 5 6 6 7 7Z M-1,-1L-2-2" fill="#FFF7E9" stroke="none"/>
        <circle cx="5" cy="5" r="2" fill="#F58A24" stroke="#171715" stroke-width="1"/>
        <ellipse cx="5" cy="5" rx="2" ry="1" fill="none" stroke="#171715" stroke-width="0.5"/>
        </svg>
        """
        let d = try SVGPoseReader.read(svg)
        XCTAssertEqual(d.strokes.count, 3)
        XCTAssertEqual(d.strokes[0].commands, [
            .move(x: 0, y: 0), .line(x: 1, y: 1), .line(x: 2, y: 2), .quad(cx: 3, cy: 3, x: 4, y: 4),
            .cubic(c1x: 5, c1y: 5, c2x: 6, c2y: 6, x: 7, y: 7), .close, .move(x: -1, y: -1), .line(x: -2, y: -2),
        ])
        XCTAssertEqual(d.strokes[0].fill, .paper)
        XCTAssertNil(d.strokes[0].stroke)
        XCTAssertEqual(d.strokes[0].lineWidth, 0)
        XCTAssertEqual(d.strokes[1].fill, .orange)
        XCTAssertEqual(d.strokes[1].commands.count, 6, "four arcs, a move and a close")
        guard case .move(let x, let y) = d.strokes[1].commands[0] else { return XCTFail() }
        XCTAssertEqual(x, 7); XCTAssertEqual(y, 5)
        XCTAssertEqual(d.strokes[2].lineWidth, 0.5)
    }

    func testAnythingUnexpectedIsRefused() {
        let head = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\">"
        XCTAssertThrowsError(try SVGPoseReader.read(head + "<rect x=\"0\" y=\"0\" width=\"1\" height=\"1\"/></svg>")) {
            XCTAssertEqual($0 as? SVGPoseReaderError, .unsupportedElement("rect"))
        }
        XCTAssertThrowsError(try SVGPoseReader.read(head + "<path d=\"M0 0 A1 1 0 0 0 1 1\" stroke=\"#171715\"/></svg>")) {
            XCTAssertEqual($0 as? SVGPoseReaderError, .unsupportedPathCommand("A"))
        }
        XCTAssertThrowsError(try SVGPoseReader.read(head + "<path d=\"M0 0 L1\" stroke=\"#171715\"/></svg>"))
        XCTAssertThrowsError(try SVGPoseReader.read(head + "<path d=\"M0 0\" stroke=\"#123456\"/></svg>")) {
            XCTAssertEqual($0 as? SVGPoseReaderError, .unknownColor("#123456"))
        }
        XCTAssertThrowsError(try SVGPoseReader.read(head + "<g transform=\"skewX(10)\"><path d=\"M0 0\"/></g></svg>")) {
            XCTAssertEqual($0 as? SVGPoseReaderError, .unsupportedTransform("skewX(10)"))
        }
        XCTAssertThrowsError(try SVGPoseReader.read("<html></html>")) {
            XCTAssertEqual($0 as? SVGPoseReaderError, .notAnSVG)
        }
    }

    private func points(_ command: PathCommand) -> [(Double, Double)] {
        switch command {
        case .move(let x, let y), .line(let x, let y): [(x, y)]
        case .quad(let cx, let cy, let x, let y): [(cx, cy), (x, y)]
        case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y): [(c1x, c1y), (c2x, c2y), (x, y)]
        case .close: []
        }
    }
}
