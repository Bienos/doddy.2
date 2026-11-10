import XCTest
@testable import DoddyCore

final class OpeningPolicyTests: XCTestCase {
    private func conditions(
        listenOnOpen: Bool = false, atHome: Bool = true, voiceAvailable: Bool = true,
        microphoneAllowed: Bool = true, somethingIsOpen: Bool = false
    ) -> OpeningConditions {
        OpeningConditions(
            listenOnOpen: listenOnOpen, atHome: atHome, voiceAvailable: voiceAvailable,
            microphoneAllowed: microphoneAllowed, somethingIsOpen: somethingIsOpen)
    }

    func testOpeningTheAppGoesStraightHomeUnlessListeningWasExplicitlyEnabled() {
        XCTAssertEqual(OpeningPolicy.decide(conditions(), trigger: .coldLaunch), .nothing)
        XCTAssertEqual(OpeningPolicy.decide(conditions(), trigger: .returned(after: 3600)), .nothing)
        XCTAssertEqual(OpeningPolicy.decide(conditions(listenOnOpen: true), trigger: .coldLaunch), .listenOnly)
        XCTAssertEqual(OpeningPolicy.decide(conditions(listenOnOpen: true), trigger: .returned(after: 3600)), .listenOnly)
    }

    func testListeningNeedsTheMicrophoneAndVoice() {
        XCTAssertFalse(OpeningPolicy.decide(conditions(listenOnOpen: true, microphoneAllowed: false), trigger: .returned(after: 3600)).listens)
        XCTAssertFalse(OpeningPolicy.decide(conditions(listenOnOpen: true, voiceAvailable: false), trigger: .coldLaunch).listens)
    }

    func testAQuickSwitchAwayAndBackIsNotAnOpening() {
        let after = OpeningPolicy.replayAfter - 1
        XCTAssertEqual(OpeningPolicy.decide(conditions(listenOnOpen: true), trigger: .returned(after: after)), .nothing)
    }

    func testOpeningNeverOverlaysAnotherScreen() {
        XCTAssertEqual(OpeningPolicy.decide(conditions(listenOnOpen: true, atHome: false), trigger: .coldLaunch), .nothing)
        XCTAssertEqual(OpeningPolicy.decide(conditions(listenOnOpen: true, somethingIsOpen: true), trigger: .coldLaunch), .nothing)
    }
}
