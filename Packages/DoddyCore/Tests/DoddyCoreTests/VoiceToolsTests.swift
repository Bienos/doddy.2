import XCTest
@testable import DoddyCore

final class VoiceToolsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    /// 2026-10-09 10:00 in Warsaw.
    private var now: Date { date(2026, 10, 9, 10, 0) }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func parse(_ name: String, _ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: name, parametersJSON: Data(json.utf8), now: now, calendar: calendar)
    }

    func testParsing() {
        XCTAssertEqual(VoiceToolRequest.parse(name: "search_memories", parametersJSON: Data(#"{"query":"klucze"}"#.utf8)), .searchMemories(query: "klucze"))
        XCTAssertEqual(VoiceToolRequest.parse(name: "save_memory", parametersJSON: Data(#"{"text":"Keys in the tin"}"#.utf8)), .saveMemory(text: "Keys in the tin"))
        XCTAssertEqual(VoiceToolRequest.parse(name: "save_memory", parametersJSON: Data(#"{"text":"  "}"#.utf8)), .invalid(name: "save_memory", reason: "missing text"))
        XCTAssertEqual(VoiceToolRequest.parse(name: "send_sms", parametersJSON: Data("{}".utf8)), .unsupported(name: "send_sms"))
        XCTAssertEqual(VoiceToolRequest.parse(name: "search_memories", parametersJSON: Data("not json".utf8)), .invalid(name: "search_memories", reason: "missing query"))
    }

    func testSearchReplyOnlyStatesStoredText() throws {
        XCTAssertTrue(VoiceToolReply.search(.noMatch).hasPrefix("No saved note matched"))
        let record = try MemoryRecord(id: UUID(), rawText: "Klucze są w niebieskiej puszce", source: .explicitText, capturedAt: Date(timeIntervalSince1970: 0))
        let reply = VoiceToolReply.search(.matches([MemoryCandidate(record: record, matchedTerms: ["klucze"])]))
        XCTAssertTrue(reply.contains("\"Klucze są w niebieskiej puszce\""))
        XCTAssertTrue(reply.hasPrefix("Found 1 saved note "))
    }

    // MARK: Calendar reads

    func testReadCalendarNamedRanges() {
        XCTAssertEqual(parse("read_calendar", #"{"range":"today"}"#),
                       .readCalendar(VoiceTimeRange(start: date(2026, 10, 9, 0, 0), end: date(2026, 10, 10, 0, 0))))
        XCTAssertEqual(parse("read_calendar", #"{"range":"tomorrow"}"#),
                       .readCalendar(VoiceTimeRange(start: date(2026, 10, 10, 0, 0), end: date(2026, 10, 11, 0, 0))))
        XCTAssertEqual(parse("read_calendar", #"{"range":"week"}"#),
                       .readCalendar(VoiceTimeRange(start: date(2026, 10, 9, 0, 0), end: date(2026, 10, 16, 0, 0))))
        XCTAssertEqual(parse("read_calendar", #"{"range":"month"}"#),
                       .invalid(name: "read_calendar", reason: "range must be today, tomorrow or week"))
    }

    func testReadCalendarExplicitRanges() {
        XCTAssertEqual(parse("read_calendar", #"{"from":"2026-10-12T09:00","to":"2026-10-12T17:30"}"#),
                       .readCalendar(VoiceTimeRange(start: date(2026, 10, 12, 9, 0), end: date(2026, 10, 12, 17, 30))))
        // "to" defaults to one day after "from".
        XCTAssertEqual(parse("read_calendar", #"{"from":"2026-10-12"}"#),
                       .readCalendar(VoiceTimeRange(start: date(2026, 10, 12, 0, 0), end: date(2026, 10, 13, 0, 0))))
        XCTAssertEqual(parse("read_calendar", #"{"from":"2026-10-12T09:00","to":"2026-10-11T09:00"}"#),
                       .invalid(name: "read_calendar", reason: "to must be after from"))
        XCTAssertEqual(parse("read_calendar", #"{"from":"2026-02-31"}"#),
                       .invalid(name: "read_calendar", reason: "missing range or from"))
    }

    // MARK: Calendar events

    func testCreateEventWithTimes() {
        let request = parse("create_calendar_event", #"{"title":"Dentist","start":"2026-10-12T15:00","end":"2026-10-12T16:00","location":"Mokotów"}"#)
        XCTAssertEqual(request, .createCalendarEvent(CalendarEventDraft(
            title: "Dentist", start: date(2026, 10, 12, 15, 0), end: date(2026, 10, 12, 16, 0),
            allDay: false, location: "Mokotów", notes: nil)))
    }

    func testCreateEventDefaultsToOneHour() {
        let request = parse("create_calendar_event", #"{"title":"Call","start":"2026-10-12T15:00"}"#)
        XCTAssertEqual(request, .createCalendarEvent(CalendarEventDraft(
            title: "Call", start: date(2026, 10, 12, 15, 0), end: date(2026, 10, 12, 16, 0),
            allDay: false, location: nil, notes: nil)))
    }

    func testCreateEventNeedsTimeUnlessAllDay() {
        XCTAssertEqual(parse("create_calendar_event", #"{"title":"Trip","start":"2026-10-12"}"#),
                       .invalid(name: "create_calendar_event", reason: "start needs a time unless all_day is true"))
        XCTAssertEqual(parse("create_calendar_event", #"{"title":"Trip","start":"2026-10-12","all_day":true}"#),
                       .createCalendarEvent(CalendarEventDraft(
                           title: "Trip", start: date(2026, 10, 12, 0, 0), end: date(2026, 10, 13, 0, 0),
                           allDay: true, location: nil, notes: nil)))
    }

    func testCreateEventRejectsEndBeforeStartAndMissingTitle() {
        XCTAssertEqual(parse("create_calendar_event", #"{"title":"X","start":"2026-10-12T15:00","end":"2026-10-12T14:00"}"#),
                       .invalid(name: "create_calendar_event", reason: "end must be a time after start"))
        XCTAssertEqual(parse("create_calendar_event", #"{"start":"2026-10-12T15:00"}"#),
                       .invalid(name: "create_calendar_event", reason: "missing title"))
    }

    // MARK: Reminders and contacts

    func testCreateReminderWithAndWithoutTime() {
        XCTAssertEqual(parse("create_reminder", #"{"title":"Call Marta","due":"2026-10-12T18:00"}"#),
                       .createReminder(ReminderDraft(title: "Call Marta", due: date(2026, 10, 12, 18, 0), dueHasTime: true, notes: nil)))
        XCTAssertEqual(parse("create_reminder", #"{"title":"Pay rent","due":"2026-10-31"}"#),
                       .createReminder(ReminderDraft(title: "Pay rent", due: date(2026, 10, 31, 0, 0), dueHasTime: false, notes: nil)))
        XCTAssertEqual(parse("create_reminder", #"{"title":"Buy milk"}"#),
                       .createReminder(ReminderDraft(title: "Buy milk", due: nil, dueHasTime: false, notes: nil)))
        XCTAssertEqual(parse("create_reminder", #"{"title":"Buy milk","due":"tomorrow"}"#),
                       .invalid(name: "create_reminder", reason: "due is not a date"))
    }

    func testLookupContactNeedsName() {
        XCTAssertEqual(parse("lookup_contact", #"{"name":"Marta"}"#), .lookupContact(name: "Marta"))
        XCTAssertEqual(parse("lookup_contact", #"{}"#), .invalid(name: "lookup_contact", reason: "missing name"))
    }

    func testConnectionServesItsTools() {
        XCTAssertEqual(VoiceConnection.serving("read_calendar"), .calendar)
        XCTAssertEqual(VoiceConnection.serving("create_calendar_event"), .calendar)
        XCTAssertEqual(VoiceConnection.serving("create_reminder"), .reminders)
        XCTAssertEqual(VoiceConnection.serving("lookup_contact"), .contacts)
        XCTAssertNil(VoiceConnection.serving("save_memory"))
        XCTAssertEqual(VoiceConnection.calendar.preferenceKey, "voiceConnection.calendar")
    }

    // MARK: Replies

    func testReplyPrefixesMatchTheAgentPrompt() {
        XCTAssertTrue(VoiceToolReply.notConnected(.calendar).hasPrefix("Calendar isn't connected."))
        XCTAssertTrue(VoiceToolReply.notConnected(.calendar).contains("Settings, Connections"))

        let event = CalendarEventDraft(title: "Dentist", start: date(2026, 10, 12, 15, 0), end: date(2026, 10, 12, 16, 0), allDay: false, location: nil, notes: nil)
        let added = VoiceToolReply.eventAdded(event, calendar: calendar)
        XCTAssertTrue(added.hasPrefix("added: "))
        XCTAssertTrue(added.contains("2026-10-12 15:00 to 2026-10-12 16:00"))

        XCTAssertTrue(VoiceToolReply.reminderAdded(ReminderDraft(title: "Buy milk", due: nil, dueHasTime: false, notes: nil), calendar: calendar).hasPrefix("added: reminder"))
        XCTAssertTrue(VoiceToolReply.declinedEvent.hasPrefix("declined: "))
        XCTAssertTrue(VoiceToolReply.notAdded("Calendar is read-only.").hasPrefix("failed: "))
        XCTAssertTrue(VoiceToolReply.addUnconfirmed.hasPrefix("unknown: "))
    }

    func testCalendarReplyListsOnlyTitlesAndTimes() {
        let range = VoiceTimeRange(start: date(2026, 10, 12, 0, 0), end: date(2026, 10, 13, 0, 0))
        XCTAssertTrue(VoiceToolReply.calendarEvents([], range: range, calendar: calendar).hasPrefix("No calendar events from 2026-10-12 to 2026-10-13"))

        let events = [
            CalendarEventSummary(title: "Dentist", start: date(2026, 10, 12, 15, 0), end: date(2026, 10, 12, 16, 0), allDay: false),
            CalendarEventSummary(title: "Holiday", start: date(2026, 10, 12, 0, 0), end: date(2026, 10, 13, 0, 0), allDay: true),
        ]
        let reply = VoiceToolReply.calendarEvents(events, range: range, calendar: calendar)
        XCTAssertTrue(reply.hasPrefix("Found 2 calendar events"))
        XCTAssertTrue(reply.contains("\"Dentist\" 2026-10-12 15:00–2026-10-12 16:00"))
        XCTAssertTrue(reply.contains("\"Holiday\" 2026-10-12 (all day)"))
    }

    func testContactReplyCarriesNamesOnly() {
        let reply = VoiceToolReply.contactMatches(["Marta Kowalska"], query: "Marta")
        XCTAssertTrue(reply.contains("Marta Kowalska"))
        XCTAssertTrue(reply.contains("Their details are on the user's screen"))
        XCTAssertTrue(VoiceToolReply.contactMatches([], query: "Ola").hasPrefix("No contact matched \"Ola\""))
    }
}
