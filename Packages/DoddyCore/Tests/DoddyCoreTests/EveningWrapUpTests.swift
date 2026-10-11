import DoddyCore
import XCTest

/// Evening wrap-up (ADR-256): what is offered, and where "tomorrow" lands.
final class EveningWrapUpTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }
    private func at(_ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private func reminder(_ title: String, _ due: ReminderDue?, done: Bool = false) -> ReminderSnapshot {
        ReminderSnapshot(id: title, title: title, listTitle: "Reminders", due: due, markerURL: nil, isCompleted: done)
    }
    private let zone = "Europe/Warsaw"

    func testOnlyOpenRemindersDueTodayOrEarlierAreOfferedOldestFirst() {
        let now = at(10, 11, 21)
        let offered = EveningWrapUp.movable([
            reminder("Tomorrow", ReminderDue(year: 2026, month: 10, day: 12, hour: 9, timeZoneID: zone)),
            reminder("Tonight", ReminderDue(year: 2026, month: 10, day: 11, hour: 22, timeZoneID: zone)),
            reminder("Last week", ReminderDue(year: 2026, month: 10, day: 4, timeZoneID: nil)),
            reminder("No date", nil),
            reminder("Done", ReminderDue(year: 2026, month: 10, day: 11, hour: 8, timeZoneID: zone), done: true),
        ], now: now, local: calendar)
        XCTAssertEqual(offered.map(\.title), ["Last week", "Tonight"])
    }

    func testTomorrowKeepsTheTimeAndIsTheDayAfterNow() {
        let now = at(10, 11, 21)
        let overdue = ReminderDue(year: 2026, month: 10, day: 4, hour: 8, minute: 30, timeZoneID: zone)
        XCTAssertEqual(EveningWrapUp.tomorrow(overdue, now: now, local: calendar)?.localText, "2026-10-12T08:30")
        let dayOnly = ReminderDue(year: 2026, month: 10, day: 11, timeZoneID: nil)
        let moved = EveningWrapUp.tomorrow(dayOnly, now: now, local: calendar)
        XCTAssertEqual(moved?.localText, "2026-10-12")
        XCTAssertFalse(moved?.hasTime ?? true)
    }

    func testATimeTheClocksSkipTomorrowIsNotGuessed() {
        // 2027-03-28: Poland's clocks go from 02:00 to 03:00.
        let night = calendar.date(from: DateComponents(year: 2027, month: 3, day: 27, hour: 21))!
        let due = ReminderDue(year: 2027, month: 3, day: 27, hour: 2, minute: 30, timeZoneID: zone)
        XCTAssertNil(EveningWrapUp.tomorrow(due, now: night, local: calendar))
    }

    func testSettingsAreOffByDefaultAndTheNotificationSaysNothingPersonal() {
        XCTAssertFalse(EveningWrapUpSettings().isOn)
        XCTAssertEqual(EveningWrapUpSettings().hour, 21)
        XCTAssertEqual(EveningWrapUp.body(.english), "Anything to move to tomorrow?")
        XCTAssertTrue(EveningWrapUp.isWrapUp(notificationID: EveningWrapUp.notificationID))
        XCTAssertFalse(MorningCheckIn.isCheckIn(notificationID: EveningWrapUp.notificationID))
    }
}
