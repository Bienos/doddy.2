import XCTest
@testable import DoddyCore

/// "What Doddy did": entries say only what the app's own reply to the agent said.
final class ActivityLogTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))! }

    private let reminder = ReminderDraft(title: "Buy milk", due: nil, notes: nil)
    private let receipt = ReminderReceipt(title: "Buy milk", listTitle: "Reminders", due: nil)

    private func entry(_ request: VoiceToolRequest, reply: String) -> ActivityEntry {
        ActivityEntry(request: ActivityRequest.describe(request, calendar: calendar)!, reply: reply, at: now)
    }

    func testOutcomesComeFromTheVerifiedReply() {
        let add = VoiceToolRequest.createReminder(reminder)
        XCTAssertEqual(entry(add, reply: VoiceToolReply.reminder(.added(receipt))).outcome, .done)
        XCTAssertEqual(entry(add, reply: VoiceToolReply.reminder(.alreadyThere(receipt))).outcome, .alreadyThere)
        XCTAssertEqual(entry(add, reply: VoiceToolReply.addUnconfirmed).outcome, .notSure)
        XCTAssertEqual(entry(add, reply: VoiceToolReply.declinedReminder).outcome, .declined)

        let failed = entry(add, reply: VoiceToolReply.notAdded("Reminders isn't connected."))
        XCTAssertEqual(failed.outcome, .notDone)
        XCTAssertEqual(failed.note, "Reminders isn't connected.")

        let off = entry(add, reply: VoiceToolReply.notConnected(.reminders))
        XCTAssertEqual(off.outcome, .notDone)
        XCTAssertEqual(off.note, "Reminders isn't connected.")

        XCTAssertEqual(entry(.openMap(place: "Hala Koszyki"), reply: VoiceToolReply.mapOpened("Hala Koszyki")).outcome, .opened)
        // A reply the app never phrased as a result is not shown as done.
        XCTAssertEqual(entry(add, reply: "something else").outcome, .notSure)
    }

    /// Review C1: every result the app phrases is read from its start, so changes, deletes, new
    /// lists and list changes show as done, and nothing-changed replies show as didn't happen.
    func testEveryReplyPrefixHasItsOutcome() throws {
        let event = CalendarEventSummary(id: "a", title: "Dentist", start: now, end: now.addingTimeInterval(3600), allDay: false)
        let move = VoiceToolRequest.changeCalendarEvent(EventChangeDraft(
            title: "Dentist", currentStart: now, currentIsDayOnly: false, newStart: now.addingTimeInterval(86_400), newEnd: nil, newTitle: nil))
        let change = VoiceToolRequest.changeReminder(ReminderChangeDraft(title: "Rent", newDue: nil, markDone: true))
        let delete = VoiceToolRequest.deleteCalendarEvent(EventChangeDraft(
            title: "Dentist", currentStart: now, currentIsDayOnly: false, newStart: nil, newEnd: nil, newTitle: nil))
        let listID = UUID()
        let milk = ListItem(id: UUID(), listID: listID, text: "milk", source: .voice, addedAt: now, doneAt: nil, position: 0)
        let shopping = DoddyList(
            record: try MemoryRecord(id: listID, rawText: "Shopping", source: .explicitVoice, category: .list, capturedAt: now), items: [milk])
        let add = VoiceToolRequest.addToList(ListVoiceRequest(list: "Shopping", items: ["milk"]))
        let tick = VoiceToolRequest.checkOff(ListVoiceRequest(list: "Shopping", items: ["milk"]))
        let remove = VoiceToolRequest.removeFromList(ListVoiceRequest(list: "Shopping", items: ["milk"]))
        let create = VoiceToolRequest.createList(ListVoiceRequest(list: "Shopping", items: []))

        let cases: [(VoiceToolRequest, String, ActivityOutcome)] = [
            (move, VoiceToolReply.eventChanged(event, calendar: calendar), .done),
            (change, VoiceToolReply.reminderChanged("Rent", due: nil), .done),
            (change, VoiceToolReply.reminderCompleted("Rent"), .done),
            (delete, VoiceToolReply.eventDeleted(event, calendar: calendar), .done),
            (.deleteReminder(title: "Rent"), VoiceToolReply.reminderDeleted("Rent"), .done),
            (create, VoiceToolReply.listCreated(shopping), .done),
            (add, VoiceToolReply.listAdded(ListAddResult(added: [milk], alreadyThere: [], tooLong: [], noRoom: []), list: "Shopping"), .done),
            (tick, VoiceToolReply.listChanged(verb: "ticked", changed: [milk], list: "Shopping", notFound: [], ambiguous: []), .done),
            (remove, VoiceToolReply.listChanged(verb: "removed", changed: [milk], list: "Shopping", notFound: [], ambiguous: []), .done),
            (add, VoiceToolReply.listAdded(ListAddResult(added: [], alreadyThere: ["milk"], tooLong: [], noRoom: []), list: "Shopping"), .notDone),
            (tick, VoiceToolReply.listChanged(verb: "ticked", changed: [], list: "Shopping", notFound: ["eggs"], ambiguous: []), .notDone),
            (add, VoiceToolReply.listNotFound("Groceries", lists: [shopping]), .notDone),
            (add, VoiceToolReply.listAmbiguous("Shop", lists: [shopping, shopping]), .notDone),
            (create, VoiceToolReply.listNameTaken("Shopping"), .notDone),
            (create, VoiceToolReply.declinedList, .declined),
            (move, VoiceToolReply.eventNotFound("Dentist"), .notDone),
            (move, VoiceToolReply.eventAmbiguous([event, event], calendar: calendar), .notDone),
            (move, VoiceToolReply.changeNothingNew, .notDone),
            (move, VoiceToolReply.eventChangeUnconfirmed, .notSure),
            (move, VoiceToolReply.changeDeclined, .declined),
            (change, VoiceToolReply.reminderNotFound("Rent"), .notDone),
            (move, VoiceToolReply.translatorRefused(VoiceToolName.changeCalendarEvent), .notDone),
            (move, VoiceToolReply.notConnected(.calendar), .notDone),
        ]
        for (request, reply, expected) in cases {
            XCTAssertEqual(entry(request, reply: reply).outcome, expected, reply)
        }
    }

    /// Review C1: "isn't connected" counts only at the start of the reply, not inside a quoted note.
    func testQuotedTextNeverDecidesTheOutcome() throws {
        let saved = try MemoryRecord(id: UUID(), rawText: "The printer isn't connected to wifi", source: .explicitVoice, capturedAt: now)
        let save = entry(.saveMemory(text: saved.currentText), reply: VoiceToolReply.saved(saved))
        XCTAssertEqual(save.outcome, .done)
        XCTAssertNil(save.note)
        // A reminder whose title mentions Reminders is still a new reminder.
        let receipt = ReminderReceipt(title: "Check what is already in Reminders", listTitle: "Reminders", due: nil)
        let add = VoiceToolRequest.createReminder(ReminderDraft(title: receipt.title, due: nil, notes: nil))
        XCTAssertEqual(entry(add, reply: VoiceToolReply.reminder(.added(receipt))).outcome, .done)
        XCTAssertEqual(entry(add, reply: VoiceToolReply.reminder(.alreadyThere(receipt))).outcome, .alreadyThere)
    }

    /// Review C2: the log outlives a deleted note or "Delete all memories", so it keeps no note
    /// text, search, list name or item; the card still shows them before the user confirms.
    func testNotesAndListsRowsKeepNoNoteText() {
        let at = now.addingTimeInterval(86_400)
        let requests: [VoiceToolRequest] = [
            .saveMemory(text: "My PIN hint is the dog's name"),
            .searchMemories(query: "dog's name"),
            .remindAboutNote(NoteReminderVoiceDraft(noteText: "Dog's vet", target: .time(at, timeZoneID: "Europe/Warsaw"))),
            .remindAboutNote(NoteReminderVoiceDraft(noteText: "Dog's vet", target: .place(query: "Vet clinic", onArrival: true))),
            .addToList(ListVoiceRequest(list: "Pharmacy", items: ["sertraline", "plasters"])),
            .checkOff(ListVoiceRequest(list: "Pharmacy", items: ["sertraline"])),
            .removeFromList(ListVoiceRequest(list: "Pharmacy", items: ["plasters"])),
            .readList(name: "Pharmacy"),
            .createList(ListVoiceRequest(list: "Pharmacy", items: [])),
        ]
        for request in requests {
            let described = ActivityRequest.describe(request, calendar: calendar)!
            XCTAssertNotNil(described.detail, "the card still shows what is asked")
            for logged in [ActivityEntry(request: described, reply: "saved: x", at: now), ActivityEntry.started(described, at: now)] {
                for secret in ["dog", "Dog", "Vet", "Pharmacy", "sertraline", "plasters"] {
                    XCTAssertFalse(logged.detail?.contains(secret) ?? false, "\(described.title): \(logged.detail ?? "")")
                }
            }
        }
        let ticked = ActivityEntry(request: ActivityRequest.describe(requests[4], calendar: calendar)!, reply: "", at: now)
        XCTAssertEqual(ticked.detail, "2 items")
        let timed = ActivityEntry(request: ActivityRequest.describe(requests[2], calendar: calendar)!, reply: "", at: now)
        XCTAssertEqual(timed.detail, "2026-10-11 12:00")
        // Other apps keep their detail.
        XCTAssertEqual(entry(.openMap(place: "Hala Koszyki"), reply: VoiceToolReply.mapOpened("Hala Koszyki")).detail, "“Hala Koszyki”")
    }

    /// Review C2: rows an older version wrote with note text lose it the next time the log is pruned.
    func testOlderNoteTextIsDroppedWhenTheLogIsPruned() {
        let old = ActivityEntry(at: now, app: .memories, title: "Save a note", detail: "“My PIN hint”", outcome: .done)
        let map = ActivityEntry(at: now, app: .maps, title: "Open in Maps", detail: "“Hala Koszyki”", outcome: .opened)
        let pruned = ActivityLog.pruned([old, map], now: now)
        XCTAssertEqual(pruned.first { $0.id == old.id }?.detail, nil)
        XCTAssertEqual(pruned.first { $0.id == old.id }?.outcome, .done)
        XCTAssertEqual(pruned.first { $0.id == map.id }?.detail, "“Hala Koszyki”")
    }

    func testLookupsAreLoggedButFailuresStillShow() {
        let search = VoiceToolRequest.searchMemories(query: "klucze")
        XCTAssertEqual(entry(search, reply: VoiceToolReply.search(.noMatch)).outcome, .lookedUp)
        XCTAssertEqual(entry(search, reply: VoiceToolReply.failed("The store is locked.")).outcome, .notDone)
        XCTAssertNil(ActivityRequest.describe(.unsupported(name: "send_sms"), calendar: calendar))
    }

    func testOnlineAccountWritesAreReadFromTheServerResult() {
        let draft = VoiceToolRequest.cloudTool(CloudToolCall(name: CloudToolName.draftEmail, arguments: [:]))
        XCTAssertEqual(entry(draft, reply: "drafted: Gmail draft to a@b.pl with subject \"Hi\" was created.").outcome, .done)
        let demo = entry(draft, reply: "DEMO DATA from a test server, not the user's real account. Tell the user it is demo data. drafted: Gmail draft was created.")
        XCTAssertEqual(demo.outcome, .done)
        XCTAssertEqual(demo.note, "Demo data from a test server, not your account.")
        XCTAssertEqual(entry(draft, reply: VoiceToolReply.cloudDeclined(CloudToolName.draftEmail)).outcome, .declined)
    }

    func testOnlineAccountEntriesKeepNoContent() {
        let request = ActivityRequest.describe(.cloudTool(CloudToolCall(name: CloudToolName.checkEmail, arguments: [:])), calendar: calendar)
        XCTAssertEqual(request?.app, .gmail)
        XCTAssertNil(request?.detail)
    }

    func testCheckIsOfferedOnlyForUnsureRemindersAndSettlesIt() {
        let unsure = entry(.createReminder(reminder), reply: VoiceToolReply.addUnconfirmed)
        XCTAssertTrue(unsure.canCheckInReminders)
        XCTAssertEqual(unsure.reminderKey, ReminderWrite(reminder).key)
        XCTAssertFalse(entry(.openMap(place: "x"), reply: VoiceToolReply.addUnconfirmed).canCheckInReminders)

        let found = ActivityLog.checked(unsure, found: true, at: now)
        XCTAssertEqual(found.outcome, .done)
        XCTAssertFalse(found.canCheckInReminders)
        XCTAssertEqual(ActivityLog.checked(unsure, found: false, at: now).outcome, .notDone)
    }

    func testChangeCutOffMidWayBecomesNotSureNeverDone() {
        let request = ActivityRequest.describe(.createReminder(reminder), calendar: calendar)!
        let started = ActivityEntry.started(request, at: now)
        XCTAssertEqual(started.outcome, .inProgress)
        let lookup = entry(.searchMemories(query: "x"), reply: VoiceToolReply.search(.noMatch))

        let recovered = ActivityLog.recoverInterrupted([started, lookup])
        XCTAssertEqual(recovered[0].outcome, .notSure)
        XCTAssertEqual(recovered[0].note, ActivityLog.interruptedNote)
        XCTAssertTrue(recovered[0].canCheckInReminders, "an interrupted reminder can be checked")
        XCTAssertEqual(recovered[1], lookup, "finished entries are untouched")

        // A result that does arrive replaces the started entry under the same id.
        let finished = ActivityEntry(id: started.id, request: request, reply: VoiceToolReply.addUnconfirmed, at: now)
        XCTAssertEqual(finished.id, started.id)
        XCTAssertEqual(finished.outcome, .notSure)
    }

    func testLogIsNewestFirstAndBounded() {
        let old = ActivityEntry(at: now.addingTimeInterval(-31 * 86_400), app: .maps, title: "Old", detail: nil, outcome: .opened)
        var log = [old]
        for minute in 0..<(ActivityLog.maxEntries + 5) {
            let item = ActivityEntry(at: now.addingTimeInterval(Double(minute) * 60), app: .maps, title: "\(minute)", detail: nil, outcome: .opened)
            log = ActivityLog.appending(item, to: log, now: now)
        }
        XCTAssertEqual(log.count, ActivityLog.maxEntries)
        XCTAssertFalse(log.contains(old), "entries older than 30 days are dropped")
        XCTAssertEqual(log.first?.title, "\(ActivityLog.maxEntries + 4)")
    }
}

final class ConnectionPauseTests: XCTestCase {
    func testPauseStopsEveryAppButLeavesNotes() {
        let draft = ReminderDraft(title: "Buy milk", due: nil, notes: nil)
        let paused: [VoiceToolRequest] = [
            .readCalendar(VoiceTimeRange(start: Date(), end: Date().addingTimeInterval(3600))),
            .createReminder(draft), .lookupContact(name: "Marta"), .openMap(place: "Koszyki"),
            .runShortcut(name: "Home"), .setTimer(TimerDraft(seconds: 60, label: nil)),
            .draftMessage(MessageDraft(recipientName: "Marta", channel: .text, body: "Hi")),
            .cloudTool(CloudToolCall(name: CloudToolName.checkEmail, arguments: [:])),
        ]
        for request in paused { XCTAssertTrue(ConnectionPause.applies(to: request), "\(request)") }
        XCTAssertFalse(ConnectionPause.applies(to: .searchMemories(query: "klucze")))
        XCTAssertFalse(ConnectionPause.applies(to: .saveMemory(text: "x")))
    }

    func testPausedRequestsShowAsNotDoneInWhatDoddyDid() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let draft = ReminderDraft(title: "Buy milk", due: nil, notes: nil)
        for request in [VoiceToolRequest.createReminder(draft), .lookupContact(name: "Marta")] {
            let entry = ActivityEntry(
                request: ActivityRequest.describe(request, calendar: calendar)!, reply: ConnectionPause.reply, at: Date())
            XCTAssertEqual(entry.outcome, .notDone)
            XCTAssertEqual(entry.note, "Connections were paused.")
        }
    }
}
