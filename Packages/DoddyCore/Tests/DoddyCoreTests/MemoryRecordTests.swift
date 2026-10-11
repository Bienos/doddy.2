import XCTest
@testable import DoddyCore

final class MemoryRecordTests: XCTestCase {
    private let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_760_003_600)

    // MARK: validation (A-03 domain rules)

    func testRejectsEmptyAndWhitespaceOnly() {
        for text in ["", " ", "\n\t  \n"] {
            XCTAssertThrowsError(try MemoryTextValidator.validate(text), "\(text.debugDescription)") {
                XCTAssertEqual($0 as? MemoryValidationError, .empty)
            }
        }
    }

    func testBoundaryLength() throws {
        try MemoryTextValidator.validate(String(repeating: "a", count: 5_000))
        XCTAssertThrowsError(try MemoryTextValidator.validate(String(repeating: "a", count: 5_001))) {
            XCTAssertEqual($0 as? MemoryValidationError, .tooLong(length: 5_001, maximum: 5_000))
        }
    }

    func testLengthCountsUnicodeScalarsLikeTheJSONSchema() throws {
        // Family emoji = 7 scalars, 1 grapheme: 715 of them is 5_005 scalars → rejected.
        let family = "👨‍👩‍👧‍👦"
        XCTAssertEqual(family.unicodeScalars.count, 7)
        XCTAssertThrowsError(try MemoryTextValidator.validate(String(repeating: family, count: 715)))
        try MemoryTextValidator.validate(String(repeating: family, count: 714)) // 4_998
    }

    func testAcceptsPolishAndEmojiExactly() throws {
        let text = "  Zażółć gęślą jaźń 🙂 — Marta poleciła „Lalkę”.\n"
        let new = try NewMemory(text: text, capturedAt: t0)
        XCTAssertEqual(new.text, text, "accepted text must not be trimmed or normalised")
    }

    func testNewMemoryRejectsNonCapturableSources() {
        for source in [MemorySource.importedLegacyUnknown, .sampleFixture] {
            XCTAssertThrowsError(try NewMemory(text: "x", source: source, capturedAt: t0)) {
                XCTAssertEqual($0 as? MemoryValidationError, .sourceNotCapturable(source))
            }
        }
        for source in [MemorySource.explicitText, .explicitVoice, .sharedContent] {
            XCTAssertNoThrow(try NewMemory(text: "x", source: source, capturedAt: t0))
        }
    }

    // MARK: provenance (A-02, A-06 domain rules)

    func testCaptureKeepsExactRawTextAndProvenance() throws {
        let new = try NewMemory(text: "The parcel locker code is 1234", category: .fact, capturedAt: t0)
        let record = try MemoryRecord(id: id, capturing: new)
        XCTAssertEqual(record.rawText, "The parcel locker code is 1234")
        XCTAssertEqual(record.currentText, record.rawText)
        XCTAssertEqual(record.source, .explicitText)
        XCTAssertEqual(record.capturedAt, t0)
        XCTAssertNil(record.updatedAt)
        XCTAssertFalse(record.userEdited)
    }

    func testCorrectionKeepsRawTextAndOriginalCaptureDate() throws {
        let original = try MemoryRecord(id: id, capturing: NewMemory(text: "Locker code 1234", capturedAt: t0))
        let corrected = try original.correcting(to: "Locker code 1243", at: t1)
        XCTAssertEqual(corrected.rawText, "Locker code 1234")
        XCTAssertEqual(corrected.currentText, "Locker code 1243")
        XCTAssertEqual(corrected.capturedAt, t0)
        XCTAssertEqual(corrected.updatedAt, t1)
        XCTAssertTrue(corrected.userEdited)
        XCTAssertEqual(corrected.id, original.id)
        XCTAssertEqual(original.currentText, "Locker code 1234", "value type: original is unchanged")
    }

    func testInvalidCorrectionIsRejected() throws {
        let original = try MemoryRecord(id: id, capturing: NewMemory(text: "x", capturedAt: t0))
        XCTAssertThrowsError(try original.correcting(to: "   ", at: t1))
        XCTAssertThrowsError(try original.correcting(to: String(repeating: "a", count: 5_001), at: t1))
    }

    func testUnknownCaptureDateOnlyForImportedLegacy() throws {
        let imported = try MemoryRecord(id: id, rawText: "old", source: .importedLegacyUnknown, capturedAt: nil)
        XCTAssertNil(imported.capturedAt, "import time must never stand in for the capture date")
        XCTAssertThrowsError(try MemoryRecord(id: id, rawText: "x", source: .explicitText, capturedAt: nil)) {
            XCTAssertEqual($0 as? MemoryValidationError, .missingCaptureDate(.explicitText))
        }
        XCTAssertThrowsError(try MemoryRecord(id: id, rawText: "x", source: .importedLegacyUnknown, capturedAt: t0)) {
            XCTAssertEqual($0 as? MemoryValidationError, .unexpectedCaptureDate(.importedLegacyUnknown))
        }
    }

    func testSampleFixturesAreNotEligibleForPersonalRecall() {
        XCTAssertFalse(MemorySource.sampleFixture.isEligibleForPersonalRecall)
        for source in MemorySource.allCases where source != .sampleFixture {
            XCTAssertTrue(source.isEligibleForPersonalRecall)
        }
    }

    // MARK: serialisation contract

    func testJSONRoundTripIsLossless() throws {
        let edited = try MemoryRecord(id: id, capturing: NewMemory(text: "Zażółć 🙂", category: .place, capturedAt: t0))
            .correcting(to: "Zażółć gęślą", at: t1)
        let data = try JSONEncoder().encode(edited)
        XCTAssertEqual(try JSONDecoder().decode(MemoryRecord.self, from: data), edited)

        let imported = try MemoryRecord(id: id, rawText: "old", source: .importedLegacyUnknown, capturedAt: nil)
        XCTAssertEqual(try JSONDecoder().decode(MemoryRecord.self, from: JSONEncoder().encode(imported)), imported)
    }

    func testDecodingRejectsInvalidRecords() throws {
        func decode(_ json: String) throws -> MemoryRecord {
            try JSONDecoder().decode(MemoryRecord.self, from: Data(json.utf8))
        }
        let base = #""id":"11111111-1111-1111-1111-111111111111","source":"explicit_text","category":"other","userEdited":false"#
        XCTAssertNoThrow(try decode(#"{"schemaVersion":1,\#(base),"rawText":"a","currentText":"a","capturedAtMs":1}"#))
        XCTAssertThrowsError(try decode(#"{"schemaVersion":2,\#(base),"rawText":"a","currentText":"a","capturedAtMs":1}"#))
        XCTAssertThrowsError(try decode(#"{"schemaVersion":1,\#(base),"rawText":"","currentText":"a","capturedAtMs":1}"#))
        XCTAssertThrowsError(try decode(#"{"schemaVersion":1,\#(base),"rawText":"a","currentText":"a","capturedAtMs":null}"#))
    }

    /// The Swift model and `schemas/memory.schema.json` must not drift apart.
    func testEncodingMatchesProposedJSONSchema() throws {
        let schemaURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()   // DoddyCoreTests, Tests
            .deletingLastPathComponent().deletingLastPathComponent()   // DoddyCore, Packages
            .deletingLastPathComponent()                               // repo root
            .appendingPathComponent("schemas/memory.schema.json")
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL)) as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let required = Set(try XCTUnwrap(schema["required"] as? [String]))

        let record = try MemoryRecord(id: id, capturing: NewMemory(text: "x", capturedAt: t0))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])

        XCTAssertTrue(required.isSubset(of: Set(json.keys)), "missing required keys")
        // `deletedAtMs` is intentionally not modelled (deletion is a purge); see DECISIONS.md.
        XCTAssertEqual(Set(json.keys).subtracting(properties.keys), [], "keys not in schema")
        XCTAssertEqual(Set(properties.keys).subtracting(json.keys), ["deletedAtMs"])

        func enumValues(_ name: String) throws -> Set<String> {
            let property = try XCTUnwrap(properties[name] as? [String: Any])
            return Set(try XCTUnwrap(property["enum"] as? [String]))
        }
        XCTAssertEqual(try enumValues("source"), Set(MemorySource.allCases.map(\.rawValue)))
        XCTAssertEqual(try enumValues("category"), Set(MemoryCategory.allCases.map(\.rawValue)))
        let raw = try XCTUnwrap(properties["rawText"] as? [String: Any])
        XCTAssertEqual(raw["maxLength"] as? Int, MemoryLimits.maxTextLength)
    }

    /// Review B9: one millisecond conversion. Files round, the database rounds down, and a whole
    /// millisecond survives both unchanged.
    func testEpochMillisecondsRoundingAndRoundTrip() {
        let t = Date(timeIntervalSince1970: 1_760_000_000.1236)
        XCTAssertEqual(EpochMilliseconds.rounded(t), 1_760_000_000_124)
        XCTAssertEqual(EpochMilliseconds.truncated(t), 1_760_000_000_123)
        for ms in stride(from: Int64(1_760_000_000_000), to: 1_760_000_020_000, by: 7) {
            let date = EpochMilliseconds.date(ms)
            XCTAssertEqual(EpochMilliseconds.rounded(date), ms)
            XCTAssertEqual(EpochMilliseconds.truncated(date), ms)
        }
    }
}
