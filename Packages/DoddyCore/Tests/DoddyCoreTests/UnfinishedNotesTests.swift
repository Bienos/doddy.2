import XCTest
@testable import DoddyCore

/// OP-042, ADR-362: an unfinished note survives a restart as a draft, never as a note.
final class UnfinishedNotesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_630_000)

    private func note(_ text: String, id: UUID = UUID(), at date: Date? = nil) -> UnfinishedNote {
        UnfinishedNote(id: id, text: text, startedAt: date ?? t0)
    }

    func testOnlyWordsAreKeptAndEachScreenHasItsOwnDraft() {
        var book = UnfinishedNoteBook()
        let a = note("Gate code 48", id: UUID())
        book.keep(a)
        XCTAssertEqual(book.notes, [a])

        var typed = a
        typed.text = "Gate code 4821"
        typed.updatedAt = t0 + 5
        book.keep(typed)
        XCTAssertEqual(book.notes, [typed], "the same screen updates its draft, never adds a second")

        let b = note("Spare keys", at: t0 + 10)
        book.keep(b)
        XCTAssertEqual(book.notes.map(\.text), ["Spare keys", "Gate code 4821"], "newest first; the other screen's draft is untouched")

        var cleared = b
        cleared.text = "  \n"
        book.keep(cleared)
        XCTAssertEqual(book.notes, [typed], "a screen emptied of words has no draft")
    }

    func testSavedOrDiscardedIsRemoved() {
        var book = UnfinishedNoteBook()
        let a = note("Gate code 4821")
        book.keep(a)
        book.remove(id: a.id)
        XCTAssertTrue(book.notes.isEmpty)
    }

    func testAtMostFiveAndOldOnesGo() {
        var book = UnfinishedNoteBook()
        for i in 0..<7 { book.keep(note("note \(i)", at: t0 + Double(i))) }
        XCTAssertEqual(book.notes.count, UnfinishedNoteBook.maxNotes)
        XCTAssertEqual(book.newest?.text, "note 6")
        XCTAssertFalse(book.notes.contains { $0.text == "note 0" })

        let pruned = UnfinishedNoteBook(notes: [note("old", at: t0), note("new", at: t0 + 29 * 86_400)]).pruned(now: t0 + 30 * 86_400 + 1)
        XCTAssertEqual(pruned.notes.map(\.text), ["new"])
    }

    func testItSurvivesARestartExactlyAndAStrangeFileIsNotRead() throws {
        var book = UnfinishedNoteBook()
        var a = UnfinishedNote(text: "Kod do bramy 4821\nza śmietnikiem", category: .place, isSharedText: true,
                               hadPhoto: true, hadRecording: false, startedAt: t0)
        a.updatedAt = t0 + 3.123_456
        book.keep(a)
        let back = try XCTUnwrap(UnfinishedNoteBook.decoded(book.encoded()))
        XCTAssertEqual(back, book, "the words, type and flags come back as written")

        XCTAssertNil(UnfinishedNoteBook.decoded(Data("not json".utf8)))
        let future = Data(#"{"version":2,"notes":[]}"#.utf8)
        XCTAssertNil(UnfinishedNoteBook.decoded(future), "a newer format is kept aside, not misread")
    }

    func testWhichDraftAScreenOpensWith() {
        XCTAssertEqual(UnfinishedNoteResume.start(sharedText: nil, book: UnfinishedNoteBook()), .fresh)
        let older = note("Spare keys", at: t0)
        let newer = note("Gate code", at: t0 + 60)
        let book = UnfinishedNoteBook(notes: [older, newer])
        XCTAssertEqual(UnfinishedNoteResume.start(sharedText: nil, book: book), .resumed(newer))
        XCTAssertEqual(UnfinishedNoteResume.start(sharedText: "", book: book), .resumed(newer), "an empty shortcut is a new note")
        XCTAssertEqual(UnfinishedNoteResume.start(sharedText: "From Safari", book: book), .sharedWithOtherWaiting(newer),
                       "shared text is never mixed with or replaced by the draft")
        XCTAssertEqual(UnfinishedNoteResume.start(sharedText: nil, book: book, asked: older.id), .resumed(older))
    }

    func testThePrivacyScreenSaysDraftsStayOnThePhone() {
        let state = DataFlowState(
            rememberConversations: false, shareProfileWithVoice: false, tokenServerSet: false,
            connectionsOn: [], pauseAll: false, doddyServerSet: false, askDoddyOn: false, askDoddyUsesNotes: true)
        XCTAssertTrue(DataFlow.staysOnPhone(state).contains { $0.hasPrefix("Unfinished notes:") })
    }

    func testPreviewIsTheFirstLineCut() {
        XCTAssertEqual(note("\n  Gate code 4821  \nbehind the bins").preview(), "Gate code 4821")
        XCTAssertEqual(note(String(repeating: "a", count: 100)).preview(limit: 10), "aaaaaaaaa…")
    }
}
