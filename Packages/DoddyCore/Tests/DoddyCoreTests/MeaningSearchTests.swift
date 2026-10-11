import DoddyCore
import XCTest

/// Find by meaning (ADR-227): ranking, filters and the in-memory index, with a fake embedder.
final class MeaningSearchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ text: String, category: MemoryCategory = .other, source: MemorySource = .explicitText) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: source, category: category, capturedAt: now)
    }

    /// Words map to fixed directions; a text's vector is the sum of its known words.
    private struct FakeEmbedder: MeaningEmbedder {
        let axes: [String: [Float]]
        func vector(for text: String) async -> [Float]? {
            var v: [Float] = [0, 0, 0, 0]
            var any = false
            for word in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
                if let axis = axes[String(word)] { any = true; for i in v.indices { v[i] += axis[i] } }
            }
            return any ? v : nil
        }
    }

    private let embedder = FakeEmbedder(axes: [
        "dumplings": [1, 0, 0, 0], "pierogi": [1, 0, 0, 0], "restaurant": [0.9, 0.1, 0, 0], "place": [0.8, 0.2, 0, 0],
        "keys": [0, 1, 0, 0], "spare": [0, 0.9, 0.1, 0], "passport": [0, 0, 1, 0], "renew": [0, 0, 0.9, 0.1],
        "wifi": [0, 0, 0, 1],
    ])

    func testCosine() {
        XCTAssertEqual(MeaningSearch.cosine([1, 0], [1, 0]), 1, accuracy: 0.0001)
        XCTAssertEqual(MeaningSearch.cosine([1, 0], [0, 1]), 0, accuracy: 0.0001)
        XCTAssertEqual(MeaningSearch.cosine([1, 0], [1]), 0, "different sizes never match")
    }

    func testCloseInMeaningIsFoundAndUnrelatedIsNot() async throws {
        let zapiecek = try note("Zapiecek restaurant, great dumplings")
        let keys = try note("Spare keys in the blue tin")
        let passport = try note("Renew passport before May")
        let wifi = try note("Wifi password on the router")
        let index = MeaningIndex(embedder: embedder)
        let hits = await index.search("the place with good pierogi", in: [zapiecek, keys, passport, wifi], excluding: [])
        XCTAssertEqual(hits.map(\.record.id), [zapiecek.id])
    }

    func testListsSamplesAndWordHitsAreLeftOut() async throws {
        let dumplings = try note("dumplings")
        let list = try note("dumplings", category: .list)
        let sample = try note("dumplings restaurant", source: .sampleFixture)
        let keys = try note("spare keys")
        let index = MeaningIndex(embedder: embedder)
        let none = await index.search("pierogi place", in: [dumplings, list, sample, keys], excluding: [dumplings.id])
        XCTAssertTrue(none.isEmpty, "the word search already showed it; lists and samples never count")
    }

    func testShortOrUnreadableQuestionsFindNothing() async throws {
        let index = MeaningIndex(embedder: embedder)
        let notes = [try note("dumplings")]
        let short = await index.search("pi", in: notes, excluding: [])
        let unreadable = await index.search("zzzz qqq", in: notes, excluding: [])
        XCTAssertTrue(short.isEmpty)
        XCTAssertTrue(unreadable.isEmpty)
    }

    func testAtMostFiveHits() throws {
        let notes = try (0..<9).map { _ in (record: try note("dumplings"), vector: [Float](arrayLiteral: 1, 0, 0, 0)) }
        let others = try (0..<20).map { _ in (record: try note("keys"), vector: [Float](arrayLiteral: 0, 1, 0, 0)) }
        XCTAssertEqual(MeaningSearch.rank(query: [1, 0, 0, 0], notes: notes + others).count, MeaningSearch.maxHits)
    }
}
