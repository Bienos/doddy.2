import DoddyCore
import DoddyPersistence
import Foundation
import XCTest

/// Voice memos (ADR-230): the written-out text, the limits, and the recording link on real SQLite.
final class VoiceMemoTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testFileNamesAndDurations() {
        let id = UUID()
        XCTAssertTrue(MemoryAudio.isValidFileName(MemoryAudio.fileName(for: id)))
        XCTAssertFalse(MemoryAudio.isValidFileName("../secret.m4a"))
        XCTAssertFalse(MemoryAudio.isValidFileName(MemoryPhoto.fileName(for: id)))
        XCTAssertFalse(MemoryAudio.isValidDuration(200), "a mis-tap isn't kept")
        XCTAssertTrue(MemoryAudio.isValidDuration(300_000))
        XCTAssertFalse(MemoryAudio.isValidDuration(301_000))
        XCTAssertEqual(VoiceMemoText.duration(milliseconds: 42_900), "0:42")
        XCTAssertEqual(VoiceMemoText.duration(milliseconds: 245_000), "4:05")
    }

    func testTranscriptIsTrimmedAndCutAtAWholeWord() {
        XCTAssertEqual(VoiceMemoText.transcript("  Buy milk.\n"), RecognizedText.Result(text: "Buy milk.", wasCut: false))
        let long = String(repeating: "word ", count: 700)
        let cut = VoiceMemoText.transcript(long)
        XCTAssertTrue(cut.wasCut)
        XCTAssertLessThanOrEqual(cut.text.count, VoiceMemoLimits.maxTranscriptCharacters)
        XCTAssertTrue(cut.text.hasSuffix("word"), "never half a word")
    }

    func testWritingOutAgainSwapsOnlyTheUntouchedText() {
        let first = VoiceMemoText.replacing(nil, with: "kupić mleko", in: "Shopping")
        XCTAssertEqual(first, "Shopping\n\nkupić mleko")
        XCTAssertEqual(VoiceMemoText.replacing("kupić mleko", with: "buy milk", in: first), "Shopping\n\nbuy milk")
        XCTAssertEqual(VoiceMemoText.replacing("kupić mleko", with: "buy milk", in: "Shopping, edited"), "Shopping, edited\n\nbuy milk",
                       "the user's edit is kept; the new text goes after it")
    }

    func testAttachDetachAndCascade() async throws {
        let database = try DoddyDatabase.inMemory()
        let memories = SQLiteMemoryRepository(database: database)
        let audio = SQLiteAudioRepository(database: database)
        let note = try await memories.save(NewMemory(text: "Idea for the garden", capturedAt: t0))
        let memo = MemoryAudio(memoryID: note.id, fileName: MemoryAudio.fileName(for: note.id), durationMilliseconds: 12_345, addedAt: t0)
        let stored = try await audio.attach(memo)
        XCTAssertEqual(stored, memo)
        let all = try await audio.allAudio()
        XCTAssertEqual(all, [memo])

        do {
            _ = try await audio.attach(MemoryAudio(memoryID: UUID(), fileName: MemoryAudio.fileName(for: UUID()), durationMilliseconds: 1000, addedAt: t0))
            XCTFail("no note, no recording")
        } catch AudioError.noteNotFound {}
        do {
            _ = try await audio.attach(MemoryAudio(memoryID: note.id, fileName: "x.m4a", durationMilliseconds: 1000, addedAt: t0))
            XCTFail("bad file name")
        } catch AudioError.badFileName {}
        do {
            _ = try await audio.attach(MemoryAudio(memoryID: note.id, fileName: memo.fileName, durationMilliseconds: 400_000, addedAt: t0))
            XCTFail("too long")
        } catch AudioError.badDuration {}

        // Deleting the note takes the link with it; the app then deletes the file.
        try await memories.delete(id: note.id)
        let gone = try await audio.audio(forMemory: note.id)
        XCTAssertNil(gone)

        let other = try await memories.save(NewMemory(text: "Call the plumber", capturedAt: t0))
        _ = try await audio.attach(MemoryAudio(memoryID: other.id, fileName: MemoryAudio.fileName(for: other.id), durationMilliseconds: 900, addedAt: t0))
        let removed = try await audio.detach(memoryID: other.id)
        XCTAssertEqual(removed?.memoryID, other.id)
        let none = try await audio.detach(memoryID: other.id)
        XCTAssertNil(none)
    }
}
