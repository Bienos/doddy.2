import Foundation
import XCTest
@testable import DoddyCore

/// Today's own add and edit of a reminder (owner, 13 Nov 2026).
final class ReminderFormTests: XCTestCase {
    private func calendar(_ zone: String, _ identifier: Calendar.Identifier = .gregorian) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ text: String, zone: String = "Europe/Warsaw") -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    // MARK: Title and notes

    func testTitleIsTrimmedAndOneLine() {
        XCTAssertEqual(ReminderForm.checkTitle("  Buy milk \n"), .ok("Buy milk"))
        XCTAssertEqual(ReminderForm.checkTitle("Call\nmum"), .ok("Call mum"))
        XCTAssertEqual(ReminderForm.checkTitle("   \n "), .empty)
        XCTAssertEqual(ReminderForm.checkTitle(""), .empty)
        XCTAssertEqual(ReminderForm.checkTitle(String(repeating: "a", count: ReminderDetails.maxTitleLength)),
                       .ok(String(repeating: "a", count: ReminderDetails.maxTitleLength)))
        XCTAssertEqual(ReminderForm.checkTitle(String(repeating: "a", count: ReminderDetails.maxTitleLength + 1)), .tooLong)
    }

    func testNotesLeftAsReadStayExactlySo() {
        XCTAssertEqual(ReminderForm.checkNotes("Gate B \n", original: "Gate B \n"), .ok("Gate B \n"))
        XCTAssertEqual(ReminderForm.checkNotes("", original: nil), .ok(nil))
        XCTAssertEqual(ReminderForm.checkNotes("  Gate C  ", original: "Gate B"), .ok("Gate C"))
        XCTAssertEqual(ReminderForm.checkNotes("   ", original: "Gate B"), .ok(nil), "emptied notes are cleared")
        XCTAssertEqual(ReminderForm.checkNotes(String(repeating: "n", count: ReminderDetails.maxReplacedNotesLength + 1), original: nil), .tooLong)
    }

    // MARK: Due from the pickers

    func testDueWithAndWithoutATime() {
        let warsaw = calendar("Europe/Warsaw")
        let picked = date("2026-11-14 18:30")
        XCTAssertEqual(ReminderForm.due(from: picked, hasTime: true, calendar: warsaw),
                       ReminderDue(year: 2026, month: 11, day: 14, hour: 18, minute: 30, timeZoneID: "Europe/Warsaw"))
        let day = ReminderForm.due(from: picked, hasTime: false, calendar: warsaw)
        XCTAssertEqual(day, ReminderDue(year: 2026, month: 11, day: 14, timeZoneID: "Europe/Warsaw"))
        XCTAssertFalse(day.hasTime)
        XCTAssertNil(day.minute)
    }

    func testDueIsGregorianWhateverCalendarTheIPhoneUses() {
        let buddhist = calendar("Asia/Bangkok", .buddhist)
        let picked = date("2026-11-14 09:05", zone: "Asia/Bangkok")
        let due = ReminderForm.due(from: picked, hasTime: true, calendar: buddhist)
        XCTAssertEqual(due.year, 2026, "not 2569, the Buddhist year")
        XCTAssertEqual(due.hour, 9)
        XCTAssertEqual(due.minute, 5)
        XCTAssertEqual(due.timeZoneID, "Asia/Bangkok")
    }

    func testDueReadBackInThePickersIsTheSameWallClock() {
        let warsaw = calendar("Europe/Warsaw")
        let due = ReminderDue(year: 2026, month: 11, day: 14, hour: 18, minute: 30, timeZoneID: "Europe/Warsaw")
        let shown = ReminderForm.pickerDate(for: due, local: warsaw, otherwise: .distantPast)
        XCTAssertEqual(shown, date("2026-11-14 18:30"))
        XCTAssertTrue(EventChange.sameDue(ReminderForm.due(from: shown, hasTime: true, calendar: warsaw), due))
        XCTAssertEqual(ReminderForm.pickerDate(for: nil, local: warsaw, otherwise: .distantPast), .distantPast)
    }

    func testSuggestedDueIsTheNextFullHour() {
        let warsaw = calendar("Europe/Warsaw")
        XCTAssertEqual(ReminderForm.suggestedDue(now: date("2026-11-13 10:20"), calendar: warsaw), date("2026-11-13 11:00"))
        XCTAssertEqual(ReminderForm.suggestedDue(now: date("2026-11-13 23:45"), calendar: warsaw), date("2026-11-14 00:00"))
    }

    // MARK: Edit

    private let before = ReminderSnapshot(
        id: "r1", title: "Buy milk", listTitle: "Reminders",
        due: ReminderDue(year: 2026, month: 11, day: 14, hour: 9, minute: 0, timeZoneID: "Europe/Warsaw"),
        markerURL: nil, notes: "2 litres")

    func testAnEditThatChangesNothingWritesNothing() {
        let same = ReminderEdit(title: "Buy milk", notes: "2 litres", due: before.due)
        XCTAssertTrue(same.changesNothing(before))
        XCTAssertFalse(same.movesDue(from: before))
        XCTAssertFalse(ReminderEdit(title: "Buy oat milk", notes: "2 litres", due: before.due).changesNothing(before))
        XCTAssertFalse(ReminderEdit(title: "Buy milk", notes: nil, due: before.due).changesNothing(before))
        let noDue = ReminderEdit(title: "Buy milk", notes: "2 litres", due: nil)
        XCTAssertFalse(noDue.changesNothing(before))
        XCTAssertTrue(noDue.movesDue(from: before))
    }

    func testReadBackConfirmsOnlyAnOpenReminderShowingEveryChange() {
        let due = ReminderDue(year: 2026, month: 11, day: 15, timeZoneID: "Europe/Warsaw")
        let edit = ReminderEdit(title: "Buy oat milk", notes: nil, due: due)
        let back = ReminderSnapshot(id: "r1", title: "Buy oat milk", listTitle: "Reminders", due: due, markerURL: nil, notes: nil)
        XCTAssertTrue(edit.confirms(back))
        let done = ReminderSnapshot(id: "r1", title: "Buy oat milk", listTitle: "Reminders", due: due, markerURL: nil, isCompleted: true)
        XCTAssertFalse(edit.confirms(done), "done elsewhere is not this change")
        let oldTitle = ReminderSnapshot(id: "r1", title: "Buy milk", listTitle: "Reminders", due: due, markerURL: nil)
        XCTAssertFalse(edit.confirms(oldTitle))
        let notesKept = ReminderSnapshot(id: "r1", title: "Buy oat milk", listTitle: "Reminders", due: due, markerURL: nil, notes: "2 litres")
        XCTAssertFalse(edit.confirms(notesKept))
        let dueKept = ReminderSnapshot(id: "r1", title: "Buy oat milk", listTitle: "Reminders", due: before.due, markerURL: nil)
        XCTAssertFalse(edit.confirms(dueKept))
    }

    // MARK: Calendar app

    func testCalendarAppLinkCountsSecondsFrom2001() {
        XCTAssertEqual(CalendarAppLink.url(at: Date(timeIntervalSinceReferenceDate: 784_800_000.7))?.absoluteString, "calshow:784800000")
        XCTAssertEqual(CalendarAppLink.url(at: Date(timeIntervalSinceReferenceDate: 0))?.absoluteString, "calshow:0")
        XCTAssertEqual(CalendarAppLink.url(at: Date(timeIntervalSinceReferenceDate: 0))?.scheme, "calshow")
    }
}
