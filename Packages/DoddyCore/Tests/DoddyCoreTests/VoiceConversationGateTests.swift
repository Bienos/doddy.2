import XCTest
@testable import DoddyCore

final class VoiceConversationGateTests: XCTestCase {
    private final class Conversation {
        var busy = false
    }

    private let isBusy: (Conversation) -> Bool = { $0.busy }

    func testTheFirstConversationGoesAhead() {
        var gate = VoiceConversationGate<Conversation>()
        let screen = Conversation()
        XCTAssertEqual(gate.request(screen, isBusy: isBusy), .go)
        XCTAssertNil(gate.running(isBusy: isBusy), "not busy yet: nothing is running")
        screen.busy = true
        XCTAssertTrue(gate.running(isBusy: isBusy) === screen)
    }

    func testASecondConversationIsRefusedWhileTheFirstIsStartingOrLive() {
        var gate = VoiceConversationGate<Conversation>()
        let second = Conversation()
        let screen = Conversation()
        XCTAssertEqual(gate.request(second, isBusy: isBusy), .go)
        second.busy = true
        XCTAssertEqual(gate.request(screen, isBusy: isBusy), .anotherIsRunning)
        XCTAssertTrue(gate.running(isBusy: isBusy) === second, "the refused one never becomes the holder")
    }

    func testAnEndedConversationNeverKeepsTheGateShut() {
        var gate = VoiceConversationGate<Conversation>()
        let first = Conversation()
        let second = Conversation()
        _ = gate.request(first, isBusy: isBusy)
        first.busy = true
        first.busy = false  // ended, failed or never got going: nobody had to tell the gate
        XCTAssertEqual(gate.request(second, isBusy: isBusy), .go)
        XCTAssertNil(gate.running(isBusy: isBusy))
    }

    func testAFreedConversationNeverKeepsTheGateShut() {
        var gate = VoiceConversationGate<Conversation>()
        var first: Conversation? = Conversation()
        _ = gate.request(first!, isBusy: isBusy)
        first!.busy = true
        first = nil
        let second = Conversation()
        XCTAssertEqual(gate.request(second, isBusy: isBusy), .go)
    }

    func testTheSameConversationMayAskAgain() {
        var gate = VoiceConversationGate<Conversation>()
        let screen = Conversation()
        _ = gate.request(screen, isBusy: isBusy)
        screen.busy = true
        XCTAssertEqual(gate.request(screen, isBusy: isBusy), .go, "\"Talk again\" on the same screen")
    }

    func testAfterARefusalTheRunningOneStaysTheHolderUntilItEnds() {
        var gate = VoiceConversationGate<Conversation>()
        let second = Conversation()
        let screen = Conversation()
        _ = gate.request(second, isBusy: isBusy)
        second.busy = true
        XCTAssertEqual(gate.request(screen, isBusy: isBusy), .anotherIsRunning)
        second.busy = false
        XCTAssertEqual(gate.request(screen, isBusy: isBusy), .go)
        screen.busy = true
        XCTAssertEqual(gate.request(second, isBusy: isBusy), .anotherIsRunning)
    }
}
