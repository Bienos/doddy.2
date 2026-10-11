import XCTest
@testable import DoddyCore

/// Voice note reminders (ADR-198): what the agent may ask for, how its quote finds a note, and what
/// it is told afterwards.
final class NoteReminderVoiceTests: XCTestCase {
    // Sat 10 Oct 2026, 13:02 in Warsaw.
    private let now = Date(timeIntervalSince1970: 1_791_630_120)
    private var warsaw: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return cal
    }

    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(
            name: VoiceToolName.remindAboutNote, parametersJSON: Data(json.utf8), now: now, calendar: warsaw)
    }

    func testTimeAndPlaceRequestsParse() {
        XCTAssertEqual(
            parse(#"{"note":"Kod do paczkomatu: 5678","due":"2026-10-11T09:00"}"#),
            .remindAboutNote(NoteReminderVoiceDraft(
                noteText: "Kod do paczkomatu: 5678",
                target: .time(Date(timeIntervalSince1970: 1_791_702_000), timeZoneID: "Europe/Warsaw"))))
        XCTAssertEqual(
            parse(#"{"note":"Parcel code 5678","place":"InPost Marszałkowska Warszawa","when_leaving":true}"#),
            .remindAboutNote(NoteReminderVoiceDraft(
                noteText: "Parcel code 5678", target: .place(query: "InPost Marszałkowska Warszawa", onArrival: false))))
        XCTAssertEqual(
            parse(#"{"note":"Parcel code 5678","place":"post office"}"#),
            .remindAboutNote(NoteReminderVoiceDraft(noteText: "Parcel code 5678", target: .place(query: "post office", onArrival: true))))
    }

    /// ADR-256: a list is named instead of a note; never both.
    func testAListCanBeNamedInsteadOfANote() {
        XCTAssertEqual(
            parse(#"{"list":"Shopping","place":"Lidl Puławska"}"#),
            .remindAboutNote(NoteReminderVoiceDraft(
                noteText: "Shopping", target: .place(query: "Lidl Puławska", onArrival: true), isList: true)))
        guard case .invalid = parse(#"{"list":"Shopping","note":"milk","place":"Lidl"}"#) else { return XCTFail("note or list, not both") }
        guard case .invalid = parse(#"{"list":"  ","place":"Lidl"}"#) else { return XCTFail("an empty list name isn't a list") }
    }

    func testUnclearRequestsGoBackToTheAgentWithoutACard() {
        guard case .invalid = parse(#"{"note":"x"}"#) else { return XCTFail("needs due or place") }
        guard case .invalid = parse(#"{"note":"x","due":"2026-10-11T09:00","place":"home"}"#) else { return XCTFail("not both") }
        guard case .invalid = parse(#"{"due":"2026-10-11T09:00"}"#) else { return XCTFail("needs a note") }
        // A day without a time, a past time, or words: ask the user, nothing is shown or set.
        for due in ["2026-10-11", "2026-10-10T09:00", "tomorrow at nine"] {
            guard case .needsClarification(let name, _) = parse(#"{"note":"x","due":"\#(due)"}"#) else {
                return XCTFail("\(due) should be clarified")
            }
            XCTAssertEqual(name, VoiceToolName.remindAboutNote)
        }
    }

    func testQuoteFindsTheNoteOrNothing() throws {
        func record(_ text: String, _ seconds: Double) throws -> MemoryRecord {
            try MemoryRecord(id: UUID(), rawText: text, source: .explicitVoice, capturedAt: Date(timeIntervalSince1970: seconds))
        }
        let old = try record("Parcel code 5678", 1)
        let new = try record("Parcel code 5678", 2)
        let other = try record("The spare keys are in the blue tin.", 3)
        let notes = [old, other, new]
        XCTAssertEqual(NoteQuoteMatch.find("Parcel code 5678", in: notes)?.id, new.id, "newest of identical notes")
        XCTAssertEqual(NoteQuoteMatch.find("  “the spare keys are in   the blue tin.” ", in: notes)?.id, other.id)
        XCTAssertNil(NoteQuoteMatch.find("Parcel code", in: notes), "no partial or closest match")
        XCTAssertNil(NoteQuoteMatch.find("“ ”", in: notes))
    }

    func testRepliesUseTheActivityLogPrefixes() throws {
        let time = MemoryReminder(
            id: UUID(), memoryID: UUID(), fireAt: Date(timeIntervalSince1970: 1_791_702_000),
            timeZoneID: "Europe/Warsaw", createdAt: now)
        let place = MemoryReminder(
            id: UUID(), memoryID: UUID(),
            trigger: .place(try ReminderPlace(name: "Post office", latitude: 52.2, longitude: 21.0, radiusMeters: 200, onArrival: true)),
            createdAt: now)
        XCTAssertEqual(
            VoiceToolReply.noteReminderSet(time, note: "Parcel code 5678"),
            "added: a reminder about the note below: at Sun 11 Oct, 09:00 (Warsaw time). It is a notification on this iPhone.\n<<<DATA\nNote: \"Parcel code 5678\"\nDATA>>>")
        XCTAssertTrue(VoiceToolReply.noteReminderSet(place, note: "x").contains("when you arrive at the place below (within 200 m"))
        XCTAssertTrue(VoiceToolReply.noteReminderSet(place, note: "x").hasSuffix("<<<DATA\nNote: \"x\"\nPlace: \"Post office\"\nDATA>>>"))
        XCTAssertTrue(VoiceToolReply.noteReminderInDoddyOnly(time, note: "x").contains("won't alert"))
        XCTAssertEqual(VoiceToolReply.noteReminderFailed("Precise Location is off."), "failed: Precise Location is off. Nothing was set.")

        // The activity log reads these exactly as for other tools.
        let request = ActivityRequest.describe(
            .remindAboutNote(NoteReminderVoiceDraft(noteText: "x", target: .place(query: "post office", onArrival: true))),
            calendar: warsaw)!
        XCTAssertEqual(request.detail, "“x” · arriving at “post office”")
        XCTAssertEqual(ActivityEntry(request: request, reply: VoiceToolReply.noteReminderSet(place, note: "x"), at: now).outcome, .done)
        XCTAssertEqual(ActivityEntry(request: request, reply: VoiceToolReply.declinedNoteReminder, at: now).outcome, .declined)
        XCTAssertEqual(ActivityEntry(request: request, reply: VoiceToolReply.noteNotFound(), at: now).outcome, .notDone)
    }

    /// Review C3: replacing a note's reminder is said on the card and to the agent, never silent.
    func testReplacingAReminderIsNamed() {
        let monday20 = Date(timeIntervalSince1970: 1_791_828_000)
        let weekly = MemoryReminder(
            id: UUID(), memoryID: UUID(), trigger: .time(fireAt: monday20, timeZoneID: "Europe/Warsaw"), createdAt: now, repeats: .weekly)
        let once = MemoryReminder(
            id: UUID(), memoryID: weekly.memoryID, fireAt: Date(timeIntervalSince1970: 1_791_702_000),
            timeZoneID: "Europe/Warsaw", createdAt: now)
        let reply = VoiceToolReply.noteReminderSet(once, note: "Bins", replacing: weekly)
        XCTAssertTrue(reply.hasPrefix("added: a reminder about the note below: at Sun 11 Oct, 09:00 (Warsaw time)."), reply)
        XCTAssertTrue(reply.hasSuffix(
            " It replaced the note's earlier reminder (every Monday at 20:00 (Warsaw time), first on Mon 12 Oct, 20:00, until the user stops it on the note), which is gone now. Tell the user.\n<<<DATA\nNote: \"Bins\"\nDATA>>>"), reply)
        XCTAssertTrue(VoiceToolReply.noteReminderInDoddyOnly(once, note: "Bins", replacing: weekly).contains("It replaced the note's earlier reminder"))
        XCTAssertFalse(VoiceToolReply.noteReminderSet(once, note: "Bins").contains("replaced"))
        let line = NoteReminderReplacement.cardLine(weekly, locale: Locale(identifier: "en_GB"))
        XCTAssertTrue(line.hasPrefix("Replaces its reminder: "), line)
        XCTAssertTrue(line.hasSuffix("(stops repeating)"), line)
        XCTAssertFalse(NoteReminderReplacement.cardLine(once).contains("repeating"))
    }

    func testRepeatArgumentIsCheckedBeforeAnyCard() throws {
        // Mon 12 Oct 2026, 20:00 Warsaw.
        let monday20 = Date(timeIntervalSince1970: 1_791_828_000)
        XCTAssertEqual(
            parse(#"{"note":"Bins","due":"2026-10-12T20:00","repeat":"weekly"}"#),
            .remindAboutNote(NoteReminderVoiceDraft(
                noteText: "Bins", target: .time(monday20, timeZoneID: "Europe/Warsaw"), repeats: .weekly)))
        XCTAssertEqual(
            parse(#"{"note":"Bins","due":"2026-10-12T20:00","repeat":"never"}"#),
            .remindAboutNote(NoteReminderVoiceDraft(noteText: "Bins", target: .time(monday20, timeZoneID: "Europe/Warsaw"))))
        guard case .invalid = parse(#"{"note":"x","due":"2026-10-12T20:00","repeat":"hourly"}"#) else { return XCTFail("unknown rule") }
        guard case .invalid = parse(#"{"note":"x","place":"home","repeat":"daily"}"#) else { return XCTFail("a place can't repeat") }
        guard case .needsClarification(_, let clarification) = parse(#"{"note":"x","due":"2026-10-30T09:00","repeat":"monthly"}"#) else {
            return XCTFail("monthly on the 30th goes back to the agent")
        }
        XCTAssertTrue(clarification.problem.contains("1 to 28"))

        let reminder = MemoryReminder(
            id: UUID(), memoryID: UUID(), trigger: .time(fireAt: monday20, timeZoneID: "Europe/Warsaw"), createdAt: now, repeats: .weekly)
        XCTAssertEqual(
            VoiceToolReply.noteReminderSet(reminder, note: "Bins"),
            "added: a reminder about the note below: every Monday at 20:00 (Warsaw time), first on Mon 12 Oct, 20:00, until the user stops it on the note. It is a notification on this iPhone.\n<<<DATA\nNote: \"Bins\"\nDATA>>>")
        let request = ActivityRequest.describe(
            .remindAboutNote(NoteReminderVoiceDraft(noteText: "Bins", target: .time(monday20, timeZoneID: "Europe/Warsaw"), repeats: .weekly)),
            calendar: warsaw)!
        XCTAssertEqual(request.detail, "“Bins” · every Monday at 20:00")
    }

    func testPauseAllConnectionsStopsOnlyThePlaceLookup() {
        XCTAssertTrue(ConnectionPause.applies(to: parse(#"{"note":"x","place":"post office"}"#)))
        XCTAssertFalse(ConnectionPause.applies(to: parse(#"{"note":"x","due":"2026-10-11T09:00"}"#)))
    }
}
