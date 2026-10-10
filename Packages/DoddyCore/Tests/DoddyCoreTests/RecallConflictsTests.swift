import XCTest
@testable import DoddyCore

final class RecallConflictsTests: XCTestCase {
    private func candidate(_ text: String, _ terms: [String]) throws -> MemoryCandidate {
        MemoryCandidate(
            record: try MemoryRecord(id: UUID(), rawText: text, source: .explicitText, capturedAt: Date(timeIntervalSince1970: 0)),
            matchedTerms: terms)
    }

    func testSameWordsDifferentNumbersAreFlagged() throws {
        let old = try candidate("Gate code 4821", ["gate", "code"])
        let new = try candidate("New gate code is 7710", ["gate", "code"])
        let other = try candidate("Parcel locker code 55", ["code"])
        let flagged = RecallConflicts.flagged([old, new, other])
        XCTAssertEqual(flagged, [old.memoryID, new.memoryID])
    }

    func testSameNumbersOrNoNumbersAreNotFlagged() throws {
        let a = try candidate("Gate code 4821", ["gate", "code"])
        let b = try candidate("Remember gate code 4821 for Anna", ["gate", "code"])
        let c = try candidate("Keys are in the blue tin", ["keys"])
        let d = try candidate("Spare keys with the neighbour", ["keys"])
        XCTAssertTrue(RecallConflicts.flagged([a, b, c, d]).isEmpty)
    }

    func testLeadingZerosCountAsDifferentCodes() {
        XCTAssertEqual(RecallConflicts.numbers(in: "PIN 0042, then 42 at 18:30"), ["0042", "42", "18", "30"])
    }

    func testVoiceReplyMarksNotesThatMayDisagree() throws {
        let old = try candidate("Gate code 4821", ["gate", "code"])
        let new = try candidate("New gate code is 7710", ["gate", "code"])
        let reply = VoiceToolReply.search(.matches([new, old]))
        XCTAssertTrue(reply.contains("\"New gate code is 7710\"") && reply.contains("[may disagree]"))
        XCTAssertTrue(reply.contains("Do not pick one."))
        XCTAssertFalse(VoiceToolReply.search(.matches([old])).contains("may disagree"))
    }
}
