import DoddyCore
import XCTest

/// One owner of the audio session (ADR-695): who may take it from whom, and when it may be switched off.
final class AudioSessionPolicyTests: XCTestCase {
    private let listeners: [AudioUse] = [.conversation, .captureRecording, .memoRecording, .dictation]
    private let players: [AudioUse] = [.memoPlayback, .recordingPlayback, .readAloud, .voicePreview]

    func testEveryUseIsEitherListeningOrPlaying() {
        XCTAssertEqual(Set(listeners + players), Set(AudioUse.allCases))
        XCTAssertTrue(listeners.allSatisfy(\.usesMicrophone))
        XCTAssertFalse(players.contains(where: \.usesMicrophone))
        XCTAssertEqual(Set(AudioSessionPolicy.precedence), Set(AudioUse.allCases), "every use can be named in a refusal")
    }

    func testWithNothingRunningEveryUseGoesAhead() {
        for use in AudioUse.allCases {
            XCTAssertEqual(AudioSessionPolicy.claim(use, active: []), .go(stopping: []), "\(use)")
        }
    }

    func testDictationDuringAConversationIsRefused() {
        // The bug of the 29 Oct review: dictation in Messages took the conversation's microphone.
        XCTAssertEqual(AudioSessionPolicy.claim(.dictation, active: [.conversation]), .refused(by: .conversation))
    }

    func testAConversationIsRefusedWhileDictationOrAMemoRecordingListens() {
        XCTAssertEqual(AudioSessionPolicy.claim(.conversation, active: [.dictation]), .refused(by: .dictation))
        XCTAssertEqual(AudioSessionPolicy.claim(.conversation, active: [.memoRecording]), .refused(by: .memoRecording))
        XCTAssertEqual(AudioSessionPolicy.claim(.conversation, active: [.captureRecording]), .refused(by: .captureRecording))
    }

    func testNothingTakesTheMicrophoneFromAnythingThatListens() {
        for holder in listeners {
            for asker in AudioUse.allCases where !(asker == .conversation && holder == .conversation) {
                XCTAssertEqual(AudioSessionPolicy.claim(asker, active: [holder]), .refused(by: holder), "\(asker) while \(holder)")
            }
        }
    }

    func testAPlaybackDuringAConversationIsRefusedNotPlayed() {
        // ADR-676: playing switches the session to playback only, which deafens the conversation.
        for player in players {
            XCTAssertEqual(AudioSessionPolicy.claim(player, active: [.conversation]), .refused(by: .conversation), "\(player)")
        }
    }

    func testAConversationAskingIgnoresConversationsAndLeavesThemToTheGate() {
        XCTAssertEqual(AudioSessionPolicy.claim(.conversation, active: [.conversation]), .go(stopping: []))
        XCTAssertEqual(AudioSessionPolicy.claim(.conversation, active: [.conversation, .dictation]), .refused(by: .dictation))
    }

    func testWhatPlaysStopsForSomethingThatListens() {
        XCTAssertEqual(AudioSessionPolicy.claim(.conversation, active: [.readAloud, .memoPlayback]),
                       .go(stopping: [.readAloud, .memoPlayback]))
        XCTAssertEqual(AudioSessionPolicy.claim(.dictation, active: [.voicePreview]), .go(stopping: [.voicePreview]))
    }

    func testOneThingPlaysAtATime() {
        XCTAssertEqual(AudioSessionPolicy.claim(.readAloud, active: [.memoPlayback]), .go(stopping: [.memoPlayback]))
        // Another memo player playing is stopped for this one.
        XCTAssertEqual(AudioSessionPolicy.claim(.memoPlayback, active: [.memoPlayback]), .go(stopping: [.memoPlayback]))
    }

    func testTwoOfTheSameListenerAreRefused() {
        XCTAssertEqual(AudioSessionPolicy.claim(.memoRecording, active: [.memoRecording]), .refused(by: .memoRecording))
        XCTAssertEqual(AudioSessionPolicy.claim(.dictation, active: [.dictation]), .refused(by: .dictation))
    }

    func testTheRefusalNamesTheFirstInPrecedence() {
        XCTAssertEqual(AudioSessionPolicy.claim(.memoPlayback, active: [.dictation, .conversation, .readAloud]),
                       .refused(by: .conversation))
        XCTAssertEqual(AudioSessionPolicy.claim(.readAloud, active: [.dictation, .captureRecording]),
                       .refused(by: .captureRecording))
    }

    func testTheSessionIsSwitchedOffOnlyWhenNothingElseUsesIt() {
        // Dictation stopping during a conversation must not switch the conversation's audio off.
        XCTAssertFalse(AudioSessionPolicy.mayDeactivate(stillActive: [.conversation]))
        XCTAssertFalse(AudioSessionPolicy.mayDeactivate(stillActive: [.readAloud]))
        XCTAssertTrue(AudioSessionPolicy.mayDeactivate(stillActive: []))
    }
}
