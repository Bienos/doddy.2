@testable import DoddyCore
import XCTest

final class RecallMatchingTests: XCTestCase {
    private func matched(_ query: String, _ note: String) -> [String] {
        RecallMatching.matchedWords(RecallMatching.terms(query), in: note)
    }

    func testPrefixRuleStillWorks() {
        XCTAssertEqual(matched("klucz", "Klucze są w szufladzie"), ["klucz"])
        XCTAssertEqual(matched("Lodz", "Łódź, środa"), ["lodz"])
    }

    func testNumberWordsAndDigitsMeet() {
        XCTAssertEqual(matched("4821", "cztery osiem dwa jeden"), ["4821"])
        XCTAssertEqual(matched("four", "PIN 4821"), ["four"])
        XCTAssertEqual(matched("pięć", "room 5"), ["piec"])
        XCTAssertTrue(RecallMatching.noteWords("kod 5 6 7 8").contains("5678"))
        XCTAssertFalse(RecallMatching.noteWords("5 apples and 6 pears").contains("56"), "a word between numbers ends the run")
    }

    func testPolishAndEnglishCounterparts() {
        XCTAssertEqual(matched("parcel", "Paczka czeka w paczkomacie"), ["parcel"])
        XCTAssertEqual(matched("klucze", "spare keys in the tin"), ["klucze"])
    }

    func testTyposNeedLongEnoughWords() {
        XCTAssertEqual(matched("dentsit", "dentist on Friday"), ["dentsit"])
        XCTAssertEqual(matched("apointmnet", "appointment at 9"), ["apointmnet"], "two edits allowed from 8 letters")
        XCTAssertEqual(matched("kot", "kod do bramy"), [], "short words need an exact prefix")
        XCTAssertEqual(matched("dentist", "density chart"), [], "two edits at 7 letters is too many")
    }

    func testSingleLettersAreNotSearchedButSingleDigitsAre() {
        XCTAssertEqual(RecallMatching.terms("What's Jake's birthday?").map(\.word), ["jake", "birthday"])
        XCTAssertEqual(RecallMatching.terms("ile witaminy D").map(\.word), ["witaminy"])
        XCTAssertEqual(RecallMatching.terms("room 5").map(\.word), ["room", "5"])
        XCTAssertEqual(matched("what's my blood type", "Spare keys in the tin"), [])
    }

    func testShortWordsNeedAWholeWordOrACommonEnding() {
        XCTAssertEqual(matched("car", "two cars outside"), ["car"])
        XCTAssertEqual(matched("car", "library card"), [], "car is not card")
        XCTAssertEqual(matched("kod", "nie pamiętam kodu"), ["kod"])
        XCTAssertEqual(matched("lek", "kupić leki"), ["lek"])
        XCTAssertEqual(matched("lek", "lekarz w piątek"), [], "a medicine is not a doctor")
        XCTAssertEqual(matched("four", "PIN 4821"), ["four"], "digits keep the plain prefix")
        XCTAssertEqual(matched("klucz", "Klucze są w szufladzie"), ["klucz"], "4+ letters keep the plain prefix")
    }

    func testTypoCountsOnlyWhenNoNoteHasTheWordAsTyped() {
        let matcher = RecallMatching.Matcher(RecallMatching.terms("password"))
        let notes = ["wifi password sunflower", "passport expires in august"].map(SearchFolding.fold)
        XCTAssertEqual(matcher.matchedWords(inFolded: notes), [["password"], []])
        // With no note saying "password", the typo is the best there is and still counts.
        XCTAssertEqual(matcher.matchedWords(inFolded: [notes[1]]), [["password"]])
        let typo = RecallMatching.Matcher(RecallMatching.terms("pasport"))
        XCTAssertEqual(typo.matchedWords(inFolded: notes), [[], ["pasport"]])
        // One edit always counts: Polish "polisy" for "policy", even with an English "policy" note.
        let policy = RecallMatching.Matcher(RecallMatching.terms("policy"))
        XCTAssertEqual(policy.matchedWords(inFolded: ["travel policy", "numer polisy"].map(SearchFolding.fold)), [["policy"], ["policy"]])
    }

    func testStopwordsAndQuestionWordsAreIgnored() {
        XCTAssertEqual(RecallMatching.terms("kiedy mam urodziny?").map(\.word), ["urodziny"])
        XCTAssertEqual(RecallMatching.terms("what do you know about ten").map(\.word), [], "'ten' is Polish 'this' too")
    }

    func testFtsPatternUsesOnlyLettersAndDigits() throws {
        let pattern = try XCTUnwrap(RecallMatching.ftsPattern(RecallMatching.terms("code \"OR\" kod*")))
        XCTAssertTrue(pattern.contains("\"kod\"*"))
        XCTAssertFalse(pattern.contains("\"\"\""))
        XCTAssertNil(RecallMatching.ftsPattern(RecallMatching.terms("what is it")))
    }

    func testEditDistance() {
        XCTAssertEqual(RecallMatching.editDistance("dentist", "dentsit"), 1, "swap counts once")
        XCTAssertEqual(RecallMatching.editDistance("kod", "kot"), 1)
        XCTAssertEqual(RecallMatching.editDistance("", "abc"), 3)
    }
}

extension RecallMatchingTests {
    func testEditDistanceMatchesKnownValues() {
        XCTAssertEqual(RecallMatching.editDistance("kitten", "sitting"), 3)
        XCTAssertEqual(RecallMatching.editDistance("ca", "abc"), 3, "restricted swap, not full Damerau")
        XCTAssertEqual(RecallMatching.editDistance("paczkomat", "paczkomta"), 1)
        XCTAssertEqual(RecallMatching.editDistance("same", "same"), 0)
    }
}
