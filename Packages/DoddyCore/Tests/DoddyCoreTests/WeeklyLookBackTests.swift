import XCTest
@testable import DoddyCore

final class WeeklyLookBackTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ offset: Double) -> Date { now.addingTimeInterval(offset * 86_400) }

    private func note(_ text: String, at date: Date, category: MemoryCategory = .fact) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: .explicitText, category: category, capturedAt: date)
    }

    func testOnlyTheLastSevenDaysAndOnlyWhatWasDone() throws {
        let notes = [
            try note("Spare key in the blue tin", at: day(-1)),
            try note("Marta recommends Dune", at: day(-3)),
            try note("Old note", at: day(-9)),
            try note("Shopping", at: day(-2), category: .list),
        ]
        let record = try note("Shopping", at: day(-20), category: .list)
        let list = DoddyList(record: record, items: [
            ListItem(id: UUID(), listID: record.id, text: "milk", source: .typed, addedAt: day(-10), doneAt: day(-2), position: 0),
            ListItem(id: UUID(), listID: record.id, text: "eggs", source: .typed, addedAt: day(-10), doneAt: day(-8), position: 1),
            ListItem(id: UUID(), listID: record.id, text: "bread", source: .typed, addedAt: day(-1), doneAt: nil, position: 2),
        ])
        let activity = [
            ActivityEntry(at: day(-1), app: .calendar, title: "Add event", detail: nil, outcome: .done),
            ActivityEntry(at: day(-2), app: .calendar, title: "Add event", detail: nil, outcome: .done),
            ActivityEntry(at: day(-2), app: .reminders, title: "Add reminder", detail: nil, outcome: .done),
            ActivityEntry(at: day(-2), app: .reminders, title: "Add reminder", detail: nil, outcome: .notSure),
            ActivityEntry(at: day(-3), app: .reminders, title: "Change reminder", detail: nil, outcome: .done, undoState: .undone(day(-3))),
            ActivityEntry(at: day(-12), app: .timers, title: "Start timer", detail: nil, outcome: .done),
        ]
        let events = [
            CalendarEventSummary(title: "Dentist", start: day(2), end: day(2.05), allDay: false),
            CalendarEventSummary(title: "Last week", start: day(-1), end: day(-0.9), allDay: false),
            CalendarEventSummary(title: "Far off", start: day(10), end: day(10.1), allDay: false),
        ]
        let week = WeeklyLookBack.make(notes: notes, lists: [list], activity: activity, events: events, remindersDue: 3, now: now)
        XCTAssertEqual(week.notes, ["Spare key in the blue tin", "Marta recommends Dune"], "newest first; no lists, nothing older")
        XCTAssertEqual(week.noteCount, 2)
        XCTAssertEqual(week.ticked, 1)
        XCTAssertEqual(week.doneByApp.map(\.app), [.calendar, .reminders])
        XCTAssertEqual(week.doneByApp.map(\.count), [2, 1], "not sure and undone don't count")
        XCTAssertEqual(week.upcomingEvents?.map(\.title), ["Dentist"])
        XCTAssertEqual(week.remindersDue, 3)
        XCTAssertFalse(week.isQuiet)
    }

    func testConnectionsOffMeansNothingWasRead() {
        let week = WeeklyLookBack.make(notes: [], lists: [], activity: [], events: nil, remindersDue: nil, now: now)
        XCTAssertNil(week.upcomingEvents)
        XCTAssertNil(week.remindersDue)
        XCTAssertTrue(week.isQuiet)
    }

    func testSettingsAndTheNotificationSayNothingPersonal() {
        let defaults = UserDefaults(suiteName: "WeeklyLookBackTests")!
        defaults.removePersistentDomain(forName: "WeeklyLookBackTests")
        XCTAssertEqual(WeeklyLookBackSettings.stored(defaults), WeeklyLookBackSettings(isOn: false, weekday: 1, hour: 19, minute: 0), "off until turned on; Sunday 19:00, after the tidy-up")
        WeeklyLookBackSettings(isOn: true, weekday: 9, hour: 30, minute: -1).store(defaults)
        XCTAssertEqual(WeeklyLookBackSettings.stored(defaults), WeeklyLookBackSettings(isOn: true, weekday: 7, hour: 23, minute: 0))
        XCTAssertEqual(WeeklyLookBack.title(.english), "Your week with Doddy")
        XCTAssertEqual(WeeklyLookBack.body(.polish), "Krótkie podsumowanie, gdy zechcesz.")
        XCTAssertTrue(WeeklyLookBack.isLookBack(notificationID: WeeklyLookBack.notificationID))
    }
}
