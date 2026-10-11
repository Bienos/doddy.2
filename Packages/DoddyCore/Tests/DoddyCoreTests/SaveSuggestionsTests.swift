@testable import DoddyCore
import Foundation
import XCTest

/// ADR-247. Synthetic transcripts only.
final class SaveSuggestionsTests: XCTestCase {
    private func suggest(_ lines: [String], proposed: [String] = [], notes: [MemoryRecord] = []) -> [String] {
        SaveSuggestions.suggest(userLines: lines, alreadyProposed: proposed, existingNotes: notes).map(\.text)
    }

    // MARK: What is offered

    func testOffersUsefulFactsInTheUsersOwnWordsInOrder() {
        let lines = [
            "Hey Doddy, how are you?",
            "Oh, by the way, Marta's birthday is on the 12th of May.",
            "What's the weather like tomorrow in Kraków?",
            "The plumber Adam comes on Tuesday morning.",
            "Thanks, that's all.",
        ]
        XCTAssertEqual(suggest(lines), [
            "Marta's birthday is on the 12th of May",
            "The plumber Adam comes on Tuesday morning",
        ])
    }

    func testPolishSentences() {
        let lines = [
            "Cześć, co słychać?",
            "Słuchaj, Kasia poleciła mi książkę Lalka, warto przeczytać.",
            "Mama lubi róże, nie tulipany.",
            "Jaka będzie jutro pogoda?",
        ]
        XCTAssertEqual(suggest(lines), [
            "Kasia poleciła mi książkę Lalka, warto przeczytać",
            "Mama lubi róże, nie tulipany",
        ])
    }

    func testAskedToRememberButNothingWasSavedRanksFirst() {
        let lines = [
            "My sister lives in Gdańsk now.",
            "Gym closes at 21 on Sundays.",
            "Marta loves orchids.",
            "Remember that the spare key is under the blue pot on Fridays",
        ]
        let found = SaveSuggestions.suggest(userLines: lines, alreadyProposed: [], existingNotes: [])
        XCTAssertEqual(found.count, SaveSuggestions.maxSuggestions)
        XCTAssertTrue(found.contains { $0.text == "The spare key is under the blue pot on Fridays" && $0.reason == .askedToRemember },
                      "the 'remember that' prefix is dropped; the rest is kept as said")
        XCTAssertEqual(found.map(\.id), [0, 1, 2])
    }

    func testDecimalsAndTimesStayInOneSentence() {
        XCTAssertEqual(SaveSuggestions.sentences("Train leaves at 12.05 from platform 3. See you"),
                       ["Train leaves at 12.05 from platform 3.", "See you"])
        XCTAssertEqual(SaveSuggestions.sentences("One\nTwo; three"), ["One", "Two;", "three"])
    }

    // MARK: What is never offered

    func testQuestionsRequestsAndSmallTalkAreNotOffered() {
        let lines = [
            "When is Marta's birthday?",
            "Remind me to call Adam on Tuesday at 5.",
            "Set a timer for 10 minutes please.",
            "Can you check my calendar for Friday",
            "Czy masz zapisany kod do bramy?",
            "Przypomnij mi jutro o 9 o dentyście",
            "Thank you so much Doddy, bye!",
            "You're funny, Doddy, you know that?",
            "That's great to hear from you today",
        ]
        XCTAssertEqual(suggest(lines), [])
    }

    func testSecretsAreNeverOffered() {
        let lines = [
            "My Netflix password is Sunshine2024 for the account.",
            "Moje hasło do banku to Kot123 od wczoraj.",
            "My card number is 4111 1111 1111 1111 for the record.",
            "Mój PESEL to 90010112345, zapisz gdzieś.",
            "The card PIN is 1234 for the blue Visa.",
        ]
        XCTAssertEqual(suggest(lines), [])
    }

    func testAPinOnItsOwnIsASecret() {
        XCTAssertEqual(suggest(["My PIN is 4821.", "Mój PIN to 4821 do telefonu.", "PINs for the bank cards: 4821 and 1234."]), [])
    }

    func testDoddysOwnLinesAreNeverAnInput() {
        // Only user lines are passed in; this documents that the API has no place for agent text.
        XCTAssertEqual(SaveSuggestions.suggest(userLines: [], alreadyProposed: [], existingNotes: []), [])
    }

    func testVagueChatterIsNotOffered() {
        XCTAssertEqual(suggest(["I had a really great day at the park", "My boss is annoying today", "I will think about it"]), [])
    }

    func testTooShortOrTooLongIsNotOffered() {
        XCTAssertEqual(suggest(["Marta, 12 May"]), [], "under four words")
        XCTAssertEqual(suggest([String(repeating: "Marta likes the 12 May plan a lot and ", count: 6)]), [], "over forty words")
    }

    // MARK: Nothing twice

    func testWhatWasAlreadyProposedOrSavedIsNotOfferedAgain() throws {
        let saved = try MemoryRecord(id: UUID(), rawText: "Gate code 4821", source: .explicitVoice, capturedAt: Date(timeIntervalSince1970: 0))
        let lines = [
            "My gate code is 4821.",
            "Remember Marta's birthday is on the 12th of May.",
            "The gate code is 5555 since Monday.",
        ]
        XCTAssertEqual(
            suggest(lines, proposed: ["Marta's birthday: 12 May"], notes: [saved]),
            ["The gate code is 5555 since Monday"],
            "covered by a saved note or a save card in this conversation; a new number is still offered")
    }

    func testSameSentenceTwiceIsOfferedOnce() {
        XCTAssertEqual(suggest(["Marta's birthday is on the 12th of May.", "Marta's birthday is on the 12th of May!"]),
                       ["Marta's birthday is on the 12th of May"])
    }

    func testSampleNotesDoNotBlockSuggestions() throws {
        let sample = try MemoryRecord(id: UUID(), rawText: "Gate code 4821", source: .sampleFixture, capturedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(suggest(["My gate code is 4821."], notes: [sample]), ["My gate code is 4821"])
    }

    // MARK: The card

    private func record(_ text: String) throws -> MemoryRecord {
        try MemoryRecord(id: UUID(), rawText: text, source: .explicitVoice, capturedAt: Date(timeIntervalSince1970: 0))
    }

    /// The loop `VoiceSessionController.saveTickedSuggestions` runs.
    private func saveTicked(_ card: inout SaveSuggestionCard, _ save: (String) throws -> MemoryRecord) {
        for (id, text) in card.beginSaving() {
            do {
                card.finish(id, .success(try save(text)))
            } catch {
                card.finish(id, .failure(SaveSuggestionFailure(message: "Couldn't save.")))
            }
        }
    }

    func testCardStartsUntickedAndSavesOnlyTickedItemsWithTheirFinalWords() throws {
        var card = SaveSuggestionCard([
            SaveSuggestion(id: 0, text: "Marta's birthday is 12 May", reason: .personalFact),
            SaveSuggestion(id: 1, text: "Gym closes at 21 on Sundays", reason: .dateOrNumber),
            SaveSuggestion(id: 2, text: "Plumber Adam comes on Tuesday", reason: .plan),
        ])
        XCTAssertEqual(card.tickedCount, 0, "nothing is ticked for the user")
        card.toggle(0)
        card.setText(2, "Plumber Adam comes on Wednesday")
        XCTAssertEqual(card.tickedCount, 2, "changing the words ticks the item")

        var savedTexts: [String] = []
        saveTicked(&card) { text in
            savedTexts.append(text)
            if text.contains("Wednesday") { throw MemoryStoreError.verificationFailed }
            return try self.record(text)
        }

        XCTAssertEqual(savedTexts, ["Marta's birthday is 12 May", "Plumber Adam comes on Wednesday"])
        XCTAssertEqual(card.savedCount, 1)
        XCTAssertTrue(card.hasResults)
        guard case .saved(let saved) = card.items[0].state else { return XCTFail("first saved") }
        XCTAssertEqual(saved.currentText, "Marta's birthday is 12 May")
        XCTAssertEqual(card.items[1].state, .offered, "unticked item untouched")
        XCTAssertEqual(card.items[2].state, .failed("Couldn't save."), "a failure is never shown as saved")
    }

    func testSavingTwiceDoesNotSaveAgain() throws {
        var card = SaveSuggestionCard([SaveSuggestion(id: 0, text: "Marta's birthday is 12 May", reason: .personalFact)])
        card.toggle(0)
        var calls = 0
        saveTicked(&card) { text in calls += 1; return try self.record(text) }
        saveTicked(&card) { text in calls += 1; return try self.record(text) }
        XCTAssertEqual(calls, 1)
        card.toggle(0)
        card.setText(0, "changed")
        XCTAssertEqual(card.items[0].text, "Marta's birthday is 12 May", "a saved item can't be changed on the card")
    }

    func testBeginSavingMarksItemsSoASecondTapIsIgnored() {
        var card = SaveSuggestionCard([SaveSuggestion(id: 0, text: "Marta's birthday is 12 May", reason: .personalFact)])
        card.toggle(0)
        XCTAssertEqual(card.beginSaving().count, 1)
        XCTAssertTrue(card.isSaving)
        XCTAssertFalse(card.hasResults)
        XCTAssertEqual(card.beginSaving().count, 0)
    }
}
