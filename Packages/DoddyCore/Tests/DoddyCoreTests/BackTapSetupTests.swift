import XCTest
@testable import DoddyCore

final class BackTapSetupTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func coordinatorAtTest(now: Date) -> BackTapSetupCoordinator {
        var c = BackTapSetupCoordinator()
        XCTAssertEqual(c.handle(.start), .accepted)
        XCTAssertEqual(c.handle(.shortcutReady), .accepted)
        XCTAssertEqual(c.handle(.startTest(now: now)), .accepted)
        return c
    }

    func testGuideHasSixNonEmptyStepsAndTheManualPath() {
        XCTAssertEqual(BackTapGuide.steps.count, 6)
        for step in BackTapGuide.steps {
            XCTAssertFalse(step.title.isEmpty); XCTAssertFalse(step.instruction.isEmpty); XCTAssertFalse(step.reportLabel.isEmpty)
        }
        XCTAssertEqual(Set(BackTapGuide.steps.map(\.id)).count, 6, "step ids are unique")
        XCTAssertEqual(BackTapGuide.settingsPath, ["Settings", "Accessibility", "Touch", "Back Tap", "Double Tap", "Talk to Doddy"])
        XCTAssertEqual(BackTapGuide.appShortcutTitle, "Talk to Doddy")
        XCTAssertEqual(BackTapGuide.fallbackShortcutName, "Open Doddy")
        XCTAssertEqual(BackTapGuide.reportableSteps.count, 5)
        XCTAssertEqual(BackTapGuide.steps[BackTapGuide.chooseShortcutStepIndex].id, "double-tap")
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
        c.handle(.start); c.handle(.shortcutReady)
        XCTAssertEqual(c.handle(.receipt(ShortcutReceipt(receivedAt: t0))), .ignored("no active test"))
        XCTAssertEqual(c.phase, .guiding(step: 0))
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
        XCTAssertEqual(c.phase, .guiding(step: BackTapGuide.chooseShortcutStepIndex))
        XCTAssertFalse(c.isDone)
        XCTAssertEqual(c.summary.status, .notStarted)
    }

    func testReportedPageJumpsToThatStepAndUnknownPagesAreNotGuessed() {
        var c = BackTapSetupCoordinator()
        c.handle(.start); c.handle(.shortcutReady)
        XCTAssertEqual(c.handle(.report(page: "I’m in Touch")), .accepted)
        XCTAssertEqual(c.phase, .guiding(step: 2))
        XCTAssertEqual(c.handle(.report(page: "back tap")), .accepted)
        XCTAssertEqual(c.phase, .guiding(step: 3))
        XCTAssertEqual(c.handle(.report(page: "Control Center")), .ignored("unknown page"))
        XCTAssertEqual(c.phase, .guiding(step: 3), "an unknown report changes nothing")
        XCTAssertEqual(c.handle(.report(page: "")), .ignored("unknown page"))
    }

    func testNextPreviousAndBounds() {
        var c = BackTapSetupCoordinator()
        c.handle(.start); c.handle(.shortcutReady)
        XCTAssertEqual(c.handle(.previous), .accepted)
        XCTAssertEqual(c.phase, .shortcutPreparation)
        XCTAssertEqual(c.handle(.next), .ignored("not guiding"))
        c.handle(.shortcutReady)
        for expected in 1..<BackTapGuide.steps.count {
            XCTAssertEqual(c.handle(.next), .accepted)
            XCTAssertEqual(c.phase, .guiding(step: expected))
        }
        XCTAssertEqual(c.handle(.next), .ignored("last step; start the test"))
        XCTAssertEqual(c.currentStep?.id, "assigned")
    }

    func testDeferAndRevisit() {
        var c = BackTapSetupCoordinator()
        c.handle(.start); c.handle(.shortcutReady); c.handle(.next)
        XCTAssertEqual(c.handle(.deferSetup), .accepted)
        XCTAssertEqual(c.phase, .deferred)
        XCTAssertEqual(c.summary.status, .deferred)
        XCTAssertEqual(c.handle(.start), .accepted, "deferred setup can be started again")
        XCTAssertEqual(c.phase, .shortcutPreparation)

        var done = coordinatorAtTest(now: t0)
        done.handle(.receipt(ShortcutReceipt(receivedAt: t0.addingTimeInterval(1))))
        done.handle(.confirmDoubleTap(now: t0.addingTimeInterval(2)))
        XCTAssertEqual(done.handle(.deferSetup), .ignored("already tested"))
        XCTAssertEqual(done.handle(.revisit), .accepted)
        XCTAssertEqual(done.phase, .shortcutPreparation)
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
        c.handle(.shortcutReady); c.handle(.next)
        XCTAssertEqual(c.summary.status, .notStarted)
        XCTAssertNil(c.summary.activeTest)
    }
}
