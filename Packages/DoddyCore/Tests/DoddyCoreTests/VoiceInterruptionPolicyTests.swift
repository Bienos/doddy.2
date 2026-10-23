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

    // MARK: What Doddy says first after a call cut the conversation off (ADR-584)

    private let utc = TimeZone(identifier: "UTC")!

    private func cutByCall(_ lines: [ConversationLog.Line], endedAt: Date? = nil, ended: String? = nil) -> ConversationLog {
        ConversationLog(startedAt: (endedAt ?? t0) - 120, endedAt: endedAt ?? t0, lines: lines,
                        ended: ended ?? VoiceSessionEnd.dropped(.audioInterrupted).code)
    }

    private func user(_ text: String) -> ConversationLog.Line { ConversationLog.Line(fromUser: true, text: text) }
    private func doddy(_ text: String) -> ConversationLog.Line { ConversationLog.Line(fromUser: false, text: text) }

    func testItNamesWhereTheConversationStoppedInTheUsersOwnWords() throws {
        let log = cutByCall([user("Remind me about the dentist on Thursday"), doddy("Sure, what time?"), user("Maybe around three in the afternoon")])
        let line = try XCTUnwrap(SessionRecovery.interruptedOpening(logs: [log], now: t0 + 60, polish: false, timeZone: utc))
        XCTAssertEqual(line, "Sorry, the call cut us off. We were on “Maybe around three in the afternoon”. Want to carry on from there?")
    }

    func testItSpeaksPolishWhenTheConversationLanguageIsPolish() throws {
        let log = cutByCall([user("Przypomnij mi o dentyście w czwartek")])
        let line = try XCTUnwrap(SessionRecovery.interruptedOpening(logs: [log], now: t0 + 60, polish: true, timeZone: utc))
        XCTAssertEqual(line, "Przepraszam, rozmowę przerwał telefon. Skończyliśmy na „Przypomnij mi o dentyście w czwartek”. Chcesz kontynuować?")
    }

    func testAShortLastLineIsSkippedForTheLastRealOne() throws {
        let log = cutByCall([user("Plan the trip to Rome for next month"), doddy("Which days?"), user("Yes"), user("ok")])
        let line = try XCTUnwrap(SessionRecovery.interruptedOpening(logs: [log], now: t0 + 60, polish: false, timeZone: utc))
        XCTAssertTrue(line.contains("“Plan the trip to Rome for next month”"), line)
    }

    func testWithNothingToQuoteItOnlySaysTheCallCutItOff() throws {
        for lines in [[user("Hello"), doddy("Hi, what's up?")], [user("yes please"), doddy("Done.")]] {
            let line = try XCTUnwrap(SessionRecovery.interruptedOpening(logs: [cutByCall(lines)], now: t0 + 60, polish: false, timeZone: utc))
            XCTAssertEqual(line, "Sorry, the call cut us off. Want to start again?", "no memory is claimed when there is none")
        }
        let polish = try XCTUnwrap(SessionRecovery.interruptedOpening(
            logs: [cutByCall([user("Cześć"), doddy("Hej, co słychać?")])], now: t0 + 60, polish: true, timeZone: utc))
        XCTAssertEqual(polish, "Przepraszam, rozmowę przerwał telefon. Chcesz zacząć od nowa?")
        // A conversation with no lines is never kept, so it is never told to the agent or named here.
        XCTAssertNil(SessionRecovery.interruptedOpening(logs: [cutByCall([])], now: t0 + 60, polish: false, timeZone: utc))
    }

    func testALongLastLineIsCutAtAWord() throws {
        let long = (1...40).map { "word\($0)" }.joined(separator: " ")
        let line = try XCTUnwrap(SessionRecovery.interruptedOpening(logs: [cutByCall([user(long)])], now: t0 + 60, polish: false, timeZone: utc))
        let quoted = try XCTUnwrap(line.split(separator: "“").last?.split(separator: "”").first)
        XCTAssertLessThanOrEqual(quoted.count, SessionRecovery.maxQuoteCharacters + 1, String(quoted))
        XCTAssertTrue(quoted.hasSuffix("…"), String(quoted))
        XCTAssertFalse(quoted.dropLast().hasSuffix("wor"), "cut at a word, not in the middle of one: \(quoted)")
    }

    func testQuotesBracketsAndLineBreaksAreRemovedBecauseTheLineIsSpokenAndSentAsAnInstruction() throws {
        let log = cutByCall([user("Say \"hello\" <b>to</b> {Anna}\nplease now")])
        let line = try XCTUnwrap(SessionRecovery.interruptedOpening(logs: [log], now: t0 + 60, polish: false, timeZone: utc))
        let quoted = try XCTUnwrap(line.split(separator: "“").last?.split(separator: "”").first)
        for bad in ["\"", "<", ">", "{", "}", "\n", "\\"] {
            XCTAssertFalse(quoted.contains(bad), "\(bad) in \(quoted)")
        }
        XCTAssertEqual(quoted, "Say hello b to /b Anna please now")
    }

    func testOnlyAnInterruptionByACallGetsThisOpening() {
        let lines = [user("Remind me about the dentist on Thursday")]
        for ended in ["user", "doddy", "stopped", "dropped-connection", "dropped-offline", "dropped-error", nil] {
            XCTAssertNil(SessionRecovery.interruptedOpening(logs: [cutByCall(lines, ended: ended ?? "")], now: t0 + 60, polish: false, timeZone: utc),
                         "ended: \(ended ?? "nil")")
        }
        let beforeADR360 = ConversationLog(startedAt: t0 - 120, endedAt: t0, lines: lines, ended: nil)
        XCTAssertNil(SessionRecovery.interruptedOpening(logs: [beforeADR360], now: t0 + 60, polish: false, timeZone: utc))
    }

    func testItIsOnlyForTheNewestConversationAndOnlyForAWhile() {
        let lines = [user("Remind me about the dentist on Thursday")]
        let cut = cutByCall(lines, endedAt: t0)
        let later = ConversationLog(startedAt: t0 + 100, endedAt: t0 + 200, lines: lines, ended: "user")
        XCTAssertNil(SessionRecovery.interruptedOpening(logs: [cut, later], now: t0 + 300, polish: false, timeZone: utc), "a newer conversation ended normally")
        XCTAssertNotNil(SessionRecovery.interruptedOpening(logs: [cut], now: t0 + SessionRecovery.resumeWindow, polish: false, timeZone: utc))
        XCTAssertNil(SessionRecovery.interruptedOpening(logs: [cut], now: t0 + SessionRecovery.resumeWindow + 1, polish: false, timeZone: utc), "too long ago")
        XCTAssertNil(SessionRecovery.interruptedOpening(logs: [cut], now: t0 - 5, polish: false, timeZone: utc), "a clock set back")
        XCTAssertNil(SessionRecovery.interruptedOpening(logs: [], now: t0, polish: false, timeZone: utc))
    }

    func testItNeverNamesWhatTheAgentIsNotAlsoToldAbout() {
        // The conversation must be among those sent next time, like the resume note's own test.
        let lines = [user("Remind me about the dentist on Thursday")]
        let cut = cutByCall(lines)
        XCTAssertNil(SessionRecovery.interruptedOpening(logs: [cut], now: t0 + 60, polish: false, timeZone: utc, maxCharacters: 5))
    }
}
