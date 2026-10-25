import XCTest
@testable import DoddyCore

/// ADR-652: a stopwatch that counts up. Time is only what the clock says; a pause stops the count,
/// a clock set back counts nothing, and a stored copy comes back exactly.
final class StopwatchTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    func testItCountsUpFromTheStart() {
        let watch = Stopwatch(label: nil, now: t0)
        XCTAssertTrue(watch.isRunning)
        XCTAssertEqual(watch.elapsed(at: t0), 0)
        XCTAssertEqual(watch.elapsed(at: t0.addingTimeInterval(727)), 727)
        XCTAssertEqual(watch.countsFrom, watch.countsFrom, "the same reading every time while it runs")
        XCTAssertEqual(watch.countsFrom, t0, "a clock that started at the beginning shows 12:07 now")
    }

    func testAPauseStopsTheCountAndAResumeCarriesOn() {
        var watch = Stopwatch(label: "Bieg", now: t0)
        watch.pause(at: t0.addingTimeInterval(60))
        XCTAssertTrue(watch.isPaused)
        XCTAssertEqual(watch.elapsed(at: t0.addingTimeInterval(3_600)), 60, "an hour passes while paused: still 1:00")
        XCTAssertNil(watch.countsFrom, "nothing ticks while paused")
        watch.resume(at: t0.addingTimeInterval(3_600))
        XCTAssertTrue(watch.isRunning)
        XCTAssertEqual(watch.elapsed(at: t0.addingTimeInterval(3_630)), 90)
        // The ticking clock starts 90 s before now, so it reads 1:30 now and goes on from there.
        XCTAssertEqual(watch.countsFrom, t0.addingTimeInterval(3_540))
    }

    func testStopKeepsTheReadingAndEverythingElseIsIgnoredAfterwards() {
        var watch = Stopwatch(label: nil, now: t0)
        watch.stop(at: t0.addingTimeInterval(125))
        XCTAssertTrue(watch.isOver)
        XCTAssertEqual(watch.elapsed(at: t0.addingTimeInterval(9_999)), 125)
        watch.resume(at: t0.addingTimeInterval(200))
        watch.pause(at: t0.addingTimeInterval(300))
        watch.stop(at: t0.addingTimeInterval(400))
        XCTAssertEqual(watch.stoppedAt, t0.addingTimeInterval(125), "a second stop changes nothing")
        XCTAssertEqual(watch.elapsed(at: t0.addingTimeInterval(500)), 125)
    }

    func testAStopWhilePausedKeepsThePausedReading() {
        var watch = Stopwatch(label: nil, now: t0)
        watch.pause(at: t0.addingTimeInterval(30))
        watch.stop(at: t0.addingTimeInterval(1_000))
        XCTAssertEqual(watch.elapsed(at: t0.addingTimeInterval(2_000)), 30)
    }

    func testAClockSetBackCountsNothingAndNeverGoesNegative() {
        let watch = Stopwatch(label: nil, now: t0)
        XCTAssertEqual(watch.elapsed(at: t0.addingTimeInterval(-500)), 0)
    }

    func testAStopwatchLeftForADayStopsAtTheLimit() {
        var watch = Stopwatch(label: nil, now: t0)
        let later = t0.addingTimeInterval(Stopwatch.maxElapsed + 5_000)
        XCTAssertEqual(watch.elapsed(at: later), Stopwatch.maxElapsed)
        XCTAssertTrue(watch.stopIfAtLimit(at: later))
        XCTAssertEqual(watch.stoppedAt, t0.addingTimeInterval(Stopwatch.maxElapsed), "stopped when it reached the limit, not when noticed")
        XCTAssertFalse(watch.stopIfAtLimit(at: later), "already stopped")
        var young = Stopwatch(label: nil, now: t0)
        XCTAssertFalse(young.stopIfAtLimit(at: t0.addingTimeInterval(60)))
    }

    func testTheLabelIsTrimmedOnOneLineAndShort() {
        XCTAssertNil(Stopwatch(label: "   ", now: t0).label)
        XCTAssertEqual(Stopwatch(label: "  Bieg\nwieczorny ", now: t0).label, "Bieg wieczorny")
        XCTAssertEqual(Stopwatch(label: String(repeating: "a", count: 90), now: t0).label?.count, Stopwatch.maxLabelLength)
    }

    func testTheReadingIsShownAsAClock() {
        XCTAssertEqual(Stopwatch.clock(0), "0:00")
        XCTAssertEqual(Stopwatch.clock(7.9), "0:07")
        XCTAssertEqual(Stopwatch.clock(727), "12:07")
        XCTAssertEqual(Stopwatch.clock(3_727), "1:02:07")
        XCTAssertEqual(Stopwatch.clock(-4), "0:00")
    }

    func testTheReadingInWordsForWhatDoddySays() {
        XCTAssertEqual(Stopwatch.spoken(727, polish: false), "12 minutes 7 seconds")
        XCTAssertEqual(Stopwatch.spoken(61, polish: false), "1 minute 1 second")
        XCTAssertEqual(Stopwatch.spoken(727, polish: true), "12 minut 7 sekund")
        XCTAssertEqual(Stopwatch.spoken(3_723, polish: true), "1 godzina 2 minuty 3 sekundy")
        XCTAssertEqual(Stopwatch.spoken(0, polish: true), "0 sekund")
        XCTAssertEqual(Stopwatch.spoken(22 * 60, polish: true), "22 minuty")
    }

    func testAStoredCopyComesBackExactly() throws {
        var watch = Stopwatch(label: "Bieg", now: t0)
        watch.pause(at: t0.addingTimeInterval(95))
        let data = try JSONEncoder().encode(watch)
        let back = try JSONDecoder().decode(Stopwatch.self, from: data)
        XCTAssertEqual(back, watch)
        XCTAssertEqual(back.elapsed(at: t0.addingTimeInterval(500)), 95)
        XCTAssertTrue(back.isPaused)
    }
}
