import DoddyCore
import SwiftUI
import UIKit
import XCTest
@testable import Doddy

/// ADR-546: his eyes on Home are only drawn if the app has the pictures (every cut eye, and every
/// picture the face table measures, at the size those measurements assume), and the pieces land on
/// the eyes the picture drew.
final class DoddyEyesAssetsTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.set(false, forKey: PreferenceKey.hideCharacterArt)
    }

    func testEveryCutEyeIsInTheApp() {
        XCTAssertEqual(DoddyEyes.pieceAssets.count, 20)
        for asset in DoddyEyes.pieceAssets {
            let image = UIImage(named: asset)
            XCTAssertNotNil(image, asset)
            // An eye is a few points across, never a picture.
            XCTAssertLessThan(image?.size.width ?? 99, 12, asset)
            XCTAssertLessThan(image?.size.height ?? 99, 12, asset)
        }
    }

    func testEveryPictureWithAMeasuredFaceIsThereAtTheSizeTheMeasurementsAssume() {
        XCTAssertTrue(DoddyEyes.hasFace(IslandPose.crosslegged.assetName), "Home's Doddy")
        for asset in DoddyEyes.pictureAssets {
            guard let image = UIImage(named: asset) else { return XCTFail("\(asset) is missing") }
            // The face table is in pixels of the @3x file, 300 x 450: 100 x 150 points at any scale.
            XCTAssertEqual(image.size.width, DoddyEyes.pictureWidth / 3, accuracy: 0.5, asset)
            XCTAssertEqual(image.size.height, DoddyEyes.pictureHeight / 3, accuracy: 0.5, asset)
        }
    }

    // MARK: Drawn for real

    private struct Pixels {
        var width: Int
        var height: Int
        var data: [UInt8]

        /// Brightness (0 to 255) of one pixel, or -1 where the picture is transparent.
        func brightness(x: Int, y: Int) -> Double {
            guard (0..<width).contains(x), (0..<height).contains(y) else { return -1 }
            let i = (y * width + x) * 4
            guard data[i + 3] > 200 else { return -1 }
            return (Double(data[i]) + Double(data[i + 1]) + Double(data[i + 2])) / 3
        }
    }

    @MainActor
    private func render(_ look: DoddyLook) -> Pixels? {
        let eyes = HomeEyesModel()
        eyes.show(look)
        let renderer = ImageRenderer(content: HomeDoddyFigure(pose: .crosslegged, height: 190, eyes: eyes))
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

    /// Where a pixel of the picture's @3x file lands in the render (as `HomeDoddyFigure` crops it).
    private func renderPoint(x: Double, y: Double) -> (x: Int, y: Int) {
        let box = IslandPose.crosslegged.figure
        let width = 190 / (box.height * 1.5)
        let unit = width / DoddyEyes.pictureWidth
        return (Int(((x * unit - box.x * width) * 3).rounded()), Int(((y * unit - box.y * width * 1.5) * 3).rounded()))
    }

    /// With his eyes closed, the spot where each of the picture's eyes was is paper; at you, it is
    /// ink; and nothing but the area round his eyes changes.
    @MainActor
    func testClosedEyesCoverThePicturesOwnEyesAndChangeNothingElse() throws {
        let asset = IslandPose.crosslegged.assetName
        let atYou = try XCTUnwrap(render(.atYou), "the picture renders")
        let closed = try XCTUnwrap(render(.closed))
        XCTAssertEqual(atYou.width, closed.width)
        XCTAssertEqual(atYou.height, closed.height)
        let covers = DoddyEyes.layers(for: asset, look: .closed).filter {
            if case .cover = $0.kind { return true } else { return false }
        }
        XCTAssertEqual(covers.count, 2)
        for cover in covers {
            let p = renderPoint(x: cover.x, y: cover.y)
            XCTAssertLessThan(atYou.brightness(x: p.x, y: p.y), 90, "his own eye is ink at \(p)")
            XCTAssertGreaterThan(closed.brightness(x: p.x, y: p.y), 200, "closed, that spot is paper at \(p)")
        }
        let topLeft = renderPoint(x: covers.map(\.x).min()! - 24, y: covers.map(\.y).min()! - 24)
        let bottomRight = renderPoint(x: covers.map(\.x).max()! + 24, y: covers.map(\.y).max()! + 24)
        var changed = 0
        for y in 0..<atYou.height {
            for x in 0..<atYou.width {
                let i = (y * atYou.width + x) * 4
                guard (0..<4).contains(where: { abs(Int(atYou.data[i + $0]) - Int(closed.data[i + $0])) > 3 }) else { continue }
                let inside = x >= topLeft.x && x <= bottomRight.x && y >= topLeft.y && y <= bottomRight.y
                guard inside else { return XCTFail("a pixel changed away from his eyes at (\(x), \(y))") }
                changed += 1
            }
        }
        XCTAssertGreaterThan(changed, 40, "the eyes did change")
    }

    @MainActor
    func testAtYouIsThePictureAsDrawnAndALookIsNot() throws {
        let atYou = try XCTUnwrap(render(.atYou))
        let again = try XCTUnwrap(render(.gaze(column: 1, row: 1)))
        let upRight = try XCTUnwrap(render(.gaze(column: 2, row: 0)))
        XCTAssertEqual(atYou.data, again.data)
        XCTAssertNotEqual(atYou.data, upRight.data)
    }

    @MainActor
    func testAFingerSetsTheLookAndItComesBackAfterTheFingerLifts() async throws {
        let eyes = HomeEyesModel()
        // His eyes at (100, 300) on the screen.
        let unit = 1.0
        eyes.pictureMoved(asset: IslandPose.crosslegged.assetName,
                          frame: CGRect(x: 100 - DoddyEyes.eyesCentre(IslandPose.crosslegged.assetName)!.x * unit,
                                        y: 300 - DoddyEyes.eyesCentre(IslandPose.crosslegged.assetName)!.y * unit,
                                        width: DoddyEyes.pictureWidth * unit, height: DoddyEyes.pictureHeight * unit))
        eyes.fingerMoved(to: CGPoint(x: 400, y: 300))
        XCTAssertEqual(eyes.look, .gaze(column: 2, row: 1))
        eyes.setPressed(true)
        XCTAssertEqual(eyes.look, .half, "pressed: half closed")
        eyes.setPressed(false)
        eyes.fingerLifted(at: CGPoint(x: 400, y: 300))
        XCTAssertEqual(eyes.look, .gaze(column: 2, row: 1), "still there just after it lifts")
        try await Task.sleep(for: .seconds(0.6))
        XCTAssertEqual(eyes.look, .atYou, "back at you")
    }
}
