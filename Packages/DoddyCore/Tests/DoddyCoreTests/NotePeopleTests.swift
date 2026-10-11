import XCTest
@testable import DoddyCore

/// A page per person (ADR-341): names written with @ in a note.
final class NotePeopleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ text: String, at offset: TimeInterval = 0) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: .explicitText, category: .other, capturedAt: now.addingTimeInterval(offset))
    }

    func testOnlyRealMentionsAreRead() {
        XCTAssertEqual(NotePeople.names(in: "@Marta wants the blue scarf, ask @marta's size (@Kuba)"), ["Marta", "Kuba"])
        XCTAssertEqual(NotePeople.names(in: "Dinner with @Gosia and [@Łukasz]"), ["Gosia", "Łukasz"])
        // Not people: email addresses, a lone @, numbers only.
        XCTAssertEqual(NotePeople.names(in: "write to anna@example.com, meet @ 5, room @12"), [])
        // Tags and people don't mix.
        XCTAssertEqual(NoteTags.tags(in: "@Marta #gifts"), ["gifts"])
    }

    func testPossessiveApostropheEndsTheName() {
        // "'" isn't a name character, so "@marta's" is Marta.
        XCTAssertEqual(NotePeople.names(in: "@marta's birthday"), ["marta"])
    }

    func testPeopleGroupIgnoringCaseAndShowTheNewestSpelling() throws {
        let old = try note("@marta likes tulips", at: -100)
        let new = try note("@Marta wants the blue scarf", at: 0)
        let other = try note("@Kuba allergic to nuts", at: -50)
        let people = NotePeople.people([old, new, other])
        XCTAssertEqual(people.map(\.name), ["Marta", "Kuba"])
        XCTAssertEqual(people.first?.count, 2)
        XCTAssertEqual(NotePeople.notes([old, new, other], about: "@MARTA").map(\.id), [new.id, old.id])
        XCTAssertEqual(NotePeople.notes([old, new, other], about: "").count, 0)
    }

    func testVoiceQueryIsExactlyOneMention() {
        XCTAssertEqual(NotePeople.personQuery(" @Marta "), "Marta")
        XCTAssertNil(NotePeople.personQuery("@Marta scarf"))
        XCTAssertNil(NotePeople.personQuery("Marta"))
        XCTAssertNil(NotePeople.personQuery("@"))
    }

    func testBirthdayOnlyFromOneMatchingCard() {
        let marta = BirthdayContact(id: "1", name: "Marta Nowak", month: 3, day: 14)
        let lukasz = BirthdayContact(id: "2", name: "Łukasz Wiśniewski", month: 7, day: 2)
        XCTAssertEqual(NotePeople.birthday(for: "marta", in: [marta, lukasz]), marta)
        XCTAssertEqual(NotePeople.birthday(for: "Lukasz", in: [marta, lukasz]), lukasz)
        // Two Martas: no birthday rather than the wrong one.
        let marta2 = BirthdayContact(id: "3", name: "Marta Kowalska", month: 1, day: 1)
        XCTAssertNil(NotePeople.birthday(for: "Marta", in: [marta, marta2]))
        XCTAssertNil(NotePeople.birthday(for: "Kuba", in: [marta]))
    }

    func testReplyNeverGuesses() throws {
        XCTAssertTrue(VoiceToolReply.personNotes("Kuba", notes: []).hasPrefix("No saved note mentions @Kuba"))
        let reply = VoiceToolReply.personNotes("Marta", notes: [try note("@Marta wants the blue scarf")])
        XCTAssertTrue(reply.contains("\"@Marta wants the blue scarf\""))
        XCTAssertEqual(NotePeople.newNoteText(about: "Marta"), "@Marta ")
    }
}
