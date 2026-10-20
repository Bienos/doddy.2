import DoddyCore
import SwiftUI
import UIKit
import XCTest
@testable import Doddy

/// MV7 (ADR-558): the eyes the engine can choose are only drawn if the app has the pictures: every
/// cut eye, and every picture the face table measures, in the size those measurements assume.
final class MotionFaceAssetsTests: XCTestCase {
    func testEveryCutEyeIsInTheApp() {
        XCTAssertEqual(MotionFace.pieceAssets.count, 20)
        for asset in MotionFace.pieceAssets {
            let image = UIImage(named: asset)
            XCTAssertNotNil(image, asset)
            // An eye is a few points across, never a picture.
            XCTAssertLessThan(image?.size.width ?? 99, 12, asset)
            XCTAssertLessThan(image?.size.height ?? 99, 12, asset)
        }
    }

    func testEveryPictureWithAMeasuredFaceIsThereAtTheSizeTheMeasurementsAssume() {
        XCTAssertEqual(MotionFace.pictures.count, 10)
        for picture in MotionFace.pictures {
            let asset = DoddyFigureMetrics.picture(picture).asset
            guard let image = UIImage(named: asset) else { return XCTFail("\(asset) is missing") }
            // The face table is in pixels of the @3x file, 300 x 450: 100 x 150 points at any scale.
            XCTAssertEqual(image.size.width, MotionFace.pictureWidth / 3, accuracy: 0.5, asset)
            XCTAssertEqual(image.size.height, MotionFace.pictureHeight / 3, accuracy: 0.5, asset)
        }
    }

    func testTheArtTheDirectorBuildsCarriesTheEyesAndTheirLayers() {
        var art = MotionArt(picture: .strip("idle", 1))
        XCTAssertTrue(art.faceLayers.isEmpty, "at you: the picture as drawn")
        art.eyes = .half
        XCTAssertEqual(art.faceLayers.count, 4)
        XCTAssertEqual(art.eyes.marker, "doddy.eyes.half")
        art.picture = .strip("jump", 3)
        XCTAssertTrue(art.faceLayers.isEmpty, "no front eyes on a three-quarter head")
    }

    // MARK: Drawn for real

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
    }

    @MainActor
    private func render(_ picture: MotionArt.Picture, eyes: MotionEyes) -> Pixels? {
        let figure = DoddyFigure(art: MotionArt(picture: picture, eyes: eyes), x: 0, y: 0, scale: 1, opacity: 1)
        let renderer = ImageRenderer(content: PersistentDoddyView(figure: figure, spot: "test"))
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

    /// The pieces are laid on the real drawing: with his eyes closed, the spot where each of his
    /// own eyes was is paper; at you, it is ink; and nothing but his face changes.
    @MainActor
    func testClosedEyesCoverTheEyesTheirPictureDrewAndChangeNothingElse() throws {
        let picture = MotionArt.Picture.strip("idle", 1)
        let atYou = try XCTUnwrap(render(picture, eyes: .atYou), "the picture renders")
        let closed = try XCTUnwrap(render(picture, eyes: .closed))
        XCTAssertEqual(atYou.width, closed.width)
        XCTAssertEqual(atYou.height, closed.height)

        // One picture pixel is `unit` points, and the render is 3 pixels a point.
        let unit = (DoddyFigureMetrics.pictureHeight / 1.5) / MotionFace.pictureWidth
        let toRender = unit * 3
        let covers = MotionFace.layers(for: picture, eyes: .closed).filter {
            if case .cover = $0.kind { return true } else { return false }
        }
        XCTAssertEqual(covers.count, 2)
        for cover in covers {
            let x = Int((cover.x * toRender).rounded()), y = Int((cover.y * toRender).rounded())
            XCTAssertLessThan(atYou.brightness(x: x, y: y, radius: 0), 90, "his own eye is ink at (\(x), \(y))")
            XCTAssertGreaterThan(closed.brightness(x: x, y: y, radius: 0), 200, "closed, that spot is paper at (\(x), \(y))")
        }

        // Every pixel that changed is on his face, around his eyes.
        let left = covers.map(\.x).min()!, right = covers.map(\.x).max()!
        let top = covers.map(\.y).min()!, bottom = covers.map(\.y).max()!
        let box = (x0: (left - 24) * toRender, x1: (right + 24) * toRender, y0: (top - 24) * toRender, y1: (bottom + 24) * toRender)
        var changedInside = 0
        for y in 0..<atYou.height {
            for x in 0..<atYou.width {
                let i = (y * atYou.width + x) * 4
                let changed = (0..<4).contains { abs(Int(atYou.data[i + $0]) - Int(closed.data[i + $0])) > 3 }
                guard changed else { continue }
                let inside = Double(x) >= box.x0 && Double(x) <= box.x1 && Double(y) >= box.y0 && Double(y) <= box.y1
                XCTAssertTrue(inside, "a pixel changed away from his eyes at (\(x), \(y))")
                if inside { changedInside += 1 }
                if !inside { return }
            }
        }
        XCTAssertGreaterThan(changedInside, 40, "the eyes did change")
    }

    @MainActor
    func testAGazeMovesTheEyesUpAndRightAndAtYouDrawsTheUntouchedPicture() throws {
        let picture = MotionArt.Picture.strip("idle", 1)
        let atYou = try XCTUnwrap(render(picture, eyes: .atYou))
        let gaze = try XCTUnwrap(render(picture, eyes: .gaze(column: 2, row: 0)))
        let again = try XCTUnwrap(render(picture, eyes: .gaze(column: 1, row: 1)))
        XCTAssertEqual(atYou.data, again.data, "at you is exactly the picture, whichever way it is asked for")
        XCTAssertNotEqual(atYou.data, gaze.data)
        // The centre of ink of the right eye's box moved up and to the right.
        let unit = (DoddyFigureMetrics.pictureHeight / 1.5) / MotionFace.pictureWidth
        let toRender = unit * 3
        let cover = MotionFace.layers(for: picture, eyes: .gaze(column: 2, row: 0)).first!
        func inkCentre(_ p: Pixels) -> (x: Double, y: Double) {
            var sx = 0.0, sy = 0.0, n = 0.0
            let r = Int(((cover.width + 14) * toRender / 2).rounded())
            let cx = Int((cover.x * toRender).rounded()), cy = Int((cover.y * toRender).rounded())
            for y in max(0, cy - r)...min(p.height - 1, cy + r) {
                for x in max(0, cx - r)...min(p.width - 1, cx + r) {
                    let i = (y * p.width + x) * 4
                    let dark = 255 - (Double(p.data[i]) + Double(p.data[i + 1]) + Double(p.data[i + 2])) / 3
                    guard dark > 100 else { continue }
                    sx += Double(x) * dark; sy += Double(y) * dark; n += dark
                }
            }
            return (sx / n, sy / n)
        }
        let before = inkCentre(atYou), after = inkCentre(gaze)
        XCTAssertGreaterThan(after.x, before.x + 1, "looks right")
        XCTAssertLessThan(after.y, before.y - 0.5, "looks up")
    }
}
