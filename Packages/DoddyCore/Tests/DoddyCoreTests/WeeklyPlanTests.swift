import XCTest
@testable import DoddyCore

/// ADR-612: the weekly plan's notification names nothing, and its screen is the next seven days
/// from what this iPhone already has.
final class WeeklyPlanTests: XCTestCase {
    private let zone = "Europe/Warsaw"
    private var calendar: Calendar { ReminderSchedule.calendar(zone) }
    /// Mon 26 Oct 2026, 08:00 in Warsaw.
    private var now: Date { at(26, 8) }

    private func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func event(_ title: String, _ start: Date, hours: Double = 1, allDay: Bool = false) -> CalendarEventSummary {
        CalendarEventSummary(title: title, start: start, end: start.addingTimeInterval(hours * 3_600), allDay: allDay)
    }

    func testTheSettingsStartOffOnMondayMorning() {
        let settings = WeeklyPlanSettings()
        XCTAssertFalse(settings.isOn)
        XCTAssertEqual(settings.weekday, 2)
        XCTAssertEqual(settings.hour, 8)
        XCTAssertEqual(WeeklyPlanSettings(weekday: 9, hour: 30).weekday, 7)
    }

    func testTheNotificationNamesNothing() {
        XCTAssertEqual(WeeklyPlan.title(.polish), "Nowy tydzień")
        XCTAssertEqual(WeeklyPlan.body(.polish), "Zerknąć, co Cię czeka?")
        XCTAssertEqual(WeeklyPlan.body(.english), "Take a look at what's coming?")
        XCTAssertTrue(WeeklyPlan.isPlan(notificationID: WeeklyPlan.notificationID))
        XCTAssertFalse(WeeklyPlan.isPlan(notificationID: WeeklyLookBack.notificationID))
    }

    func testSevenDaysFromTodayEachWithItsOwnThingsInOrder() {
        let plan = WeeklyPlan.make(
            events: [event("Dentysta", at(27, 15)), event("Urlop", at(30), hours: 24, allDay: true), event("Za tydzień", at(2 + 31, 9))],
            reminders: [ReminderSummary(id: "r1", title: "Zapłacić czynsz", due: at(27), dueHasTime: false),
                        ReminderSummary(id: "r2", title: "Zadzwonić do mamy", due: at(27, 18), dueHasTime: true)],
            noteReminders: [], birthdays: [], now: now, calendar: calendar)
        XCTAssertEqual(plan.days.count, 7)
        XCTAssertEqual(plan.days.first?.date, at(26))
        let tuesday = plan.days[1].items
        XCTAssertEqual(tuesday.map(\.title), ["Zapłacić czynsz", "Dentysta", "Zadzwonić do mamy"], "untimed first, then by time")
        XCTAssertEqual(tuesday.map(\.kind), [.reminder, .event, .reminder])
        XCTAssertEqual(plan.days[4].items.map(\.title), ["Urlop"])
        XCTAssertFalse(plan.days.flatMap(\.items).contains { $0.title == "Za tydzień" }, "outside the seven days")
        XCTAssertFalse(plan.isEmpty)
    }

    func testWhatIsAlreadyPastIsLeftOutButAnEventUnderWayShowsToday() {
        let plan = WeeklyPlan.make(
            events: [event("Poranne spotkanie", at(26, 7), hours: 2), event("Już było", at(26, 6))],
            reminders: [ReminderSummary(id: "r", title: "O szóstej", due: at(26, 6), dueHasTime: true),
                        ReminderSummary(id: "o", title: "Zaległe", due: at(20, 9), dueHasTime: true)],
            noteReminders: [], birthdays: [], now: now, calendar: calendar)
        XCTAssertEqual(plan.days[0].items.map(\.title), ["Poranne spotkanie"])
        XCTAssertEqual(plan.days[0].items.first?.at, at(26, 7))
    }

    func testDoddysRepeatingRemindersShowEachTimeTheyFire() {
        let daily = MemoryReminder(
            id: UUID(), memoryID: UUID(), trigger: .time(fireAt: at(20, 20), timeZoneID: zone), createdAt: at(20), repeats: .daily)
        let once = MemoryReminder(id: UUID(), memoryID: UUID(), fireAt: at(28, 9), timeZoneID: zone, createdAt: at(20))
        let placeReminder = MemoryReminder(
            id: UUID(), memoryID: UUID(),
            trigger: .place(try! ReminderPlace(name: "Lidl", latitude: 52, longitude: 21, radiusMeters: 150, onArrival: true)),
            createdAt: at(20))
        let plan = WeeklyPlan.make(
            events: nil, reminders: nil,
            noteReminders: [(daily, "Leki"), (once, "Kod do paczkomatu"), (placeReminder, "Lista")],
            birthdays: [], now: now, calendar: calendar)
        let all = plan.days.flatMap(\.items)
        XCTAssertEqual(all.filter { $0.title == "Leki" }.count, 7, "every evening of the seven days")
        XCTAssertEqual(all.filter { $0.title == "Kod do paczkomatu" }.map(\.at), [at(28, 9)])
        XCTAssertFalse(all.contains { $0.title == "Lista" }, "a place has no time")
        XCTAssertTrue(plan.calendarOff)
        XCTAssertTrue(plan.remindersOff)
    }

    func testBirthdaysShowOnTheirDay() {
        let birthdays = UpcomingBirthdays.upcoming(
            [ContactBirthday(name: "Ania", month: 10, day: 30), ContactBirthday(name: "Tomek", month: 12, day: 1)],
            now: now, days: WeeklyPlan.days, calendar: calendar)
        let plan = WeeklyPlan.make(events: [], reminders: [], noteReminders: [], birthdays: birthdays, now: now, calendar: calendar)
        XCTAssertEqual(plan.days[4].items.map(\.title), ["Ania"])
        XCTAssertEqual(plan.days[4].items.first?.kind, .birthday)
        XCTAssertFalse(plan.days.flatMap(\.items).contains { $0.title == "Tomek" })
    }

    func testAnEmptyWeekIsSaidPlainly() {
        let plan = WeeklyPlan.make(events: [], reminders: [], noteReminders: [], birthdays: [], now: now, calendar: calendar)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.days.count, 7)
        XCTAssertFalse(plan.calendarOff)
        XCTAssertEqual(WeeklyPlan.Kind.noteReminder.label(.polish), "Przypomnienie Doddy'ego")
    }
}
