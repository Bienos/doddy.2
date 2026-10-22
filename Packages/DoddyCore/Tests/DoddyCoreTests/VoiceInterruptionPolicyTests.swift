import XCTest
@testable import DoddyCore

/// ADR-584: a phone call during a conversation. Short interruptions resume; anything longer ends
/// the conversation as a drop, so it never stays "listening" with a deaf microphone.
final class VoiceInterruptionPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let grace = VoiceInterruptionPolicy.resumeGraceSeconds

    func testACallStartingPausesALiveConversationOnly() {
        XCTAssertEqual(VoiceInterruptionPolicy.began(isLive: true), .markPaused)
        XCTAssertEqual(VoiceInterruptionPolicy.began(isLive: false), .ignore)
    }

    func testADeclinedCallWithinTheGraceTimeResumes() {
        XCTAssertEqual(VoiceInterruptionPolicy.ended(pausedSince: t0, shouldResume: true, now: t0 + 4, isLive: true), .resume)
        XCTAssertEqual(VoiceInterruptionPolicy.ended(pausedSince: t0, shouldResume: true, now: t0 + grace, isLive: true), .resume,
                       "exactly at the grace time still resumes")
    }

    func testAnAnsweredCallEndsTheConversationEvenWhenIOSSaysResume() {
        XCTAssertEqual(VoiceInterruptionPolicy.ended(pausedSince: t0, shouldResume: true, now: t0 + 45, isLive: true), .endAsDrop)
        XCTAssertEqual(VoiceInterruptionPolicy.ended(pausedSince: t0, shouldResume: true, now: t0 + grace + 0.5, isLive: true), .endAsDrop)
    }

    func testAnEndWithoutShouldResumeEndsTheConversation() {
        XCTAssertEqual(VoiceInterruptionPolicy.ended(pausedSince: t0, shouldResume: false, now: t0 + 2, isLive: true), .endAsDrop)
    }

    func testAnEndWithNoBeginningIsIgnored() {
        XCTAssertEqual(VoiceInterruptionPolicy.ended(pausedSince: nil, shouldResume: true, now: t0, isLive: true), .ignore)
        XCTAssertEqual(VoiceInterruptionPolicy.ended(pausedSince: nil, shouldResume: false, now: t0, isLive: true), .ignore)
    }

    func testNothingHappensToAConversationThatIsAlreadyOver() {
        XCTAssertEqual(VoiceInterruptionPolicy.ended(pausedSince: t0, shouldResume: false, now: t0 + 60, isLive: false), .ignore)
        XCTAssertEqual(VoiceInterruptionPolicy.stillPaused(pausedSince: t0, now: t0 + 60, isLive: false), .ignore)
        XCTAssertEqual(VoiceInterruptionPolicy.mediaServicesReset(isLive: false), .ignore)
    }

    func testAPauseWithNoEndIsEndedAfterTheGraceTime() {
        // iOS doesn't promise an `.ended`: the timer, or coming back to Doddy, ends it.
        XCTAssertEqual(VoiceInterruptionPolicy.stillPaused(pausedSince: t0, now: t0 + 3, isLive: true), .ignore)
        XCTAssertEqual(VoiceInterruptionPolicy.stillPaused(pausedSince: t0, now: t0 + grace, isLive: true), .ignore)
        XCTAssertEqual(VoiceInterruptionPolicy.stillPaused(pausedSince: t0, now: t0 + grace + 0.5, isLive: true), .endAsDrop)
        XCTAssertEqual(VoiceInterruptionPolicy.stillPaused(pausedSince: nil, now: t0 + 600, isLive: true), .ignore, "never paused")
    }

    func testAMediaServicesResetEndsALiveConversation() {
        XCTAssertEqual(VoiceInterruptionPolicy.mediaServicesReset(isLive: true), .endAsDrop)
    }

    func testTheGraceTimeIsShortEnoughForADeclinedCallButNotAnAnsweredOne() {
        XCTAssertGreaterThanOrEqual(grace, 5, "declining a call or dismissing Siri takes a few seconds")
        XCTAssertLessThanOrEqual(grace, 15, "nobody should come back to a deaf Doddy")
    }

    // MARK: How the end is shown and remembered

    func testTheInterruptedEndIsADropWithItsOwnCode() {
        let end = VoiceSessionEnd.dropped(.audioInterrupted)
        XCTAssertTrue(end.isDrop)
        XCTAssertEqual(end.code, "dropped-interrupted")
    }

    func testTheInterruptedEndSaysWhatHappenedInBothLanguages() {
        for connected in [true, false] {
            let english = SessionRecovery.status(.dropped(.audioInterrupted), connected: connected)
            XCTAssertEqual(english.title, "The conversation was interrupted")
            XCTAssertTrue(english.detail?.contains("phone call") == true, english.detail ?? "")
            XCTAssertFalse(english.detail?.contains("internet") == true, "an interruption is never blamed on the connection")
            let polish = SessionRecovery.status(.dropped(.audioInterrupted), connected: connected, language: .polish)
            XCTAssertEqual(polish.title, "Rozmowa została przerwana")
            XCTAssertTrue(polish.detail?.contains("połączenie telefoniczne") == true, polish.detail ?? "")
        }
    }

    func testTheNextConversationIsToldACallCutItOff() throws {
        let log = ConversationLog(
            startedAt: t0 - 120, endedAt: t0,
            lines: [ConversationLog.Line(fromUser: true, text: "Remind me about the dentist")],
            ended: VoiceSessionEnd.dropped(.audioInterrupted).code)
        let note = try XCTUnwrap(SessionRecovery.resumeNote(newest: log, now: t0 + 60, timeZone: TimeZone(identifier: "UTC")!))
        XCTAssertTrue(note.contains("was cut off at"), note)
        XCTAssertTrue(note.contains("phone call"), note)
        XCTAssertFalse(note.contains("connection dropped"), note)
    }

    func testAConnectionDropStillSaysTheConnectionDropped() throws {
        let log = ConversationLog(
            startedAt: t0 - 120, endedAt: t0,
            lines: [ConversationLog.Line(fromUser: true, text: "Hello")],
            ended: VoiceSessionEnd.dropped(.connectionLost).code)
        let note = try XCTUnwrap(SessionRecovery.resumeNote(newest: log, now: t0 + 60, timeZone: TimeZone(identifier: "UTC")!))
        XCTAssertTrue(note.contains("the connection dropped"), note)
    }
}
