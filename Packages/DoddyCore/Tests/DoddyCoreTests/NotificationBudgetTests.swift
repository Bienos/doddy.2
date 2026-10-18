import DoddyCore
import Foundation
import XCTest

/// ADR-523: iOS keeps 64 pending notifications per app and silently drops the rest, so the kinds a
/// person sets up share what Doddy's own notifications leave.
final class NotificationBudgetTests: XCTestCase {
    private func notes(_ count: Int) -> [String] { (0..<count).map { MemoryReminder.notificationID(for: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))!) } }
    private func birthdays(_ count: Int) -> [String] { (0..<count).map { Birthdays.notificationID(for: "contact-\($0)") } }
    private func others(_ count: Int) -> [String] { (0..<count).map { "doddy.timer.\($0)" } }

    func testAnEmptyPoolLeavesTheLimitMinusTheReserve() {
        XCTAssertEqual(NotificationBudget.room(for: .noteReminders, pending: []), 64 - 14)
        XCTAssertEqual(NotificationBudget.room(for: .birthdays, pending: []), 64 - 14)
    }

    func testAKindIgnoresItsOwnPendingRequests() {
        XCTAssertEqual(NotificationBudget.room(for: .noteReminders, pending: notes(30)), 50, "the caller counts its own")
        XCTAssertEqual(NotificationBudget.room(for: .birthdays, pending: birthdays(12)), 50)
    }

    func testNoteRemindersAndBirthdaysShareThePool() {
        XCTAssertEqual(NotificationBudget.room(for: .noteReminders, pending: birthdays(20)), 30)
        XCTAssertEqual(NotificationBudget.room(for: .birthdays, pending: notes(45)), 5)
        XCTAssertEqual(NotificationBudget.room(for: .birthdays, pending: notes(50)), 0)
    }

    func testDoddysOwnNotificationsAlwaysKeepTheReserve() {
        // Up to the reserve, routines and timers take nothing from the user-set kinds.
        XCTAssertEqual(NotificationBudget.room(for: .noteReminders, pending: others(14)), 50)
        // Past it, they do: the total never goes over 64.
        XCTAssertEqual(NotificationBudget.room(for: .noteReminders, pending: others(20)), 44)
        XCTAssertEqual(NotificationBudget.room(for: .noteReminders, pending: others(20) + birthdays(20)), 24)
        XCTAssertEqual(NotificationBudget.room(for: .noteReminders, pending: others(70)), 0, "never negative")
    }

    func testAddingNeverTakesThePoolPastTheLimit() {
        for noteCount in stride(from: 0, through: 50, by: 5) {
            for other in [0, 8, 14, 20] {
                let room = NotificationBudget.room(for: .birthdays, pending: notes(noteCount) + others(other))
                guard noteCount + other <= NotificationBudget.systemLimit else {
                    // Already over (Doddy's own notifications grew past the reserve after the notes
                    // were set): nothing more is added. The budget can't take back what iOS holds.
                    XCTAssertEqual(room, 0, "notes \(noteCount), others \(other)")
                    continue
                }
                XCTAssertLessThanOrEqual(noteCount + other + min(Birthdays.maxReminders, room), NotificationBudget.systemLimit,
                                         "notes \(noteCount), others \(other)")
            }
        }
    }

    func testKinds() {
        XCTAssertEqual(NotificationBudget.kind(of: notes(1)[0]), .noteReminders)
        XCTAssertEqual(NotificationBudget.kind(of: birthdays(1)[0]), .birthdays)
        XCTAssertNil(NotificationBudget.kind(of: "doddy.timer.1"))
        XCTAssertNil(NotificationBudget.kind(of: "morning-checkin-2"))
    }

    func testBirthdaysStopAtWhatThePoolLeaves() {
        let now = Date(timeIntervalSince1970: 1_791_630_120)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let many = (1...30).map { BirthdayContact(id: "c\($0)", name: "Person \($0)", month: ($0 % 12) + 1, day: 10) }
        let picked = Set(many.map(\.id))
        XCTAssertEqual(Birthdays.toSchedule(many, picked: picked, now: now, calendar: calendar).count, Birthdays.maxReminders,
                       "no pending notifications: the old cap of 20")
        XCTAssertEqual(Birthdays.toSchedule(many, picked: picked, now: now, calendar: calendar, pending: notes(42)).count, 8)
        XCTAssertEqual(Birthdays.toSchedule(many, picked: picked, now: now, calendar: calendar, pending: notes(50)).count, 0)
        let soonest = Birthdays.toSchedule(many, picked: picked, now: now, calendar: calendar).prefix(8).map(\.id)
        XCTAssertEqual(Birthdays.toSchedule(many, picked: picked, now: now, calendar: calendar, pending: notes(42)).map(\.id),
                       Array(soonest), "the next birthdays are the ones kept")
    }
}
