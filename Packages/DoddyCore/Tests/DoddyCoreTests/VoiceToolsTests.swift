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

    // MARK: Calendar event times (ADR-127: same strict rules as reminders)

    private func clarification(_ request: VoiceToolRequest, file: StaticString = #filePath, line: UInt = #line) -> ReminderClarification? {
        guard case .needsClarification(let name, let clarification) = request else {
            XCTFail("expected a question for the agent, got \(request)", file: file, line: line)
            return nil
        }
        XCTAssertEqual(name, "create_calendar_event", file: file, line: line)
        return clarification
    }

    func testCreateEventKeepsTheMinutes() {
        XCTAssertEqual(parse("create_calendar_event", #"{"title":"Dinner","start":"2026-10-12T18:30","end":"2026-10-12T20:45"}"#),
                       .createCalendarEvent(CalendarEventDraft(
                           title: "Dinner", start: date(2026, 10, 12, 18, 30), end: date(2026, 10, 12, 20, 45),
                           allDay: false, location: nil, notes: nil)))
        // Seconds are allowed and dropped, as for reminders.
        XCTAssertEqual(parse("create_calendar_event", #"{"title":"Dinner","start":"2026-10-12T18:30:00"}"#),
                       .createCalendarEvent(CalendarEventDraft(
                           title: "Dinner", start: date(2026, 10, 12, 18, 30), end: date(2026, 10, 12, 19, 30),
                           allDay: false, location: nil, notes: nil)))
    }

    /// The old parser read "18:30+02:00" as 18:00. Now it is never shown as a card at all.
    func testCreateEventWithZoneOffsetIsAskedAboutNotShifted() {
        for start in ["2026-10-12T18:30+02:00", "2026-10-12T18:30Z", "2026-10-12T16:30:00+00:00"] {
            let request = parse("create_calendar_event", #"{"title":"Dinner","start":"\#(start)"}"#)
            XCTAssertEqual(clarification(request)?.kind, .unreadable, start)
        }
        let end = parse("create_calendar_event", #"{"title":"Dinner","start":"2026-10-12T18:30","end":"2026-10-12T20:00+02:00"}"#)
        XCTAssertEqual(clarification(end)?.kind, .unreadable)
    }

    func testCreateEventClarificationReply() throws {
        let request = parse("create_calendar_event", #"{"title":"Dinner","start":"2026-10-12T18:30+02:00"}"#)
        guard case .needsClarification(let name, let found) = request else { return XCTFail("expected a question") }
        let reply = VoiceToolReply.clarification(found, tool: name)
        // Keeps the reply contract: a "failed" result that adds nothing, naming the tool to call again.
        XCTAssertTrue(reply.hasPrefix("failed: not added yet: "), reply)
        XCTAssertTrue(reply.contains("\"2026-10-12T18:30+02:00\""), reply)
        XCTAssertTrue(reply.contains("without a time zone"), reply)
        XCTAssertTrue(reply.contains("then call create_calendar_event again with their answer"), reply)
        XCTAssertTrue(reply.hasSuffix("Nothing was added."), reply)
        XCTAssertFalse(reply.contains("create_reminder"), reply)
    }

    func testCreateEventImpossibleAndClockChangeTimesAreAskedAbout() {
        let impossible = parse("create_calendar_event", #"{"title":"X","start":"2026-02-31T10:00"}"#)
        XCTAssertEqual(clarification(impossible)?.kind, .unreadable)
        let bareTime = parse("create_calendar_event", #"{"title":"X","start":"18:30"}"#)
        XCTAssertEqual(clarification(bareTime)?.kind, .unreadable)
        // Warsaw: clocks go forward at 02:00 on 28 Mar 2027 and back at 03:00 on 25 Oct 2026.
        let skipped = parse("create_calendar_event", #"{"title":"X","start":"2027-03-28T02:30"}"#)
        XCTAssertEqual(clarification(skipped)?.kind, .timeSkipped)
        let repeated = parse("create_calendar_event", #"{"title":"X","start":"2026-10-25T01:00","end":"2026-10-25T02:30"}"#)
        XCTAssertEqual(clarification(repeated)?.kind, .timeRepeated)
    }

    /// Like reminders (ADR-128): a start that has passed is asked about, not shown. Now is 10:00.
    func testCreateEventInThePastIsAskedAbout() {
        let earlier = parse("create_calendar_event", #"{"title":"Lunch","start":"2026-10-08T12:00"}"#)
        XCTAssertEqual(clarification(earlier)?.kind, .timePassed)
        let thisMorning = parse("create_calendar_event", #"{"title":"Standup","start":"2026-10-09T09:30"}"#)
        XCTAssertEqual(clarification(thisMorning)?.kind, .timePassed)
        let yesterday = parse("create_calendar_event", #"{"title":"Trip","start":"2026-10-08","all_day":true}"#)
        XCTAssertEqual(clarification(yesterday)?.kind, .dayPassed)

        guard case .needsClarification(let name, let late) = earlier else { return XCTFail("expected a question") }
        let reply = VoiceToolReply.clarification(late, tool: name)
        XCTAssertTrue(reply.hasPrefix("failed: not added yet: 2026-10-08 12:00 has already passed (it is now 2026-10-09 10:00 in Europe/Warsaw)"), reply)
        XCTAssertTrue(reply.contains("then call create_calendar_event again"), reply)
    }

    func testCreateEventLaterTodayAndAllDayTodayAreShown() {
        XCTAssertEqual(parse("create_calendar_event", #"{"title":"Gym","start":"2026-10-09T10:30"}"#),
                       .createCalendarEvent(CalendarEventDraft(
                           title: "Gym", start: date(2026, 10, 9, 10, 30), end: date(2026, 10, 9, 11, 30),
                           allDay: false, location: nil, notes: nil)))
        // An all-day event counts until its day ends, even if the agent also sent a morning time.
        XCTAssertEqual(parse("create_calendar_event", #"{"title":"Holiday","start":"2026-10-09T08:00","all_day":true}"#),
                       .createCalendarEvent(CalendarEventDraft(
                           title: "Holiday", start: date(2026, 10, 9, 0, 0), end: date(2026, 10, 10, 0, 0),
                           allDay: true, location: nil, notes: nil)))
    }

    /// The tap rechecks: the card may wait while the start goes by.
    func testEventPassedWhileTheCardWaited() {
        let gym = CalendarEventDraft(title: "Gym", start: date(2026, 10, 9, 10, 30), end: date(2026, 10, 9, 11, 30), allDay: false, location: nil, notes: nil)
        XCTAssertNil(gym.passed(now: date(2026, 10, 9, 10, 29), calendar: calendar))
        XCTAssertEqual(gym.passed(now: date(2026, 10, 9, 10, 31), calendar: calendar)?.kind, .timePassed)
        let holiday = CalendarEventDraft(title: "Holiday", start: date(2026, 10, 9, 0, 0), end: date(2026, 10, 10, 0, 0), allDay: true, location: nil, notes: nil)
        XCTAssertNil(holiday.passed(now: date(2026, 10, 9, 23, 59), calendar: calendar))
        XCTAssertEqual(holiday.passed(now: date(2026, 10, 10, 0, 1), calendar: calendar)?.kind, .dayPassed)
    }

    /// ISO dates are Gregorian even when the phone uses another calendar (2026 is not Buddhist 2026).
    func testCreateEventReadsGregorianDatesOnANonGregorianPhone() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = calendar.timeZone
        let request = VoiceToolRequest.parse(
            name: "create_calendar_event", parametersJSON: Data(#"{"title":"Dinner","start":"2026-10-12T18:30"}"#.utf8),
            now: now, calendar: buddhist)
        XCTAssertEqual(request, .createCalendarEvent(CalendarEventDraft(
            title: "Dinner", start: date(2026, 10, 12, 18, 30), end: date(2026, 10, 12, 19, 30),
            allDay: false, location: nil, notes: nil)))
    }

    func testReadCalendarRefusesAZoneOffsetInsteadOfShiftingIt() {
        XCTAssertEqual(parse("read_calendar", #"{"from":"2026-10-12T18:30+02:00"}"#),
                       .invalid(name: "read_calendar", reason: "missing range or from"))
        XCTAssertEqual(parse("read_calendar", #"{"from":"2026-10-12T09:00","to":"2026-10-12T18:30+02:00"}"#),
                       .invalid(name: "read_calendar", reason: "to is not a date"))
    }

    // MARK: Reminders and contacts

    func testCreateReminderWithAndWithoutTime() {
        let warsaw = "Europe/Warsaw"
        XCTAssertEqual(parse("create_reminder", #"{"title":"Call Marta","due":"2026-10-12T18:00"}"#),
                       .createReminder(ReminderDraft(title: "Call Marta", due: ReminderDue(year: 2026, month: 10, day: 12, hour: 18, minute: 0, timeZoneID: warsaw), notes: nil)))
        XCTAssertEqual(parse("create_reminder", #"{"title":"Pay rent","due":"2026-10-31"}"#),
                       .createReminder(ReminderDraft(title: "Pay rent", due: ReminderDue(year: 2026, month: 10, day: 31, timeZoneID: warsaw), notes: nil)))
        XCTAssertEqual(parse("create_reminder", #"{"title":"  Buy milk "}"#),
                       .createReminder(ReminderDraft(title: "Buy milk", due: nil, notes: nil)))
        guard case .needsClarification(let name, let clarification) = parse("create_reminder", #"{"title":"Buy milk","due":"tomorrow"}"#) else {
            return XCTFail("a word instead of a date must be sent back as a question")
        }
        XCTAssertEqual(name, "create_reminder")
        XCTAssertEqual(clarification.kind, .unreadable)
    }

    func testLookupContactNeedsName() {
        XCTAssertEqual(parse("lookup_contact", #"{"name":"Marta"}"#), .lookupContact(name: "Marta"))
        XCTAssertEqual(parse("lookup_contact", #"{}"#), .invalid(name: "lookup_contact", reason: "missing name"))
    }

    // MARK: Timers, maps, shortcuts and drafts

    func testTimerDurations() {
        XCTAssertEqual(parse("set_timer", #"{"minutes":10,"label":"Pasta"}"#),
                       .setTimer(TimerDraft(seconds: 600, label: "Pasta")))
        XCTAssertEqual(parse("set_timer", #"{"minutes":1.5}"#),
                       .setTimer(TimerDraft(seconds: 90, label: nil)))
        XCTAssertEqual(parse("set_timer", #"{"seconds":45}"#),
                       .setTimer(TimerDraft(seconds: 45, label: nil)))
        XCTAssertEqual(parse("set_timer", #"{}"#), .invalid(name: "set_timer", reason: "missing duration"))
        XCTAssertEqual(parse("set_timer", #"{"minutes":-5}"#), .invalid(name: "set_timer", reason: "negative duration"))
        XCTAssertEqual(parse("set_timer", #"{"minutes":1500}"#), .invalid(name: "set_timer", reason: "timer is longer than 24 hours"))
    }

    func testMapAndShortcutNeedTheirText() {
        XCTAssertEqual(parse("open_map", #"{"place":"Mokotów Tower"}"#), .openMap(place: "Mokotów Tower"))
        XCTAssertEqual(parse("open_map", #"{}"#), .invalid(name: "open_map", reason: "missing place"))
        XCTAssertEqual(parse("run_shortcut", #"{"name":"Morning routine"}"#), .runShortcut(name: "Morning routine"))
        XCTAssertEqual(parse("run_shortcut", #"{}"#), .invalid(name: "run_shortcut", reason: "missing name"))
    }

    func testMessageDraftChannels() {
        XCTAssertEqual(parse("draft_message", #"{"to":"Marta","body":"See you at six"}"#),
                       .draftMessage(MessageDraft(recipientName: "Marta", channel: .text, body: "See you at six")))
        XCTAssertEqual(parse("draft_message", #"{"to":"Marta","channel":"Email","body":"Agenda attached"}"#),
                       .draftMessage(MessageDraft(recipientName: "Marta", channel: .email, body: "Agenda attached")))
        XCTAssertEqual(parse("draft_message", #"{"to":"Marta","channel":"fax","body":"x"}"#),
                       .invalid(name: "draft_message", reason: "channel must be text or email"))
        XCTAssertEqual(parse("draft_message", #"{"to":"Marta"}"#), .invalid(name: "draft_message", reason: "missing body"))
    }

    func testOpenLinksEncodeAndRefuseEmptyNumbers() {
        XCTAssertEqual(OpenLinks.map(place: "Mokotów Tower")?.absoluteString, "https://maps.apple.com/?q=Mokot%C3%B3w%20Tower")
        XCTAssertEqual(OpenLinks.shortcut(name: "Morning routine")?.absoluteString, "shortcuts://run-shortcut?name=Morning%20routine")
        XCTAssertEqual(OpenLinks.call(number: "+48 600-123-456")?.absoluteString, "tel:+48600123456")
        XCTAssertNil(OpenLinks.call(number: "call me"))
        XCTAssertEqual(OpenLinks.text(number: "+48600123456", body: "Hi & bye +1")?.absoluteString,
                       "sms:+48600123456&body=Hi%20%26%20bye%20%2B1")
        XCTAssertEqual(OpenLinks.email(address: "marta@example.com", body: "Hej")?.absoluteString,
                       "mailto:marta@example.com?body=Hej")
        XCTAssertNil(OpenLinks.email(address: "marta @example.com", body: "Hej"))
    }

    func testConnectionServesItsTools() {
        XCTAssertEqual(VoiceConnection.serving("read_calendar"), .calendar)
        XCTAssertEqual(VoiceConnection.serving("create_calendar_event"), .calendar)
        XCTAssertEqual(VoiceConnection.serving("create_reminder"), .reminders)
        XCTAssertEqual(VoiceConnection.serving("lookup_contact"), .contacts)
        XCTAssertEqual(VoiceConnection.serving("set_timer"), .timers)
        XCTAssertEqual(VoiceConnection.serving("open_map"), .maps)
        XCTAssertEqual(VoiceConnection.serving("run_shortcut"), .shortcuts)
        XCTAssertEqual(VoiceConnection.serving("draft_message"), .messages)
        XCTAssertNil(VoiceConnection.serving("save_memory"))
        XCTAssertEqual(VoiceConnection.calendar.preferenceKey, "voiceConnection.calendar")
        XCTAssertEqual(VoiceConnection.allCases.count, 7)
    }

    // MARK: Replies

    func testReplyPrefixesMatchTheAgentPrompt() {
        XCTAssertTrue(VoiceToolReply.notConnected(.calendar).hasPrefix("Calendar isn't connected."))
        XCTAssertTrue(VoiceToolReply.notConnected(.calendar).contains("Settings, Connections"))

        let event = CalendarEventDraft(title: "Dentist", start: date(2026, 10, 12, 15, 0), end: date(2026, 10, 12, 16, 0), allDay: false, location: nil, notes: nil)
        let added = VoiceToolReply.eventAdded(event, calendar: calendar)
        XCTAssertTrue(added.hasPrefix("added: "))
        XCTAssertTrue(added.contains("2026-10-12 15:00 to 2026-10-12 16:00"))

        XCTAssertTrue(VoiceToolReply.reminder(.added(ReminderReceipt(title: "Buy milk", listTitle: "Reminders", due: nil))).hasPrefix("added: reminder"))
        XCTAssertTrue(VoiceToolReply.declinedEvent.hasPrefix("declined: "))
        XCTAssertTrue(VoiceToolReply.notAdded("Calendar is read-only.").hasPrefix("failed: "))
        XCTAssertTrue(VoiceToolReply.addUnconfirmed.hasPrefix("unknown: "))
    }

    func testTimerReplyStatesWhenItRings() {
        let draft = TimerDraft(seconds: 600, label: "Pasta")
        let reply = VoiceToolReply.timerAdded(draft, endsAt: date(2026, 10, 9, 10, 10), calendar: calendar)
        XCTAssertEqual(reply, "added: timer \"Pasta\", 10 minutes, rings at 2026-10-09 10:10.")
        XCTAssertEqual(VoiceToolReply.timerAdded(TimerDraft(seconds: 45, label: nil), endsAt: date(2026, 10, 9, 10, 0), calendar: calendar),
                       "added: timer 45 seconds, rings at 2026-10-09 10:00.")
    }

    func testOpenedRepliesNeverClaimSending() {
        let draft = MessageDraft(recipientName: "Marta", channel: .text, body: "See you")
        XCTAssertTrue(VoiceToolReply.messageOpened(draft, recipient: "Marta").contains("Nothing was sent by Doddy"))
        XCTAssertTrue(VoiceToolReply.messageOpened(draft, recipient: "Marta").hasPrefix("opened: Messages"))
        XCTAssertTrue(VoiceToolReply.shortcutRequested("Morning routine").contains("can't see whether it finished"))
        XCTAssertTrue(VoiceToolReply.noAddress("Marta", channel: .email).hasPrefix("failed: Marta has no email address"))
        XCTAssertTrue(VoiceToolReply.declinedMessage.hasPrefix("declined: "))
        XCTAssertEqual(VoiceToolReply.notOpened("Maps didn't open."), "failed: Maps didn't open. Nothing was opened.")
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

/// Repeating events and reminders by voice (ADR-282).
final class CalendarRepeatTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12))! }
    private func parse(_ name: String, _ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: name, parametersJSON: Data(json.utf8), now: now, calendar: calendar)
    }

    func testAnEventCanRepeatUntilADay() {
        guard case .createCalendarEvent(let draft) = parse(VoiceToolName.createCalendarEvent,
            #"{"title":"Gym","start":"2026-10-12T07:00","repeat":"weekly","repeat_until":"2026-12-31"}"#) else { return XCTFail() }
        XCTAssertEqual(draft.repeats?.frequency, .weekly)
        XCTAssertEqual(draft.repeats?.until?.localText, "2026-12-31")
        XCTAssertTrue(VoiceToolReply.eventAdded(draft, calendar: calendar).hasSuffix("Repeats every week until 2026-12-31."))
        guard case .invalid = parse(VoiceToolName.createCalendarEvent,
            #"{"title":"Gym","start":"2026-10-12T07:00","repeat":"weekly","repeat_until":"2026-10-01"}"#) else {
            return XCTFail("an end before the first date is refused")
        }
        guard case .invalid = parse(VoiceToolName.createCalendarEvent,
            #"{"title":"Gym","start":"2026-10-12T07:00","repeat":"hourly"}"#) else { return XCTFail("unknown repeat") }
    }

    func testAReminderRepeatNeedsADue() {
        guard case .createReminder(let draft) = parse(VoiceToolName.createReminder,
            #"{"title":"Take pills","due":"2026-10-12T08:00","repeat":"daily"}"#) else { return XCTFail() }
        XCTAssertEqual(draft.repeats, CalendarRepeat(frequency: .daily))
        XCTAssertEqual(ReminderWrite(draft).repeats, draft.repeats)
        guard case .invalid = parse(VoiceToolName.createReminder, #"{"title":"Take pills","repeat":"daily"}"#) else {
            return XCTFail("a repeat needs a first date")
        }
    }

    func testReadBackConfirmsOnlyTheSameRule() {
        XCTAssertEqual(CalendarRepeat.from(unit: .weekly, interval: 1, weekdays: [2, 3, 4, 5, 6], until: nil)?.frequency, .weekdays)
        XCTAssertEqual(CalendarRepeat.from(unit: .weekly, interval: 2, weekdays: [2], until: nil)?.frequency, .everyTwoWeeks)
        XCTAssertNil(CalendarRepeat.from(unit: .weekly, interval: 3, weekdays: nil, until: nil), "a rule Doddy doesn't write")
        XCTAssertNil(CalendarRepeat.from(unit: .weekly, interval: 1, weekdays: [2, 4], until: nil))
        let write = ReminderWrite(ReminderDraft(title: "Pills", due: ReminderDue(year: 2026, month: 10, day: 12, hour: 8, timeZoneID: "Europe/Warsaw"), notes: nil, repeats: CalendarRepeat(frequency: .daily)))
        let plain = ReminderSnapshot(id: "1", title: "Pills", listTitle: "R", due: write.due, markerURL: nil)
        let repeating = ReminderSnapshot(id: "1", title: "Pills", listTitle: "R", due: write.due, markerURL: nil, repeats: CalendarRepeat(frequency: .daily))
        XCTAssertFalse(ReminderMatching.confirms(plain, write), "the repeat must read back too")
        XCTAssertTrue(ReminderMatching.confirms(repeating, write))
    }

    func testAPlanStepKeepsItsRepeatWhenEdited() {
        let step = PlanStep(number: 1, toolName: VoiceToolName.createReminder, request: parse(VoiceToolName.createReminder,
            #"{"title":"Take pills","due":"2026-10-12T08:00","repeat":"daily"}"#))
        var form = PlanStepForm(step, now: now, calendar: calendar)
        form.text = "Take vitamins"
        guard case .step(let edited) = form.apply(to: step, now: now, calendar: calendar),
              case .createReminder(let draft) = edited.request else { return XCTFail() }
        XCTAssertEqual(draft.title, "Take vitamins")
        XCTAssertEqual(draft.repeats?.frequency, .daily)
    }
}
