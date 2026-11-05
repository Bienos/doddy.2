import XCTest
@testable import DoddyCore

/// OP-019, ADR-364: "Listen until I finish". The user ends the turn; only the words are sent.
final class LongTurnTests: XCTestCase {
    func testOnlyWordsAreSentTidiedAndCut() {
        XCTAssertNil(LongTurn.message("  \n\t "), "no words: nothing to send")
        XCTAssertEqual(LongTurn.message("  So  I was thinking\n about the trip  "), "So I was thinking about the trip")

        let long = Array(repeating: "word", count: 2000).joined(separator: " ")
        let cut = LongTurn.message(long)!
        XCTAssertLessThanOrEqual(cut.count, LongTurn.maxCharacters)
        XCTAssertTrue(cut.hasSuffix("word…"), "cut at a word and marked")
    }

    func testTheLanguageFollowsTheConversationAndNeverGuessesAnother() {
        let onDevice = ["en-GB", "pl-PL"]
        XCTAssertEqual(LongTurn.locale(conversationCode: "pl", onDevice: onDevice), "pl-PL")
        XCTAssertEqual(LongTurn.locale(conversationCode: nil, onDevice: onDevice), "en-GB", "automatic: the iPhone's first")
        XCTAssertNil(LongTurn.locale(conversationCode: "de", onDevice: onDevice), "German set but not on this iPhone: not written out in English")
        XCTAssertNil(LongTurn.locale(conversationCode: nil, onDevice: []))
    }

    func testOnlyAFailedWriteOutCanBeTriedAgainAndEveryProblemHasPolish() {
        let all: [LongTurnProblem] = [.nothingHeard, .tooShort, .notOnDevice, .notAllowed, .writeOutFailed, .recordingFailed, .couldNotSend]
        for problem in all {
            XCTAssertEqual(LongTurn.draft(for: problem).canWriteOutAgain, problem == .writeOutFailed, "\(problem)")
            XCTAssertNotEqual(LongTurn.problem(problem, .polish), LongTurn.problem(problem, .english))
        }
        XCTAssertEqual(LongTurn.draft(for: .couldNotSend, text: "Hi").text, "Hi", "what couldn't be sent is kept")
        for line in [LongTurn.startLabel, LongTurn.listeningTitle, LongTurn.listeningDetail, LongTurn.writingOut] {
            XCTAssertNotEqual(line(.polish), line(.english))
        }
        XCTAssertEqual(LongTurn.listeningTitle(.english), "I'm listening. Tap Done when you've finished.")
    }

    func testTheClock() {
        XCTAssertEqual(LongTurn.clock(42.9), "0:42")
        XCTAssertEqual(LongTurn.clock(LongTurn.maxSeconds), "3:00")
    }

    func testTheIndicatorSaysTheIPhoneIsRecordingNotMuted() throws {
        let snapshot = MicrophoneSnapshot(conversation: .longTurn)
        XCTAssertEqual(snapshot.open, [.conversation], "Stop listening ends it")
        let indicator = try XCTUnwrap(ListeningIndicator.current(snapshot))
        XCTAssertEqual(indicator.title(.english), "Listening until you finish")
        XCTAssertFalse(indicator.title(.english).contains("muted"))
        XCTAssertNotEqual(indicator.detail(.polish), indicator.detail(.english))
    }
}
