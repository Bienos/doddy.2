import XCTest
@testable import DoddyCore

// Another mode adds its own name without touching ExpertResult.swift.
extension ExpertMode {
    static let invoicesForTest: ExpertMode = "invoices"
}

/// ADR-642: the typed result every expert mode answers in (research section 7.2).
final class ExpertResultTests: XCTestCase {
    private func sample() -> ExpertResult {
        ExpertResult(mode: .personalTraining, answer: "Zrób dziś 20 minut treningu całego ciała.",
                     sources: [ExpertSource(url: "https://example.org/a", checkedAt: "2026-10-24")], riskLevel: .low)
    }

    func testTheJSONUsesTheResearchsKeysAndWritesNullForTheMemoryProposal() throws {
        let text = String(decoding: try sample().json(), as: UTF8.self)
        for key in ["\"mode\":\"personal_training\"", "\"answer\"", "\"proposed_actions\":[]", "\"missing_data\":[]", "\"sources\":[",
                    "\"checked_at\":\"2026-10-24\"", "\"caveats\":[]", "\"memory_update_proposal\":null", "\"risk_level\":\"low\"",
                    "\"verified_external_action\":false"] {
            XCTAssertTrue(text.contains(key), "\(key) missing in \(text)")
        }
        XCTAssertEqual(text, String(decoding: try sample().json(), as: UTF8.self), "the same result gives the same bytes")
    }

    func testItRoundTrips() throws {
        let result = ExpertResult(mode: .personalTraining, answer: "x", proposedActions: [ExpertProposedAction(kind: "keep_plan", summary: "s")],
                                  missingData: ["goal"], sources: [.who2020, .acsm2026], caveats: ["c"], riskLevel: .high)
        XCTAssertEqual(try JSONDecoder().decode(ExpertResult.self, from: result.json()), result)
        let withMemory = ExpertResult(mode: .invoicesForTest, answer: "y", memoryUpdateProposal: "Remember my VAT id?")
        XCTAssertEqual(try JSONDecoder().decode(ExpertResult.self, from: withMemory.json()), withMemory)
    }

    func testNothingIsVerifiedUnlessSaidSoOnPurpose() {
        XCTAssertFalse(sample().verifiedExternalAction)
        XCTAssertFalse(ExpertResult(mode: .personalTraining, answer: "a").verifiedExternalAction)
        XCTAssertNil(sample().memoryUpdateProposal)
    }

    func testRiskOrdersAndTurnsHumorOffAboveLow() {
        XCTAssertLessThan(RiskLevel.low, .moderate)
        XCTAssertLessThan(RiskLevel.moderate, .high)
        XCTAssertLessThan(RiskLevel.high, .emergency)
        XCTAssertEqual(RiskLevel.allCases.filter(\.humorAllowed), [.low])
        for level in RiskLevel.allCases {
            XCTAssertEqual(ExpertResult(mode: .personalTraining, answer: "a", riskLevel: level).humorAllowed, level == .low)
        }
    }

    func testTheSourcesTheTrainingAnswersCiteAreTheOnesRead() {
        XCTAssertEqual(ExpertSource.who2020.url, "https://www.ncbi.nlm.nih.gov/books/NBK566046/")
        XCTAssertEqual(ExpertSource.acsm2026.url, "https://pmc.ncbi.nlm.nih.gov/articles/PMC12965823/")
        XCTAssertEqual(ExpertSource.frandsen2025.url, "https://doi.org/10.1136/bjsports-2024-109380")
        for source in [ExpertSource.who2020, .acsm2026, .frandsen2025] { XCTAssertEqual(source.checkedAt, "2026-10-24") }
    }
}
