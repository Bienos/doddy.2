import XCTest

@testable import DoddyCore

final class DictationRulesTests: XCTestCase {
    func testSpokenWordsGoInAnEmptyBox() {
        XCTAssertEqual(DictationRules.merged(base: "", spoken: "  buy milk "), "buy milk")
        XCTAssertEqual(DictationRules.merged(base: "  \n", spoken: "buy milk"), "buy milk")
    }

    func testSpokenWordsFollowWhatWasTyped() {
        XCTAssertEqual(DictationRules.merged(base: "Remind me", spoken: "to call Anna"), "Remind me to call Anna")
        XCTAssertEqual(DictationRules.merged(base: "Remind me ", spoken: "to call Anna"), "Remind me to call Anna")
    }

    func testALaterGuessReplacesTheEarlierOneInsteadOfStackingOnIt() {
        let base = "Remind me"
        let first = DictationRules.merged(base: base, spoken: "to call")
        let second = DictationRules.merged(base: base, spoken: "to call Anna")
        XCTAssertEqual(first, "Remind me to call")
        XCTAssertEqual(second, "Remind me to call Anna")
    }

    func testHearingNothingLeavesTheBoxAsItWas() {
        XCTAssertEqual(DictationRules.merged(base: "Hello", spoken: "   "), "Hello")
        XCTAssertEqual(DictationRules.merged(base: "", spoken: ""), "")
    }

    func testADictationHasALimit() {
        XCTAssertEqual(DictationRules.maxSeconds, 120)
    }
}
