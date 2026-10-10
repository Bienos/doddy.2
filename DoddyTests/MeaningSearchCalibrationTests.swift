import DoddyCore
import XCTest
@testable import Doddy

/// ADR-228 calibration with Apple's real on-device model (Mac / iPhone only; never run on Linux).
/// Synthetic notes only. Prints every score so the thresholds in `MeaningPolicy` can be checked
/// against what the model actually does, and fails if meaning search is mostly wrong.
final class MeaningSearchCalibrationTests: XCTestCase {
    private let notes = [
        "Kasia says the sushi spot on Mokotowska is great",
        "Parked on level 3 of the garage, row C",
        "Allergic to penicillin",
        "Passport expires in March 2027",
        "Router password is on the sticker under the box",
        "Marta wants a pottery class as a birthday present",
        "Boss moved the report deadline to Friday",
        "Spare keys in the blue tin above the fridge",
        "Hydraulik Adam przychodzi we wtorek rano",
        "Siłownia w niedziele zamknięta o 21",
        "Mama lubi róże, nie tulipany",
        "Numer polisy ubezpieczenia samochodu: 4471-22",
    ]

    /// Question → the note it should find, sharing none of its words.
    private let cases: [(question: String, expected: Int)] = [
        ("where should we go for japanese food", 0),
        ("where did I leave the car", 1),
        ("which antibiotic can't I take", 2),
        ("when do I need a new travel document", 3),
        ("how do I get online at home", 4),
        ("gift idea for Marta", 5),
        ("kiedy przyjdzie fachowiec od rur", 8),
        ("jakie kwiaty kupić dla mamy", 10),
    ]

    func testRealModelFindsNotesByMeaning() async throws {
        guard let embedder = OnDeviceMeaningEmbedder() else {
            throw XCTSkip("No Latin-script contextual embedding on this device or simulator")
        }
        var noteVectors: [MeaningVector] = []
        do {
            for (index, text) in notes.enumerated() {
                noteVectors.append(MeaningVector(
                    memoryID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
                    textHash: MeaningRanking.textHash(text), values: try await embedder.embed(text)))
            }
        } catch MeaningSearchError.modelUnavailable {
            throw XCTSkip("Model assets not available (offline simulator?)")
        }

        var topHits = 0, offered = 0, wrongOffers = 0
        for (question, expected) in cases {
            let scored = MeaningRanking.scores(question: try await embedder.embed(question), notes: noteVectors)
            let ranked = scored.sorted { $0.score > $1.score }
            let chosen = MeaningRanking.select(scored, excluding: [], policy: .standard)
            let expectedID = noteVectors[expected].memoryID
            if ranked.first?.id == expectedID { topHits += 1 }
            if chosen.contains(where: { $0.id == expectedID }) { offered += 1 }
            wrongOffers += chosen.filter { $0.id != expectedID }.count
            let line = ranked.prefix(3).map { hit in
                "\(String(format: "%.3f", hit.score)) \(notes[noteVectors.firstIndex { $0.memoryID == hit.id }!])"
            }.joined(separator: " | ")
            print("[calibration] \(question) → \(line) · offered \(chosen.count)")
        }
        print("[calibration] model \(embedder.modelID): top-1 \(topHits)/\(cases.count), offered \(offered)/\(cases.count), wrong offers \(wrongOffers)")
        XCTAssertGreaterThanOrEqual(topHits, 6, "the right note should rank first for most questions")
        XCTAssertLessThanOrEqual(wrongOffers, cases.count / 2, "few unrelated notes offered")
    }
}
