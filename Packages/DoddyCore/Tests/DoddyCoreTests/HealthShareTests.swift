import Foundation
import XCTest
@testable import DoddyCore

/// Sport mode step 2 (ADR-622): the week's totals and the summary text a person may send.
final class HealthShareTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// Saturday 24 October 2026, 09:30 in Warsaw.
    private var now: Date { at(24, 9, 30) }

    private func workout(_ activity: WorkoutActivity, _ start: Date, minutes: Double, meters: Double? = nil) -> HealthWorkout {
        HealthWorkout(activity: activity, start: start, end: start.addingTimeInterval(minutes * 60), distanceMeters: meters,
                      activeKilocalories: nil, averageHeartRate: nil)
    }

    func testThePreviousWeekIsTheSevenDaysBefore() {
        let previous = HealthWindow.previousDays(now: now, calendar: calendar)
        XCTAssertEqual(previous.start, at(11, 0))
        XCTAssertEqual(previous.end, at(18, 0))
        XCTAssertEqual(previous.end, HealthWindow.lastDays(now: now, calendar: calendar).start, "the weeks meet, no gap, no overlap")
    }

    func testWeekTotals() {
        let week = HealthWindow.lastDays(now: now, calendar: calendar)
        let all = [
            workout(.running, at(19, 7), minutes: 50, meters: 9000),
            workout(.running, at(22, 7), minutes: 25, meters: 5000),
            workout(.running, at(23, 18), minutes: 30),                     // treadmill, no distance
            workout(.strength, at(20, 18), minutes: 60),
            workout(.cycling, at(21, 17), minutes: 40, meters: 15_000),
            workout(.running, at(16, 7), minutes: 45, meters: 8000),        // the week before
        ]
        let totals = WeekTotals.of(all, in: week)
        XCTAssertEqual(totals.workouts, 5)
        XCTAssertEqual(totals.duration, (50 + 25 + 30 + 60 + 40) * 60)
        XCTAssertEqual(totals.runningMeters, 14_000, "runs with a distance only; the ride doesn't count")
        XCTAssertEqual(totals.runningPaceSecondsPerKilometre!, 75 * 60 / 14, accuracy: 0.001, "the treadmill run's time is left out of the pace")

        let before = WeekTotals.of(all, in: HealthWindow.previousDays(now: now, calendar: calendar))
        XCTAssertEqual(before, WeekTotals(workouts: 1, duration: 45 * 60, runningMeters: 8000, runningSecondsWithDistance: 45 * 60))
        XCTAssertEqual(WeekTotals.of([], in: week), .none)
        XCTAssertNil(WeekTotals.none.runningPaceSecondsPerKilometre)
    }

    func testAGlanceWithOnlyLastWeeksWorkoutsIsNotEmpty() {
        let glance = HealthGlance(workouts: [], previousWeek: WeekTotals(workouts: 2, duration: 3600, runningMeters: 0, runningSecondsWithDistance: 0),
                                  lastNight: nil, restingHeartRate: nil, heartRateVariability: nil, vo2Max: nil)
        XCTAssertFalse(glance.isEmpty, "there is something to compare with")
    }

    func testConsentVersion() {
        XCTAssertFalse(HealthShareConsent.isGranted(storedVersion: 0), "never asked")
        XCTAssertTrue(HealthShareConsent.isGranted(storedVersion: HealthShareConsent.version))
    }

    // MARK: The text

    private let leftOut: (Int) -> String = { "(\($0) older workouts left out)" }

    func testTheMessageIsTheQuestionThenWorkoutsThenTheRest() {
        let text = HealthShareText.assemble(question: "How did my week go?", workoutLines: ["• Run A", "• Run B"],
                                            otherLines: ["Last night: 7 h", "Resting heart rate: 52"], leftOut: leftOut)
        XCTAssertEqual(text, "How did my week go?\n\n• Run A\n• Run B\nLast night: 7 h\nResting heart rate: 52")
    }

    func testTheOldestWorkoutsGoFirstWhenItIsTooLong() {
        let lines = (1...5).map { "• workout \($0) " + String(repeating: "x", count: 40) }
        let full = HealthShareText.assemble(question: "Q", workoutLines: lines, otherLines: ["end"], leftOut: leftOut)!
        let limit = full.unicodeScalars.count - 10
        let cut = HealthShareText.assemble(question: "Q", workoutLines: lines, otherLines: ["end"], leftOut: leftOut, limit: limit)!
        XCTAssertLessThanOrEqual(cut.unicodeScalars.count, limit)
        XCTAssertTrue(cut.contains("workout 1"), "the newest stays")
        XCTAssertFalse(cut.contains("workout 5"), "the oldest goes")
        XCTAssertTrue(cut.contains("older workouts left out"))
        XCTAssertTrue(cut.hasSuffix("end"), "the other lines are never cut")
    }

    func testNothingHalfCutIsEverOffered() {
        XCTAssertNil(HealthShareText.assemble(question: String(repeating: "q", count: 50), workoutLines: ["• a"],
                                              otherLines: [], leftOut: leftOut, limit: 20))
    }

    func testTheDefaultLimitIsMessagesOwn() {
        let lines = (1...60).map { "• workout \($0) " + String(repeating: "ż", count: 60) }
        let text = HealthShareText.assemble(question: "Jak mi poszło?", workoutLines: lines, otherLines: ["koniec"], leftOut: leftOut)!
        XCTAssertLessThanOrEqual(text.unicodeScalars.count, AssistantLimits.maxQuestionLength)
        XCTAssertTrue(AssistantRequestCheck.fits(text))
    }
}

/// The same length rule Messages uses before sending.
private enum AssistantRequestCheck {
    static func fits(_ text: String) -> Bool { text.unicodeScalars.count <= AssistantLimits.maxQuestionLength }
}
