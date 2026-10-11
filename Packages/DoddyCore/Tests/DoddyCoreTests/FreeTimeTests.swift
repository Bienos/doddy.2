import XCTest
@testable import DoddyCore

/// "When am I free?" (ADR-332).
final class FreeTimeTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2027, month: 1, day: day, hour: hour, minute: minute))!
    }

    func testGapsBetweenTimedEventsAndAllDayNamed() {
        let request = FreeTimeRequest(firstDay: at(14, 0), days: 1, minMinutes: 30, earliest: 9 * 60, latest: 18 * 60)
        let events = [
            CalendarEventSummary(title: "Standup", start: at(14, 9), end: at(14, 9, 15), allDay: false),
            CalendarEventSummary(title: "Dentist", start: at(14, 11), end: at(14, 12), allDay: false),
            CalendarEventSummary(title: "Overlap", start: at(14, 11, 30), end: at(14, 13), allDay: false),
            CalendarEventSummary(title: "Short gap", start: at(14, 13, 15), end: at(14, 17), allDay: false),
            CalendarEventSummary(title: "Mum's birthday", start: at(14, 0), end: at(15, 0), allDay: true),
        ]
        let days = FreeTime.days(request, events: events, now: at(13, 8), calendar: calendar)
        XCTAssertEqual(days.count, 1)
        // 09:15–11:00 and 17:00–18:00; the 15-minute gap at 13:00 is too short.
        XCTAssertEqual(days[0].slots.map(\.start), [at(14, 9, 15), at(14, 17)])
        XCTAssertEqual(days[0].slots.map(\.end), [at(14, 11), at(14, 18)])
        XCTAssertEqual(days[0].allDayTitles, ["Mum's birthday"])
        let reply = VoiceToolReply.freeTime(days, request: request, calendar: calendar)
        XCTAssertTrue(reply.contains("Thursday 2027-01-14: 09:15–11:00, 17:00–18:00 (1 all-day event, below)"), reply)
        // Calendar titles follow as data (ToolData).
        XCTAssertTrue(reply.contains("All-day events' titles, by day:\n<<<DATA\n- Thursday 2027-01-14: \"Mum's birthday\"\nDATA>>>"), reply)
        XCTAssertTrue(reply.contains("Nothing was booked"))
    }

    func testTodayStartsNowAndAFullDayHasNoGap() {
        let request = FreeTimeRequest(firstDay: at(14, 0), days: 2, minMinutes: 30, earliest: 9 * 60, latest: 18 * 60)
        let events = [CalendarEventSummary(title: "Workshop", start: at(15, 8), end: at(15, 19), allDay: false)]
        let days = FreeTime.days(request, events: events, now: at(14, 16, 20), calendar: calendar)
        XCTAssertEqual(days[0].slots.map(\.start), [at(14, 16, 20)])
        XCTAssertEqual(days[1].slots, [])
        XCTAssertTrue(VoiceToolReply.freeTime(days, request: request, calendar: calendar).contains("2027-01-15: no free gap"))
    }

    func testParsing() {
        func parse(_ json: String) -> VoiceToolRequest {
            VoiceToolRequest.parse(name: "find_free_time", parametersJSON: Data(json.utf8), now: at(13, 8), calendar: calendar)
        }
        XCTAssertEqual(parse(#"{"from": "2027-01-14", "to": "2027-01-16", "min_minutes": 60, "earliest": "10:00", "latest": "17:30"}"#),
                       .findFreeTime(FreeTimeRequest(firstDay: at(14, 0), days: 3, minMinutes: 60, earliest: 600, latest: 1050)))
        XCTAssertEqual(parse(#"{"from": "2027-01-14"}"#), .findFreeTime(FreeTimeRequest(firstDay: at(14, 0), days: 1)))
        guard case .invalid = parse(#"{"from": "2027-01-14", "to": "2027-01-30"}"#) else { return XCTFail("more than 7 days") }
        guard case .invalid = parse(#"{"from": "2027-01-10"}"#) else { return XCTFail("days that passed") }
        guard case .invalid = parse(#"{"from": "2027-01-14", "earliest": "18:00", "latest": "09:00"}"#) else { return XCTFail("window") }
        guard case .invalid = parse(#"{"from": "14.01.2027"}"#) else { return XCTFail("format") }
    }
}
