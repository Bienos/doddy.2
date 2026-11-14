import XCTest
@testable import DoddyCore

/// A new note that changes an old one (decision `2026-11-14-changed-facts-update-the-note`): when the
/// words about to be saved are about the same thing as one saved note, and say something different,
/// the person is offered "update that note" (the old wording stays in its history, ADR-252) beside
/// "save as a new note". The rules only offer; nothing here saves or changes a note.
final class NoteUpdateMatchTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    private func note(_ text: String, category: MemoryCategory = .fact, source: MemorySource = .explicitText,
                      id: UUID = UUID(), daysAgo: Double = 10) throws -> MemoryRecord {
        try MemoryRecord(id: id, rawText: text, source: source, category: category,
                         capturedAt: day.addingTimeInterval(-daysAgo * 86_400))
    }

    private func offer(_ new: String, _ notes: [MemoryRecord], privateIDs: Set<UUID> = []) -> NoteUpdateOffer? {
        NoteUpdateMatch.offer(forNewText: new, notes: notes, privateIDs: privateIDs)
    }

    // MARK: Same words, a different number

    func testTheSameWordsWithADifferentNumberReplaceTheOldNote() throws {
        let gate = try note("Gate code 4821")
        let found = offer("My gate code is 5555", [gate, try note("Dentist on Tuesday at 14:00")])
        XCTAssertEqual(found, NoteUpdateOffer(noteID: gate.id, oldText: "Gate code 4821", newText: "My gate code is 5555"))
    }

    func testPolishWordsAndNumbersWork() throws {
        let gate = try note("Kod do bramy 4821")
        XCTAssertEqual(offer("Kod do bramy to 5555", [gate])?.noteID, gate.id)
        let phone = try note("Mój numer telefonu to 600 111 222")
        XCTAssertEqual(offer("Mój numer telefonu to 600 999 888", [phone])?.noteID, phone.id)
    }

    func testATimeThatMovedIsAnUpdate() throws {
        let dentist = try note("Dentist on Tuesday at 14:00")
        XCTAssertEqual(offer("Dentist on Tuesday at 15:00", [dentist])?.noteID, dentist.id)
    }

    func testTwoDifferentPeopleOrPlacesAreNotTheSameThing() throws {
        XCTAssertNil(offer("Marta's birthday is 12 May", [try note("Tom's birthday is 3 June")]))
        XCTAssertNil(offer("Wifi code at the office 1234", [try note("Wifi code at home 5678")]),
                     "the extra word on each side is a different thing, not the same words")
    }

    func testOneSharedWordIsTooLittleToCallItTheSameThing() throws {
        XCTAssertNil(offer("Code 1234", [try note("Code 5678")]))
    }

    func testTheSameNumberOrNoNumberIsNotAChange() throws {
        XCTAssertNil(offer("Gate code is 4821.", [try note("gate code 4821")]), "the same number: nothing changed (a plain duplicate has its own warning)")
        XCTAssertNil(offer("The gate code is for the shed", [try note("Gate code 4821")]), "no number to change")
    }

    // MARK: A fact with one value

    func testWhereYouLiveChangesTheOldNoteInBothLanguages() throws {
        let warsaw = try note("Mieszkam w Warszawie")
        XCTAssertEqual(offer("Mieszkam w Berlinie", [warsaw])?.noteID, warsaw.id)
        let en = try note("I live in Warsaw")
        XCTAssertEqual(offer("I live in Berlin now", [en])?.noteID, en.id)
    }

    func testAMoveWrittenAnotherWayIsTheSameSlot() throws {
        let warsaw = try note("Mieszkam w Warszawie")
        XCTAssertEqual(offer("Przeprowadziłem się do Berlina", [warsaw])?.noteID, warsaw.id)
        XCTAssertEqual(offer("I moved to Berlin", [try note("I live in Warsaw")])?.oldText, "I live in Warsaw")
    }

    func testWhereYouWorkChanges() throws {
        let acme = try note("I work at Acme")
        XCTAssertEqual(offer("I work at Initech", [acme])?.noteID, acme.id)
        let allegro = try note("Pracuję w Allegro")
        XCTAssertEqual(offer("Pracuję w Google", [allegro])?.noteID, allegro.id)
    }

    func testWhereYouLiveAndWhereYouWorkAreDifferentThings() throws {
        XCTAssertNil(offer("Pracuję w Berlinie", [try note("Mieszkam w Warszawie")]))
        XCTAssertNil(offer("I live in Berlin", [try note("I work at Acme")]))
    }

    func testTheSamePlaceWithMoreWordsIsNotAChange() throws {
        XCTAssertNil(offer("Mieszkam w Berlinie od 2019", [try note("Mieszkam w Berlinie")]))
        XCTAssertNil(offer("I live in Berlin now", [try note("I live in Berlin")]))
    }

    func testThingsThatAddUpAreNotReplaced() throws {
        XCTAssertNil(offer("Marta lubi herbatę", [try note("Marta lubi kawę", category: .preference)]),
                     "a second thing she likes, not a changed one")
        XCTAssertNil(offer("I'm allergic to pollen", [try note("I'm allergic to nuts")]))
    }

    // MARK: Never guess, never reveal

    func testTwoNotesThatBothFitMeanNoOfferBecauseNobodyKnowsWhichOne() throws {
        let notes = [try note("Mieszkam w Warszawie"), try note("I live in Krakow")]
        XCTAssertNil(offer("Mieszkam w Berlinie", notes))
    }

    func testAPrivateNoteIsNeverOfferedOrCounted() throws {
        let secret = try note("Mieszkam w Warszawie")
        XCTAssertNil(offer("Mieszkam w Berlinie", [secret], privateIDs: [secret.id]))
        // Hidden from the match, it can't make a second note look ambiguous either.
        let other = try note("I live in Krakow")
        XCTAssertEqual(offer("Mieszkam w Berlinie", [secret, other], privateIDs: [secret.id])?.noteID, other.id)
    }

    func testListsAndSampleNotesAreNeverOffered() throws {
        XCTAssertNil(offer("Mieszkam w Berlinie", [try note("Mieszkam w Warszawie", category: .list)]))
        XCTAssertNil(offer("Mieszkam w Berlinie", [try note("Mieszkam w Warszawie", source: .sampleFixture)]))
    }

    func testEmptyTextOffersNothing() throws {
        XCTAssertNil(offer("   ", [try note("Mieszkam w Warszawie")]))
        XCTAssertNil(offer("Mieszkam w Berlinie", []))
    }

    func testTheOfferCarriesTheNotesCurrentWordsAfterACorrection() throws {
        let old = try MemoryRecord(id: UUID(), rawText: "Gate code 1111", currentText: "Gate code 4821", source: .explicitText,
                                   category: .fact, capturedAt: day, updatedAt: day, userEdited: true)
        XCTAssertEqual(offer("Gate code is 5555", [old])?.oldText, "Gate code 4821", "the person sees what the note says now")
        XCTAssertNil(offer("Gate code is 4821", [old]), "and it is compared with that, not with the first wording")
    }
}
