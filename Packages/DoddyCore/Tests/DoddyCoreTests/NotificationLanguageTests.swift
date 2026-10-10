import XCTest
@testable import DoddyCore

/// Polish notification text (ADR-207): what iOS shows outside Doddy follows the iPhone's language.
final class NotificationLanguageTests: XCTestCase {
    private let zone = "Europe/Warsaw"
    // Mon 12 Oct 2026, 20:00 Warsaw; the following days add 86 400 s (no clock change that week).
    private let monday20 = Date(timeIntervalSince1970: 1_791_828_000)

    func testTheIPhonesFirstLanguageDecides() {
        XCTAssertEqual(NotificationLanguage.preferred(["pl-PL", "en-GB"]), .polish)
        XCTAssertEqual(NotificationLanguage.preferred(["pl"]), .polish)
        XCTAssertEqual(NotificationLanguage.preferred(["en-PL", "pl-PL"]), .english, "only the first language counts")
        XCTAssertEqual(NotificationLanguage.preferred(["de-DE"]), .english, "other languages wait for reviewed copy")
        XCTAssertEqual(NotificationLanguage.preferred([]), .english)
    }

    func testPolishCadenceUsesTheRightFormForEachDay() {
        let expected = ["w każdy poniedziałek", "w każdy wtorek", "w każdą środę", "w każdy czwartek",
                        "w każdy piątek", "w każdą sobotę", "w każdą niedzielę"]
        for (offset, phrase) in expected.enumerated() {
            let day = monday20.addingTimeInterval(Double(offset) * 86_400)
            XCTAssertEqual(ReminderFormat.cadence(.weekly, anchor: day, timeZoneID: zone, language: .polish), phrase)
        }
        XCTAssertEqual(ReminderFormat.cadence(.daily, anchor: monday20, timeZoneID: zone, language: .polish), "codziennie")
        XCTAssertEqual(ReminderFormat.cadence(.weekdays, anchor: monday20, timeZoneID: zone, language: .polish), "w dni robocze")
        XCTAssertEqual(ReminderFormat.cadence(.monthly, anchor: monday20, timeZoneID: zone, language: .polish), "co miesiąc, 12. dnia")
        XCTAssertEqual(ReminderFormat.cadence(.weekly, anchor: monday20, timeZoneID: zone), "every Monday", "English stays the default")
    }

    func testPolishTitleBodyAndButtons() throws {
        XCTAssertEqual(NoteReminderCopy.title(.polish), "Przypomnienie")
        XCTAssertEqual(NoteReminderCopy.privateBody(.polish), "Notatka, którą chcesz zobaczyć ponownie.")
        XCTAssertEqual(NoteReminderCopy.body(noteText: "Kod 5678", showNoteText: true, language: .polish), "Kod 5678",
                       "the user's own note is never translated")
        XCTAssertEqual(
            NoteReminderCopy.title(repeating: .weekly, anchor: monday20, timeZoneID: zone, language: .polish),
            "Przypomnienie · w każdy poniedziałek")
        XCTAssertEqual(
            [.openNote, .inAnHour, .tomorrowMorning, .done, .doneThisTime].map { NoteReminderCopy.action($0, .polish) },
            ["Otwórz notatkę", "Za godzinę", "Jutro 09:00", "Gotowe", "Gotowe tym razem"])

        let reminder = MemoryReminder(
            id: UUID(), memoryID: UUID(), trigger: .time(fireAt: monday20, timeZoneID: zone),
            createdAt: monday20.addingTimeInterval(-86_400), repeats: .weekly)
        let request = try XCTUnwrap(NoteReminderNotification.requests(
            for: reminder, noteText: "x", showNoteText: false, at: monday20, language: .polish).first)
        XCTAssertEqual(request.title, "Przypomnienie · w każdy poniedziałek")
        XCTAssertEqual(request.body, "Notatka, którą chcesz zobaczyć ponownie.")
        XCTAssertEqual(request.identifier, reminder.notificationID, "language never changes identifiers")
    }
}
