import XCTest
@testable import DoddyCore

/// Several changes on one card (ADR-280).
final class BulkChangeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }
    private let zone = "Europe/Warsaw"
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 21))! }
    private func at(_ day: Int, _ hour: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
    private func parse(_ name: String, _ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: name, parametersJSON: Data(json.utf8), now: now, calendar: calendar)
    }

    func testClearingAnAfternoonTakesOnlyEventsThatStartInIt() {
        guard case .deleteCalendarEvents(let range) = parse(VoiceToolName.deleteCalendarEvents,
            #"{"from":"2026-10-15T12:00","to":"2026-10-15T18:00"}"#) else { return XCTFail() }
        let events = [
            CalendarEventSummary(id: "a", title: "Lunch", start: at(15, 12), end: at(15, 13), allDay: false),
            CalendarEventSummary(id: "b", title: "Morning block", start: at(15, 9), end: at(15, 14), allDay: false),
            CalendarEventSummary(id: "c", title: "Call", start: at(15, 16), end: at(15, 17), allDay: false),
            CalendarEventSummary(id: "d", title: "Dinner", start: at(15, 19), end: at(15, 21), allDay: false),
        ]
        XCTAssertEqual(BulkChange.eventsToDelete(events, in: range).map(\.title), ["Lunch", "Call"])
        guard case .deleteCalendarEvents(let day) = parse(VoiceToolName.deleteCalendarEvents, #"{"from":"2026-10-15","to":"2026-10-15"}"#) else {
            return XCTFail("a day alone covers the whole day")
        }
        XCTAssertEqual(day.end, at(16, 0))
        guard case .invalid = parse(VoiceToolName.deleteCalendarEvents, #"{"from":"2026-10-01","to":"2026-12-01"}"#) else {
            return XCTFail("at most 31 days")
        }
    }

    func testMovingTodaysRemindersKeepsTheirTimes() {
        guard case .moveReminders(let dueBy, let to) = parse(VoiceToolName.moveReminders, #"{"due_by":"2026-10-11","to":"2026-10-12"}"#) else {
            return XCTFail()
        }
        let open = [
            ReminderSnapshot(id: "1", title: "Call mum", listTitle: "R", due: ReminderDue(year: 2026, month: 10, day: 11, hour: 18, timeZoneID: zone), markerURL: nil),
            ReminderSnapshot(id: "2", title: "Old one", listTitle: "R", due: ReminderDue(year: 2026, month: 10, day: 2, timeZoneID: nil), markerURL: nil),
            ReminderSnapshot(id: "3", title: "Later", listTitle: "R", due: ReminderDue(year: 2026, month: 10, day: 14, hour: 9, timeZoneID: zone), markerURL: nil),
            ReminderSnapshot(id: "4", title: "No date", listTitle: "R", due: nil, markerURL: nil),
        ]
        let (moves, skipped) = BulkChange.remindersToMove(open, dueBy: dueBy, to: to, local: calendar)
        XCTAssertEqual(moves.map(\.title), ["Old one", "Call mum"])
        guard case .moveReminder(_, let newDue) = moves[1] else { return XCTFail() }
        XCTAssertEqual(newDue.localText, "2026-10-12T18:00")
        XCTAssertTrue(skipped.isEmpty)
        guard case .needsClarification = parse(VoiceToolName.moveReminders, #"{"due_by":"2026-10-11","to":"2026-10-01"}"#) else {
            return XCTFail("not into the past")
        }
    }

    func testTheAnswerSaysVerbOnlyWhenEverythingChanged() {
        let a = BulkItem.deleteEvent(CalendarEventSummary(id: "a", title: "Lunch", start: at(15, 12), end: at(15, 13), allDay: false))
        let b = BulkItem.deleteEvent(CalendarEventSummary(id: "b", title: "Call", start: at(15, 16), end: at(15, 17), allDay: false))
        XCTAssertTrue(VoiceToolReply.bulkResult([(a, .done), (b, .done)], verb: "deleted").hasPrefix("deleted: all 2"))
        let partly = VoiceToolReply.bulkResult([(a, .done), (b, .changedElsewhere)], verb: "deleted")
        XCTAssertTrue(partly.hasPrefix("partly deleted: 1 of 2"))
        XCTAssertTrue(partly.contains("\"Call\""))
        XCTAssertTrue(VoiceToolReply.bulkResult([(a, .unconfirmed)], verb: "deleted").hasPrefix("unknown"))
        XCTAssertTrue(VoiceToolReply.bulkResult([(a, .failed)], verb: "deleted").hasPrefix("failed"))
    }

    func testBulkToolsArePausedServedAndLogged() {
        XCTAssertEqual(VoiceConnection.serving(VoiceToolName.deleteCalendarEvents), .calendar)
        XCTAssertEqual(VoiceConnection.serving(VoiceToolName.moveReminders), .reminders)
        let request = parse(VoiceToolName.moveReminders, #"{"due_by":"2026-10-11","to":"2026-10-12"}"#)
        XCTAssertTrue(ConnectionPause.applies(to: request))
        XCTAssertEqual(ActivityRequest.describe(request, calendar: calendar)?.title, "Move reminders")
    }
}
