import XCTest
@testable import DoddyCore

final class OpeningPolicyTests: XCTestCase {
    private func conditions(
        listenOnOpen: Bool = false, atHome: Bool = true, voiceAvailable: Bool = true,
        microphoneAllowed: Bool = true, somethingIsOpen: Bool = false, openedByURL: Bool = false
    ) -> OpeningConditions {
        OpeningConditions(
            listenOnOpen: listenOnOpen, atHome: atHome, voiceAvailable: voiceAvailable,
            microphoneAllowed: microphoneAllowed, somethingIsOpen: somethingIsOpen, openedByURL: openedByURL)
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

    // MARK: A link goes where it points

    func testALinkNeverAlsoStartsListening() {
        for trigger in [OpeningTrigger.coldLaunch, .returned(after: 3600)] {
            XCTAssertEqual(OpeningPolicy.decide(conditions(listenOnOpen: true, openedByURL: true), trigger: trigger), .nothing,
                           "a link opened Doddy: the conversation doesn't start on top of where it points")
            XCTAssertEqual(OpeningPolicy.decide(conditions(listenOnOpen: true, openedByURL: false), trigger: trigger), .listenOnly)
        }
    }

    func testTheShortFormAgreesWithTheDecision() {
        XCTAssertTrue(OpeningPolicy.shouldListen(openedByURL: false))
        XCTAssertFalse(OpeningPolicy.shouldListen(openedByURL: true))
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNothingNotedMeansNoLinkOpenedTheApp() {
        var note = LinkOpenNote()
        XCTAssertFalse(note.take(for: .coldLaunch, now: now))
        XCTAssertFalse(note.take(for: .returned(after: 3600), now: now))
    }

    func testALinkBeforeTheLaunchDecisionCountsHoweverLongTheLaunchTakes() {
        var note = LinkOpenNote()
        note.linkOpened(at: now)
        // The first-launch welcome or a slow start can hold the decision back for minutes.
        XCTAssertTrue(note.take(for: .coldLaunch, now: now.addingTimeInterval(20 * 60)))
    }

    func testALinkCountsForTheNextDecisionOnly() {
        var note = LinkOpenNote()
        note.linkOpened(at: now)
        XCTAssertTrue(note.take(for: .returned(after: 3600), now: now.addingTimeInterval(1)))
        XCTAssertFalse(note.take(for: .returned(after: 3600), now: now.addingTimeInterval(2)), "used up: the next return is an ordinary one")
    }

    func testAnOldLinkDoesNotSuppressALaterReturn() {
        var note = LinkOpenNote()
        note.linkOpened(at: now)
        // The link arrived while Doddy was in front; much later the person comes back from the background.
        XCTAssertFalse(note.take(for: .returned(after: 3600), now: now.addingTimeInterval(LinkOpenNote.validFor + 1)))
        XCTAssertFalse(note.take(for: .returned(after: 3600), now: now.addingTimeInterval(LinkOpenNote.validFor + 2)), "and it is gone")
    }

    func testTheLatestLinkWins() {
        var note = LinkOpenNote()
        note.linkOpened(at: now)
        note.linkOpened(at: now.addingTimeInterval(100))
        XCTAssertTrue(note.take(for: .returned(after: 3600), now: now.addingTimeInterval(100 + LinkOpenNote.validFor)))
    }

    func testAClockThatWentBackwardsStillCountsTheLink() {
        var note = LinkOpenNote()
        note.linkOpened(at: now)
        XCTAssertTrue(note.take(for: .returned(after: 3600), now: now.addingTimeInterval(-30)))
    }
}
