import XCTest
@testable import DoddyCore

/// "Whose birthday is coming up?" (ADR-265): read only, from Contacts, names with day and month.
final class BirthdaysTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: "upcoming_birthdays", parametersJSON: Data(json.utf8))
    }

    func testParsingTakesAWholeNumberOfDaysOrTheWeek() {
        XCTAssertEqual(parse("{}"), .upcomingBirthdays(days: 7))
        XCTAssertEqual(parse(#"{"days":1}"#), .upcomingBirthdays(days: 1))
        XCTAssertEqual(parse(#"{"days":30}"#), .upcomingBirthdays(days: 30))
        XCTAssertEqual(parse(#"{"days":"14"}"#), .upcomingBirthdays(days: 14))
        let invalid = VoiceToolRequest.invalid(name: "upcoming_birthdays", reason: "days must be a whole number from 1 to 60")
        XCTAssertEqual(parse(#"{"days":0}"#), invalid)
        XCTAssertEqual(parse(#"{"days":61}"#), invalid)
        XCTAssertEqual(parse(#"{"days":2.5}"#), invalid)
        XCTAssertEqual(parse(#"{"days":"soon"}"#), invalid)
        XCTAssertEqual(parse(#"{"days":null}"#), invalid)
    }

    func testUsesTheContactsSwitchPauseAllAndTheActivityList() {
        XCTAssertEqual(VoiceConnection.serving("upcoming_birthdays"), .contacts)
        XCTAssertTrue(ConnectionPause.applies(to: .upcomingBirthdays(days: 7)))
        let logged = ActivityRequest.describe(.upcomingBirthdays(days: 7), calendar: calendar)
        XCTAssertEqual(logged?.title, "Read birthdays")
        XCTAssertEqual(logged?.detail, "Next 7 days")
        XCTAssertEqual(logged?.isLookup, true)
        XCTAssertEqual(logged?.app, .contacts)
    }

    func testFindsBirthdaysFromTodaySoonestFirstAndAcrossTheNewYear() {
        let people = [
            ContactBirthday(name: "Ola", month: 1, day: 2, year: 1990),
            ContactBirthday(name: "Tomek", month: 12, day: 30),
            ContactBirthday(name: "Anna", month: 12, day: 28, year: 1985),
            ContactBirthday(name: "Bartek", month: 12, day: 28),
            ContactBirthday(name: "Past", month: 12, day: 27),
            ContactBirthday(name: "Later", month: 1, day: 10),
        ]
        let found = Birthdays.upcoming(people, now: date(2026, 12, 28, 23), days: 7, calendar: calendar)
        XCTAssertEqual(found.map(\.name), ["Anna", "Bartek", "Tomek", "Ola"])
        XCTAssertEqual(found.map(\.daysAway), [0, 0, 2, 5])
        XCTAssertEqual(found[3].date, calendar.startOfDay(for: date(2027, 1, 2)))
        // Yesterday's birthday is next year's, far outside the week.
        XCTAssertFalse(found.contains { $0.name == "Past" })
    }

    func testTodayOnlyAndTheLongestLook() {
        let people = [ContactBirthday(name: "Anna", month: 10, day: 11), ContactBirthday(name: "Ola", month: 10, day: 12)]
        XCTAssertEqual(Birthdays.upcoming(people, now: date(2026, 10, 11), days: 1, calendar: calendar).map(\.name), ["Anna"])
        // Asking for more than 60 days still looks 60 days ahead at most.
        let far = [ContactBirthday(name: "Far", month: 12, day: 15)]
        XCTAssertEqual(Birthdays.upcoming(far, now: date(2026, 10, 11), days: 500, calendar: calendar).count, 0)
        XCTAssertEqual(Birthdays.upcoming(far, now: date(2026, 10, 11), days: 66, calendar: calendar).count, 0)
    }

    func testLeapDayBirthdaysFallOnThe28thInOtherYearsAndImpossibleDatesAreSkipped() {
        let people = [
            ContactBirthday(name: "Leap", month: 2, day: 29, year: 2000),
            ContactBirthday(name: "Nonsense", month: 2, day: 30),
            ContactBirthday(name: "Wrong year", month: 2, day: 29, year: 2001),
            ContactBirthday(name: "Bad month", month: 13, day: 1),
        ]
        let plain = Birthdays.upcoming(people, now: date(2027, 2, 27), days: 7, calendar: calendar)
        XCTAssertEqual(plain.map(\.name), ["Leap"])
        XCTAssertEqual(plain[0].date, calendar.startOfDay(for: date(2027, 2, 28)))
        XCTAssertTrue(plain[0].movedFromLeapDay)

        let leapYear = Birthdays.upcoming(people, now: date(2028, 2, 27), days: 7, calendar: calendar)
        XCTAssertEqual(leapYear[0].date, calendar.startOfDay(for: date(2028, 2, 29)))
        XCTAssertFalse(leapYear[0].movedFromLeapDay)
    }

    func testTheAgentHearsNamesWithDayAndMonthNeverAYearOrAge() {
        let people = [
            ContactBirthday(name: "Anna Nowak", month: 10, day: 11, year: 1985),
            ContactBirthday(name: "Ola", month: 10, day: 12, year: 1990),
            ContactBirthday(name: "Tomek", month: 10, day: 14),
        ]
        let found = Birthdays.upcoming(people, now: date(2026, 10, 11), days: 7, calendar: calendar)
        let reply = VoiceToolReply.birthdays(found, days: 7, calendar: calendar)
        XCTAssertEqual(reply, "birthdays: from the user's Contacts in the next 7 days (today included): \"Anna Nowak\" today; \"Ola\" tomorrow; \"Tomek\" Wed 14 Oct. Ages and years are not shared with you; don't guess them.")
        XCTAssertFalse(reply.contains("1985"))
        XCTAssertFalse(reply.contains("2026"))
        XCTAssertFalse(reply.contains("41"))

        XCTAssertEqual(
            VoiceToolReply.birthdays([], days: 1, calendar: calendar),
            "birthdays: no birthdays saved in the user's Contacts today. Only birthdays saved on contact cards are known; don't guess others.")
    }

    func testALongListIsCutAndCounted() {
        let people = (1...20).map { ContactBirthday(name: String(format: "P%02d", $0), month: 10, day: 12) }
        let found = Birthdays.upcoming(people, now: date(2026, 10, 11), days: 7, calendar: calendar)
        let reply = VoiceToolReply.birthdays(found, days: 7, calendar: calendar)
        XCTAssertTrue(reply.contains("\"P15\" tomorrow; and 5 more."))
        XCTAssertFalse(reply.contains("P16"))
    }
}
