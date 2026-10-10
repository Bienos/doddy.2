import DoddyCore
import Foundation
import XCTest

final class DuplicateNoteTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private func note(_ text: String, at offset: TimeInterval = 0, source: MemorySource = .explicitText) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: source, capturedAt: t0.addingTimeInterval(offset))
    }

    func testSameWordsMatchIgnoringCaseAccentsPunctuationAndSpacing() throws {
        let saved = try note("Kod do bramy: 4821.")
        XCTAssertEqual(DuplicateNote.existing(for: "kod do  BRAMY 4821", in: [saved]), saved)
        XCTAssertEqual(DuplicateNote.existing(for: "Kód do bramy — 4821!", in: [saved]), saved)
    }

    func testDifferentWordsOrNumbersDoNotMatch() throws {
        let saved = try note("Gate code 4821")
        XCTAssertNil(DuplicateNote.existing(for: "Gate code 4822", in: [saved]))
        XCTAssertNil(DuplicateNote.existing(for: "Gate code", in: [saved]))
        XCTAssertNil(DuplicateNote.existing(for: "code gate 4821", in: [saved]), "order matters")
        XCTAssertNil(DuplicateNote.existing(for: "  …  ", in: [saved]), "no words, no match")
    }

    func testBothCurrentAndOriginalTextCountAndTheNewestWins() throws {
        let corrected = try note("Keys in the blue tin", at: 0).correcting(to: "Keys in the red tin", at: t0.addingTimeInterval(5))
        XCTAssertEqual(DuplicateNote.existing(for: "keys in the blue tin", in: [corrected]), corrected)
        XCTAssertEqual(DuplicateNote.existing(for: "keys in the red tin", in: [corrected]), corrected)

        let older = try note("Call Ania", at: 10), newer = try note("call ania", at: 20)
        XCTAssertEqual(DuplicateNote.existing(for: "Call Ania", in: [older, newer]), newer)
        XCTAssertNil(DuplicateNote.existing(for: "Sample", in: [try note("Sample", source: .sampleFixture)]))
    }
}
