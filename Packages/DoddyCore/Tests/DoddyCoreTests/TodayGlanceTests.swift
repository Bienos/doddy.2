import DoddyCore
import XCTest

final class TodayGlanceTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()

    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10 + dayOffset))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarEventSummary {
        CalendarEventSummary(id: "ev-\(title)", title: title, start: start, end: end, allDay: allDay)
    }

    private func reminder(_ title: String, _ due: Date?, time: Bool = true) -> ReminderSummary {
        ReminderSummary(id: "r-\(title)", title: title, due: due, dueHasTime: time)
    }

    private func clock(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private func free(_ slot: FreeDay.Slot) -> String { "free \(clock(slot.start))–\(clock(slot.end))" }

    /// The timeline as words: event titles, and "free 13:00–14:00" for the gaps.
    private func describe(_ items: [TodayTimelineItem]) -> [String] {
        items.map { item in
            switch item {
            case .event(let event): event.title
            case .free(let slot): free(slot)
            }
        }
    }

    private var day: [CalendarEventSummary] {
        [
            event("Standup", at(9), at(9, 15)),
            event("Work block", at(10), at(12, 30)),
            event("Lunch", at(12), at(13)),
            event("Dentist", at(14), at(15)),
            event("Call", at(15), at(15, 20)),
            event("Dinner", at(19), at(21)),
            event("Name day", at(0), at(0, dayOffset: 1), allDay: true),
            event("Gym", at(7, dayOffset: 1), at(8, dayOffset: 1)),
            event("Holiday", at(0, dayOffset: 1), at(0, dayOffset: 2), allDay: true),
            event("Flight", at(11, dayOffset: 1), at(13, dayOffset: 1)),
            event("Day after", at(9, dayOffset: 2), at(10, dayOffset: 2)),
        ]
    }

    func testNowNextAndTheRestOfTheDayWithFreeTime() {
        let glance = TodayGlance(events: day, reminders: [], now: at(11), calendar: calendar)
        XCTAssertEqual(glance.allDay.map(\.title), ["Name day"])
        XCTAssertEqual(glance.onNow.map(\.title), ["Work block"], "standup is over; lunch hasn't started")
        XCTAssertEqual(glance.nextUp?.title, "Lunch")
        XCTAssertNil(glance.freeBeforeNext, "the work block runs into lunch")
        XCTAssertEqual(describe(glance.later), ["free 13:00–14:00", "Dentist", "Call", "free 15:20–19:00", "Dinner"])
        XCTAssertEqual(glance.eventsLeft, 6, "all-day, on now and the four still to come")
    }

    func testFreeTimeBeforeTheNextEventAfterWhatIsOnNow() {
        let events = [event("Workshop", at(9), at(11)), event("Review", at(13), at(14))]
        let glance = TodayGlance(events: events, reminders: [], now: at(10), calendar: calendar)
        XCTAssertEqual(glance.onNow.map(\.title), ["Workshop"])
        XCTAssertEqual(glance.nextUp?.title, "Review")
        XCTAssertEqual(glance.freeBeforeNext.map(free), "free 11:00–13:00")
        XCTAssertEqual(glance.freeBeforeNext?.minutes, 120)
        XCTAssertEqual(glance.later, [])
    }

    func testFreeTimeIgnoresShortGapsMergesOverlapsAndStopsAtMidnight() {
        let events = [
            event("A", at(9), at(10)),
            event("B", at(10, 20), at(11)),          // 20 min after A: too short
            event("C", at(10, 30), at(12)),          // overlaps B
            event("D", at(13), at(13)),              // no length, still splits
            event("E", at(14), at(14, 30)),
            event("Late", at(23), at(2, dayOffset: 1)),
            event("Party", at(0), at(0, dayOffset: 1), allDay: true),
        ]
        let slots = TodayGlance.freeBetweenEvents(events, now: at(8), calendar: calendar)
        XCTAssertEqual(slots.map(free), ["free 12:00–13:00", "free 13:00–14:00", "free 14:30–23:00"],
                       "not before the first event, not after the last; 20 minutes is too short")
        XCTAssertEqual(slots.last?.minutes, 510)
        XCTAssertEqual(TodayGlance.freeBetweenEvents(events, now: at(13, 30), calendar: calendar).map(free), ["free 14:30–23:00"],
                       "free time starts from now, never in the past")
        let evening = TodayGlance.freeBetweenEvents([event("A", at(9), at(10)), event("B", at(12), at(13))], now: at(8), calendar: calendar)
        XCTAssertEqual(evening.map(free), ["free 10:00–12:00"], "the evening after the last event isn't a gap")
    }

    func testLaterIsCappedAndCounted() {
        let events = (0..<10).map { event("E\($0)", at(12 + $0), at(12 + $0, 30)) }
        let glance = TodayGlance(events: events, reminders: [], now: at(11), calendar: calendar)
        XCTAssertEqual(glance.nextUp?.title, "E0")
        let listed = glance.later.compactMap { if case .event(let e) = $0 { e.title } else { nil } }
        XCTAssertEqual(listed, ["E1", "E2", "E3", "E4", "E5", "E6"])
        XCTAssertEqual(glance.moreLater, 3)
        XCTAssertEqual(describe(glance.later).last, "E6", "no gap after the last listed event")
        XCTAssertEqual(describe(glance.later).first, "free 12:30–13:00")
    }

    func testRemindersTodayCountOverdueAndTomorrowsGoToTomorrow() {
        let reminders = [
            reminder("Pay rent", at(0, dayOffset: -1), time: false),
            reminder("Call mum", at(18)),
            reminder("Taxes", at(9)),
            reminder("Someday", nil, time: false),
            reminder("Buy milk", at(0, dayOffset: 1), time: false),
            reminder("Pick up parcel", at(10, dayOffset: 1)),
        ]
        let glance = TodayGlance(events: day, reminders: reminders, now: at(11), calendar: calendar)
        XCTAssertEqual(glance.reminders.map(\.title), ["Pay rent", "Taxes", "Call mum"])
        XCTAssertEqual(glance.remindersDue, 3)
        XCTAssertEqual(glance.overdue, 2, "yesterday's day-only and 09:00 today; 18:00 is still ahead")
        XCTAssertEqual(glance.tomorrow, [
            .event(event("Holiday", at(0, dayOffset: 1), at(0, dayOffset: 2), allDay: true)),
            .event(event("Gym", at(7, dayOffset: 1), at(8, dayOffset: 1))),
            .reminder(reminder("Pick up parcel", at(10, dayOffset: 1))),
        ])
        XCTAssertEqual(glance.moreTomorrow, 2, "the flight and the day-only reminder")
    }

    func testSwitchedOffSourcesAreLeftOutEvenIfPassed() {
        let reminders = [reminder("Call mum", at(18))]
        let calendarOnly = TodayGlance(events: day, reminders: reminders, now: at(11), calendar: calendar, remindersOn: false)
        XCTAssertEqual(calendarOnly.remindersDue, 0)
        XCTAssertTrue(calendarOnly.reminders.isEmpty)
        let remindersOnly = TodayGlance(events: day, reminders: reminders, now: at(11), calendar: calendar, calendarOn: false)
        XCTAssertNil(remindersOnly.nextUp)
        XCTAssertEqual(remindersOnly.eventsLeft, 0)
        XCTAssertTrue(remindersOnly.tomorrow.isEmpty)
    }

    func testNextUpStatus() {
        let dentist = event("Dentist", at(14), at(15))
        XCTAssertEqual(NextUpStatus.of(dentist, at: at(13, 35)), .startsIn(minutes: 25))
        XCTAssertEqual(NextUpStatus.of(dentist, at: at(13, 59).addingTimeInterval(30)), .startsIn(minutes: 1), "never 'in 0 min'")
        XCTAssertEqual(NextUpStatus.of(dentist, at: at(14)), .now(until: at(15)))
        XCTAssertEqual(NextUpStatus.of(dentist, at: at(15)), .over)
    }

    func testSummaryIsBuiltFromTheCountsInBothLanguages() {
        let reminders = [reminder("Pay rent", at(0, dayOffset: -1), time: false), reminder("Call mum", at(18))]
        let glance = TodayGlance(events: day, reminders: reminders, now: at(11), calendar: calendar)
        XCTAssertEqual(TodayGlanceText.summary(glance, nextTime: "12:00", .english),
                       "6 events left, the next at 12:00 · 2 reminders, 1 overdue")
        XCTAssertEqual(TodayGlanceText.summary(glance, nextTime: "12:00", .polish),
                       "Jeszcze 6 wydarzeń, następne o 12:00 · 2 przypomnienia, w tym 1 zaległe")

        let one = TodayGlance(events: [event("Dentist", at(14), at(15))], reminders: [], now: at(11), calendar: calendar)
        XCTAssertEqual(TodayGlanceText.summary(one, nextTime: "14:00", .english), "1 event left, the next at 14:00 · No reminders due")
        XCTAssertEqual(TodayGlanceText.summary(one, nextTime: "14:00", .polish), "Jeszcze 1 wydarzenie, następne o 14:00 · Brak przypomnień na dziś")

        let onNowOnly = TodayGlance(events: [event("Dentist", at(14), at(15))], reminders: [], now: at(14, 30), calendar: calendar, remindersOn: false)
        XCTAssertEqual(TodayGlanceText.summary(onNowOnly, nextTime: nil, .english), "1 event left", "no 'next' when nothing is still to start")

        let empty = TodayGlance(events: [], reminders: [], now: at(11), calendar: calendar)
        XCTAssertEqual(TodayGlanceText.summary(empty, nextTime: nil, .english), "Nothing left for today")
        XCTAssertEqual(TodayGlanceText.summary(empty, nextTime: nil, .polish), "Na dziś nic już nie zostało")
        let calendarOnly = TodayGlance(events: [], reminders: [], now: at(11), calendar: calendar, remindersOn: false)
        XCTAssertEqual(TodayGlanceText.summary(calendarOnly, nextTime: nil, .english), "No more events today",
                       "never says 'no reminders' when Reminders is off")

        let many = (0..<5).map { reminder("R\($0)", at(0, dayOffset: -1), time: false) }
        let late = TodayGlance(events: [], reminders: many, now: at(11), calendar: calendar, calendarOn: false)
        XCTAssertEqual(TodayGlanceText.summary(late, nextTime: nil, .polish), "5 przypomnień, w tym 5 zaległych")
        XCTAssertEqual(TodayGlanceText.summary(late, nextTime: nil, .english), "5 reminders, 5 overdue")
    }

    func testStatusFreeAndDurationWords() {
        XCTAssertEqual(TodayGlanceText.status(.startsIn(minutes: 25), endTime: "15:00", .english), "in 25 min")
        XCTAssertEqual(TodayGlanceText.status(.startsIn(minutes: 70), endTime: "15:00", .polish), "za 1 h 10 min")
        XCTAssertEqual(TodayGlanceText.status(.now(until: at(15)), endTime: "15:00", .english), "now, until 15:00")
        XCTAssertEqual(TodayGlanceText.status(.now(until: at(15)), endTime: "15:00", .polish), "teraz, do 15:00")
        XCTAssertEqual(TodayGlanceText.free(slot(at(11), at(13, 30)), start: "11:00", end: "13:30", .english),
                       "Free 11:00–13:30 · 2 h 30 min")
        XCTAssertEqual(TodayGlanceText.free(slot(at(11), at(13)), start: "11:00", end: "13:00", .polish),
                       "Wolne 11:00–13:00 · 2 h")
        XCTAssertEqual(TodayGlanceText.duration(45), "45 min")
    }

    /// A real slot from `freeBetweenEvents` (the type has no public initialiser).
    private func slot(_ start: Date, _ end: Date) -> FreeDay.Slot {
        TodayGlance.freeBetweenEvents([event("Before", at(0, 30), start), event("After", end, at(23))], now: at(0), calendar: calendar)[0]
    }

    func testMapsPlace() {
        XCTAssertEqual(TodayGlance.mapsPlace("  Dental Clinic\nul. Marszałkowska 10\n00-001 Warszawa "),
                       "Dental Clinic, ul. Marszałkowska 10, 00-001 Warszawa")
        XCTAssertNil(TodayGlance.mapsPlace(nil))
        XCTAssertNil(TodayGlance.mapsPlace(" \n "))
        XCTAssertNil(TodayGlance.mapsPlace("https://meet.example.com/abc-defg"), "an online meeting has no place")
        XCTAssertNil(TodayGlance.mapsPlace("www.example.com/room"))
    }

    func testTickGoesAheadOnlyForTheReminderAsShown() {
        let due = ReminderDue(year: 2026, month: 11, day: 10, hour: 18, minute: 0, timeZoneID: "Europe/Warsaw")
        let shown = ReminderSummary(id: "r1", title: "Call mum", due: at(18), dueHasTime: true)
        let current = ReminderSnapshot(id: "r1", title: "Call mum", listTitle: "Home", due: due, markerURL: nil)
        XCTAssertTrue(ReminderTick.stillAsShown(shown, now: current, local: calendar))

        let done = ReminderSnapshot(id: "r1", title: "Call mum", listTitle: "Home", due: due, markerURL: nil, isCompleted: true)
        XCTAssertFalse(ReminderTick.stillAsShown(shown, now: done, local: calendar), "already done in Reminders")
        let renamed = ReminderSnapshot(id: "r1", title: "Call dad", listTitle: "Home", due: due, markerURL: nil)
        XCTAssertFalse(ReminderTick.stillAsShown(shown, now: renamed, local: calendar))
        let moved = ReminderSnapshot(
            id: "r1", title: "Call mum", listTitle: "Home",
            due: ReminderDue(year: 2026, month: 11, day: 10, hour: 19, minute: 0, timeZoneID: "Europe/Warsaw"), markerURL: nil)
        XCTAssertFalse(ReminderTick.stillAsShown(shown, now: moved, local: calendar))
        let other = ReminderSnapshot(id: "r2", title: "Call mum", listTitle: "Home", due: due, markerURL: nil)
        XCTAssertFalse(ReminderTick.stillAsShown(shown, now: other, local: calendar))

        let dayOnly = ReminderSummary(id: "r3", title: "", due: at(0), dueHasTime: false)
        let floating = ReminderSnapshot(
            id: "r3", title: "", listTitle: "Home", due: ReminderDue(year: 2026, month: 11, day: 10, timeZoneID: nil), markerURL: nil)
        XCTAssertTrue(ReminderTick.stillAsShown(dayOnly, now: floating, local: calendar), "a floating day reads on this iPhone's clock")
        let untitled = ReminderSummary(id: "r3", title: "Untitled", due: at(0), dueHasTime: false)
        XCTAssertTrue(ReminderTick.stillAsShown(untitled, now: floating, local: calendar))
        let gotATime = ReminderSnapshot(
            id: "r3", title: "", listTitle: "Home", due: ReminderDue(year: 2026, month: 11, day: 10, hour: 0, minute: 0, timeZoneID: nil), markerURL: nil)
        XCTAssertFalse(ReminderTick.stillAsShown(dayOnly, now: gotATime, local: calendar))
        XCTAssertFalse(ReminderTick.stillAsShown(
            ReminderSummary(id: "r1", title: "Call mum", due: nil, dueHasTime: false), now: current, local: calendar))
    }
}

