import XCTest
@testable import DoddyCore

/// The parts of quiet memory (decision `2026-11-14-quiet-memory`) that need no database: which sentences become
/// proposals, and how "kept quietly" is written into a learned item's provenance without changing old rows.
final class QuietMemoryRulesTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_760_000_000)

    private func said(_ texts: [(String, SaveSuggestion.Reason)]) -> [SaveSuggestion] {
        texts.enumerated().map { SaveSuggestion(id: $0.offset + 1, text: $0.element.0, reason: $0.element.1) }
    }

    func testEveryPreferenceAndPersonalFactBecomesAProposalPreferencesFirst() throws {
        let proposals = FactProposer.proposeAll(
            from: said([("My sister lives in Gdańsk", .personalFact), ("Dentist at 14:00", .dateOrNumber), ("I like black coffee", .preference)]),
            savedTexts: [], date: date, keptQuietly: true)
        let facts = proposals.compactMap { proposal -> FactProposal? in
            if case .fact(let fact) = proposal { return fact } else { return nil }
        }
        XCTAssertEqual(facts.map(\.value), ["I like black coffee", "My sister lives in Gdańsk"])
        XCTAssertTrue(facts.allSatisfy(\.provenance.keptQuietly))
        XCTAssertEqual(facts.map(\.kind), [.preference, .person])
    }

    func testTheCardsOneProposalIsUnchanged() throws {
        let one = try XCTUnwrap(FactProposer.propose(
            from: said([("My sister lives in Gdańsk", .personalFact), ("I like black coffee", .preference)]), savedTexts: [], date: date))
        guard case .fact(let fact) = one else { return XCTFail("a fact") }
        XCTAssertEqual(fact.value, "I like black coffee")
        XCTAssertFalse(fact.provenance.keptQuietly, "a card's proposal is not kept quietly")
    }

    func testSentencesAlreadySavedAsNotesAreLeftOut() {
        let proposals = FactProposer.proposeAll(
            from: said([("I like black coffee", .preference)]), savedTexts: ["I like black coffee "], date: date, keptQuietly: true)
        XCTAssertEqual(proposals, [])
    }

    func testOldProvenanceReadsAsNotQuietAndIsWrittenBackByteForByte() throws {
        let old = #"{"episodeDates":[1760000000000],"proposer":"rule","reason":"preference"}"#
        let decoded = try LearningJSON.decoder().decode(LearningProvenance.self, from: Data(old.utf8))
        XCTAssertFalse(decoded.keptQuietly)
        XCTAssertEqual(String(decoding: try LearningJSON.encoder().encode(decoded), as: UTF8.self), old,
                       "a row written before quiet memory is unchanged when written again")
    }

    func testQuietProvenanceRoundTrips() throws {
        let quiet = try LearningProvenance(proposer: .rule, reason: "preference", episodeDates: [date], keptQuietly: true)
        let data = try LearningJSON.encoder().encode(quiet)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""keptQuietly":true"#))
        XCTAssertEqual(try LearningJSON.decoder().decode(LearningProvenance.self, from: data), quiet)
    }

    func testTheLimitsAreAFewAtATime() {
        XCTAssertEqual(LearningLimits.standard.quietPerConversation, 3)
        XCTAssertEqual(LearningLimits.standard.quietPerDay, 10)
    }
}
