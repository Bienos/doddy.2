import XCTest
@testable import DoddyCore

final class OpeningPolicyTests: XCTestCase {
    private func conditions(
        sceneOn: Bool = true, listenOnOpen: Bool = false, characterArtHidden: Bool = false,
        reduceMotion: Bool = false, voiceOverRunning: Bool = false, atHome: Bool = true,
        voiceAvailable: Bool = true, microphoneAllowed: Bool = true, somethingIsOpen: Bool = false,
        firstLaunchIntroPending: Bool = false
    ) -> OpeningConditions {
        OpeningConditions(
            sceneOn: sceneOn, listenOnOpen: listenOnOpen, characterArtHidden: characterArtHidden,
            reduceMotion: reduceMotion, voiceOverRunning: voiceOverRunning, atHome: atHome,
            voiceAvailable: voiceAvailable, microphoneAllowed: microphoneAllowed,
            somethingIsOpen: somethingIsOpen, firstLaunchIntroPending: firstLaunchIntroPending)
    }

    func testFirstLaunchIntroPlaysOnlyOnceAndNeverStartsVoice() {
        let pending = conditions(firstLaunchIntroPending: true)
        XCTAssertEqual(OpeningPolicy.decide(pending, trigger: .coldLaunch), .scene(reducedMotion: false, thenListen: false))
        XCTAssertEqual(OpeningPolicy.decide(pending, trigger: .returned(after: 3600)), .nothing)
        XCTAssertFalse(OpeningPolicy.decide(pending, trigger: .coldLaunch).listens)
    }

    func testReducedMotionUsesCalmStillIntro() {
        XCTAssertEqual(
            OpeningPolicy.decide(conditions(reduceMotion: true, firstLaunchIntroPending: true), trigger: .coldLaunch),
            .scene(reducedMotion: true, thenListen: false))
    }

    func testFirstLaunchCanSkipAnimationForArtOrVoiceOverSettings() {
        XCTAssertEqual(OpeningPolicy.decide(conditions(sceneOn: false, firstLaunchIntroPending: true), trigger: .coldLaunch), .nothing)
        XCTAssertEqual(OpeningPolicy.decide(conditions(characterArtHidden: true, firstLaunchIntroPending: true), trigger: .coldLaunch), .nothing)
        XCTAssertEqual(OpeningPolicy.decide(conditions(voiceOverRunning: true, firstLaunchIntroPending: true), trigger: .coldLaunch), .nothing)
    }

    func testReturningUserGoesStraightHomeUnlessListeningWasExplicitlyEnabled() {
        XCTAssertEqual(OpeningPolicy.decide(conditions(), trigger: .coldLaunch), .nothing)
        XCTAssertEqual(OpeningPolicy.decide(conditions(), trigger: .returned(after: 3600)), .nothing)
        XCTAssertEqual(OpeningPolicy.decide(conditions(listenOnOpen: true), trigger: .returned(after: 3600)), .listenOnly)
        XCTAssertFalse(OpeningPolicy.decide(conditions(listenOnOpen: true, microphoneAllowed: false), trigger: .returned(after: 3600)).listens)
    }

    func testOpeningNeverOverlaysAnotherScreen() {
        XCTAssertEqual(OpeningPolicy.decide(conditions(atHome: false, firstLaunchIntroPending: true), trigger: .coldLaunch), .nothing)
        XCTAssertEqual(OpeningPolicy.decide(conditions(somethingIsOpen: true, firstLaunchIntroPending: true), trigger: .coldLaunch), .nothing)
    }
}
