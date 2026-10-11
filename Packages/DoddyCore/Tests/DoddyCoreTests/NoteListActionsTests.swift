import XCTest
@testable import DoddyCore

/// ADR-302: notes and lists in the action status model. An unsure note or list change is settled
/// from Doddy's own notes and lists; a note isn't saved twice after an unconfirmed try.
final class NoteListActionsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    /// Sat 10 Oct 2026, 12:00 in Warsaw.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))! }

    private func note(_ text: String, at date: Date, source: MemorySource = .explicitVoice) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: source, category: .other, capturedAt: date)
    }

    private func list(_ name: String, open: [String] = [], done: [String] = []) throws -> DoddyList {
        let record = try MemoryRecord(id: UUID(), rawText: name, source: .explicitVoice, category: .list, capturedAt: now)
        let items = (open.map { ($0, false) } + done.map { ($0, true) }).enumerated().map { index, item in
            ListItem(id: UUID(), listID: record.id, text: item.0, source: .voice, addedAt: now,
                     doneAt: item.1 ? now : nil, position: index)
        }
        return DoddyList(record: record, items: items)
    }

    private func request(_ tool: VoiceToolRequest) -> ActivityRequest { ActivityRequest.describe(tool, calendar: calendar)! }

    /// An entry cut off mid-way, as the next launch leaves it.
    private func unsure(_ tool: VoiceToolRequest, at date: Date? = nil) -> ActivityEntry {
        ActivityLog.recoverInterrupted([ActivityEntry.started(request(tool), at: date ?? now)], at: (date ?? now) + 5)[0]
    }

    // MARK: Keys and checks

    func testEveryNoteAndListChangeCarriesAKeyAndACheck() {
        let save = request(.saveMemory(text: "Gate code: 4821."))
        XCTAssertEqual(save.operationKey, NoteIdempotency.key("gate code 4821"), "same words, same note")
        XCTAssertEqual(save.check, .note(key: NoteIdempotency.key("Gate code 4821")))

        let add = request(.addToList(ListVoiceRequest(list: "Shopping", items: ["milk", "eggs"])))
        XCTAssertEqual(add.operationKey, ListOpIdempotency.key("add", list: "the shopping list", items: ["Eggs", "Milk"]), "order and the word list don't matter")
        XCTAssertEqual(add.check, .listAdd(list: "Shopping", items: ["milk", "eggs"]))
        XCTAssertNotEqual(add.operationKey, request(.checkOff(ListVoiceRequest(list: "Shopping", items: ["milk", "eggs"]))).operationKey)
        XCTAssertEqual(request(.createList(ListVoiceRequest(list: "Trip", items: []))).check, .listCreate(name: "Trip"))
        XCTAssertNil(request(.searchMemories(query: "gate")).check)
    }

    func testTheCheckIsKeptThroughStartFinishAndSaving() throws {
        let started = ActivityEntry.started(request(.saveMemory(text: "Gate 4821")), at: now)
        XCTAssertEqual(started.check, .note(key: NoteIdempotency.key("Gate 4821")))
        let back = try JSONDecoder().decode(ActivityEntry.self, from: JSONEncoder().encode(started))
        XCTAssertEqual(back.check, started.check)
        let finished = ActivityEntry.finished(started, request: request(.saveMemory(text: "Gate 4821")), reply: "saved: \"Gate 4821\" (saved x).", at: now)
        XCTAssertEqual(finished.check, started.check)
    }

    // MARK: Settling notes

    func testAnUnsureNoteIsConfirmedWhenItIsInTheNotes() throws {
        let entry = unsure(.saveMemory(text: "Gate code 4821"))
        let saved = try note("gate code: 4821", at: now + 1)
        let settled = LocalCheck.settled(entry, notes: [saved], lists: [], at: now + 60)
        XCTAssertEqual(settled.status, .confirmed)
        XCTAssertEqual(settled.note, "Found in your notes when Doddy checked.")
        XCTAssertEqual(settled.history.map(\.status), [.proposed, .pending, .unknown, .confirmed])
        XCTAssertEqual(settled.checkedAt, now + 60)
    }

    func testAnUnsureNoteNotInTheNotesDidntHappen() throws {
        let entry = unsure(.saveMemory(text: "Gate code 4821"))
        // The same words saved last week are another note, not this try.
        let older = try note("Gate code 4821", at: now - 7 * 86_400)
        let sample = try note("Gate code 4821", at: now + 1, source: .sampleFixture)
        let settled = LocalCheck.settled(entry, notes: [older, sample], lists: [], at: now + 60)
        XCTAssertEqual(settled.status, .failed)
        XCTAssertEqual(settled.note, "Not in your notes when Doddy checked, so it didn't happen. You can ask again.")
    }

    func testOnlyUnsureEntriesWithACheckAreSettled() throws {
        let saved = try note("Gate code 4821", at: now + 1)
        let done = ActivityEntry(request: request(.saveMemory(text: "Gate code 4821")), reply: VoiceToolReply.saved(saved), at: now)
        XCTAssertEqual(LocalCheck.settled(done, notes: [], lists: [], at: now + 60), done, "a confirmed entry never changes")
        let reminder = unsure(.createReminder(ReminderDraft(title: "Milk", due: nil, notes: nil)))
        XCTAssertEqual(LocalCheck.settled(reminder, notes: [saved], lists: [], at: now + 60), reminder, "Reminders are checked in Reminders, not here")
        // An entry saved before ADR-302 has no check.
        let old = ActivityEntry(at: now, app: .memories, title: "Save a note", detail: nil, outcome: .notSure)
        XCTAssertEqual(LocalCheck.settled(old, notes: [saved], lists: [], at: now + 60), old)
    }

    // MARK: Settling lists

    func testUnsureListChangesAreSettledFromTheList() throws {
        let shopping = try list("Shopping", open: ["Milk", "Bread"], done: ["Eggs"])
        let add = unsure(.addToList(ListVoiceRequest(list: "shopping list", items: ["milk", "bread"])))
        XCTAssertEqual(LocalCheck.settled(add, notes: [], lists: [shopping], at: now + 60).status, .confirmed)
        let addMissing = unsure(.addToList(ListVoiceRequest(list: "Shopping", items: ["milk", "tea"])))
        XCTAssertEqual(LocalCheck.settled(addMissing, notes: [], lists: [shopping], at: now + 60).status, .failed)

        let tick = unsure(.checkOff(ListVoiceRequest(list: "Shopping", items: ["eggs"])))
        XCTAssertEqual(LocalCheck.settled(tick, notes: [], lists: [shopping], at: now + 60).status, .confirmed)
        let tickOpen = unsure(.checkOff(ListVoiceRequest(list: "Shopping", items: ["milk"])))
        XCTAssertEqual(LocalCheck.settled(tickOpen, notes: [], lists: [shopping], at: now + 60).status, .failed)

        let remove = unsure(.removeFromList(ListVoiceRequest(list: "Shopping", items: ["tea"])))
        XCTAssertEqual(LocalCheck.settled(remove, notes: [], lists: [shopping], at: now + 60).status, .confirmed)
        let removeThere = unsure(.removeFromList(ListVoiceRequest(list: "Shopping", items: ["bread"])))
        let settled = LocalCheck.settled(removeThere, notes: [], lists: [shopping], at: now + 60)
        XCTAssertEqual(settled.status, .failed)
        XCTAssertEqual(settled.note, "Not in the list “Shopping” when Doddy checked, so it didn't happen. You can ask again.")
        // The list is gone: Doddy can't tell whether the remove happened, so it stays unsure.
        XCTAssertEqual(LocalCheck.settled(removeThere, notes: [], lists: [], at: now + 60).status, .unknown)

        let create = unsure(.createList(ListVoiceRequest(list: "Trip", items: [])))
        XCTAssertEqual(LocalCheck.settled(create, notes: [], lists: [try list("trip")], at: now + 60).status, .confirmed)
        XCTAssertEqual(LocalCheck.settled(create, notes: [], lists: [shopping], at: now + 60).status, .failed)
    }

    func testSettlingFirstMeansARetryGoesAheadOrIsCountedAsAFailure() throws {
        let tool = VoiceToolRequest.saveMemory(text: "Gate code 4821")
        let entry = unsure(tool)
        XCTAssertEqual(ActionRetry.decide(for: request(tool), in: [entry], now: now + 60), .checkFirst(since: now))
        let found = LocalCheck.settledAll([entry], notes: [try note("Gate code 4821", at: now + 1)], lists: [], at: now + 60)
        XCTAssertEqual(ActionRetry.decide(for: request(tool), in: found, now: now + 60), .go, "it is saved: the story is closed")
    }

    // MARK: Not saving a note twice

    func testAfterAnUnconfirmedTryTheSavedNoteIsFoundNotSavedAgain() throws {
        let saved = try note("Gate code: 4821", at: now + 2)
        XCTAssertEqual(NoteIdempotency.savedSince(now, text: "gate code 4821", in: [saved]), saved)
        XCTAssertNil(NoteIdempotency.savedSince(now + 3_600, text: "gate code 4821", in: [saved]), "saved before the try: another note")
        XCTAssertNil(NoteIdempotency.savedSince(now, text: "gate code 4822", in: [saved]))
    }

    func testRepliesAndReceiptsForNotesAndLists() throws {
        let saved = try note("Gate code 4821", at: now)
        let again = VoiceToolReply.noteAlreadySaved(saved)
        XCTAssertEqual(ActivityEntry.outcome(of: again, isLookup: false).0, .alreadyThere)
        XCTAssertTrue(again.hasPrefix("saved: \"Gate code 4821\" was already saved from the earlier try"))
        XCTAssertEqual(ActivityEntry.outcome(of: VoiceToolReply.saved(saved), isLookup: false).0, .done)

        let receipt = ActivityReceipt(note: saved, readAt: now)
        XCTAssertEqual(receipt.lines, ["“Gate code 4821”"])
        XCTAssertEqual(receipt.externalID, saved.id.uuidString)
        let listID = UUID()
        XCTAssertEqual(ActivityReceipt(list: "Shopping", listID: listID, lines: ["Added: milk"], readAt: now).lines, ["List: Shopping", "Added: milk"])
    }
}
