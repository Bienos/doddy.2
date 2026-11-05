import XCTest
@testable import DoddyCore

final class WelcomeFlowTests: XCTestCase {
    func testFiveChaptersEachWithItsOwnPose() {
        XCTAssertEqual(WelcomeChapter.count, 5)
        XCTAssertEqual(WelcomeFlow.lastPage, 4)
        XCTAssertEqual(WelcomeChapter.allCases.map(\.rawValue), [0, 1, 2, 3, 4])
        let poses = WelcomeChapter.allCases.map(\.pose)
        XCTAssertEqual(Set(poses).count, 5, "every chapter has a different pose")
        for pose in WelcomePose.allCases {
            XCTAssertTrue(pose.assetName.hasPrefix("WholeDoddy_"), "only the owner's pack pictures")
            XCTAssertTrue((0.5...1.0).contains(pose.soleFraction))
        }
    }

    func testProgressIsClampedAtBothEnds() {
        XCTAssertEqual(WelcomeFlow.clamped(-0.4), 0)
        XCTAssertEqual(WelcomeFlow.clamped(4.6), 4)
        XCTAssertEqual(WelcomeFlow.clamped(2.25), 2.25)
        XCTAssertEqual(WelcomeFlow.clamped(.nan), 0)
        XCTAssertEqual(WelcomeFlow.clamped(.infinity), 0)
        XCTAssertEqual(WelcomeFlow.page(at: 1.4), 1)
        XCTAssertEqual(WelcomeFlow.page(at: 1.6), 2)
        XCTAssertEqual(WelcomeFlow.page(at: 99), 4, "a rubber-band overshoot still reads as the last page")
        XCTAssertEqual(WelcomeFlow.page(at: -3), 0)
    }

    func testPosesSwapInTheMiddleOfAPageChange() {
        // On a page, only its pose is drawn.
        for chapter in 0...4 {
            for other in 0...4 {
                let opacity = WelcomeFlow.poseOpacity(chapter: other, progress: Double(chapter))
                XCTAssertEqual(opacity, other == chapter ? 1 : 0, accuracy: 1e-9)
            }
        }
        // Half way between two pages, both are at one half: the swap happens at the top of the hop.
        XCTAssertEqual(WelcomeFlow.poseOpacity(chapter: 1, progress: 1.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(WelcomeFlow.poseOpacity(chapter: 2, progress: 1.5), 0.5, accuracy: 1e-9)
        // Early in the change the old pose is still fully there; late, the new one is.
        XCTAssertEqual(WelcomeFlow.poseOpacity(chapter: 1, progress: 1.3), 1, accuracy: 1e-9)
        XCTAssertEqual(WelcomeFlow.poseOpacity(chapter: 2, progress: 1.7), 1, accuracy: 1e-9)
        XCTAssertEqual(WelcomeFlow.poseOpacity(chapter: 2, progress: 1.3), 0, accuracy: 1e-9)
    }

    func testHopPeaksInTheMiddleAndIsZeroOnAPage() {
        for page in 0...4 {
            XCTAssertEqual(WelcomeFlow.hop(progress: Double(page)), 0, accuracy: 1e-9, "no hop on the spot")
            XCTAssertEqual(WelcomeFlow.tilt(progress: Double(page)), 0, accuracy: 1e-9)
        }
        XCTAssertEqual(WelcomeFlow.hop(progress: 2.5), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(WelcomeFlow.hop(progress: 2.25), 0.5)
        XCTAssertEqual(WelcomeFlow.hop(progress: 2.25), WelcomeFlow.hop(progress: 2.75), accuracy: 1e-9)
        // Past the last page (rubber-band) he stays on the ground.
        XCTAssertEqual(WelcomeFlow.hop(progress: 4.4), 0, accuracy: 1e-9)
        // He leans one way, then the other.
        XCTAssertLessThan(WelcomeFlow.tilt(progress: 1.25), 0)
        XCTAssertGreaterThan(WelcomeFlow.tilt(progress: 1.75), 0)
    }

    func testTextIsFullOnItsPageAndGoneBeforeTheNextIsHalfIn() {
        XCTAssertEqual(WelcomeFlow.textOpacity(chapter: 3, progress: 3), 1)
        XCTAssertEqual(WelcomeFlow.textOpacity(chapter: 3, progress: 2), 0, accuracy: 1e-9)
        XCTAssertEqual(WelcomeFlow.textOpacity(chapter: 3, progress: 3.5), 0.375, accuracy: 1e-9)
        XCTAssertEqual(WelcomeFlow.textOpacity(chapter: 3, progress: 3.8), 0, accuracy: 1e-9)
        // It slides towards the side it comes from.
        XCTAssertEqual(WelcomeFlow.textOffset(chapter: 1, progress: 0), 46, accuracy: 1e-9)
        XCTAssertEqual(WelcomeFlow.textOffset(chapter: 1, progress: 2), -46, accuracy: 1e-9)
        XCTAssertEqual(WelcomeFlow.textOffset(chapter: 1, progress: 1), 0, accuracy: 1e-9)
    }

    func testGroundMovesWithThePagesAndTheSkylineSlower() {
        XCTAssertEqual(WelcomeFlow.groundOffset(progress: 0, pageWidth: 390), 0)
        XCTAssertEqual(WelcomeFlow.groundOffset(progress: 2, pageWidth: 390), -780, accuracy: 1e-9)
        XCTAssertEqual(WelcomeFlow.skylineOffset(progress: 2, pageWidth: 390), -351, accuracy: 1e-9)
        XCTAssertEqual(WelcomeFlow.skylineOffset(progress: 9, pageWidth: 390), -4 * 390 * 0.45, accuracy: 1e-9, "clamped")
    }

    func testWelcomeShowsOnlyOnANewInstallationUnlessForcedOrReplayed() {
        // A new installation, not seen yet.
        XCTAssertTrue(WelcomeRule.shouldShow(seen: false, firstInstallation: true, replayRequested: false, override: nil))
        // Seen: never again.
        XCTAssertFalse(WelcomeRule.shouldShow(seen: true, firstInstallation: true, replayRequested: false, override: nil))
        // An older installation that updates is not surprised.
        XCTAssertFalse(WelcomeRule.shouldShow(seen: false, firstInstallation: false, replayRequested: false, override: nil))
        // Settings › Show the welcome again.
        XCTAssertTrue(WelcomeRule.shouldShow(seen: true, firstInstallation: false, replayRequested: true, override: nil))
        // UI tests: the launch argument wins over everything.
        XCTAssertTrue(WelcomeRule.shouldShow(seen: true, firstInstallation: false, replayRequested: false, override: true))
        XCTAssertFalse(WelcomeRule.shouldShow(seen: false, firstInstallation: true, replayRequested: true, override: false))
    }

    func testTimelineFractionsAndTyping() {
        XCTAssertEqual(WelcomeTimeline.fraction(0.2, start: 0.5, duration: 1), 0)
        XCTAssertEqual(WelcomeTimeline.fraction(1.0, start: 0.5, duration: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(WelcomeTimeline.fraction(9, start: 0.5, duration: 1), 1)
        XCTAssertEqual(WelcomeTimeline.fraction(1, start: 1, duration: 0), 1)
        XCTAssertEqual(WelcomeTimeline.easeOut(0), 0)
        XCTAssertEqual(WelcomeTimeline.easeOut(1), 1)
        XCTAssertGreaterThan(WelcomeTimeline.easeOut(0.5), 0.5)

        let text = "Dzień dobry!"
        XCTAssertEqual(WelcomeTimeline.typed(text, elapsed: 0, start: 0.3, duration: 1), "")
        XCTAssertEqual(WelcomeTimeline.typed(text, elapsed: 99, start: 0.3, duration: 1), text)
        let half = WelcomeTimeline.typed(text, elapsed: 0.8, start: 0.3, duration: 1)
        XCTAssertEqual(half, "Dzień ", "whole characters, a prefix of the text")
        XCTAssertTrue(text.hasPrefix(half))
    }

    func testPeckComesInTwoQuickBurstsEveryCycle() {
        XCTAssertEqual(WelcomeTimeline.peck(0), 0)
        XCTAssertEqual(WelcomeTimeline.peck(3.6 * 0.66), 1, accuracy: 0.01)
        XCTAssertEqual(WelcomeTimeline.peck(3.6 * 0.74), 0, accuracy: 1e-9)
        XCTAssertEqual(WelcomeTimeline.peck(3.6 * 0.82), 1, accuracy: 0.01)
        XCTAssertEqual(WelcomeTimeline.peck(3.6 + 3.6 * 0.66), 1, accuracy: 0.01, "repeats")
        XCTAssertEqual(WelcomeTimeline.peck(-3.6 * 0.34), 1, accuracy: 0.01, "a negative time wraps instead of crashing")
    }
}
