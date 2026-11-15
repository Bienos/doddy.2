import XCTest
@testable import DoddyCore

/// The voice conversation and the iPhone's lock (decision 2026-11-14-voice-mute-when-protected-data-unavailable;
/// DOD-08, DOD-11, ASK-01). With the Face ID lock on, the conversation ends when iOS says protected data is going
/// away (the iPhone locks): the microphone closes, nothing more is sent, no tool reads the person's things, a card
/// that was waiting is dropped without running, and nothing starts again by itself on the unlock. With the lock off,
/// a conversation goes on in a pocket as before. The guard only decides; `VoiceSessionController` does what it says.
final class ProtectedDataGuardTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func guardWith(available: Bool = true) -> ProtectedDataGuard {
        ProtectedDataGuard(protectedDataAvailable: available)
    }

    // MARK: the iPhone locks during a conversation

    func testTheIPhoneLockingWhileListeningEndsTheConversationOnce() {
        var lock = guardWith()
        XCTAssertEqual(lock.receive(.becameUnavailable, conversation: .running, appLockOn: true), .end(.iPhoneLocked))
        XCTAssertFalse(lock.protectedDataAvailable)
        // iOS can say it more than once; the conversation is only ended once.
        XCTAssertEqual(lock.receive(.becameUnavailable, conversation: .running, appLockOn: true), .nothing)
        XCTAssertEqual(lock.receive(.becameUnavailable, conversation: .running, appLockOn: true), .nothing)
    }

    func testTheIPhoneLockingWhileConnectingEndsTheStart() {
        var lock = guardWith()
        XCTAssertEqual(lock.receive(.becameUnavailable, conversation: .connecting, appLockOn: true), .end(.iPhoneLocked),
                       "the notes may already be on their way to the agent: the start ends too")
    }

    func testTheIPhoneLockingWithNoConversationDoesNothing() {
        var lock = guardWith()
        XCTAssertEqual(lock.receive(.becameUnavailable, conversation: .notRunning, appLockOn: true), .nothing)
        XCTAssertFalse(lock.protectedDataAvailable, "it still remembers that the iPhone is locked")
    }

    /// A conversation in a pocket, started from the island with the screen off, is a feature (ADR-577). Only a person
    /// who turned the Face ID lock on has asked for their things to stay behind it.
    func testWithTheFaceIDLockOffAConversationGoesOnWhenTheIPhoneLocks() {
        var lock = guardWith()
        XCTAssertEqual(lock.receive(.becameUnavailable, conversation: .running, appLockOn: false), .nothing)
        XCTAssertEqual(lock.receive(.becameUnavailable, conversation: .connecting, appLockOn: false), .nothing)
    }

    // MARK: the unlock

    func testUnlockingNeverResumesAnything() {
        var lock = guardWith()
        _ = lock.receive(.becameUnavailable, conversation: .running, appLockOn: true)
        XCTAssertEqual(lock.receive(.becameAvailable, conversation: .notRunning, appLockOn: true), .nothing)
        XCTAssertTrue(lock.protectedDataAvailable)
        // Not even when a conversation is somehow running at that moment.
        XCTAssertEqual(lock.receive(.becameAvailable, conversation: .running, appLockOn: true), .nothing)
        XCTAssertEqual(lock.receive(.becameAvailable, conversation: .connecting, appLockOn: true), .nothing)
    }

    func testANewConversationAfterTheUnlockEndsAgainWhenTheIPhoneLocksAgain() {
        var lock = guardWith()
        XCTAssertEqual(lock.receive(.becameUnavailable, conversation: .running, appLockOn: true), .end(.iPhoneLocked))
        _ = lock.receive(.becameAvailable, conversation: .notRunning, appLockOn: true)
        XCTAssertEqual(lock.receive(.becameUnavailable, conversation: .running, appLockOn: true), .end(.iPhoneLocked))
    }

    func testAnAvailableSignalWithoutALockChangesNothing() {
        var lock = guardWith()
        XCTAssertEqual(lock.receive(.becameAvailable, conversation: .running, appLockOn: true), .nothing)
        XCTAssertTrue(lock.protectedDataAvailable)
    }

    // MARK: a conversation that starts on a locked iPhone

    /// iOS says nothing about a lock that was already there, so the start reads its answer. The Face ID lock's own rule
    /// (`AppLockPolicy`) keeps a minute of grace after a check; the iPhone itself being locked has none.
    func testAConversationThatStartsOnALockedIPhoneEndsAtOnceWithTheFaceIDLockOn() {
        var lock = guardWith()
        XCTAssertEqual(lock.sync(protectedDataAvailable: false, conversation: .connecting, appLockOn: true), .end(.iPhoneLocked))
        XCTAssertFalse(lock.protectedDataAvailable)
        XCTAssertEqual(lock.receive(.becameUnavailable, conversation: .connecting, appLockOn: true), .nothing, "said once")
    }

    func testAConversationThatStartsOnALockedIPhoneRunsWithTheFaceIDLockOff() {
        var lock = guardWith()
        XCTAssertEqual(lock.sync(protectedDataAvailable: false, conversation: .connecting, appLockOn: false), .nothing)
    }

    func testTheStartReplacesAStaleAnswerFromAnEarlierConversation() {
        // The unlock came while nothing was listening for it.
        var lock = guardWith(available: false)
        XCTAssertEqual(lock.sync(protectedDataAvailable: true, conversation: .connecting, appLockOn: true), .nothing)
        XCTAssertTrue(lock.protectedDataAvailable)
        XCTAssertEqual(lock.decide(tool: VoiceToolName.searchMemories, appLockOn: true), .run)
    }

    // MARK: tools while the iPhone is locked

    private let theirThings = [
        VoiceToolName.searchMemories, VoiceToolName.saveMemory, VoiceToolName.readList, VoiceToolName.addToList,
        VoiceToolName.lookupContact, VoiceToolName.readCalendar, VoiceToolName.createCalendarEvent,
        VoiceToolName.createReminder, VoiceToolName.findPhotos, VoiceToolName.readHealthWeek, VoiceToolName.lookAtScreen,
        VoiceToolName.proposePlan, "read_email", "a_tool_added_later",
    ]

    /// The agent is told, in words, that nothing was read: never an empty list, an empty search or a silent success.
    func testAToolThatReadsTheirThingsWhileTheIPhoneIsLockedGetsAClearNotAvailableReply() {
        var lock = guardWith()
        _ = lock.receive(.becameUnavailable, conversation: .running, appLockOn: true)
        for tool in theirThings {
            guard case .refuse(let reply) = lock.decide(tool: tool, appLockOn: true) else {
                return XCTFail("\(tool) must not run while the iPhone is locked")
            }
            XCTAssertEqual(reply, ProtectedDataPolicy.reply, tool)
            XCTAssertTrue(reply.hasPrefix("locked:"), "the agent can tell a refusal from a result")
            XCTAssertTrue(reply.contains("Nothing was looked up, saved or changed."), "it says nothing was read")
            XCTAssertFalse(reply.isEmpty)
        }
    }

    func testTheRefusalStartsBeforeTheConversationHasFinishedEnding() {
        // The notice comes first and the stop a moment later: a call that arrives in between is refused, not run.
        var lock = guardWith()
        XCTAssertEqual(lock.receive(.becameUnavailable, conversation: .running, appLockOn: true), .end(.iPhoneLocked))
        XCTAssertEqual(lock.decide(tool: VoiceToolName.searchMemories, appLockOn: true), .refuse(reply: ProtectedDataPolicy.reply))
    }

    func testSumsAndDoddysOwnTimersStillRunAndCanStillBeStopped() {
        var lock = guardWith()
        _ = lock.receive(.becameUnavailable, conversation: .running, appLockOn: true)
        for tool in [VoiceToolName.calculate, VoiceToolName.convertUnits, VoiceToolName.setTimer, VoiceToolName.stopStopwatch,
                     VoiceToolName.stopFocus, VoiceToolName.stopWindDown, VoiceToolName.stopTranslator] {
            XCTAssertEqual(lock.decide(tool: tool, appLockOn: true), .run, tool)
        }
    }

    func testEveryToolRunsWhileTheIPhoneIsUnlockedOrTheFaceIDLockIsOff() {
        var unlocked = guardWith()
        var lockedButOff = guardWith()
        _ = lockedButOff.receive(.becameUnavailable, conversation: .running, appLockOn: false)
        for tool in theirThings {
            XCTAssertEqual(unlocked.decide(tool: tool, appLockOn: true), .run, tool)
            XCTAssertEqual(lockedButOff.decide(tool: tool, appLockOn: false), .run, tool)
        }
        _ = unlocked.receive(.becameUnavailable, conversation: .notRunning, appLockOn: true)
        _ = unlocked.receive(.becameAvailable, conversation: .notRunning, appLockOn: true)
        XCTAssertEqual(unlocked.decide(tool: VoiceToolName.searchMemories, appLockOn: true), .run, "unlocked again")
    }

    // MARK: a card waiting when the iPhone locks

    /// The plan card (and any other) is dropped with the conversation: the app clears what the end clears, and a tap
    /// that comes afterwards runs nothing. The refusal above already covers the moment before that.
    func testAPlanCardWaitingWhenTheIPhoneLocksNeverRuns() {
        let card = "call_plan_1"
        let payload = PlanCardPayload(tools: [1: "set_timer", 2: "draft_email"], prepared: [:])
        var gate = PlanApprovalGate()
        gate.show(card, payload: payload, preparedAt: t0, at: t0)

        var lock = guardWith()
        XCTAssertEqual(lock.receive(.becameUnavailable, conversation: .running, appLockOn: true), .end(.iPhoneLocked))
        gate.clear() // what ending the conversation does with a waiting card (`VoiceSessionController.stop`)
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload, at: t0.addingTimeInterval(5)), .ignore,
                       "a tap on a card from before the lock runs nothing")
        XCTAssertEqual(gate.answer(.userSaid, for: card, payload: payload, at: t0.addingTimeInterval(6)), .ignore)

        // Unlocking brings nobody's card back.
        XCTAssertEqual(lock.receive(.becameAvailable, conversation: .notRunning, appLockOn: true), .nothing)
        XCTAssertEqual(gate.answer(.tapped, for: card, payload: payload, at: t0.addingTimeInterval(20)), .ignore)
    }

    func testAnAskedToolCallIsNotRunByALateYesAfterTheLock() {
        var ledger = AskLedger()
        let request = VoiceToolRequest.parse(name: VoiceToolName.saveMemory, parametersJSON: Data(#"{"text":"Gate code 4821"}"#.utf8))
        ledger.asked("call_1", request: request, needsTap: false, at: t0)

        var lock = guardWith()
        XCTAssertEqual(lock.receive(.becameUnavailable, conversation: .running, appLockOn: true), .end(.iPhoneLocked))
        ledger.clear() // `VoiceSessionController.stop`
        XCTAssertEqual(ledger.answer(.userSaid("yes"), for: "call_1", at: t0.addingTimeInterval(2)), .unknown, "no such ask any more")
        XCTAssertFalse(ledger.mayRun("call_1", request: request, at: t0.addingTimeInterval(3)))
    }

    // MARK: how the end is named and shown

    func testTheEndIsNamedAndIsNotADrop() {
        XCTAssertEqual(VoiceSessionEnd.iPhoneLocked.code, "locked")
        XCTAssertFalse(VoiceSessionEnd.iPhoneLocked.isDrop, "the iPhone locking is not the connection dropping")
        XCTAssertEqual(SessionRecovery.status(.iPhoneLocked, connected: true).title, "Stopped listening")
        XCTAssertEqual(SessionRecovery.status(.iPhoneLocked, connected: true, language: .polish).title, "Przestano słuchać")
        XCTAssertNotEqual(SessionRecovery.status(.iPhoneLocked, connected: true).detail, SessionRecovery.status(.dropped(.connectionLost), connected: true).detail)
    }

    /// What the person said last is not offered back on a screen after a lock, and no note card is kept as a draft.
    func testNothingIsKeptAsADraftAfterTheLock() {
        let lines = [ConversationLog.Line(fromUser: true, text: "My locker code is 4512")]
        XCTAssertNil(SessionRecovery.draft(lines: lines, pendingNote: "Locker code 4512", end: .iPhoneLocked, endedAt: t0))
    }

    func testTheServerNeverGetsAnEndedByForIt() {
        XCTAssertNil(KeptConversation.endedBy(VoiceSessionEnd.iPhoneLocked.code))
    }

    func testTheReasonIsTheSameWheneverTheGuardEndsAConversation() {
        var reasons: Set<String> = []
        for state in [ProtectedDataGuard.Conversation.connecting, .running] {
            var lock = guardWith()
            if case .end(let reason) = lock.receive(.becameUnavailable, conversation: state, appLockOn: true) { reasons.insert(reason.code) }
        }
        XCTAssertEqual(reasons, ["locked"])
    }
}
