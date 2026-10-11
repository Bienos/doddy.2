import DoddyCore
import XCTest

/// Birthday reminders from contacts (ADR-288).
final class BirthdayTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12))! }
    private let marta = BirthdayContact(id: "c1", name: "Marta", month: 3, day: 2)
    private let tom = BirthdayContact(id: "c2", name: "Tom", month: 10, day: 20)
    private let leap = BirthdayContact(id: "c3", name: "Leo", month: 2, day: 29)
    private let today = BirthdayContact(id: "c4", name: "Ada", month: 10, day: 11)

    func testTheNextBirthdayComesFirstAndTodayCounts() {
        XCTAssertEqual(Birthdays.upcoming([marta, tom, leap, today], now: now, calendar: calendar).map(\.name), ["Ada", "Tom", "Leo", "Marta"])
        XCTAssertTrue(Birthdays.scheduledDay(leap) == (2, 28))
    }

    func testOnlyPickedPeopleAreScheduledAndAtMostTwenty() {
        XCTAssertEqual(Birthdays.toSchedule([marta, tom], picked: ["c2"], now: now, calendar: calendar).map(\.name), ["Tom"])
        let many = (1...30).map { BirthdayContact(id: "x\($0)", name: "P\($0)", month: 1, day: min($0, 28)) }
        XCTAssertEqual(Birthdays.toSchedule(many, picked: Set(many.map(\.id)), now: now, calendar: calendar).count, Birthdays.maxReminders)
    }

    func testTheNotificationNamesSomeoneOnlyWhenAllowed() {
        XCTAssertEqual(Birthdays.title("Marta", .english), "Marta's birthday")
        XCTAssertEqual(Birthdays.title(nil, .english), "A birthday today")
        XCTAssertFalse(Birthdays.notificationID(for: "ABC-123:ABPerson").contains("ABC"), "the contact id isn't in the request id")
        XCTAssertTrue(Birthdays.isBirthday(notificationID: Birthdays.notificationID(for: "c1")))
    }
}
