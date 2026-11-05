import XCTest
@testable import DoddyCore

final class BackTapSetupTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func coordinatorAtTest(now: Date) -> BackTapSetupCoordinator {
        var c = BackTapSetupCoordinator()
        XCTAssertEqual(c.handle(.start), .accepted)
        XCTAssertEqual(c.phase, .guiding)
        XCTAssertEqual(c.handle(.startTest(now: now)), .accepted)
        return c
    }

    func testGuideNamesTheManualPathAndBothShortcuts() {
        XCTAssertEqual(BackTapGuide.settingsPath, ["Settings", "Accessibility", "Touch", "Back Tap", "Double Tap", "Talk to Doddy"])
        XCTAssertEqual(BackTapGuide.appShortcutTitle, "Talk to Doddy")
        XCTAssertEqual(BackTapGuide.fallbackShortcutName, "Open Doddy")
        XCTAssertEqual(BackTapGuide.version, 2, "the guide changed from six cards to one screen")
    }

    func testHappyPathEndsInUserReportedTested() {
        var c = coordinatorAtTest(now: t0)
        XCTAssertEqual(c.handle(.receipt(ShortcutReceipt(receivedAt: t0.addingTimeInterval(20)))), .accepted)
        XCTAssertEqual(c.handle(.confirmDoubleTap(now: t0.addingTimeInterval(25))), .accepted)
        XCTAssertEqual(c.phase, .userReportedTested(at: t0.addingTimeInterval(25)))
        XCTAssertTrue(c.isDone)
        XCTAssertEqual(c.summary.status, .userReportedTested)
        XCTAssertEqual(c.summary.testedAt, t0.addingTimeInterval(25))
        XCTAssertNil(c.summary.activeTest)
    }

    func testNoCompletionWithoutAReceipt() {
        var c = coordinatorAtTest(now: t0)
        XCTAssertEqual(c.handle(.confirmDoubleTap(now: t0.addingTimeInterval(5))), .ignored("no shortcut received yet"))
        XCTAssertFalse(c.isDone)
        var fresh = BackTapSetupCoordinator()
        XCTAssertEqual(fresh.handle(.confirmDoubleTap(now: t0)), .ignored("no test to confirm"))
        XCTAssertEqual(fresh.phase, .notStarted)
    }

    func testReceiptOutsideAnActiveTestIsIgnored() {
        var c = BackTapSetupCoordinator()
        XCTAssertEqual(c.handle(.receipt(ShortcutReceipt(receivedAt: t0))), .ignored("no active test"))
        XCTAssertEqual(c.phase, .notStarted)
        c.handle(.start)
        XCTAssertEqual(c.handle(.receipt(ShortcutReceipt(receivedAt: t0))), .ignored("no active test"))
        XCTAssertEqual(c.phase, .guiding)
    }

    func testStaleAndEarlyReceiptsAreIgnored() {
        var c = coordinatorAtTest(now: t0)
        let late = t0.addingTimeInterval(BackTapSetupCoordinator.testWindowDuration + 1)
        XCTAssertEqual(c.handle(.receipt(ShortcutReceipt(receivedAt: late))), .ignored("test window expired"))
        XCTAssertEqual(c.handle(.receipt(ShortcutReceipt(receivedAt: t0.addingTimeInterval(-1)))), .ignored("receipt predates the test"))
        guard case .testing = c.phase else { return XCTFail("still testing, so the user can start again") }
        XCTAssertEqual(c.handle(.startTest(now: late)), .accepted, "restarting the test opens a new window")
        XCTAssertEqual(c.handle(.receipt(ShortcutReceipt(receivedAt: late.addingTimeInterval(3)))), .accepted)
    }

    func testDuplicateReceiptIsIgnored() {
        var c = coordinatorAtTest(now: t0)
        XCTAssertEqual(c.handle(.receipt(ShortcutReceipt(receivedAt: t0.addingTimeInterval(1)))), .accepted)
        XCTAssertEqual(c.handle(.receipt(ShortcutReceipt(receivedAt: t0.addingTimeInterval(2)))), .ignored("duplicate receipt"))
        guard case .receiptReceived(_, let at) = c.phase else { return XCTFail() }
        XCTAssertEqual(at, t0.addingTimeInterval(1))
    }

    func testOtherTriggerDiscardsTheReceiptAndResumesTheGuide() {
        var c = coordinatorAtTest(now: t0)
        c.handle(.receipt(ShortcutReceipt(receivedAt: t0.addingTimeInterval(1))))
        XCTAssertEqual(c.handle(.otherTrigger), .accepted)
        XCTAssertEqual(c.phase, .guiding)
        XCTAssertFalse(c.isDone)
        XCTAssertEqual(c.summary.status, .notStarted)
        XCTAssertNil(c.summary.activeTest, "the discarded receipt leaves no test window behind")
    }

    func testBackToStepsLeavesATestWithoutMarkingAnything() {
        var c = coordinatorAtTest(now: t0)
        XCTAssertEqual(c.handle(.backToSteps), .accepted)
        XCTAssertEqual(c.phase, .guiding)
        XCTAssertEqual(c.summary, BackTapSetupSummary())
        c.handle(.startTest(now: t0))
        c.handle(.receipt(ShortcutReceipt(receivedAt: t0.addingTimeInterval(1))))
        XCTAssertEqual(c.handle(.backToSteps), .accepted, "also after a receipt the user doubts")
        XCTAssertFalse(c.isDone)
        XCTAssertEqual(c.handle(.backToSteps), .ignored("no test to leave"))
    }

    func testTheTestCannotStartBeforeTheStepsAreShown() {
        var c = BackTapSetupCoordinator()
        XCTAssertEqual(c.handle(.startTest(now: t0)), .ignored("show the steps first"))
        XCTAssertEqual(c.phase, .notStarted)
        c.handle(.deferSetup)
        XCTAssertEqual(c.handle(.startTest(now: t0)), .ignored("show the steps first"))
        XCTAssertEqual(c.handle(.backToSteps), .ignored("no test to leave"))
        XCTAssertEqual(c.handle(.otherTrigger), .ignored("no receipt to discard"))
    }

    func testDeferAndRevisit() {
        var c = BackTapSetupCoordinator()
        c.handle(.start)
        XCTAssertEqual(c.handle(.start), .ignored("already started"))
        XCTAssertEqual(c.handle(.deferSetup), .accepted)
        XCTAssertEqual(c.phase, .deferred)
        XCTAssertEqual(c.summary.status, .deferred)
        XCTAssertEqual(c.handle(.start), .accepted, "deferred setup can be started again")
        XCTAssertEqual(c.phase, .guiding)

        var done = coordinatorAtTest(now: t0)
        done.handle(.receipt(ShortcutReceipt(receivedAt: t0.addingTimeInterval(1))))
        done.handle(.confirmDoubleTap(now: t0.addingTimeInterval(2)))
        XCTAssertEqual(done.handle(.deferSetup), .ignored("already tested"))
        XCTAssertEqual(done.handle(.start), .ignored("already started"), "a finished setup is reopened with revisit")
        XCTAssertEqual(done.handle(.revisit), .accepted)
        XCTAssertEqual(done.phase, .guiding)
        XCTAssertFalse(done.isDone, "going through the steps again is not done until it is tested again")
    }

    func testSummaryRoundTripResumesAnActiveTestAfterRelaunch() throws {
        let c = coordinatorAtTest(now: t0)
        let data = try JSONEncoder().encode(c.summary)
        let decoded = try JSONDecoder().decode(BackTapSetupSummary.self, from: data)
        XCTAssertEqual(decoded, c.summary)
        XCTAssertNotNil(decoded.activeTest)

        var resumed = BackTapSetupCoordinator(summary: decoded, now: t0.addingTimeInterval(30))
        XCTAssertEqual(resumed.activeTest?.id, c.activeTest?.id, "the same window is resumed")
        XCTAssertEqual(resumed.handle(.receipt(ShortcutReceipt(receivedAt: t0.addingTimeInterval(31)))), .accepted)

        let expired = BackTapSetupCoordinator(summary: decoded, now: t0.addingTimeInterval(BackTapSetupCoordinator.testWindowDuration + 60))
        XCTAssertEqual(expired.phase, .notStarted, "an expired window is dropped, nothing is marked tested")

        let tested = BackTapSetupCoordinator(summary: BackTapSetupSummary(status: .userReportedTested, testedAt: t0), now: t0)
        XCTAssertEqual(tested.phase, .userReportedTested(at: t0))
        let deferred = BackTapSetupCoordinator(summary: BackTapSetupSummary(status: .deferred), now: t0)
        XCTAssertEqual(deferred.phase, .deferred)
    }

    func testInProgressPhasesPersistAsNotStarted() {
        var c = BackTapSetupCoordinator()
        c.handle(.start)
        XCTAssertEqual(c.summary, BackTapSetupSummary())
        XCTAssertEqual(c.summary.status, .notStarted)
        XCTAssertNil(c.summary.activeTest)
    }
}
