import Foundation
import XCTest
@testable import DoddyCore

/// Sport mode step 1 (ADR-621): the numbers "What Doddy sees" shows from Apple Health.
final class HealthGlanceTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    /// Saturday 24 October 2026 in Warsaw.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { at(24, 9, 30) }

    // MARK: Window

    func testTheWindowIsSevenDaysTodayIncluded() {
        let window = HealthWindow.lastDays(now: now, calendar: calendar)
        XCTAssertEqual(window.start, at(18, 0))
        XCTAssertEqual(window.end, now)
    }

    func testTheNightRunsFromSixInTheEveningToNoonCutAtNow() {
        let night = HealthWindow.night(wakingOn: now, now: now, calendar: calendar)
        XCTAssertEqual(night.start, at(23, 18))
        XCTAssertEqual(night.end, now, "this morning: cut at now")
        let earlier = HealthWindow.night(wakingOn: at(22, 8), now: now, calendar: calendar)
        XCTAssertEqual(earlier.start, at(21, 18))
        XCTAssertEqual(earlier.end, at(22, 12))
    }

    // MARK: Workouts

    func testPaceOnlyForRunningWalkingAndHikingOfAtLeast100Metres() {
        let run = HealthWorkout(activity: .running, start: at(23, 7), end: at(23, 7, 47).addingTimeInterval(10),
                                distanceMeters: 8200, activeKilocalories: 610, averageHeartRate: 152)
        XCTAssertEqual(run.duration, 47 * 60 + 10)
        XCTAssertEqual(run.paceSecondsPerKilometre!, 2830.0 / 8.2, accuracy: 0.001)
        XCTAssertEqual(HealthFormat.pace(run.paceSecondsPerKilometre!), "5:45")

        let ride = HealthWorkout(activity: .cycling, start: at(22, 17), end: at(22, 18), distanceMeters: 25_000,
                                 activeKilocalories: nil, averageHeartRate: nil)
        XCTAssertNil(ride.paceSecondsPerKilometre, "no pace for a bike ride")
        let shortWalk = HealthWorkout(activity: .walking, start: at(22, 12), end: at(22, 12, 2), distanceMeters: 80,
                                      activeKilocalories: nil, averageHeartRate: nil)
        XCTAssertNil(shortWalk.paceSecondsPerKilometre, "under 100 m")
        let noDistance = HealthWorkout(activity: .running, start: at(22, 6), end: at(22, 6, 30), distanceMeters: nil,
                                       activeKilocalories: nil, averageHeartRate: nil)
        XCTAssertNil(noDistance.paceSecondsPerKilometre, "a treadmill run with no distance")
    }

    func testZeroOrNegativeNumbersAreMissingNotZero() {
        let lift = HealthWorkout(activity: .strength, start: at(21, 18), end: at(21, 19), distanceMeters: 0,
                                 activeKilocalories: -1, averageHeartRate: 0)
        XCTAssertNil(lift.distanceMeters)
        XCTAssertNil(lift.activeKilocalories)
        XCTAssertNil(lift.averageHeartRate)
    }

    func testRecentWorkoutsAreThoseEndingInTheWindowNewestFirst() {
        let window = HealthWindow.lastDays(now: now, calendar: calendar)
        func workout(_ activity: WorkoutActivity, _ start: Date, _ end: Date) -> HealthWorkout {
            HealthWorkout(activity: activity, start: start, end: end, distanceMeters: nil, activeKilocalories: nil, averageHeartRate: nil)
        }
        let tooOld = workout(.running, at(17, 7), at(17, 8))
        let acrossMidnight = workout(.walking, at(17, 23, 30), at(18, 0, 30))
        let monday = workout(.strength, at(19, 18), at(19, 19))
        let thursday = workout(.running, at(22, 7), at(22, 7, 45))
        let empty = workout(.yoga, at(23, 8), at(23, 8))
        let today = workout(.cycling, at(24, 7), at(24, 8))
        let recent = HealthWorkout.recent([monday, tooOld, today, empty, acrossMidnight, thursday], in: window)
        XCTAssertEqual(recent, [today, thursday, monday, acrossMidnight])
        XCTAssertEqual(HealthWorkout.recent([monday, thursday, today], in: window, limit: 2), [today, thursday])
    }

    // MARK: Sleep

    private var lastNight: (start: Date, end: Date) { HealthWindow.night(wakingOn: now, now: now, calendar: calendar) }

    func testAWatchNightWithStagesAddsUp() {
        let samples = [
            SleepSample(stage: .inBed, start: at(23, 22, 45), end: at(24, 7, 10)),
            SleepSample(stage: .core, start: at(23, 23, 0), end: at(24, 1, 0)),
            SleepSample(stage: .deep, start: at(24, 1, 0), end: at(24, 2, 0)),
            SleepSample(stage: .awake, start: at(24, 2, 0), end: at(24, 2, 15)),
            SleepSample(stage: .rem, start: at(24, 2, 15), end: at(24, 3, 45)),
            SleepSample(stage: .core, start: at(24, 3, 45), end: at(24, 6, 45)),
        ]
        let night = SleepNight.summarize(samples, window: lastNight)!
        XCTAssertEqual(night.asleep, (7 * 60 + 30) * 60, "awake and in bed aren't sleep")
        XCTAssertEqual(night.core, 5 * 3600)
        XCTAssertEqual(night.deep, 3600)
        XCTAssertEqual(night.rem, 90 * 60)
        XCTAssertEqual(night.fellAsleep, at(23, 23, 0))
        XCTAssertEqual(night.wokeUp, at(24, 6, 45))
    }

    func testTwoSourcesForTheSameHoursCountOnce() {
        // The watch staged the night; the iPhone's sleep schedule wrote one long unstaged block,
        // and another app staged part of it differently.
        let samples = [
            SleepSample(stage: .asleepUnspecified, start: at(23, 22, 30), end: at(24, 7, 0)),
            SleepSample(stage: .core, start: at(23, 23, 0), end: at(24, 3, 0)),
            SleepSample(stage: .deep, start: at(24, 0, 0), end: at(24, 1, 0)),
            SleepSample(stage: .rem, start: at(24, 3, 0), end: at(24, 4, 0)),
            SleepSample(stage: .core, start: at(24, 3, 30), end: at(24, 6, 30)),
        ]
        let night = SleepNight.summarize(samples, window: lastNight)!
        XCTAssertEqual(night.asleep, (7 * 60 + 30) * 60, "23:00 to 06:30, the unstaged block ignored")
        XCTAssertEqual(night.deep, 3600, "deep wins over the core under it")
        XCTAssertEqual(night.rem, 3600, "REM wins over the overlapping core")
        XCTAssertEqual(night.core, (5 * 60 + 30) * 60)
        XCTAssertEqual((night.core ?? 0) + (night.deep ?? 0) + (night.rem ?? 0), night.asleep)
    }

    func testUnstagedSleepCountsWhenNothingIsStaged() {
        let samples = [
            SleepSample(stage: .asleepUnspecified, start: at(23, 23, 30), end: at(24, 3, 0)),
            SleepSample(stage: .asleepUnspecified, start: at(24, 2, 0), end: at(24, 6, 0)),
            SleepSample(stage: .inBed, start: at(23, 23, 0), end: at(24, 6, 30)),
        ]
        let night = SleepNight.summarize(samples, window: lastNight)!
        XCTAssertEqual(night.asleep, (6 * 60 + 30) * 60, "the overlapping hour counts once")
        XCTAssertNil(night.core)
        XCTAssertNil(night.deep)
        XCTAssertNil(night.rem)
    }

    func testSleepIsCutAtTheWindowAndNothingAsleepIsNil() {
        let samples = [
            SleepSample(stage: .core, start: at(23, 16, 0), end: at(23, 19, 0)),
            SleepSample(stage: .core, start: at(24, 8, 0), end: at(24, 11, 0)),
        ]
        let night = SleepNight.summarize(samples, window: lastNight)!
        XCTAssertEqual(night.asleep, 3600 + 90 * 60, "18:00–19:00 and 08:00–09:30 (now)")
        XCTAssertNil(SleepNight.summarize([SleepSample(stage: .inBed, start: at(23, 23), end: at(24, 7))], window: lastNight))
        XCTAssertNil(SleepNight.summarize([SleepSample(stage: .awake, start: at(23, 23), end: at(24, 7))], window: lastNight))
        XCTAssertNil(SleepNight.summarize([], window: lastNight))
    }

    // MARK: Readings

    func testTheAverageIsOfEachDaysAverage() {
        let readings = [
            HealthReading(value: 40, date: at(20, 7)),
            HealthReading(value: 60, date: at(21, 3)),
            HealthReading(value: 62, date: at(21, 9)),
            HealthReading(value: 58, date: at(21, 22)),
            HealthReading(value: 50, date: at(23, 6)),
        ]
        let glance = ReadingGlance.of(readings, calendar: calendar)!
        XCTAssertEqual(glance.latest, HealthReading(value: 50, date: at(23, 6)))
        XCTAssertEqual(glance.average, 50, accuracy: 0.0001, "(40 + 60 + 50) / 3, not the mean of all five")
        XCTAssertEqual(glance.days, 3)
    }

    func testBadReadingsAreDroppedAndNoneIsNil() {
        XCTAssertNil(ReadingGlance.of([], calendar: calendar))
        XCTAssertNil(ReadingGlance.of([HealthReading(value: 0, date: at(22, 7)), HealthReading(value: .nan, date: at(23, 7))], calendar: calendar))
        let glance = ReadingGlance.of([HealthReading(value: 54, date: at(22, 7)), HealthReading(value: -3, date: at(23, 7))], calendar: calendar)!
        XCTAssertEqual(glance.latest.value, 54)
        XCTAssertEqual(glance.days, 1)
    }

    func testAnEmptyGlanceSaysSo() {
        XCTAssertTrue(HealthGlance(workouts: [], lastNight: nil, restingHeartRate: nil, heartRateVariability: nil, vo2Max: nil).isEmpty)
        XCTAssertFalse(HealthGlance(workouts: [], lastNight: nil, restingHeartRate: nil, heartRateVariability: nil,
                                    vo2Max: HealthReading(value: 44, date: at(20, 8))).isEmpty)
    }

    // MARK: Format

    func testClock() {
        XCTAssertEqual(HealthFormat.clock(0), "0:00")
        XCTAssertEqual(HealthFormat.clock(59.6), "1:00")
        XCTAssertEqual(HealthFormat.clock(47 * 60 + 10), "47:10")
        XCTAssertEqual(HealthFormat.clock(3600 + 5 * 60 + 20), "1:05:20")
        XCTAssertEqual(HealthFormat.clock(2 * 3600 + 15 * 60 + 3), "2:15:03")
        XCTAssertEqual(HealthFormat.clock(-5), "0:00")
    }
}
