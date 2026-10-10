import DoddyCore
import DoddyPersistence
import Foundation
import XCTest

/// Photo notes (ADR-218): the read text, the size limit, and the photo link on real SQLite.
final class PhotoNotesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testReadTextIsJoinedTrimmedAndCutAtAWholeLine() {
        let result = RecognizedText.join(["  PARKING  ", "", "Level -2, row C 14", " "])
        XCTAssertEqual(result.text, "PARKING\nLevel -2, row C 14")
        XCTAssertFalse(result.wasCut)
        let long = Array(repeating: String(repeating: "x", count: 99), count: 40)
        let cut = RecognizedText.join(long)
        XCTAssertTrue(cut.wasCut)
        XCTAssertLessThanOrEqual(cut.text.count, PhotoLimits.maxRecognizedCharacters)
        XCTAssertTrue(cut.text.split(separator: "\n").allSatisfy { $0.count == 99 }, "never cuts inside a line")
    }

    func testAddingReadTextKeepsTheUsersWordsFirst() {
        XCTAssertEqual(RecognizedText.adding("Wi-Fi: Doddy5G\nPassword: tin-kettle-42", to: ""), "Wi-Fi: Doddy5G\nPassword: tin-kettle-42")
        XCTAssertEqual(RecognizedText.adding("Level -2, C 14", to: "Where I parked"), "Where I parked\n\nLevel -2, C 14")
        XCTAssertEqual(RecognizedText.adding("Level -2, C 14", to: "Where I parked\n\nLevel -2, C 14"), "Where I parked\n\nLevel -2, C 14")
        XCTAssertEqual(RecognizedText.adding("  ", to: "keep"), "keep")
    }

    func testScaledSize() {
        XCTAssertTrue(RecognizedText.scaledSize(width: 4032, height: 3024) == (2048, 1536))
        XCTAssertTrue(RecognizedText.scaledSize(width: 1000, height: 800) == (1000, 800))
    }

    func testFileNamesAreMadeByDoddyOnly() {
        let id = UUID()
        XCTAssertTrue(MemoryPhoto.isValidFileName(MemoryPhoto.fileName(for: id)))
        XCTAssertFalse(MemoryPhoto.isValidFileName("../secret.jpg"))
        XCTAssertFalse(MemoryPhoto.isValidFileName("\(id.uuidString).png"))
    }

    func testAttachReplaceDetachAndCascade() async throws {
        let database = try DoddyDatabase.inMemory()
        let memories = SQLiteMemoryRepository(database: database)
        let photos = SQLitePhotoRepository(database: database)
        let note = try await memories.save(NewMemory(text: "Parking: level -2, C 14", capturedAt: t0))
        let photo = MemoryPhoto(memoryID: note.id, fileName: MemoryPhoto.fileName(for: note.id), width: 2048, height: 1536, addedAt: t0)
        let stored = try await photos.attach(photo)
        XCTAssertEqual(stored.fileName, photo.fileName)
        let replaced = try await photos.attach(MemoryPhoto(memoryID: note.id, fileName: photo.fileName, width: 1000, height: 800, addedAt: t0))
        XCTAssertEqual(replaced.width, 1000)
        let all = try await photos.allPhotos()
        XCTAssertEqual(all.count, 1)

        do {
            _ = try await photos.attach(MemoryPhoto(memoryID: UUID(), fileName: MemoryPhoto.fileName(for: UUID()), width: 10, height: 10, addedAt: t0))
            XCTFail("no note, no photo")
        } catch PhotoError.noteNotFound {}
        do {
            _ = try await photos.attach(MemoryPhoto(memoryID: note.id, fileName: "x.jpg", width: 10, height: 10, addedAt: t0))
            XCTFail("bad file name")
        } catch PhotoError.badFileName {}
        do {
            _ = try await photos.attach(MemoryPhoto(memoryID: note.id, fileName: photo.fileName, width: 5000, height: 10, addedAt: t0))
            XCTFail("too big")
        } catch PhotoError.badSize {}

        // Deleting the note takes the link with it; the app then deletes the file.
        try await memories.delete(id: note.id)
        let gone = try await photos.photo(forMemory: note.id)
        XCTAssertNil(gone)

        let other = try await memories.save(NewMemory(text: "Receipt", capturedAt: t0))
        _ = try await photos.attach(MemoryPhoto(memoryID: other.id, fileName: MemoryPhoto.fileName(for: other.id), width: 10, height: 10, addedAt: t0))
        let removed = try await photos.detach(memoryID: other.id)
        XCTAssertEqual(removed?.memoryID, other.id)
        let none = try await photos.detach(memoryID: other.id)
        XCTAssertNil(none)
    }
}
