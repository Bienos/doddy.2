import DoddyCore
import XCTest

final class TodayTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()

    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9 + dayOffset))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false, id: String? = nil) -> CalendarEventSummary {
        CalendarEventSummary(id: id ?? "ev-\(title)", title: title, start: start, end: end, allDay: allDay)
    }

    func testAgendaKeepsWhatIsLeftOfToday() {
        let now = at(12)
        let agenda = TodayAgenda(
            events: [
                event("Standup", at(9), at(9, 15)),
                event("Lunch", at(11, 30), at(12, 30)),
                event("Dentist", at(15), at(16)),
                event("Holiday", at(0), at(0, dayOffset: 1), allDay: true),
                event("Tomorrow", at(9, dayOffset: 1), at(10, dayOffset: 1)),
            ],
            reminders: [
                ReminderSummary(id: "r1", title: "Pay rent", due: at(0, dayOffset: -1), dueHasTime: false),
                ReminderSummary(id: "r2", title: "Call mum", due: at(18), dueHasTime: true),
                ReminderSummary(id: "r3", title: "Someday", due: nil, dueHasTime: false),
                ReminderSummary(id: "r4", title: "Next week", due: at(9, dayOffset: 7), dueHasTime: true),
            ],
            now: now, calendar: calendar)
        XCTAssertEqual(agenda.events.map(\.title), ["Holiday", "Lunch", "Dentist"], "ended and tomorrow's events are left out")
        XCTAssertEqual(agenda.reminders.map(\.title), ["Pay rent", "Call mum"], "overdue and due today only")
        XCTAssertTrue(TodayAgenda.isOverdue(agenda.reminders[0], now: now, calendar: calendar))
        XCTAssertFalse(TodayAgenda.isOverdue(agenda.reminders[1], now: now, calendar: calendar))
    }

    func testAgendaIsCappedAndCountsTheRest() {
        let events = (0..<8).map { event("E\($0)", at(13 + $0), at(13 + $0, 30)) }
        let agenda = TodayAgenda(events: events, reminders: [], now: at(12), calendar: calendar, limit: 5)
        XCTAssertEqual(agenda.events.count, 5)
        XCTAssertEqual(agenda.moreEvents, 3)
    }

    func testNudgePlanRules() throws {
        let dentist = event("Dentist", at(15), at(16), id: "ABC:123.x@2026")
        let plan = try EventNudgePlan(event: dentist, leadMinutes: 30, now: at(12))
        XCTAssertEqual(plan.fireAt, at(14, 30))
        XCTAssertEqual(plan.identifier, "doddy.nudge.ABC:123.x@2026.30")
        XCTAssertEqual(plan.body(time: "15:00"), "Dentist starts in 30 minutes (15:00).")
        XCTAssertEqual(EventNudgePlan.leadText(60), "in 1 hour")

        XCTAssertThrowsError(try EventNudgePlan(event: dentist, leadMinutes: 60, now: at(14, 30))) {
            XCTAssertEqual($0 as? NudgePlanError, .fireTimeInPast)
        }
        let holiday = event("Holiday", at(0), at(0, dayOffset: 1), allDay: true)
        XCTAssertThrowsError(try EventNudgePlan(event: holiday, leadMinutes: 10, now: at(0, dayOffset: -1))) {
            XCTAssertEqual($0 as? NudgePlanError, .notATimedEvent)
        }
        let noID = CalendarEventSummary(title: "Voice only", start: at(15), end: at(16), allDay: false)
        XCTAssertThrowsError(try EventNudgePlan(event: noID, leadMinutes: 10, now: at(12)))
    }

    func testScheduledNudgeReadsItsEventAndNoticesAMovedEvent() throws {
        let dentist = event("Dentist", at(15), at(16), id: "ABC:123.x@2026")
        let plan = try EventNudgePlan(event: dentist, leadMinutes: 30, now: at(12))
        let pending = ScheduledNudge(id: plan.identifier, fireAt: plan.fireAt)
        XCTAssertEqual(pending.eventID, "ABC:123.x@2026", "dots inside the event id survive")
        XCTAssertEqual(pending.leadMinutes, 30)
        XCTAssertEqual(pending.fits(dentist), true)

        let moved = event("Dentist", at(16), at(17), id: "ABC:123.x@2026")
        XCTAssertEqual(pending.fits(moved), false, "would fire at the old time")
        XCTAssertNil(pending.fits(event("Other", at(15), at(16))))
        XCTAssertFalse(ScheduledNudge.isNudge("doddy.timer.1234"))
    }
}
