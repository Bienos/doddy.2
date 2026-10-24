import XCTest
@testable import DoddyCore

/// ADR-608: routines stay out of 22:00–07:00, and Doddy's own tip never lands on a day a routine
/// already comes. Action items (timers, reminders) are not touched by any of this.
final class QuietHoursTests: XCTestCase {
    private var calendar: Calendar { ReminderSchedule.calendar("Europe/Warsaw") }

    func testQuietHoursAreTenAtNightToSevenInTheMorning() {
        XCTAssertTrue(QuietHours.contains(hour: 22, minute: 0))
        XCTAssertTrue(QuietHours.contains(hour: 23, minute: 59))
        XCTAssertTrue(QuietHours.contains(hour: 0, minute: 0))
        XCTAssertTrue(QuietHours.contains(hour: 6, minute: 59))
        XCTAssertFalse(QuietHours.contains(hour: 7, minute: 0))
        XCTAssertFalse(QuietHours.contains(hour: 21, minute: 59))
    }

    func testARoutineTimeInsideMovesToTheNearestEdgeAndOneOutsideIsKept() {
        XCTAssertTrue(QuietHours.adjusted(hour: 6, minute: 30) == (7, 0))
        XCTAssertTrue(QuietHours.adjusted(hour: 0, minute: 15) == (7, 0))
        XCTAssertTrue(QuietHours.adjusted(hour: 22, minute: 30) == (21, 30))
        XCTAssertTrue(QuietHours.adjusted(hour: 21, minute: 0) == (21, 0))
        XCTAssertTrue(QuietHours.adjusted(hour: 8, minute: 0) == (8, 0))
    }

    func testTheDaysRoutinesComeOn() {
        let none = OwnNotificationDays.routineWeekdays(
            morning: .init(), evening: .init(), plan: .init(), lookBack: .init(), tidyUp: .init())
        XCTAssertEqual(none, [])
        let some = OwnNotificationDays.routineWeekdays(
            morning: .init(isOn: true, weekdaysOnly: true), evening: .init(), plan: .init(isOn: true),
            lookBack: .init(isOn: true), tidyUp: .init())
        XCTAssertEqual(some, [1, 2, 3, 4, 5, 6], "weekdays, Monday's plan and Sunday's look-back; Saturday is free")
        let everyDay = OwnNotificationDays.routineWeekdays(
            morning: .init(), evening: .init(isOn: true), plan: .init(), lookBack: .init(), tidyUp: .init())
        XCTAssertEqual(everyDay, Set(1...7))
    }

    func testTheTipMovesToAFreeDayOrIsDropped() {
        // Thu 29 Oct 2026, 11:00.
        let thursday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 11))!
        XCTAssertEqual(OwnNotificationDays.tipDates([thursday], routineWeekdays: [], calendar: calendar), [thursday])
        let moved = OwnNotificationDays.tipDates([thursday], routineWeekdays: [1, 2, 3, 4, 5, 6], calendar: calendar)
        XCTAssertEqual(moved.map { calendar.component(.weekday, from: $0) }, [7], "Saturday, the free day")
        XCTAssertEqual(moved.map { calendar.component(.hour, from: $0) }, [11], "same time")
        XCTAssertEqual(OwnNotificationDays.tipDates([thursday], routineWeekdays: Set(1...7), calendar: calendar), [])
    }

    func testTheWeeklyPlanIsARoutineAndNeverTimeSensitive() {
        XCTAssertEqual(DoddyNotificationKind.weeklyPlan.urgency, .active)
        XCTAssertFalse(DoddyNotificationKind.weeklyPlan.playsSound, "a routine arrives quietly")
    }
}
