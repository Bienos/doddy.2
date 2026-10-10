import DoddyCore
import Foundation
import XCTest

final class MemoryRestoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000.123)

    private func note(_ text: String, at offset: TimeInterval = 0, source: MemorySource = .explicitText) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: source, capturedAt: t0.addingTimeInterval(offset))
    }

    private func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    func testExportReadsBackExactlyIncludingCorrectionsAndUnknownDates() throws {
        let corrected = try note("Spare keys: blue tin").correcting(to: "Spare keys: red tin", at: t0.addingTimeInterval(60))
        let legacy = try MemoryRecord(id: UUID(), rawText: "Old note", source: .importedLegacyUnknown, capturedAt: nil)
        let voice = try note("Kod: 5678", at: 30, source: .explicitVoice)
        let data = try MemoryExport.json([corrected, legacy, voice], exportedAt: t0.addingTimeInterval(120))

        let read = try MemoryRestore.read(data)
        XCTAssertEqual(read.records, [corrected, legacy, voice])
        XCTAssertEqual(read.exportedAt, Date(timeIntervalSince1970: 1_760_000_120.123))
    }

    func testPlanAddsOnlyNewNotesAndNeverReplacesOnesOnThePhone() throws {
        let same = try note("Same everywhere", at: 10)
        let original = try note("Dentist Tuesday", at: 20)
        let correctedHere = try original.correcting(to: "Dentist Wednesday", at: t0.addingTimeInterval(500))
        let new = try note("New on the file", at: 30)
        let older = try note("Older new one", at: 5)
        let sample = try note("Sample", source: .sampleFixture)

        let plan = MemoryRestore.plan([same, original, older, new, sample], existing: [same, correctedHere], exportedAt: nil)
        XCTAssertEqual(plan.toAdd, [new, older], "newest first")
        XCTAssertEqual(plan.alreadyHere, 1)
        XCTAssertEqual(plan.keptOnPhone, 1)
        XCTAssertEqual(plan.skippedSamples, 1)
        XCTAssertTrue(MemoryRestore.plan([same], existing: [same], exportedAt: nil).isEmpty)
    }

    func testFilesThatAreNotUsableAreRefusedWhole() throws {
        let good = try JSONSerialization.jsonObject(with: try MemoryExport.json([try note("One"), try note("Two")], exportedAt: t0)) as! [String: Any]

        XCTAssertThrowsError(try MemoryRestore.read(Data("not json".utf8))) { XCTAssertEqual($0 as? MemoryRestoreError, .notADoddyExport) }
        XCTAssertThrowsError(try MemoryRestore.read(try json(["memories": []]))) { XCTAssertEqual($0 as? MemoryRestoreError, .notADoddyExport) }

        var newer = good
        newer["formatVersion"] = 2
        XCTAssertThrowsError(try MemoryRestore.read(try json(newer))) { XCTAssertEqual($0 as? MemoryRestoreError, .newerFormat(2)) }

        var damaged = good
        var notes = good["memories"] as! [[String: Any]]
        notes[1]["rawText"] = "   "
        damaged["memories"] = notes
        XCTAssertThrowsError(try MemoryRestore.read(try json(damaged))) { XCTAssertEqual($0 as? MemoryRestoreError, .unreadableNote(position: 2)) }

        var duplicated = good
        var twin = (good["memories"] as! [[String: Any]])[0]
        twin["currentText"] = "Changed"
        duplicated["memories"] = (good["memories"] as! [[String: Any]]) + [twin]
        XCTAssertThrowsError(try MemoryRestore.read(try json(duplicated))) { XCTAssertEqual($0 as? MemoryRestoreError, .conflictingDuplicate(position: 3)) }

        let identicalTwice = good.merging(["memories": (good["memories"] as! [[String: Any]]) + [(good["memories"] as! [[String: Any]])[0]]]) { $1 }
        XCTAssertEqual(try MemoryRestore.read(try json(identicalTwice)).records.count, 2, "an exact repeat is harmless")

        let big = Data(count: MemoryRestore.maxFileBytes + 1)
        XCTAssertThrowsError(try MemoryRestore.read(big)) {
            XCTAssertEqual($0 as? MemoryRestoreError, .tooLarge(bytes: MemoryRestore.maxFileBytes + 1, maximum: MemoryRestore.maxFileBytes))
        }
    }
}
