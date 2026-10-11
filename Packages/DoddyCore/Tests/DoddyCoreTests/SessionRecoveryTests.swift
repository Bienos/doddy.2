import XCTest
@testable import DoddyCore

/// ADR-330 (OP-023): a voice conversation that drops is never shown as a normal end, what Doddy
/// last heard is offered as a draft (not a note), and the next conversation is told it was cut off.
final class SessionRecoveryTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let t0 = Date(timeIntervalSince1970: 1_791_630_000)

    private func line(_ user: Bool, _ text: String) -> ConversationLog.Line { ConversationLog.Line(fromUser: user, text: text) }

    // MARK: How it ended

    func testOnlyTheOtherSideClosingIsADrop() {
        XCTAssertEqual(VoiceSessionEnd.afterDisconnect(.agent, userAsked: false), .dropped(.connectionLost))
        XCTAssertEqual(VoiceSessionEnd.afterDisconnect(.user, userAsked: false), .doddyEnded, "the agent's end_call ends it through the SDK's own end")
        XCTAssertEqual(VoiceSessionEnd.afterDisconnect(.error, userAsked: false), .dropped(.error("")))
        for kind in [VoiceSessionEnd.Disconnect.user, .agent, .error] {
            XCTAssertEqual(VoiceSessionEnd.afterDisconnect(kind, userAsked: true), .userEnded, "after End, any disconnect is the user's end")
        }
        XCTAssertTrue(VoiceSessionEnd.dropped(.offline).isDrop)
        XCTAssertFalse(VoiceSessionEnd.quietTimeout.isDrop)
        XCTAssertEqual(
            [VoiceSessionEnd.userEnded, .doddyEnded, .quietTimeout, .dropped(.offline), .dropped(.connectionLost), .dropped(.error("x"))].map(\.code),
            ["user", "doddy", "quiet", "dropped-offline", "dropped-connection", "dropped-error"])
    }

    func testADropAfterListeningIsNeverCouldntConnectOrEnded() {
        XCTAssertEqual(SessionRecovery.status(.userEnded, connected: true).title, "Conversation ended")
        XCTAssertEqual(SessionRecovery.status(.doddyEnded, connected: true).title, "Conversation ended")
        let dropped = SessionRecovery.status(.dropped(.connectionLost), connected: true)
        XCTAssertEqual(dropped.title, "The conversation dropped")
        XCTAssertEqual(dropped.detail, "It stopped before you ended it, so Doddy didn't hear anything after that. Nothing was saved because of it.")
        XCTAssertEqual(SessionRecovery.status(.dropped(.error("Server said no")), connected: true).title, "The conversation dropped")
        // Before Doddy was ever listening it really is "Couldn't connect", with the reason when known.
        XCTAssertEqual(SessionRecovery.status(.dropped(.error("Token server down.")), connected: false).title, "Couldn't connect")
        XCTAssertEqual(SessionRecovery.status(.dropped(.error("Token server down.")), connected: false).detail, "Token server down.")
        XCTAssertEqual(SessionRecovery.status(.dropped(.offline), connected: true).title, "You're offline")
    }

    // MARK: The draft

    func testTheDraftIsWhatDoddyHeardAndHadntAnswered() throws {
        let lines = [line(true, "Remind me about the dentist"), line(false, "Sure, when?"), line(true, "Thursday at 3"), line(true, "  and bring the X-rays ")]
        let draft = try XCTUnwrap(SessionRecovery.draft(lines: lines, pendingNote: nil, end: .dropped(.connectionLost), endedAt: t0))
        XCTAssertEqual(draft.unanswered, ["Thursday at 3", "and bring the X-rays"])
        XCTAssertEqual(draft.text, "Thursday at 3 and bring the X-rays")
        XCTAssertNil(draft.pendingNote)
    }

    func testANoteDoddyWasAskingAboutComesFirst() throws {
        let lines = [line(true, "My locker code is 4412"), line(false, "Shall I save that?")]
        let draft = try XCTUnwrap(SessionRecovery.draft(lines: lines, pendingNote: "Locker code: 4412", end: .dropped(.offline), endedAt: t0))
        XCTAssertEqual(draft.unanswered, [], "Doddy had answered")
        XCTAssertEqual(draft.text, "Locker code: 4412")
    }

    func testNoDraftAfterANormalEndOrWhenNothingWasLeft() {
        let lines = [line(true, "Thursday at 3")]
        XCTAssertNil(SessionRecovery.draft(lines: lines, pendingNote: "x", end: .userEnded, endedAt: t0))
        XCTAssertNil(SessionRecovery.draft(lines: lines, pendingNote: nil, end: .doddyEnded, endedAt: t0))
        XCTAssertNil(SessionRecovery.draft(lines: [line(true, "Hi"), line(false, "Hello!")], pendingNote: "  ", end: .dropped(.connectionLost), endedAt: t0))
        XCTAssertNil(SessionRecovery.draft(lines: [], pendingNote: nil, end: .dropped(.connectionLost), endedAt: t0))
        // Nothing Doddy said is ever offered as the user's words.
        XCTAssertNil(SessionRecovery.draft(lines: [line(false, "Your code is 4412")], pendingNote: nil, end: .dropped(.connectionLost), endedAt: t0))
    }

    // MARK: Carrying on

    private func log(_ ended: String?, endedAt: Date, lines: [ConversationLog.Line]? = nil) -> ConversationLog {
        ConversationLog(startedAt: endedAt - 120, endedAt: endedAt, lines: lines ?? [line(true, "Thursday at 3")], ended: ended)
    }

    func testTheNextConversationIsToldItWasCutOffForAWhile() throws {
        let dropped = log("dropped-connection", endedAt: t0)
        let note = try XCTUnwrap(SessionRecovery.resumeNote(newest: dropped, now: t0 + 60, timeZone: utc))
        XCTAssertTrue(note.contains("was cut off at"), note)
        XCTAssertTrue(note.contains("Do not assume you heard anything after them"))
        XCTAssertNil(SessionRecovery.resumeNote(newest: dropped, now: t0 + SessionRecovery.resumeWindow + 1, timeZone: utc), "too long ago")
        XCTAssertNil(SessionRecovery.resumeNote(newest: log("user", endedAt: t0), now: t0 + 60), "ended normally")
        XCTAssertNil(SessionRecovery.resumeNote(newest: log(nil, endedAt: t0), now: t0 + 60), "kept before ADR-330")
        XCTAssertNil(SessionRecovery.resumeNote(newest: nil, now: t0))
    }

    func testTheNoteGoesFirstOnlyWhenTheCutOffConversationIsSent() {
        let logs = [log("user", endedAt: t0 - 3_600), log("dropped-connection", endedAt: t0)]
        let recent = VoiceContext.recentConversations(logs, timeZone: utc)
        let with = SessionRecovery.withResumeNote(recent, logs: logs, now: t0 + 30, timeZone: utc)
        XCTAssertTrue(with.text.hasPrefix("Note: the newest conversation below was cut off"))
        XCTAssertTrue(with.text.hasSuffix(recent.text))
        XCTAssertEqual(with.includedCount, recent.includedCount)

        // The dropped one is too long to be sent: no note about a conversation the agent can't see.
        let huge = [log("dropped-connection", endedAt: t0, lines: (0..<40).map { line($0 % 2 == 0, String(repeating: "word ", count: 80)) })]
        let hugeRecent = VoiceContext.recentConversations(huge, timeZone: utc)
        XCTAssertEqual(SessionRecovery.withResumeNote(hugeRecent, logs: huge, now: t0 + 30, timeZone: utc), hugeRecent)
        // The newest one ended normally: nothing added.
        let fine = [log("dropped-connection", endedAt: t0 - 60), log("doddy", endedAt: t0)]
        let fineRecent = VoiceContext.recentConversations(fine, timeZone: utc)
        XCTAssertEqual(SessionRecovery.withResumeNote(fineRecent, logs: fine, now: t0 + 30, timeZone: utc), fineRecent)
    }

    // MARK: The log records how it ended

    func testTheLogKeepsHowItEndedAndOldLogsStillLoad() throws {
        let kept = log("dropped-offline", endedAt: t0)
        let back = try JSONDecoder().decode(ConversationLog.self, from: JSONEncoder().encode(kept))
        XCTAssertEqual(back.ended, "dropped-offline")
        let old = #"{"id":"6F1B2C9E-1C1A-4B6D-9F51-0B1D2C3E4F50","startedAt":781790400,"endedAt":781790460,"lines":[{"fromUser":true,"text":"Hi"}]}"#
        XCTAssertNil(try JSONDecoder().decode(ConversationLog.self, from: Data(old.utf8)).ended)
    }
}
