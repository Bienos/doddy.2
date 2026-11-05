@testable import DoddyCore
import XCTest

/// ADR-604: the voice island's updates are paced, newest state first.
final class LiveActivityPacerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 50_000)
    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testNothingIsSentBeforeTheActivityStarts() {
        var pacer = LiveActivityPacer<String>(minimumGap: 0.5)
        XCTAssertEqual(pacer.delay(now: start), 0)
        XCTAssertNil(pacer.next(now: start))
        XCTAssertNil(pacer.resend(now: start))
    }

    func testTheStartStateCountsAsSent() {
        var pacer = LiveActivityPacer<String>(minimumGap: 0.5)
        pacer.started(with: "listening", at: start)
        XCTAssertFalse(pacer.want("listening"), "asking for what iOS has is not a change")
        XCTAssertNil(pacer.next(now: at(1)))
    }

    func testAChangeWaitsOutTheGapSinceTheLastUpdate() {
        var pacer = LiveActivityPacer<String>(minimumGap: 0.5)
        pacer.started(with: "listening", at: start)
        XCTAssertTrue(pacer.want("speaking"))
        XCTAssertEqual(pacer.delay(now: at(0.2)), 0.3, accuracy: 0.0001)
        XCTAssertEqual(pacer.delay(now: at(0.7)), 0, "a change after a quiet spell goes at once")
        XCTAssertEqual(pacer.next(now: at(0.7)), "speaking")
        XCTAssertEqual(pacer.sent, "speaking")
    }

    func testOnlyTheNewestOfQuickChangesIsSent() {
        var pacer = LiveActivityPacer<String>(minimumGap: 0.5)
        pacer.started(with: "listening", at: start)
        pacer.want("thinking")
        pacer.want("speaking")
        pacer.want("listening")
        pacer.want("speaking")
        XCTAssertEqual(pacer.next(now: at(0.5)), "speaking", "the in-between states never reach the island")
        XCTAssertNil(pacer.next(now: at(1.0)), "nothing new to send")
    }

    func testAFlipAndFlipBackSendsNothing() {
        var pacer = LiveActivityPacer<String>(minimumGap: 0.5)
        pacer.started(with: "speaking", at: start)
        XCTAssertTrue(pacer.want("listening"))
        XCTAssertTrue(pacer.want("speaking"))
        XCTAssertNil(pacer.next(now: at(0.5)), "iOS already shows speaking")
    }

    func testUpdatesNeverGoCloserThanTheGap() {
        var pacer = LiveActivityPacer<Int>(minimumGap: 0.5)
        pacer.started(with: 0, at: start)
        var sentAt: [TimeInterval] = []
        var clock: TimeInterval = 0
        // A status that changes every 0.1 s for 3 s, sent whenever the pacer allows.
        for step in 1...30 {
            clock = Double(step) * 0.1
            pacer.want(step)
            if pacer.delay(now: at(clock)) == 0, pacer.next(now: at(clock)) != nil {
                sentAt.append(clock)
            }
        }
        XCTAssertFalse(sentAt.isEmpty)
        for (a, b) in zip(sentAt, sentAt.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, 0.5 - 0.0001)
        }
        XCTAssertLessThanOrEqual(sentAt.count, 6, "at most two updates a second")
    }

    func testResendGoesWhateverIOSHasAndRestartsTheGap() {
        var pacer = LiveActivityPacer<String>(minimumGap: 0.5)
        pacer.started(with: "speaking", at: start)
        XCTAssertEqual(pacer.resend(now: at(40)), "speaking", "the heartbeat re-sends an unchanged state")
        pacer.want("listening")
        XCTAssertEqual(pacer.delay(now: at(40.1)), 0.4, accuracy: 0.0001)
    }

    func testResendCarriesTheNewestStateSoAQueuedUpdateHasNothingLeft() {
        var pacer = LiveActivityPacer<String>(minimumGap: 0.5)
        pacer.started(with: "listening", at: start)
        pacer.want("speaking")
        XCTAssertEqual(pacer.resend(now: at(0.1)), "speaking", "the alert that opens the island shows what is true now")
        XCTAssertNil(pacer.next(now: at(0.6)))
    }

    func testHasPendingOnlyWhenTheWantedStateIsNotTheSentOne() {
        var pacer = LiveActivityPacer<String>(minimumGap: 0.5)
        XCTAssertFalse(pacer.hasPending, "nothing wanted yet")
        pacer.started(with: "listening", at: start)
        XCTAssertFalse(pacer.hasPending)
        pacer.want("speaking")
        XCTAssertTrue(pacer.hasPending)
        pacer.want("listening")
        XCTAssertFalse(pacer.hasPending, "flipped back to what iOS has")
        pacer.want("speaking")
        _ = pacer.next(now: at(1))
        XCTAssertFalse(pacer.hasPending)
    }

    func testResetForgetsEverything() {
        var pacer = LiveActivityPacer<String>(minimumGap: 0.5)
        pacer.started(with: "speaking", at: start)
        pacer.want("listening")
        pacer.reset()
        XCTAssertNil(pacer.latest)
        XCTAssertNil(pacer.sent)
        XCTAssertEqual(pacer.delay(now: start), 0)
        XCTAssertNil(pacer.next(now: start))
    }
}
