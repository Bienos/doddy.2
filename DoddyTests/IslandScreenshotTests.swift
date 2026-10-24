import SwiftUI
import UIKit
import XCTest
@testable import Doddy

/// The Dynamic Island's own SwiftUI pieces (what `DoddyVoiceLiveActivity` puts into the island's
/// regions), drawn off screen in the states a conversation goes through (owner, 24 Oct 2026,
/// ADR-607): only his head on the compact island, all of him in his light on the expanded one,
/// and the bolder waves.
///
/// The pictures go to `build/island-screenshots/` (the hosted Mac job keeps that folder) and are
/// attached to the test result. They are drawn by ImageRenderer from sample states: not iOS's own
/// island (iOS lays the regions out itself) and not a conversation. `MemoryBaselineTests` keeps
/// the native screenshots, of the offline fixture.
final class IslandScreenshotTests: XCTestCase {
    private typealias State = DoddyVoiceAttributes.ContentState

    private static func scene(_ status: State.Status, muted: Bool = false, style: IslandStyle = .wholeDoddy) -> IslandScene {
        var state = State(status: status, isMuted: muted)
        state.islandStyle = style
        return state.islandScene(isStale: false)
    }

    /// The states shown, in a conversation's order.
    private static let samples: [(file: String, name: String, status: State.Status, muted: Bool)] = [
        ("1-connecting", "Connecting", .connecting, false),
        ("2-listening", "Listening: he hears you", .listening, false),
        ("3-speaking", "Speaking: the whole island in waves", .speaking, false),
        ("4-thinking", "Working on it", .thinking, false),
        ("5-muted", "Muted", .listening, true),
        ("6-confirm", "A card waits in Doddy", .needsConfirmation, false),
    ]

    // MARK: What the owner asked for

    /// Small island: his head only, a 26 pt circle, never the whole of him at 30 pt (ADR-607).
    @MainActor
    func testTheCompactIslandShowsOnlyHisHead() throws {
        for sample in Self.samples {
            let scene = Self.scene(sample.status, muted: sample.muted)
            XCTAssertNotNil(scene.pose, "\(sample.name): Whole Doddy has a pose")
            let head = try XCTUnwrap(pixels(IslandCompactLeadingView(scene: scene)), sample.name)
            XCTAssertEqual(head.width, 26 * 3, "\(sample.name): one 26 pt head")
            XCTAssertEqual(head.height, 26 * 3, "\(sample.name): as tall as wide, not a 22 x 30 figure")
            // His face is cream: the picture loaded and the crop is on his head, not his legs.
            XCTAssertGreaterThan(head.brightest(inMiddleThird: true), 200, "\(sample.name): his cream face")
        }
    }

    /// Big island: all of him (the pose, standing in an 82 x 118 pt box) with a 1.5 pt cream edge
    /// and only a faint light behind him (owner: he doesn't need to be lit up so much).
    @MainActor
    func testTheExpandedIslandShowsAllOfHimWithAFaintLight() throws {
        let scene = Self.scene(.listening)
        XCTAssertEqual(scene.pose, .listening)
        let figure = try XCTUnwrap(pixels(IslandPoseView(pose: .listening, maxSize: CGSize(width: 82, height: 118),
                                                         edgeWidth: 1.5)))
        XCTAssertEqual(figure.height, 118 * 3)
        let light = try XCTUnwrap(pixels(IslandDoddyLight().background(Color.islandBlack)))
        XCTAssertEqual(light.width, 110 * 3)
        let middle = light.brightness(x: light.width / 2, y: light.height / 2)
        XCTAssertGreaterThan(middle, 30, "a little light in the middle")
        XCTAssertLessThan(middle, 80, "only a little: not a spotlight")
        XCTAssertLessThan(light.brightness(x: 2, y: light.height / 2), 15, "black at the edge")
    }

    /// The waves are 2 pt or more (owner: the 1.3 pt lines were too thin), and a thick line on the
    /// narrow compact island keeps at least six line widths per wave.
    func testTheWavesAreBoldAndStayWavesWhenNarrow() {
        for kind in [IslandWavesView.Kind.line, .full, .speech] {
            for wave in IslandWavesView.waves(kind) {
                XCTAssertGreaterThanOrEqual(wave.width, 2, "\(kind)")
            }
        }
        let main = IslandWavesView.waves(.line)[0]
        XCTAssertEqual(IslandWaveLine.waveCount(main, width: 240), main.frequency, "a wide line keeps its waves")
        XCTAssertEqual(IslandWaveLine.waveCount(main, width: 42), main.frequency, "the compact line too")
        XCTAssertEqual(IslandWaveLine.waveCount(main, width: 12), 12 / 18, accuracy: 0.001, "fewer, never a zigzag")
    }

    /// His talking waves start together beside him, spread out to the right and stay inside
    /// their band under his status (owner: not across the whole island, and not behind him).
    func testHisTalkingWavesStartBesideHimAndStayInTheirBand() {
        let lines = IslandWavesView.waves(.speech).map {
            IslandWaveLine(wave: $0, shape: .fromLeading(centre: IslandWavesView.speechCentre), phase: 0)
        }
        for line in lines {
            XCTAssertEqual(line.y(at: 0, waves: line.wave.frequency), IslandWavesView.speechCentre, accuracy: 0.0001)
            for step in 0...200 {
                let y = line.y(at: Double(step) / 200, waves: line.wave.frequency)
                XCTAssertTrue((0...1).contains(y), "inside the band at \(step)")
            }
        }
        let atEnd = lines.map { $0.y(at: 1, waves: $0.wave.frequency) }
        XCTAssertGreaterThan((atEnd.max() ?? 0) - (atEnd.min() ?? 0), 0.4, "spread out by the end")
    }

    // MARK: The pictures

    @MainActor
    func testDrawTheIslandInEveryState() throws {
        let startedAt = Date(timeIntervalSinceNow: -83)
        var boards: [IslandBoardPicture] = []
        for sample in Self.samples {
            let board = IslandBoardPicture(name: sample.name, scene: Self.scene(sample.status, muted: sample.muted),
                                           muted: sample.muted, startedAt: startedAt)
            _ = try keep(board.padding(16).background(Self.backdrop), name: sample.file)
            boards.append(board)
        }
        let all = boards
        let sheet = VStack(alignment: .leading, spacing: 22) {
            Text(verbatim: "Doddy's Dynamic Island, drawn at 3x from the widget's own views (ImageRenderer). Sample states: not a conversation and not iOS's island.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(width: 371, alignment: .leading)
            ForEach(all.indices, id: \.self) { all[$0] }
        }
        .padding(20)
        .background(Self.backdrop)
        let image = try keep(sheet, name: "0-all-states")
        XCTAssertGreaterThan(image.size.height, 160 * CGFloat(Self.samples.count))
    }

    private static let backdrop = Color(red: 0.23, green: 0.23, blue: 0.25)

    // MARK: Helpers

    private static var outputFolder: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/island-screenshots", isDirectory: true)
    }

    /// Renders at 3x, attaches the picture and writes it to `build/island-screenshots/`.
    @MainActor
    private func keep(_ view: some View, name: String) throws -> UIImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage, "\(name) renders")
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let data = image.pngData() {
            do {
                try FileManager.default.createDirectory(at: Self.outputFolder, withIntermediateDirectories: true)
                try data.write(to: Self.outputFolder.appendingPathComponent("\(name).png"))
            } catch {
                // Where the source folder can't be written (a device), the attachment still has it.
            }
        }
        return image
    }

    private struct Pixels {
        var width: Int
        var height: Int
        var data: [UInt8]

        /// Mean brightness (0 to 255) of a small box around a point, where the picture is opaque.
        func brightness(x: Int, y: Int, radius: Int = 1) -> Double {
            var sum = 0.0, n = 0.0
            for yy in max(0, y - radius)...min(height - 1, y + radius) {
                for xx in max(0, x - radius)...min(width - 1, x + radius) {
                    let i = (yy * width + xx) * 4
                    guard data[i + 3] > 200 else { continue }
                    sum += (Double(data[i]) + Double(data[i + 1]) + Double(data[i + 2])) / 3
                    n += 1
                }
            }
            return n > 0 ? sum / n : -1
        }

        /// The brightest opaque pixel, in the whole picture or its middle third.
        func brightest(inMiddleThird: Bool) -> Double {
            let xs = inMiddleThird ? (width / 3)..<(2 * width / 3) : 0..<width
            let ys = inMiddleThird ? (height / 3)..<(2 * height / 3) : 0..<height
            var best = -1.0
            for y in ys {
                for x in xs {
                    let i = (y * width + x) * 4
                    guard data[i + 3] > 200 else { continue }
                    best = max(best, (Double(data[i]) + Double(data[i + 1]) + Double(data[i + 2])) / 3)
                }
            }
            return best
        }
    }

    @MainActor
    private func pixels(_ view: some View) -> Pixels? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        guard let cg = renderer.uiImage?.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return Pixels(width: w, height: h, data: data)
    }
}

/// One state: the expanded island (371 pt wide, the camera's place drawn in dark grey), then the
/// compact (230 x 36.67 pt) and minimal (45 pt) islands, laid out with the boards' sizes
/// (design/dynamic-island-v4/Design-notes.md). The buttons are the widget's pills, drawn only.
private struct IslandBoardPicture: View {
    let name: String
    let scene: IslandScene
    let muted: Bool
    let startedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
            expanded
            HStack(spacing: 12) {
                compact
                IslandMinimalView(scene: scene, startedAt: startedAt)
                    .frame(width: 45, height: 36.67)
                    .background(Color.islandBlack, in: Capsule())
            }
        }
    }

    private var expanded: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                IslandLabelView(scene: scene)
                    .padding(.leading, 8)
                Spacer(minLength: 129)
                IslandTimeView(scene: scene, startedAt: startedAt)
                    .padding(.trailing, 8)
            }
            .frame(height: 29)
            IslandBottomView(scene: scene, startedAt: startedAt) {
                HStack(spacing: 6) {
                    IslandPillLabel(title: muted ? "Unmute" : "Mute",
                                    systemImage: muted ? "mic.fill" : "mic.slash.fill", prominent: muted)
                    IslandPillLabel(title: "Open", systemImage: "arrow.up.forward.app")
                    IslandPillLabel(title: "Stop", systemImage: "stop.fill")
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .padding(.horizontal, 14)
        .frame(width: 371)
        .background(Color.islandBlack)
        .overlay(alignment: .top) {
            // The camera's place (Design-notes.md: x 122.83, y 8, 125.34 x 29 pt).
            Capsule()
                .fill(Color(white: 0.12))
                .frame(width: 125.34, height: 29)
                .padding(.top, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
    }

    private var compact: some View {
        HStack(spacing: 0) {
            IslandCompactLeadingView(scene: scene)
                .frame(width: 52.33)
            Spacer(minLength: 0)
            IslandCompactTrailingView(scene: scene, startedAt: startedAt)
                .frame(width: 52.33)
        }
        .frame(width: 230, height: 36.67)
        .background(Color.islandBlack, in: Capsule())
    }
}
