import Foundation
import XCTest
@testable import DoddyCore

final class FocusSessionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testStartRunsForTheChosenMinutes() {
        let s = FocusSession(minutes: 25, label: "  Write one paragraph \n", now: t0)
        XCTAssertEqual(s.endsAt, t0.addingTimeInterval(1500))
        XCTAssertEqual(s.label, "Write one paragraph")
        XCTAssertEqual(s.remaining(at: t0.addingTimeInterval(60)), 1440)
        XCTAssertEqual(s.fractionLeft(at: t0.addingTimeInterval(750)), 0.5, accuracy: 0.0001)
    }

    func testEmptyLabelIsNilAndLongLabelIsCut() {
        XCTAssertNil(FocusSession(minutes: 15, label: "   ", now: t0).label)
        XCTAssertNil(FocusSession(minutes: 15, label: nil, now: t0).label)
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(FocusSession(minutes: 15, label: long, now: t0).label?.count, FocusSession.maxLabelLength)
        XCTAssertEqual(FocusSession.cleanLabel("one\ntwo"), "one two")
    }

    func testMinutesAreClamped() {
        XCTAssertEqual(FocusSession(minutes: 0, label: nil, now: t0).duration, 60)
        XCTAssertEqual(FocusSession(minutes: 999, label: nil, now: t0).duration, 180 * 60)
    }

    func testPauseKeepsTheTimeLeftAndResumeMovesTheEnd() {
        var s = FocusSession(minutes: 25, label: nil, now: t0)
        s.pause(at: t0.addingTimeInterval(100))
        XCTAssertEqual(s.state, .paused(remaining: 1400))
        // Time passing while paused changes nothing.
        XCTAssertEqual(s.remaining(at: t0.addingTimeInterval(5000)), 1400)
        s.resume(at: t0.addingTimeInterval(1000))
        XCTAssertEqual(s.endsAt, t0.addingTimeInterval(2400))
        XCTAssertTrue(s.isRunning)
    }

    func testPauseAfterTheEndFinishesInstead() {
        var s = FocusSession(minutes: 15, label: nil, now: t0)
        s.pause(at: t0.addingTimeInterval(2000))
        XCTAssertEqual(s.state, .finished(at: t0.addingTimeInterval(900)))
    }

    func testFinishIfDueOnlyAfterTheEnd() {
        var s = FocusSession(minutes: 15, label: nil, now: t0)
        XCTAssertFalse(s.finishIfDue(at: t0.addingTimeInterval(899)))
        XCTAssertTrue(s.finishIfDue(at: t0.addingTimeInterval(901)))
        XCTAssertEqual(s.state, .finished(at: t0.addingTimeInterval(900)))
        XCTAssertFalse(s.finishIfDue(at: t0.addingTimeInterval(2000)))
    }

    func testStopBeforeTheEndIsStoppedNotFinished() {
        var s = FocusSession(minutes: 15, label: nil, now: t0)
        s.stop(at: t0.addingTimeInterval(10))
        XCTAssertEqual(s.state, .stopped(at: t0.addingTimeInterval(10)))
        XCTAssertEqual(s.remaining(at: t0.addingTimeInterval(11)), 0)
        // Stopping again changes nothing.
        s.stop(at: t0.addingTimeInterval(20))
        XCTAssertEqual(s.state, .stopped(at: t0.addingTimeInterval(10)))
    }

    func testStopAfterTheEndCountsAsFinished() {
        var s = FocusSession(minutes: 15, label: nil, now: t0)
        s.stop(at: t0.addingTimeInterval(1000))
        XCTAssertEqual(s.state, .finished(at: t0.addingTimeInterval(900)))
    }

    func testCodableRoundTrip() throws {
        var s = FocusSession(minutes: 25, label: "Read", now: t0)
        s.pause(at: t0.addingTimeInterval(30))
        let back = try JSONDecoder().decode(FocusSession.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }
}
