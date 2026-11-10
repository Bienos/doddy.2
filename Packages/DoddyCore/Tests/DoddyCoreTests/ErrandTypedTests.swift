@testable import DoddyCore
import XCTest

/// A task typed on the Tasks screen (decision 2026-11-10-tasks-redesign): the words go as typed, the
/// note says Doddy wrote none, the title is the start of the words and fits the server's limit, and
/// the request is checked by the same rules as one handed over by voice (no link, the same limits,
/// the same digest).
final class ErrandTypedTests: XCTestCase {
    private let rome = "Porównaj loty do Rzymu na tydzień w przyszłym miesiącu, do 2000 zł"

    func testTheWordsGoAsTypedOnlyTrimmed() {
        let draft = ErrandDraft.typed("  \(rome)\n", language: "pl")
        XCTAssertEqual(draft.words, rome)
        XCTAssertEqual(draft.language, "pl")
        XCTAssertNil(draft.kind, "a typed task is a research task")
        XCTAssertEqual(draft.priorities, [])
        XCTAssertEqual(draft.validationIssues(), [])
    }

    func testTheNoteSaysDoddyWroteNone() {
        XCTAssertEqual(ErrandDraft.typed(rome, language: "pl").brief, ErrandDraft.typedNote(language: "pl"))
        XCTAssertTrue(ErrandDraft.typedNote(language: "pl").contains("nie dopisał własnej notatki"))
        XCTAssertEqual(ErrandDraft.typed("Find three quiet cafés", language: "en").brief, ErrandDraft.typedNote(language: "en"))
        XCTAssertTrue(ErrandDraft.typedNote(language: "en").contains("Doddy added no note of its own"))
        // Any other language gets the English note; the result is still written in that language.
        let german = ErrandDraft.typed("Flüge nach Rom vergleichen", language: "de")
        XCTAssertEqual(german.language, "de")
        XCTAssertEqual(german.brief, ErrandDraft.typedNote(language: "en"))
        for language in ["pl", "en"] {
            let note = ErrandDraft.typedNote(language: language)
            XCTAssertLessThanOrEqual(note.utf16.count, ErrandDraft.maxBrief)
            XCTAssertFalse(LinkShape.isIn(note))
        }
    }

    func testAShortFirstLineIsTheWholeTitle() {
        XCTAssertEqual(ErrandDraft.typedTitle("Loty do Rzymu"), "Loty do Rzymu")
        XCTAssertEqual(ErrandDraft.typedTitle("Loty   do\tRzymu\nhotel blisko Trastevere"), "Loty do Rzymu", "first line, spaces made one")
        XCTAssertEqual(ErrandDraft.typedTitle(""), "")
        XCTAssertEqual(ErrandDraft.typed("   ", language: "pl").validationIssues(), [.missingWords, .missingTitle])
    }

    func testALongTitleIsCutAfterAWholeWord() {
        let title = ErrandDraft.typedTitle(rome)
        XCTAssertEqual(title, "Porównaj loty do Rzymu na tydzień w przyszłym miesiącu, do…")
        XCTAssertLessThanOrEqual(title.utf16.count, ErrandDraft.typedTitleLength + 1)
        XCTAssertTrue(rome.hasPrefix(String(title.dropLast())))
    }

    func testOneVeryLongWordIsCutBetweenCharacters() {
        let word = String(repeating: "ż", count: 70)
        XCTAssertEqual(ErrandDraft.typedTitle(word), String(repeating: "ż", count: 60) + "…")
        // An emoji is two UTF-16 units and is never split.
        let emoji = String(repeating: "🙂", count: 40)
        XCTAssertEqual(ErrandDraft.typedTitle(emoji), String(repeating: "🙂", count: 30) + "…")
    }

    func testEveryTitleFitsTheServer() {
        for words in [rome, String(repeating: "słowo ", count: 200), String(repeating: "🙂", count: 500), String(repeating: "a", count: 1_000)] {
            let draft = ErrandDraft.typed(words, language: "pl")
            XCTAssertLessThanOrEqual(draft.title.utf16.count, ErrandDraft.maxTitle)
            XCTAssertFalse(draft.validationIssues().contains(.titleTooLong))
        }
    }

    func testTheSameRulesAsAVoiceTask() {
        // ADR-716: a link is refused, never cut out.
        let withLink = ErrandDraft.typed("Sprawdź https://example.com/oferta i porównaj", language: "pl")
        XCTAssertTrue(withLink.validationIssues().contains(.containsLink))
        XCTAssertEqual(ErrandDraft.typed("Porównaj ceny na allegro.pl", language: "pl").validationIssues(), [])
        XCTAssertEqual(ErrandDraft.typed(String(repeating: "a", count: 1_001), language: "pl").validationIssues(), [.wordsTooLong])
        // The digest is over exactly what the card shows: the words, the note, the title and the language.
        let draft = ErrandDraft.typed(rome, language: "pl")
        let same = ErrandDraft(words: draft.words, brief: draft.brief, title: draft.title, language: "pl")
        XCTAssertEqual(draft.digest, same.digest)
        XCTAssertNotEqual(draft.digest, ErrandDraft.typed(rome, language: "en").digest)
    }

    func testTheLanguageComesFromTheAppsLanguage() {
        XCTAssertEqual(ErrandDraft.typedLanguage("pl"), "pl")
        XCTAssertEqual(ErrandDraft.typedLanguage("en-GB"), "en")
        XCTAssertEqual(ErrandDraft.typedLanguage("pt-BR"), "pt")
        XCTAssertEqual(ErrandDraft.typedLanguage("zh-Hans"), "zh")
        XCTAssertEqual(ErrandDraft.typedLanguage("en_US"), "en")
        XCTAssertEqual(ErrandDraft.typedLanguage("PL"), "pl")
        for odd in ["", "Base", "fil", "1x"] {
            XCTAssertEqual(ErrandDraft.typedLanguage(odd), "en", odd)
        }
    }
}
