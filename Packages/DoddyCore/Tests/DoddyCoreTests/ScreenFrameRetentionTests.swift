import XCTest
@testable import DoddyCore

/// The last picture of the screen is not kept longer than it is useful: gone at launch, and gone when Doddy
/// comes back to the front unless it belongs to a share that is still running (decision
/// 2026-11-09-doddy-looks-at-the-screen; the files are `ScreenShareFiles`).
final class ScreenFrameRetentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(live: Bool = true, frameAgo: TimeInterval? = 1) -> ScreenShareState {
        ScreenShareState(live: live, startedAt: now.addingTimeInterval(-600),
                         frameAt: frameAgo.map { now.addingTimeInterval(-$0) }, frameBytes: frameAgo == nil ? nil : 64)
    }

    private func deletes(_ moment: ScreenFrameRetention.Moment, exists: Bool = true, _ state: ScreenShareState?) -> Bool {
        ScreenFrameRetention.shouldDeleteFrame(at: moment, frameExists: exists, state: state, now: now)
    }

    func testThereIsNothingToDeleteWithoutAPicture() {
        for moment in [ScreenFrameRetention.Moment.launch, .foreground] {
            XCTAssertFalse(deletes(moment, exists: false, state()))
            XCTAssertFalse(deletes(moment, exists: false, nil))
        }
    }

    func testAPictureLeftFromBeforeThisLaunchIsAlwaysDeleted() {
        XCTAssertTrue(deletes(.launch, state(frameAgo: 1)), "even a fresh one: the next one is written within a second")
        XCTAssertTrue(deletes(.launch, state(live: false)))
        XCTAssertTrue(deletes(.launch, nil), "a picture with no state file is a leftover")
        XCTAssertTrue(deletes(.launch, state(frameAgo: 86_400)))
    }

    func testBackInFrontKeepsOnlyThePictureOfAShareThatIsStillRunning() {
        XCTAssertFalse(deletes(.foreground, state(frameAgo: 1)))
        XCTAssertFalse(deletes(.foreground, state(frameAgo: ScreenFrameRetention.staleAfter)), "exactly at the limit still counts")
        XCTAssertTrue(deletes(.foreground, state(frameAgo: ScreenFrameRetention.staleAfter + 1)))
        XCTAssertTrue(deletes(.foreground, state(frameAgo: 3_600)))
    }

    func testBackInFrontDeletesAPictureThatBelongsToNoShare() {
        XCTAssertTrue(deletes(.foreground, nil), "no state file: sharing never started or was cleaned up")
        XCTAssertTrue(deletes(.foreground, state(live: false)), "sharing ended")
        XCTAssertTrue(deletes(.foreground, state(frameAgo: nil)), "a share that has taken no picture yet has no picture to keep")
    }

    func testAClockFarOffDoesNotKeepAPicture() {
        XCTAssertFalse(deletes(.foreground, state(frameAgo: -2)), "a little skew is fine")
        XCTAssertTrue(deletes(.foreground, state(frameAgo: -(ScreenShare.freshFor + 1))), "a picture from the far future can't be trusted")
    }

    func testTheLimitIsAFewMinutesAndAgreesWithWhenHomeStopsSayingShared() {
        XCTAssertEqual(ScreenFrameRetention.staleAfter, ScreenShareIndicator.shownFor)
        XCTAssertGreaterThan(ScreenFrameRetention.staleAfter, ScreenShare.freshFor, "longer than the app would still send it")
        XCTAssertLessThanOrEqual(ScreenFrameRetention.staleAfter, 5 * 60)
    }
}
