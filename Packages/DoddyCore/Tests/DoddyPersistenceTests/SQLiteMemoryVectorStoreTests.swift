import DoddyCore
@testable import DoddyPersistence
import Foundation
import XCTest

/// Counts letters a–z into 26 dimensions. Only here to drive real SQLite through meaning search;
/// it is not a language model.
private final class LetterEmbedder: TextEmbedder, @unchecked Sendable {
    let modelID = "test.letters.v1"
    private let lock = NSLock()
    private var _calls = 0
    var calls: Int { lock.withLock { _calls } }

    func embed(_ text: String) async throws -> [Float] {
        lock.withLock { _calls += 1 }
        var vector = [Float](repeating: 0, count: 26)
        for scalar in SearchFolding.fold(text).unicodeScalars where ("a"..."z").contains(scalar) {
            vector[Int(scalar.value - 97)] += 1
        }
        return vector
    }
}

/// ADR-210: the vector cache in the real SQLite file. Deletion must reach it.
final class SQLiteMemoryVectorStoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func vector(_ id: UUID, _ values: [Float] = [0.25, -1.5, .pi, 0, -0, 1e-30]) -> MeaningVector {
        MeaningVector(memoryID: id, textHash: "v1-hash", values: values)
    }

    func testVectorsRoundTripExactlyAndByModel() async throws {
        let database = try DoddyDatabase.inMemory()
        let memories = SQLiteMemoryRepository(database: database)
        let store = SQLiteMemoryVectorStore(database: database)
        let note = try await memories.save(NewMemory(text: "Parked on level 3", capturedAt: t0))

        try await store.store([vector(note.id)], modelID: "model-a")
        let read = try await store.vectors(modelID: "model-a")
        XCTAssertEqual(read, [vector(note.id)], "float32 bits survive the blob")
        let other = try await store.vectors(modelID: "model-b")
        XCTAssertEqual(other, [])

        try await store.store([vector(note.id, [9, 9])], modelID: "model-b")
        let replaced = try await store.vectors(modelID: "model-b")
        XCTAssertEqual(replaced.map(\.values), [[9, 9]], "one vector per note: a new model replaces it")
        let gone = try await store.vectors(modelID: "model-a")
        XCTAssertEqual(gone, [])
    }

    func testDeletingNotesDeletesTheirVectors() async throws {
        let database = try DoddyDatabase.inMemory()
        let memories = SQLiteMemoryRepository(database: database)
        let store = SQLiteMemoryVectorStore(database: database)
        let a = try await memories.save(NewMemory(text: "Gate code 1234", capturedAt: t0))
        let b = try await memories.save(NewMemory(text: "Spare keys in the tin", capturedAt: t0))
        try await store.store([vector(a.id), vector(b.id)], modelID: "m")

        try await memories.delete(id: a.id)
        let afterOne = try await store.vectors(modelID: "m")
        XCTAssertEqual(afterOne.map(\.memoryID), [b.id])

        try await memories.deleteAll()
        let afterAll = try await store.count()
        XCTAssertEqual(afterAll, 0)
    }

    func testCorrectingANoteDropsItsOldVector() async throws {
        let database = try DoddyDatabase.inMemory()
        let memories = SQLiteMemoryRepository(database: database)
        let store = SQLiteMemoryVectorStore(database: database)
        let note = try await memories.save(NewMemory(text: "Parked on level 3", capturedAt: t0))
        try await store.store([vector(note.id)], modelID: "m")
        _ = try await memories.update(id: note.id, currentText: "Parked on level 4")
        let count = try await store.count()
        XCTAssertEqual(count, 0, "no vector of words the user corrected away")
    }

    func testVectorForADeletedNoteIsNotStored() async throws {
        let database = try DoddyDatabase.inMemory()
        let store = SQLiteMemoryVectorStore(database: database)
        try await store.store([vector(UUID())], modelID: "m")
        let count = try await store.count()
        XCTAssertEqual(count, 0)
    }

    func testRemoveAllLeavesNotesAlone() async throws {
        let database = try DoddyDatabase.inMemory()
        let memories = SQLiteMemoryRepository(database: database)
        let store = SQLiteMemoryVectorStore(database: database)
        let note = try await memories.save(NewMemory(text: "Parked on level 3", capturedAt: t0))
        try await store.store([vector(note.id)], modelID: "m")
        try await store.removeAll()
        let count = try await store.count()
        let notes = try await memories.list(limit: nil)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(notes.map(\.id), [note.id])
    }

    func testTableRejectsMalformedRows() throws {
        let database = try DoddyDatabase.inMemory()
        XCTAssertThrowsError(try database.queue.write { db in
            try db.execute(sql: "INSERT INTO memories (id, raw_text, current_text, source, search_text) VALUES ('x', 't', 't', 'explicit_text', 't')")
            try db.execute(sql: "INSERT INTO memory_vectors VALUES ('x', 'm', 'h', 3, x'00000000')")
        }, "blob length must be dimension × 4")
    }

    /// Hybrid recall over the real store: vectors are made once, kept across reopening the file,
    /// and a search after reopening embeds only the question.
    func testHybridRecallCachesVectorsAcrossReopen() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("doddy-\(UUID()).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let texts = (0..<10).map { "note \(String(repeating: Character(UnicodeScalar(UInt8(97 + $0))), count: 6))" }

        var database = try DoddyDatabase(path: path)
        var memories = SQLiteMemoryRepository(database: database)
        for text in texts { _ = try await memories.save(NewMemory(text: text, capturedAt: t0)) }
        let first = LetterEmbedder()
        _ = try await HybridRecallService(
            repository: memories,
            meaning: MeaningIndex(embedder: first, store: SQLiteMemoryVectorStore(database: database)),
            isMeaningEnabled: { true }
        ).recall("zzz qqq", limit: 20)
        XCTAssertEqual(first.calls, texts.count + 1)

        database = try DoddyDatabase(path: path)
        memories = SQLiteMemoryRepository(database: database)
        let second = LetterEmbedder()
        _ = try await HybridRecallService(
            repository: memories,
            meaning: MeaningIndex(embedder: second, store: SQLiteMemoryVectorStore(database: database)),
            isMeaningEnabled: { true }
        ).recall("zzz qqq", limit: 20)
        XCTAssertEqual(second.calls, 1, "only the question after reopening")
    }
}
