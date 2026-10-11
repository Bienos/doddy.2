@testable import DoddyCore
import XCTest

/// ADR-251: when no found note covers the whole question, the answer says which words no note
/// has instead of presenting the notes as the answer.
final class RecallCoverageTests: XCTestCase {
    private func candidate(_ text: String, _ matched: [String]) throws -> MemoryCandidate {
        MemoryCandidate(
            record: try MemoryRecord(id: UUID(), rawText: text, source: .explicitText, capturedAt: Date(timeIntervalSince1970: 0)),
            matchedTerms: matched)
    }

    func testAWordNoNoteHasMakesTheMatchPartialAndIsNamed() throws {
        let wifi = try candidate("Wifi password at mum's: Sunflower", ["password"])
        let coverage = RecallCoverage(question: "netflix password", candidates: [wifi])
        XCTAssertTrue(coverage.isPartial)
        XCTAssertEqual(coverage.missing.map(\.label), ["netflix"])
        let copy = RecallCopy.partial(coverage)
        XCTAssertEqual(copy.headline, "No saved note mentions “netflix”.")
        XCTAssertEqual(copy.detail, "The notes below match only “password”. Check them before relying on one.")
    }

    func testANoteWithEveryWordIsAWholeMatch() throws {
        let keys = try candidate("Spare keys in the blue tin", ["spare", "keys"])
        let other = try candidate("Car keys on the hook", ["keys"])
        let coverage = RecallCoverage(question: "Where are the spare keys?", candidates: [keys, other])
        XCTAssertFalse(coverage.isPartial)
        XCTAssertEqual(coverage.completeMatches, [keys.memoryID])
        XCTAssertEqual(coverage.missing, [])
    }

    func testTranslationsAndNumberWordsAreOneIdea() throws {
        // The voice agent searches in both languages at once; a Polish note covers both words.
        let locker = try candidate("Kod do paczkomatu: 7731", ["kod", "paczkomat"])
        let coverage = RecallCoverage(question: "kod code paczkomat parcel", candidates: [locker])
        XCTAssertEqual(coverage.ideas.map(\.label), ["kod / code", "paczkomat / parcel"])
        XCTAssertFalse(coverage.isPartial)
        let lock = try candidate("bike lock five six one nine", ["five"])
        XCTAssertFalse(RecallCoverage(question: "five 5", candidates: [lock]).isPartial)
    }

    func testEveryWordFoundButNeverTogether() throws {
        let a = try candidate("Jake's birthday is 12 May", ["jake"])
        let b = try candidate("The plumber's number is 601", ["number"])
        let coverage = RecallCoverage(question: "Jake's number", candidates: [a, b])
        XCTAssertTrue(coverage.isPartial)
        XCTAssertEqual(coverage.missing, [])
        XCTAssertEqual(RecallCopy.partial(coverage).headline, "No single note has all of that.")
    }

    func testMissingWordsAreShownAsTyped() throws {
        let note = try candidate("Śmieci: worki w szafce", ["smieci"])
        let coverage = RecallCoverage(question: "kiedy jest wywóz śmieci", candidates: [note])
        XCTAssertEqual(coverage.missing.map(\.label), ["wywóz"])
    }

    func testVoiceReplyNamesTheMissingWordAndKeepsTheNotes() throws {
        let wifi = try candidate("Wifi password at mum's: Sunflower", ["password"])
        let reply = VoiceToolReply.search(.matches([wifi]), question: "netflix password")
        XCTAssertTrue(reply.hasPrefix("Found 1 saved note, but none contains every key word"))
        XCTAssertTrue(reply.contains("No saved note contains: \"netflix\"."))
        XCTAssertTrue(reply.contains("Do not present them as the answer."))
        XCTAssertTrue(reply.contains("\"Wifi password at mum's: Sunflower\""), "the notes are still given, exactly")
        // A whole match reads as before.
        let both = try candidate("Wifi password at mum's: Sunflower", ["wifi", "password"])
        let whole = VoiceToolReply.search(.matches([both]), question: "wifi password")
        XCTAssertTrue(whole.hasPrefix("Found 1 saved note (exact text"))
    }
}
