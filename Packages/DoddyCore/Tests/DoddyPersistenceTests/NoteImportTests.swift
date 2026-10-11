import DoddyCore
import DoddyPersistence
import Foundation
import XCTest

/// Importing notes from Google Keep and text files (ADR-231).
final class NoteImportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func keep(_ json: String, _ name: String = "Note.json") -> NoteImport.Candidate {
        NoteImport.keep(Data(json.utf8), fileName: name)
    }

    func testKeepNoteKeepsTheWordsAndSaysWhatIsLeftOut() {
        let note = keep(#"""
            {"title":"Gate code","textContent":"4821 then #\nAsk for Ania","isTrashed":false,
             "createdTimestampUsec":1600000000000000,"labels":[{"name":"home"}],
             "attachments":[{"filePath":"a.jpg","mimetype":"image/jpeg"}],"color":"DEFAULT"}
            """#)
        XCTAssertEqual(note.content, .note("Gate code\n\n4821 then #\nAsk for Ania"))
        XCTAssertEqual(note.createdAt, Date(timeIntervalSince1970: 1_600_000_000))
        XCTAssertEqual(note.leftOut, ["1 attachment", "labels"])
        XCTAssertTrue(note.startsTicked)
        XCTAssertEqual(note.origin, .googleKeep)
    }

    func testKeepChecklistBecomesAListWithTickedItems() {
        let list = keep(#"{"title":"Zakupy","listContent":[{"text":"mleko","isChecked":false},{"text":" jajka ","isChecked":true},{"text":"","isChecked":false}]}"#)
        XCTAssertEqual(list.content, .list(.init(name: "Zakupy", open: ["mleko"], ticked: ["jajka"])))
        let untitled = keep(#"{"title":"","listContent":[{"text":"socks","isChecked":false},{"text":"charger","isChecked":true}]}"#)
        XCTAssertEqual(untitled.content, .note("socks\n✓ charger"), "no made-up list name")
    }

    /// Review B5: an item of emoji counts as the database counts it (code points), so a list the
    /// import accepts can always be saved.
    func testChecklistItemLengthCountsCodePoints() {
        let emoji = String(repeating: "👨‍👩‍👧", count: 50)
        XCTAssertEqual(emoji.count, 50)
        let list = keep(#"{"title":"Zakupy","listContent":[{"text":"\#(emoji)","isChecked":false}]}"#)
        XCTAssertEqual(list.problem, .listItemTooLong)
        let fits = keep(#"{"title":"Zakupy","listContent":[{"text":"\#(String(repeating: "👨‍👩‍👧", count: 40))","isChecked":false}]}"#)
        XCTAssertNil(fits.problem)
    }

    /// Review B6: too many items and one over-long item are told apart, so the user hears which.
    func testChecklistTooManyItemsAndTooLongItemAreDifferentProblems() {
        let items = (0...ListLimits.itemsPerList).map { #"{"text":"item \#($0)","isChecked":false}"# }.joined(separator: ",")
        let many = keep(#"{"title":"Zakupy","listContent":[\#(items)]}"#)
        XCTAssertEqual(many.problem, .tooManyItems)
        let longItem = String(repeating: "a", count: ListLimits.itemLength + 1)
        let long = keep(#"{"title":"Zakupy","listContent":[{"text":"mleko","isChecked":false},{"text":"\#(longItem)","isChecked":true}]}"#)
        XCTAssertEqual(long.problem, .listItemTooLong)
        XCTAssertFalse(long.canImport)
    }

    func testTrashOtherJSONAndBadFilesAreNotImported() {
        XCTAssertEqual(keep(#"{"title":"Old","textContent":"x","isTrashed":true}"#).problem, .inTrash)
        XCTAssertEqual(keep(#"{"name":"not keep"}"#).problem, .notAKeepNote)
        XCTAssertEqual(keep("not json").problem, .notAKeepNote)
        let big = NoteImport.read(fileName: "big.txt", data: Data(count: NoteImport.maxFileBytes + 1))
        XCTAssertEqual(big.first?.problem, .fileTooLarge)
        let latin = NoteImport.text(Data([0x66, 0xFF, 0xFE]), fileName: "x.txt", splitParagraphs: false)
        XCTAssertEqual(latin.first?.problem, .notText)
        let long = NoteImport.text(Data(String(repeating: "a", count: MemoryLimits.maxTextLength + 1).utf8), fileName: "l.md", splitParagraphs: false)
        XCTAssertEqual(long.first?.problem, .tooLong(length: MemoryLimits.maxTextLength + 1), "never cut down")
        XCTAssertFalse(long.first?.canImport ?? true)
    }

    func testTextFilesAreOneNoteOrOnePerParagraph() {
        let data = Data("\u{FEFF}Wifi: dom-5G\r\nPassword on the router\r\n\r\n\r\nBins go out on Tuesday\n".utf8)
        let whole = NoteImport.text(data, fileName: "notes.txt", splitParagraphs: false)
        XCTAssertEqual(whole.map(\.content), [.note("Wifi: dom-5G\nPassword on the router\n\n\nBins go out on Tuesday")])
        XCTAssertNil(whole.first?.createdAt, "a text file doesn't say when it was written")
        let split = NoteImport.text(data, fileName: "notes.txt", splitParagraphs: true)
        XCTAssertEqual(split.map(\.content), [.note("Wifi: dom-5G\nPassword on the router"), .note("Bins go out on Tuesday")])
        XCTAssertEqual(NoteImport.text(Data("  \n\n ".utf8), fileName: "e.txt", splitParagraphs: false).first?.problem, .empty)
        XCTAssertTrue(NoteImport.isTextFile("a.MD"))
        XCTAssertFalse(NoteImport.isTextFile("a.pdf"))
    }

    func testDuplicatesAndTakenListNames() throws {
        let saved = try MemoryRecord(id: UUID(), rawText: "Gate code 4821", source: .explicitText, capturedAt: now)
        let candidates = [
            NoteImport.Candidate(fileName: "a", origin: .textFile, content: .note("gate code: 4821"), createdAt: nil, problem: nil),
            NoteImport.Candidate(fileName: "b", origin: .textFile, content: .note("Bins on Tuesday"), createdAt: nil, problem: nil),
            NoteImport.Candidate(fileName: "c", origin: .textFile, content: .note("bins on tuesday"), createdAt: nil, problem: nil),
            NoteImport.Candidate(fileName: "d", origin: .googleKeep, content: .list(.init(name: "Shopping", open: ["milk"], ticked: [])), createdAt: nil, problem: nil),
        ]
        let checked = NoteImport.checked(candidates, notes: [saved], listNames: ["shopping"])
        XCTAssertEqual(checked.map(\.problem), [.alreadySaved, nil, .alreadySaved, .listNameTaken("Shopping")])
        XCTAssertTrue(checked[0].canImport && !checked[0].startsTicked, "the user can still tick a copy")
        XCTAssertFalse(checked[3].canImport)
    }

    func testImportedNotesAreMarkedAndRestoredExactly() async throws {
        let future = NoteImport.Candidate(fileName: "f", origin: .googleKeep, content: .note("Later"), createdAt: now.addingTimeInterval(86_400), problem: nil)
        XCTAssertNil(NoteImport.record(for: future, now: now)?.capturedAt, "a date in the future isn't believed")
        let dated = NoteImport.Candidate(fileName: "g", origin: .googleKeep, content: .note("Gate code\n\n4821"), createdAt: Date(timeIntervalSince1970: 1_600_000_000), problem: nil)
        let record = try XCTUnwrap(NoteImport.record(for: dated, now: now))
        XCTAssertEqual(record.source, .importedFile)
        XCTAssertEqual(record.rawText, "Gate code\n\n4821")

        let database = try DoddyDatabase.inMemory()
        let memories = SQLiteMemoryRepository(database: database)
        let undated = try XCTUnwrap(NoteImport.record(for: future, now: now))
        let added = try await memories.restore([record, undated])
        XCTAssertEqual(added.count, 2, "read back, dated or not")
        XCTAssertEqual(NoteImport.summary(notes: 12, lists: 1), "12 notes and 1 list")
        XCTAssertEqual(NoteImport.summary(notes: 0, lists: 2), "2 lists")
    }
}
