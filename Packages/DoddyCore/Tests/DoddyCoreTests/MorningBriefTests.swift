import DoddyCore
import XCTest

/// ADR-212. Synthetic calendar data in Europe/Warsaw.
final class MorningBriefTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()

    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12 + dayOffset))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func time(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour!, parts.minute!)
    }

    private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarEventSummary {
        CalendarEventSummary(id: "ev-\(title)", title: title, start: start, end: end, allDay: allDay)
    }

    private func brief(_ source: BriefSource, notes: [BriefNoteReminder] = [], name: String? = nil, now: Date? = nil) -> MorningBrief {
        MorningBrief.compose(source: source, noteReminders: notes, name: name, now: now ?? at(7, 30), calendar: calendar, timeText: time)
    }

    private func agenda(_ events: [CalendarEventSummary], _ reminders: [ReminderSummary] = [], now: Date? = nil) -> TodayAgenda {
        TodayAgenda(events: events, reminders: reminders, now: now ?? at(7, 30), calendar: calendar)
    }

    // MARK: What it says

    func testAFullMorning() {
        let day = agenda(
            [
                event("Marta's birthday", at(0), at(0, dayOffset: 1), allDay: true),
                event("Dentist", at(10), at(11)),
                event("Gym", at(18), at(19)),
            ],
            [
                ReminderSummary(id: "r1", title: "Pay rent", due: at(0, dayOffset: -2), dueHasTime: false),
                ReminderSummary(id: "r2", title: "Call Adam", due: at(17), dueHasTime: true),
            ])
        let result = brief(.agenda(day, calendarRead: true, remindersRead: true),
                           notes: [BriefNoteReminder(fireAt: at(14), noteText: "Bring the spare key")], name: "Patryk")
        XCTAssertEqual(result.lines.map(\.text), [
            "Good morning, Patryk.",
            "3 events left today: all day, Marta's birthday; first Dentist at 10:00.",
            "2 reminders due: Pay rent and Call Adam. One is from an earlier day.",
            "A note reminder today: at 14:00, “Bring the spare key”.",
        ])
        XCTAssertEqual(result.spokenText, result.lines.map(\.text).joined(separator: " "))
    }

    func testAnEmptyDaySaysSoPlainly() {
        let result = brief(.agenda(agenda([]), calendarRead: true, remindersRead: true))
        XCTAssertEqual(result.lines.map(\.text), [
            "Good morning.",
            "No events left in your calendar today.",
            "No reminders due today.",
        ])
    }

    func testOneTimedEvent() {
        let result = brief(.agenda(agenda([event("Dentist", at(10), at(11))]), calendarRead: true, remindersRead: false))
        XCTAssertEqual(result.lines.map(\.text), [
            "Good morning.",
            "One event left today: Dentist at 10:00.",
            "Reminders is off, so your reminders aren't in this brief.",
        ])
    }

    func testMoreThanTheCardShowsIsCountedAndNamedUpToThree() {
        let reminders = (1...7).map { ReminderSummary(id: "r\($0)", title: "Task \($0)", due: at(9 + $0), dueHasTime: true) }
        let result = brief(.agenda(agenda([], reminders), calendarRead: false, remindersRead: true))
        XCTAssertEqual(result.lines[1].text, "7 reminders due: Task 1, Task 2 and Task 3, and 4 more.")
        XCTAssertEqual(result.lines[2].text, "Calendar is off, so events aren't in this brief.")
    }

    func testNotConnectedAndPausedNeverReadOrGuess() {
        XCTAssertEqual(brief(.notConnected).lines.map(\.text), [
            "Good morning.",
            "Calendar and Reminders are off in Settings, Connections, so they aren't in this brief.",
        ])
        XCTAssertEqual(brief(.paused).lines.map(\.kind), [.greeting, .notice])
    }

    func testOnlyNoteRemindersLaterTodayAreIncluded() {
        let notes = [
            BriefNoteReminder(fireAt: at(6), noteText: "Already fired"),
            BriefNoteReminder(fireAt: at(21), noteText: "Water the plants"),
            BriefNoteReminder(fireAt: at(9), noteText: "Take the parcel\nfrom the locker"),
            BriefNoteReminder(fireAt: at(9, dayOffset: 1), noteText: "Tomorrow"),
        ]
        let result = brief(.notConnected, notes: notes)
        XCTAssertEqual(result.lines.last?.text,
                       "2 note reminders today: at 09:00, “Take the parcel from the locker” and at 21:00, “Water the plants”.")
    }

    func testBlankNameAndLongTitles() {
        let long = String(repeating: "a", count: 120)
        let result = brief(.agenda(agenda([event(long, at(10), at(11))]), calendarRead: true, remindersRead: true), name: "  ")
        XCTAssertEqual(result.lines[0].text, "Good morning.")
        XCTAssertTrue(result.lines[1].text.contains(String(repeating: "a", count: 79) + "…"))
    }

    func testNoPressureWords() {
        let reminders = (1...4).map { ReminderSummary(id: "r\($0)", title: "Task \($0)", due: at(0, dayOffset: -$0), dueHasTime: false) }
        let text = brief(.agenda(agenda([], reminders), calendarRead: true, remindersRead: true)).spokenText.lowercased()
        for word in ["overdue", "late", "should", "must", "don't forget", "great", "amazing", "!"] {
            XCTAssertFalse(text.contains(word), "no pressure or praise: \(word)")
        }
        XCTAssertTrue(text.contains("4 are from earlier days"))
    }

    // MARK: When it shows

    func testShowsFromItsTimeForFiveHoursUnlessClosed() {
        let schedule = MorningBriefSchedule(isOn: true, hour: 7, minute: 30)
        XCTAssertFalse(schedule.isShowing(now: at(7, 29), dismissedDay: nil, calendar: calendar))
        XCTAssertTrue(schedule.isShowing(now: at(7, 30), dismissedDay: nil, calendar: calendar))
        XCTAssertTrue(schedule.isShowing(now: at(12, 29), dismissedDay: nil, calendar: calendar))
        XCTAssertFalse(schedule.isShowing(now: at(12, 30), dismissedDay: nil, calendar: calendar))
        XCTAssertFalse(schedule.isShowing(now: at(9), dismissedDay: "2026-10-12", calendar: calendar), "closed today")
        XCTAssertTrue(schedule.isShowing(now: at(9), dismissedDay: "2026-10-11", calendar: calendar), "closed yesterday")
        XCTAssertFalse(MorningBriefSchedule(isOn: false).isShowing(now: at(9), dismissedDay: nil, calendar: calendar))
    }

    func testLateBriefStopsAtMidnight() {
        let schedule = MorningBriefSchedule(isOn: true, hour: 22, minute: 0)
        XCTAssertTrue(schedule.isShowing(now: at(23, 59), dismissedDay: nil, calendar: calendar))
        XCTAssertFalse(schedule.isShowing(now: at(0, 30, dayOffset: 1), dismissedDay: nil, calendar: calendar))
    }

    func testInvalidTimeFallsBackToDefault() {
        let schedule = MorningBriefSchedule(isOn: true, hour: 25, minute: 0)
        XCTAssertEqual(schedule.hour, MorningBriefSchedule.defaultHour)
        XCTAssertEqual(schedule.minute, MorningBriefSchedule.defaultMinute)
        XCTAssertEqual(MorningBriefSchedule.dayKey(at(1), calendar: calendar), "2026-10-12")
    }

    func testNotificationIsTheSameEveryDayAndHoldsNothingPersonal() {
        XCTAssertEqual(MorningBriefNotification.identifier, "doddy.brief.daily")
        XCTAssertTrue(MorningBriefNotification.isBrief("doddy.brief.daily"))
        XCTAssertFalse(MorningBriefNotification.isBrief("doddy.note.x"))
        XCTAssertFalse(MemoryReminder.reminderID(fromNotificationID: MorningBriefNotification.identifier) != nil,
                       "note-reminder clean-up never mistakes the brief for one of its own")
        XCTAssertEqual(MorningBriefNotification.body, "Your day at a glance is ready in Doddy.")
    }
}
