import DoddyCore
import XCTest
@testable import Doddy

final class MemoryStoreTests: XCTestCase {
    func testMalformedPersistentFixtureDoesNotFallBackToPersonalStore() {
        let environment = AppEnvironment.live(arguments: ["-memoryTestID", "not-a-uuid"])
        XCTAssertNotNil(environment.storageProblem)
        XCTAssertTrue(environment.memoryRepository is UnavailableMemoryRepository)
    }

    @MainActor
    func testVoiceSourceIsStoredAndOriginalSurvivesCorrection() async throws {
        let environment = AppEnvironment.live(arguments: ["-inMemoryStore"])
        XCTAssertNil(environment.storageProblem)
        let store = MemoryStore(environment: environment)
        let original = "  Marta recommended Żółć for the project.\n"
        let record = try await store.save(text: original, category: .recommendation, source: .explicitVoice)
        XCTAssertEqual(record.source, .explicitVoice)
        XCTAssertEqual(record.rawText, original)
        let corrected = try await store.correct(id: record.id, text: "Marta recommended Łódź.")
        XCTAssertEqual(corrected.rawText, original)
        XCTAssertEqual(corrected.source, .explicitVoice)
        XCTAssertEqual(corrected.capturedAt, record.capturedAt)
        XCTAssertTrue(corrected.userEdited)
        guard case .matches(let candidates) = try await store.recall("Lodz") else {
            return XCTFail("Corrected voice note must be searchable in the same repository.")
        }
        XCTAssertEqual(candidates.map(\.memoryID), [record.id])
        XCTAssertEqual(candidates.first?.record.source, .explicitVoice)
    }

    @MainActor
    func testTypedCaptureKeepsTextSourceAndDeletionRemovesRecall() async throws {
        let store = MemoryStore(environment: .live(arguments: ["-inMemoryStore"]))
        let record = try await store.save(text: "Synthetic amber notebook", category: .item)
        XCTAssertEqual(record.source, .explicitText)
        try await store.delete(id: record.id)
        XCTAssertNil(store.record(id: record.id))
        guard case .noMatch = try await store.recall("amber") else {
            return XCTFail("Deleted note must not remain in recall.")
        }
    }

    @MainActor
    func testUnavailableStorageNeverAddsAnAcknowledgedNote() async {
        let store = MemoryStore(environment: .unavailable)
        do {
            _ = try await store.save(text: "Unsaved synthetic draft", category: .other)
            XCTFail("Unavailable storage must throw, not acknowledge a save.")
        } catch {
            XCTAssertTrue(store.memories.isEmpty)
        }
    }

    /// Photo notes (ADR-218): the file is written before the link, kept through Undo, and
    /// deleted with the note or by Remove photo. In-memory launches use their own folder.
    @MainActor
    func testPhotoFollowsItsNoteThroughDeleteUndoAndRemove() async throws {
        let environment = AppEnvironment.live(arguments: ["-inMemoryStore"])
        let store = MemoryStore(environment: environment)
        let note = try await store.save(text: "Parking: level -2, C 14", category: .place)
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9])
        let photo = try await store.attachPhoto(jpeg: jpeg, width: 1200, height: 900, to: note.id)
        XCTAssertEqual(environment.photoFiles.data(photo.fileName), jpeg)
        let stored = await store.photoData(photo)
        XCTAssertEqual(stored, jpeg)
        do {
            _ = try await store.attachPhoto(jpeg: jpeg, width: 10, height: 10, to: note.id)
            XCTFail("a second photo is refused, so the first file is never overwritten")
        } catch PhotoError.alreadyAttached {}

        try await store.delete(id: note.id)
        XCTAssertNil(store.photo(for: note.id))
        XCTAssertNotNil(environment.photoFiles.data(photo.fileName), "kept while Undo is offered")
        try await store.undoDelete()
        XCTAssertEqual(store.photo(for: note.id)?.fileName, photo.fileName)

        try await store.removePhoto(from: note.id)
        XCTAssertNil(store.photo(for: note.id))
        XCTAssertNil(environment.photoFiles.data(photo.fileName))
        XCTAssertNotNil(store.record(id: note.id), "the note's words stay")
    }
}
