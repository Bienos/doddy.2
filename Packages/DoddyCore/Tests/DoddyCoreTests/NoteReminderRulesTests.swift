import XCTest
@testable import DoddyCore

/// Pure M4a rules: which quick picks exist, what moment they resolve to, what a notification says.
final class NoteReminderRulesTests: XCTestCase {
    private var warsaw: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return cal
    }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testQuickPicksOnASaturdayAfternoon() {
        // Sat 10 Oct 2026, 13:02 Warsaw.
        let options = ReminderQuickPick.options(now: date("2026-10-10T11:02:00Z"), calendar: warsaw)
        XCTAssertEqual(options.map(\.pick), [.thisEvening, .tomorrowMorning, .mondayMorning])
        XCTAssertEqual(options.map(\.date), [
            date("2026-10-10T16:00:00Z"),  // 18:00 CEST
            date("2026-10-11T07:00:00Z"),  // Sun 09:00
            date("2026-10-12T07:00:00Z"),  // Mon 09:00
        ])
    }

    func testEveningIsHiddenLateAndMondayIsNotRepeatedOnSunday() {
        // Sun 11 Oct 2026, 17:45 Warsaw: too late for 18:00, and tomorrow already is Monday.
        let options = ReminderQuickPick.options(now: date("2026-10-11T15:45:00Z"), calendar: warsaw)
        XCTAssertEqual(options.map(\.pick), [.tomorrowMorning])
        XCTAssertEqual(options.first?.date, date("2026-10-12T07:00:00Z"))
    }

    func testTomorrowMorningAcrossTheDaylightSavingChange() {
        // Clocks go back on Sun 25 Oct 2026: 09:00 that day is CET (UTC+1).
        let tomorrow = ReminderQuickPick.tomorrowMorning(after: date("2026-10-24T20:00:00Z"), calendar: warsaw)
        XCTAssertEqual(tomorrow, date("2026-10-25T08:00:00Z"))
    }

    func testNotificationBodyIsPrivateUnlessTurnedOnAndShortened() {
        let long = String(repeating: "a", count: 300)
        XCTAssertEqual(NoteReminderCopy.body(noteText: long, showNoteText: false), "A note you asked to see again.")
        let shown = NoteReminderCopy.body(noteText: long, showNoteText: true)
        XCTAssertEqual(shown.count, NoteReminderLimits.maxBodyLength)
        XCTAssertTrue(shown.hasSuffix("…"))
        XCTAssertEqual(NoteReminderCopy.body(noteText: " Short note \n", showNoteText: true), "Short note")
    }

    func testReceiptTextNamesTheZone() {
        let text = ReminderFormat.full(
            date("2026-10-11T07:00:00Z"), timeZoneID: "Europe/Warsaw", locale: Locale(identifier: "en_GB"))
        XCTAssertEqual(text, "Sun 11 Oct, 09:00 · Warsaw time")
        XCTAssertEqual(ReminderFormat.zoneName("America/New_York"), "New York time")
    }

    func testNoteRemindersShipAlongsideAppleReminders() {
        XCTAssertEqual(CapabilityCatalog.m0.status(of: .noteReminders), .notImplemented(plannedMilestone: "M4a"))
        XCTAssertFalse(CapabilityCatalog.v1Voice.isAvailable(.noteReminders))
        XCTAssertFalse(CapabilityCatalog.withMessaging(serverConfigured: true).isAvailable(.noteReminders))
        for configured in [false, true] {
            let shipping = CapabilityCatalog.shipping(serverConfigured: configured)
            XCTAssertTrue(shipping.isAvailable(.noteReminders), "no server needed")
            XCTAssertTrue(shipping.isAvailable(.reminders), "Apple Reminders stay available")
            // Exactly one claim on top of the messaging catalog.
            for capability in Capability.allCases where capability != .noteReminders {
                XCTAssertEqual(
                    shipping.status(of: capability),
                    CapabilityCatalog.withMessaging(serverConfigured: configured).status(of: capability), "\(capability)")
            }
        }
    }
}
