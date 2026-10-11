import Foundation
import XCTest
@testable import DoddyCore

/// Countdown timers (ADR-337): the timing rules behind the kitchen timer and the wind-down.
final class CountdownSessionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testStartsRunningForTheSecondsAsked() {
        let s = CountdownSession(seconds: 600, purpose: .timer, label: "  Pasta \n", now: t0)
        XCTAssertEqual(s.endsAt, t0.addingTimeInterval(600))
        XCTAssertEqual(s.label, "Pasta")
        XCTAssertTrue(s.isRunning)
        XCTAssertEqual(s.remaining(at: t0.addingTimeInterval(100)), 500)
        XCTAssertEqual(s.duration, 600)
    }

    func testSecondsAreClampedAndWindDownHasNoLabel() {
        XCTAssertEqual(CountdownSession(seconds: 0, purpose: .timer, label: nil, now: t0).duration, 5)
        XCTAssertEqual(CountdownSession(seconds: 999_999, purpose: .timer, label: nil, now: t0).duration, 86_400)
        XCTAssertNil(CountdownSession(seconds: 300, purpose: .windDown, label: "Sleep", now: t0).label)
        XCTAssertNil(CountdownSession(seconds: 300, purpose: .timer, label: "   ", now: t0).label)
        let long = String(repeating: "a", count: 100)
        XCTAssertEqual(CountdownSession(seconds: 300, purpose: .timer, label: long, now: t0).label?.count,
                       CountdownSession.maxLabelLength)
        XCTAssertEqual(CountdownSession.cleanLabel("eggs\nsoft"), "eggs soft")
    }

    func testPauseResumeStopAndFinish() {
        var s = CountdownSession(seconds: 600, purpose: .timer, label: nil, now: t0)
        s.pause(at: t0.addingTimeInterval(100))
        XCTAssertEqual(s.state, .paused(remaining: 500))
        XCTAssertEqual(s.remaining(at: t0.addingTimeInterval(9000)), 500, "time passing while paused changes nothing")
        s.resume(at: t0.addingTimeInterval(1000))
        XCTAssertEqual(s.endsAt, t0.addingTimeInterval(1500))
        XCTAssertFalse(s.finishIfDue(at: t0.addingTimeInterval(1499)))
        XCTAssertTrue(s.finishIfDue(at: t0.addingTimeInterval(1500)))
        XCTAssertEqual(s.state, .finished(at: t0.addingTimeInterval(1500)))
        XCTAssertTrue(s.isOver)
        XCTAssertEqual(s.remaining(at: t0.addingTimeInterval(2000)), 0)
        // Over is over: nothing resumes or stops it again.
        s.resume(at: t0.addingTimeInterval(3000))
        s.stop(at: t0.addingTimeInterval(3000))
        XCTAssertEqual(s.state, .finished(at: t0.addingTimeInterval(1500)))
    }

    func testStopBeforeTheEndIsStoppedButAfterItIsFinished() {
        var early = CountdownSession(seconds: 60, purpose: .windDown, label: nil, now: t0)
        early.stop(at: t0.addingTimeInterval(10))
        XCTAssertEqual(early.state, .stopped(at: t0.addingTimeInterval(10)))
        var late = CountdownSession(seconds: 60, purpose: .windDown, label: nil, now: t0)
        late.stop(at: t0.addingTimeInterval(61))
        XCTAssertEqual(late.state, .finished(at: t0.addingTimeInterval(60)), "the time had run out, so it finished")
        var paused = CountdownSession(seconds: 60, purpose: .timer, label: nil, now: t0)
        paused.pause(at: t0.addingTimeInterval(70))
        XCTAssertEqual(paused.state, .finished(at: t0.addingTimeInterval(60)), "pausing after the end finishes instead")
    }

    func testNotificationIDIsOwnAndRecognised() {
        let s = CountdownSession(seconds: 60, purpose: .timer, label: nil, now: t0)
        XCTAssertEqual(s.notificationID, "doddy.countdown.\(s.id.uuidString)")
        XCTAssertTrue(CountdownSession.isCountdown(notificationID: s.notificationID))
        XCTAssertFalse(CountdownSession.isCountdown(notificationID: "doddy.focus.x"))
    }

    func testLengthTextAndDoneWords() {
        XCTAssertEqual(CountdownSession.lengthText(600), "10 min")
        XCTAssertEqual(CountdownSession.lengthText(5400), "1 h 30 min")
        XCTAssertEqual(CountdownSession.lengthText(3600), "1 h")
        XCTAssertEqual(CountdownSession.lengthText(45), "45 s")
        XCTAssertEqual(CountdownSession.lengthText(150), "2 min 30 s")
        XCTAssertEqual(CountdownSession.doneTitle(.timer, .english), "Timer done")
        XCTAssertEqual(CountdownSession.doneBody(.timer, label: "Pasta", .polish), "Pasta", "the label is the user's own words")
        XCTAssertEqual(CountdownSession.doneBody(.timer, label: nil, .polish), "Czas minął.")
        XCTAssertEqual(CountdownSession.doneBody(.windDown, label: "ignored", .english), "Time to put the phone down.")
        XCTAssertEqual(CountdownSession.doneTitle(.windDown, .polish), "Wyciszenie dobiegło końca")
    }

    func testRoundTripsThroughJSON() throws {
        var s = CountdownSession(seconds: 300, purpose: .windDown, label: nil, now: t0)
        s.pause(at: t0.addingTimeInterval(20))
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(CountdownSession.self, from: data), s)
    }
}
