import DoddyCore
import Foundation
import XCTest

/// The Mac desktop widget's file (ADR-439): a count and a time only, read back after writing.
final class MacNoteCountTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("doddy-mac-count-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAWrittenCountIsReadBack() throws {
        let dir = try folder()
        XCTAssertNil(MacNoteCountFile.read(in: dir))
        XCTAssertTrue(MacNoteCountFile.write(MacNoteCount(count: 12, countedAt: t0), in: dir))
        XCTAssertEqual(MacNoteCountFile.read(in: dir), MacNoteCount(count: 12, countedAt: t0))
        // A newer count replaces it.
        XCTAssertTrue(MacNoteCountFile.write(MacNoteCount(count: 13, countedAt: t0.addingTimeInterval(60)), in: dir))
        XCTAssertEqual(MacNoteCountFile.read(in: dir)?.count, 13)
    }

    func testAFolderThatCannotBeWrittenIsNotReportedAsWritten() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("doddy-missing-\(UUID())/nested")
        XCTAssertFalse(MacNoteCountFile.write(MacNoteCount(count: 1, countedAt: t0), in: missing))
    }

    func testOnlyACountAndATimeAreStored() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: MacNoteCount(count: 3, countedAt: t0).encoded()) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["version", "count", "countedAt"])
    }

    func testOtherVersionsAndGarbageAreIgnored() throws {
        XCTAssertNil(MacNoteCount.decode(Data("not json".utf8)))
        XCTAssertNil(MacNoteCount.decode(Data(#"{"version":2,"count":3,"countedAt":0}"#.utf8)))
        XCTAssertNil(MacNoteCount.decode(Data(#"{"version":1,"count":-1,"countedAt":0}"#.utf8)))
        XCTAssertEqual(MacNoteCount.decode(Data(#"{"version":1,"count":3,"countedAt":0}"#.utf8))?.count, 3)
        XCTAssertEqual(MacNoteCount(count: -5, countedAt: t0).count, 0)
    }
}
