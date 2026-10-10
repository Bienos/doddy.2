import XCTest
@testable import DoddyCore

final class OpeningPolicyTests: XCTestCase {
    /// Everything on, nothing in the way: the opening plays and a conversation follows.
    private func conditions(
        sceneOn: Bool = true, listenOnOpen: Bool = true, characterArtHidden: Bool = false,
        reduceMotion: Bool = false, voiceOverRunning: Bool = false, atHome: Bool = true,
        voiceAvailable: Bool = true, microphoneDenied: Bool = false, somethingIsOpen: Bool = false
    ) -> OpeningConditions {
        OpeningConditions(
            sceneOn: sceneOn, listenOnOpen: listenOnOpen, characterArtHidden: characterArtHidden,
            reduceMotion: reduceMotion, voiceOverRunning: voiceOverRunning, atHome: atHome,
            voiceAvailable: voiceAvailable, microphoneDenied: microphoneDenied, somethingIsOpen: somethingIsOpen)
    }

    func testWithListeningOffTheOpeningPlaysAndNothingListens() {
        // Both switches are on by default (the app's OpeningPreferences); this is listening turned off.
        let decision = OpeningPolicy.decide(conditions(listenOnOpen: false), trigger: .coldLaunch)
        XCTAssertEqual(decision, .scene(reducedMotion: false, thenListen: false))
        XCTAssertFalse(decision.listens)
        XCTAssertTrue(decision.playsScene)
    }

    func testListeningOnOpenNeedsTheSwitchVoiceAndTheMicrophone() {
        XCTAssertEqual(OpeningPolicy.decide(conditions(), trigger: .coldLaunch), .scene(reducedMotion: false, thenListen: true))
        XCTAssertEqual(OpeningPolicy.decide(conditions(voiceAvailable: false), trigger: .coldLaunch), .scene(reducedMotion: false, thenListen: false))
        XCTAssertEqual(OpeningPolicy.decide(conditions(microphoneDenied: true), trigger: .coldLaunch), .scene(reducedMotion: false, thenListen: false))
        XCTAssertEqual(OpeningPolicy.decide(conditions(sceneOn: false), trigger: .coldLaunch), .listenOnly)
        XCTAssertEqual(OpeningPolicy.decide(conditions(sceneOn: false, listenOnOpen: false), trigger: .coldLaunch), .nothing)
        XCTAssertEqual(OpeningPolicy.decide(conditions(sceneOn: false, microphoneDenied: true), trigger: .coldLaunch), .nothing)
    }

    func testTheSceneGivesWayToAccessibilitySettings() {
        XCTAssertEqual(OpeningPolicy.decide(conditions(reduceMotion: true), trigger: .coldLaunch), .scene(reducedMotion: true, thenListen: true))
        XCTAssertEqual(OpeningPolicy.decide(conditions(characterArtHidden: true), trigger: .coldLaunch), .listenOnly)
        XCTAssertEqual(OpeningPolicy.decide(conditions(voiceOverRunning: true), trigger: .coldLaunch), .listenOnly)
        XCTAssertEqual(OpeningPolicy.decide(conditions(listenOnOpen: false, voiceOverRunning: true), trigger: .coldLaunch), .nothing)
    }

    func testNothingPlaysOverOnboardingOrAnotherScreen() {
        XCTAssertEqual(OpeningPolicy.decide(conditions(atHome: false), trigger: .coldLaunch), .nothing)
        XCTAssertEqual(OpeningPolicy.decide(conditions(somethingIsOpen: true), trigger: .coldLaunch), .nothing)
    }

    func testAQuickReturnIsNotAnOpening() {
        XCTAssertEqual(OpeningPolicy.decide(conditions(), trigger: .returned(after: 30)), .nothing)
        XCTAssertEqual(OpeningPolicy.decide(conditions(), trigger: .returned(after: OpeningPolicy.replayAfter - 1)), .nothing)
        XCTAssertEqual(OpeningPolicy.decide(conditions(), trigger: .returned(after: OpeningPolicy.replayAfter)), .scene(reducedMotion: false, thenListen: true))
        XCTAssertEqual(OpeningPolicy.decide(conditions(), trigger: .returned(after: 3600)), .scene(reducedMotion: false, thenListen: true))
        XCTAssertEqual(OpeningPolicy.replayAfter, 300)
    }
}
