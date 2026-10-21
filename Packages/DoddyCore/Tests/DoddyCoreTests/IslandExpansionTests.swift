@testable import DoddyCore
import XCTest

/// ADR-566: when the conversation's island asks iOS to open up into the big island.
final class IslandExpansionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testTheGreetingOpensTheIslandOnce() {
        var rule = IslandExpansion(isOn: true)
        XCTAssertTrue(rule.doddyStartedSpeaking(at: start, appOnScreen: false), "his first words open it")
        // The provider flips between speaking and listening inside one answer: not again.
        XCTAssertFalse(rule.doddyStartedSpeaking(at: start.addingTimeInterval(30), appOnScreen: false))
    }

    func testEachAnswerToTheUserOpensItAgain() {
        var rule = IslandExpansion(isOn: true)
        XCTAssertTrue(rule.doddyStartedSpeaking(at: start, appOnScreen: false))
        rule.userSpoke()
        XCTAssertTrue(rule.doddyStartedSpeaking(at: start.addingTimeInterval(25), appOnScreen: false),
                      "the answer to \"how many people live on Earth?\" opens it")
        XCTAssertFalse(rule.doddyStartedSpeaking(at: start.addingTimeInterval(60), appOnScreen: false),
                       "the rest of the same answer doesn't")
    }

    func testNotWithinTheGapBecauseEachOnePlaysASound() {
        var rule = IslandExpansion(isOn: true)
        XCTAssertTrue(rule.doddyStartedSpeaking(at: start, appOnScreen: false))
        rule.userSpoke()
        XCTAssertFalse(rule.doddyStartedSpeaking(at: start.addingTimeInterval(IslandExpansion.minimumGap - 1), appOnScreen: false))
        // Still due: the next time he starts speaking after the gap, it opens.
        XCTAssertTrue(rule.doddyStartedSpeaking(at: start.addingTimeInterval(IslandExpansion.minimumGap), appOnScreen: false))
    }

    func testNeverWhileTheAppIsOnScreenAndTheTurnIsNotSpent() {
        var rule = IslandExpansion(isOn: true)
        XCTAssertFalse(rule.doddyStartedSpeaking(at: start, appOnScreen: true), "iOS doesn't show it over the app")
        // The user went to their Home Screen while Doddy was talking: the next words open it.
        XCTAssertTrue(rule.doddyStartedSpeaking(at: start.addingTimeInterval(5), appOnScreen: false))
    }

    func testSmallIslandNeverOpensIt() {
        var rule = IslandExpansion(.smallIsland)
        XCTAssertFalse(rule.isOn)
        XCTAssertFalse(rule.doddyStartedSpeaking(at: start, appOnScreen: false))
        rule.userSpoke()
        XCTAssertFalse(rule.doddyStartedSpeaking(at: start.addingTimeInterval(60), appOnScreen: false))
    }

    func testTheOtherSettingsOpenIt() {
        XCTAssertTrue(IslandExpansion(.conversation).isOn)
        // "Only open Doddy" starts no conversation from the shortcut; one started another way still opens.
        XCTAssertTrue(IslandExpansion(.openApp).isOn)
    }
}
