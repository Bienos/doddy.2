import XCTest
@testable import DoddyCore

final class ConnectionsTests: XCTestCase {
    private let warsaw = TimeZone(identifier: "Europe/Warsaw")!
    private let now = Date(timeIntervalSince1970: 1_791_000_000)  // 2026-10-03T05:20:00Z

    func testConnectedRequiresEnabledAuthorizedAndVerified() {
        var state = ConnectionState(kind: .calendar)
        XCTAssertEqual(state.status, .off)
        state.enabled = true
        XCTAssertEqual(state.status, .notConnected)
        state.authorization = .denied
        XCTAssertEqual(state.status, .denied)
        state.authorization = .fullAccess
        XCTAssertEqual(state.status, .authorizedUnverified, "permission alone is not a connection")
        XCTAssertFalse(state.canRead)
        let proof = ConnectionVerification(verifiedAt: now, evidence: "read 2 calendars")
        state.verification = proof
        XCTAssertEqual(state.status, .connected(proof))
        XCTAssertTrue(state.canRead)
        state.lastError = "boom"
        XCTAssertEqual(state.status, .error("boom"))
        XCTAssertFalse(state.canWrite)
    }

    func testWriteOnlyAccessCanWriteButNeverReads() {
        var state = ConnectionState(kind: .calendar, enabled: true, authorization: .writeOnly)
        state.verification = ConnectionVerification(verifiedAt: now, evidence: "x")
        XCTAssertTrue(state.canWrite)
        XCTAssertFalse(state.canRead)
    }

    func testDraftValidation() {
        XCTAssertThrowsError(try EventDraft(title: "  ", start: now))
        XCTAssertThrowsError(try EventDraft(title: "Dentist", start: now, end: now.addingTimeInterval(-1)))
        let draft = try? EventDraft(title: " Dentist ", start: now)
        XCTAssertEqual(draft?.title, "Dentist")
        XCTAssertEqual(draft?.end, now.addingTimeInterval(3600), "default duration is one hour")
        XCTAssertThrowsError(try ReminderDraft(title: ""))
    }

    func testNudgePlanIsDeterministicAndRefusesThePast() throws {
        let event = CalendarEvent(id: "E1", calendarTitle: "Personal", title: "Dentist", start: now.addingTimeInterval(7200), end: now.addingTimeInterval(10800), isAllDay: false)
        let plan = try EventNudgePlan(event: event, leadMinutes: 30, now: now)
        XCTAssertEqual(plan.fireAt, event.start.addingTimeInterval(-1800))
        XCTAssertEqual(plan.identifier, "nudge.event.E1.30")
        XCTAssertEqual(try EventNudgePlan(event: event, leadMinutes: 30, now: now).identifier, plan.identifier)
        XCTAssertThrowsError(try EventNudgePlan(event: event, leadMinutes: 180, now: now)) { error in
            XCTAssertEqual(error as? NudgePlanError, .fireTimeInPast)
        }
        XCTAssertThrowsError(try EventNudgePlan(event: event, leadMinutes: 0, now: now))
        let scheduled = ScheduledNudge(id: plan.identifier, title: "Doddy", body: "", fireAt: plan.fireAt)
        XCTAssertEqual(scheduled.eventID, "E1")
        XCTAssertEqual(scheduled.leadMinutes, 30)
        XCTAssertEqual(scheduled.matches(event), true)
        let moved = CalendarEvent(id: "E1", calendarTitle: "Personal", title: "Dentist", start: event.start.addingTimeInterval(3600), end: event.end, isAllDay: false)
        XCTAssertEqual(scheduled.matches(moved), false, "a moved event makes the nudge stale")
        XCTAssertNil(ScheduledNudge(id: "other", title: "", body: "", fireAt: nil).eventID)
        XCTAssertTrue(plan.notificationBody.hasPrefix("Dentist starts in 30 minutes"))
    }

    func testToolDateParserAcceptsOffsetsAndLocalTimes() {
        let withOffset = ToolDateParser.parse("2026-10-10T15:00:00+02:00", timeZone: warsaw)
        let local = ToolDateParser.parse("2026-10-10T15:00", timeZone: warsaw)
        XCTAssertNotNil(withOffset)
        XCTAssertEqual(withOffset, local, "a local time is read in the user's time zone")
        XCTAssertEqual(ToolDateParser.parse("2026-10-10", timeZone: warsaw), ToolDateParser.parse("2026-10-10T00:00", timeZone: warsaw))
        XCTAssertNil(ToolDateParser.parse("next Tuesday", timeZone: warsaw))
        XCTAssertEqual(ToolDateParser.render(withOffset!, timeZone: warsaw), "Sat 2026-10-10 15:00")
    }

    func testReadCalendarRangesUseTheUsersDay() {
        let request = VoiceToolRequest.parse(name: "read_calendar", parametersJSON: Data(#"{"range":"today"}"#.utf8), now: now, timeZone: warsaw)
        guard case .readCalendar(let from, let to) = request else { return XCTFail("\(request)") }
        XCTAssertEqual(ToolDateParser.render(from, timeZone: warsaw), "Sat 2026-10-03 00:00")
        XCTAssertEqual(to.timeIntervalSince(from), 86_400)
        XCTAssertEqual(
            VoiceToolRequest.parse(name: "read_calendar", parametersJSON: Data(#"{"range":"someday"}"#.utf8), now: now, timeZone: warsaw),
            .invalid(name: "read_calendar", reason: "unknown range \"someday\""))
        let explicit = VoiceToolRequest.parse(name: "read_calendar", parametersJSON: Data(#"{"from":"2026-10-10T09:00","to":"2026-10-10T12:00"}"#.utf8), now: now, timeZone: warsaw)
        guard case .readCalendar(let f, let t) = explicit else { return XCTFail("\(explicit)") }
        XCTAssertEqual(t.timeIntervalSince(f), 3 * 3600)
    }

    func testWriteToolsParseIntoValidatedDrafts() {
        let event = VoiceToolRequest.parse(
            name: "create_calendar_event",
            parametersJSON: Data(#"{"title":"Dentist","start":"2026-10-10T15:00","location":"ul. Długa 5"}"#.utf8),
            now: now, timeZone: warsaw)
        guard case .createCalendarEvent(let draft) = event else { return XCTFail("\(event)") }
        XCTAssertEqual(draft.title, "Dentist")
        XCTAssertEqual(draft.location, "ul. Długa 5")
        XCTAssertEqual(draft.end.timeIntervalSince(draft.start), 3600)
        XCTAssertEqual(
            VoiceToolRequest.parse(name: "create_calendar_event", parametersJSON: Data(#"{"title":"X","start":"soon"}"#.utf8)),
            .invalid(name: "create_calendar_event", reason: "missing or unreadable start"))
        let reminder = VoiceToolRequest.parse(name: "create_reminder", parametersJSON: Data(#"{"title":"Call Marta"}"#.utf8))
        XCTAssertEqual(reminder, .createReminder(try! ReminderDraft(title: "Call Marta")))
        let dayOnly = VoiceToolRequest.parse(name: "create_reminder", parametersJSON: Data(#"{"title":"Pay rent","due":"2026-10-10"}"#.utf8), now: now, timeZone: warsaw)
        guard case .createReminder(let rent) = dayOnly else { return XCTFail("\(dayOnly)") }
        XCTAssertFalse(rent.dueIncludesTime, "a due day without a time sets no alarm time")
        let allDay = VoiceToolRequest.parse(name: "create_calendar_event", parametersJSON: Data(#"{"title":"Trip","start":"2026-10-10"}"#.utf8), now: now, timeZone: warsaw)
        guard case .createCalendarEvent(let trip) = allDay else { return XCTFail("\(allDay)") }
        XCTAssertTrue(trip.isAllDay)
        XCTAssertEqual(VoiceToolRequest.parse(name: "lookup_contact", parametersJSON: Data(#"{"name":"Marta"}"#.utf8)), .lookupContact(name: "Marta"))
    }

    func testRepliesNeverLeakContactDetailsOrInventEvents() {
        let match = ContactMatch(id: "C1", displayName: "Marta Kowalska", phoneNumbers: ["+48 600 000 000"], emailAddresses: ["marta@example.com"])
        let reply = VoiceToolReply.contacts([match], query: "Marta")
        XCTAssertTrue(reply.contains("Marta Kowalska"))
        XCTAssertFalse(reply.contains("600 000 000"))
        XCTAssertFalse(reply.contains("marta@example.com"))
        XCTAssertTrue(VoiceToolReply.calendar([], from: now, to: now.addingTimeInterval(3600), timeZone: warsaw).hasPrefix("No calendar events"))
        XCTAssertTrue(VoiceToolReply.notConnected(.calendar).contains("Settings → Connections"))
        let event = CalendarEvent(id: "E1", calendarTitle: "Personal", title: "Dentist", start: now, end: now.addingTimeInterval(3600), isAllDay: false)
        XCTAssertTrue(VoiceToolReply.eventCreated(event, timeZone: warsaw).hasPrefix("added: \"Dentist\""))
        XCTAssertTrue(VoiceToolReply.actionUnverified(.createCalendarEvent).hasPrefix("unknown:"))
    }

    func testV4aCatalogAndUnavailableAdapters() async {
        XCTAssertTrue(CapabilityCatalog.v4aConnections.isAvailable(.calendar))
        XCTAssertTrue(CapabilityCatalog.v4aConnections.isAvailable(.localNudges))
        XCTAssertFalse(CapabilityCatalog.v1Voice.isAvailable(.calendar))
        XCTAssertFalse(CapabilityCatalog.v4aConnections.isAvailable(.connectedAccounts))
        do {
            _ = try await UnavailableCalendarGateway().events(from: now, to: now)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? DoddyError, .capabilityUnavailable(.calendar))
        }
        do {
            _ = try await UnavailableNudgeScheduler().pending()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? DoddyError, .capabilityUnavailable(.localNudges))
        }
        XCTAssertEqual(UnavailableContactsGateway().authorization(), .notDetermined)
    }
}
