import XCTest
@testable import DoddyCore

// Today's reminder editing (owner, 13 Nov 2026): which single write an edit becomes.
final class ReminderEditTests: XCTestCase {
    private var warsaw: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        warsaw.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private let before = ReminderSnapshot(
        id: "r1", title: "Call the dentist", listTitle: "Reminders",
        due: ReminderDue(year: 2026, month: 11, day: 13, hour: 17, minute: 0, timeZoneID: "Europe/Warsaw"), markerURL: nil)

    func testTitlesAreTrimmedAndChecked() {
        XCTAssertEqual(try ReminderEdit.title("  Buy milk \n").get(), "Buy milk")
        XCTAssertEqual(ReminderEdit.title("   "), .failure(.emptyTitle))
        XCTAssertEqual(ReminderEdit.title(String(repeating: "a", count: ReminderDetails.maxTitleLength + 1)), .failure(.titleTooLong))
    }

    func testADueWithAndWithoutATime() {
        let timed = ReminderEdit.due(date(2026, 11, 14, 9, 30), hasTime: true, calendar: warsaw)
        XCTAssertEqual(timed, ReminderDue(year: 2026, month: 11, day: 14, hour: 9, minute: 30, timeZoneID: "Europe/Warsaw"))
        let day = ReminderEdit.due(date(2026, 11, 14, 9, 30), hasTime: false, calendar: warsaw)
        XCTAssertEqual(day, ReminderDue(year: 2026, month: 11, day: 14, timeZoneID: nil))
        XCTAssertFalse(day.hasTime)
    }

    func testOnlyTheDueMoving() throws {
        let later = ReminderDue(year: 2026, month: 11, day: 13, hour: 18, minute: 0, timeZoneID: "Europe/Warsaw")
        XCTAssertEqual(try ReminderEdit.change(title: "Call the dentist", due: later, from: before).get(), .due(later))
    }

    func testANewTitleWithOrWithoutANewDue() throws {
        XCTAssertEqual(try ReminderEdit.change(title: " Call Dr Nowak ", due: nil, from: before).get(),
                       .details(newDue: nil, ReminderDetailsChange(newTitle: "Call Dr Nowak")))
        let later = ReminderDue(year: 2026, month: 11, day: 14, hour: 8, minute: 0, timeZoneID: "Europe/Warsaw")
        XCTAssertEqual(try ReminderEdit.change(title: "Call Dr Nowak", due: later, from: before).get(),
                       .details(newDue: later, ReminderDetailsChange(newTitle: "Call Dr Nowak")))
        // The same due as before is no move.
        XCTAssertEqual(try ReminderEdit.change(title: "Call Dr Nowak", due: before.due, from: before).get(),
                       .details(newDue: nil, ReminderDetailsChange(newTitle: "Call Dr Nowak")))
    }

    func testNothingChangedAndBadTitlesWriteNothing() {
        XCTAssertEqual(ReminderEdit.change(title: "Call the dentist", due: before.due, from: before), .failure(.nothingChanged))
        XCTAssertEqual(ReminderEdit.change(title: "Call the dentist", due: nil, from: before), .failure(.nothingChanged))
        XCTAssertEqual(ReminderEdit.change(title: "  ", due: nil, from: before), .failure(.emptyTitle))
    }
}
