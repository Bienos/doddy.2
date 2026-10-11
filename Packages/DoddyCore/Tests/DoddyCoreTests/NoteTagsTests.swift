import XCTest
@testable import DoddyCore

/// Tags in notes (ADR-333).
final class NoteTagsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ text: String, at offset: TimeInterval = 0) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: .explicitText, category: .other, capturedAt: now.addingTimeInterval(offset))
    }

    func testOnlyRealTagsAreRead() {
        XCTAssertEqual(NoteTags.tags(in: "Gate code 4512 #Home #car-park #home"), ["home", "car-park"])
        XCTAssertEqual(NoteTags.tags(in: "#praca: spotkanie (#Łódź) [#zakupy]"), ["praca", "łódź", "zakupy"])
        // Not tags: a word with # inside, a link's anchor, numbers only, a lone #.
        XCTAssertEqual(NoteTags.tags(in: "I write C# and a#b, see site.com/#top, room #12, # alone"), [])
        XCTAssertEqual(NoteTags.tags(in: "#end- and #x_"), ["end", "x"])
        XCTAssertEqual(NoteTags.tags(in: "#" + String(repeating: "a", count: 31)), [])
    }

    func testCountsAndFilter() throws {
        let a = try note("Gate 4512 #home")
        let b = try note("Wi-Fi tin-kettle #home #tech")
        let c = try note("Tyres in March #car")
        let counts = NoteTags.counts([a, b, c])
        XCTAssertEqual(counts.map(\.tag), ["home", "car", "tech"])
        XCTAssertEqual(counts.first?.count, 2)
        XCTAssertEqual(NoteTags.filter([a, b, c], tag: "#Home").map(\.id), [a.id, b.id])
        XCTAssertEqual(NoteTags.filter([a, b, c], tag: nil).count, 3)
    }

    func testVoiceAsksForOneTagOnly() throws {
        XCTAssertEqual(NoteTags.tagQuery(" #Car "), "car")
        XCTAssertNil(NoteTags.tagQuery("#car keys"), "words with a tag are a normal word search")
        XCTAssertNil(NoteTags.tagQuery("car"))
        XCTAssertNil(NoteTags.tagQuery("#12"))
        let older = try note("Tyres in March #car", at: -86_400)
        let newer = try note("Service at Kowalski #car")
        let reply = VoiceToolReply.taggedNotes("car", notes: [older, newer])
        XCTAssertTrue(reply.hasPrefix("Found 2 saved notes with #car"))
        XCTAssertLessThan(reply.range(of: "Kowalski")!.lowerBound, reply.range(of: "Tyres")!.lowerBound)
        XCTAssertTrue(VoiceToolReply.taggedNotes("boat", notes: []).hasPrefix("No saved note has the tag #boat"))
    }
}
