import XCTest
@testable import DoddyCore

/// OP-024, ADR-361: one indicator while anything in Doddy has the microphone open, and a Stop
/// listening that says "Stopped" only when each one says it is closed and iOS let go of the audio.
/// ("Hey Doddy" was the third microphone user until ADR-549.)
final class ListeningPrivacyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_630_000)

    // MARK: Who has the microphone

    func testOnlyWhatIsActuallyOpenCounts() {
        XCTAssertEqual(MicrophoneSnapshot().open, [])
        XCTAssertEqual(MicrophoneSnapshot(conversation: .muted).open, [.conversation], "muted may still capture (OpenAI test voice)")
        XCTAssertEqual(MicrophoneSnapshot(voiceMemoRecording: true).open, [.voiceMemo])
    }

    // MARK: The indicator

    func testTheIndicatorShowsOnlyWhileSomethingListens() throws {
        XCTAssertNil(ListeningIndicator.current(MicrophoneSnapshot()))

        let muted = try XCTUnwrap(ListeningIndicator.current(MicrophoneSnapshot(conversation: .muted)))
        XCTAssertEqual(muted.title(.english), "Microphone muted")
        XCTAssertFalse(muted.detail(.english).contains("off"), "muted never claims the microphone is off")
        XCTAssertEqual(muted.symbol, "mic.slash.fill")

        let both = try XCTUnwrap(ListeningIndicator.current(MicrophoneSnapshot(conversation: .listening, voiceMemoRecording: true)))
        XCTAssertEqual(both.kinds, [.conversation, .voiceMemo])
        XCTAssertEqual(both.title(.english), "Doddy is listening · Recording a voice memo")
    }

    func testEveryIndicatorLineHasPolish() throws {
        let kinds: [MicrophoneSnapshot] = [
            .init(conversation: .connecting), .init(conversation: .listening), .init(conversation: .muted),
            .init(voiceMemoRecording: true),
        ]
        for snapshot in kinds {
            let indicator = try XCTUnwrap(ListeningIndicator.current(snapshot))
            XCTAssertNotEqual(indicator.title(.polish), indicator.title(.english))
            XCTAssertNotEqual(indicator.detail(.polish), indicator.detail(.english))
        }
        XCTAssertEqual(ListeningIndicator.stopLabel(.polish), "Przestań słuchać")
    }

    /// ADR-653: on Home's own conversation screen the pill steps aside (Home shows the status, Mute
    /// and End); anywhere else, or when a memo or a recording also listens, it stays.
    func testTheIndicatorStepsAsideOnlyWhereTheConversationIsShown() throws {
        let connecting = ListeningIndicator.current(MicrophoneSnapshot(conversation: .connecting))
        let talking = ListeningIndicator.current(MicrophoneSnapshot(conversation: .listening))
        let memoToo = ListeningIndicator.current(MicrophoneSnapshot(conversation: .listening, voiceMemoRecording: true))
        let memoOnly = ListeningIndicator.current(MicrophoneSnapshot(voiceMemoRecording: true))

        XCTAssertTrue(ListeningIndicator.stepsAside(connecting, transcriptOpen: false, homeShowsConversation: true), "the screenshot: Connecting… on Home")
        XCTAssertTrue(ListeningIndicator.stepsAside(talking, transcriptOpen: false, homeShowsConversation: true))
        XCTAssertFalse(ListeningIndicator.stepsAside(talking, transcriptOpen: false, homeShowsConversation: false), "Settings or Files while he talks")
        XCTAssertFalse(ListeningIndicator.stepsAside(memoToo, transcriptOpen: false, homeShowsConversation: true), "Home doesn't say a memo records")
        XCTAssertFalse(ListeningIndicator.stepsAside(memoOnly, transcriptOpen: false, homeShowsConversation: true))
        XCTAssertFalse(ListeningIndicator.stepsAside(nil, transcriptOpen: false, homeShowsConversation: true), "nothing to hide: a Stop result still shows")
        XCTAssertTrue(ListeningIndicator.stepsAside(memoToo, transcriptOpen: true, homeShowsConversation: false), "the transcript, as before")
        XCTAssertTrue(try XCTUnwrap(talking).isConversationOnly)
        XCTAssertFalse(try XCTUnwrap(memoToo).isConversationOnly)
    }

    // MARK: Stop listening

    func testStoppedOnlyWhenEachSaysItIsClosed() {
        let before = MicrophoneSnapshot(conversation: .listening)
        let report = ListeningStopReport(before: before, after: MicrophoneSnapshot(), release: .released)
        XCTAssertTrue(report.stopped)
        XCTAssertEqual(report.conversation, .closed)
        XCTAssertEqual(report.reply(.english), "Stopped. Doddy isn't listening. The conversation is ended.")

        // The conversation still says it is live after being stopped: never "Stopped".
        let stuck = ListeningStopReport(before: before, after: MicrophoneSnapshot(conversation: .listening), release: .released)
        XCTAssertFalse(stuck.stopped)
        XCTAssertEqual(stuck.stillOpen, [.conversation])
        XCTAssertFalse(stuck.reply(.english).contains("Stopped"))
        XCTAssertTrue(stuck.reply(.english).hasPrefix("Doddy couldn't stop the conversation. Try again"))
    }

    func testIOSNotLettingGoIsNotStopped() {
        let report = ListeningStopReport(before: MicrophoneSnapshot(voiceMemoRecording: true), after: MicrophoneSnapshot(),
                                         release: .failed("busy"), keptMemoDraft: true)
        XCTAssertTrue(report.stillOpen.isEmpty)
        XCTAssertFalse(report.stopped)
        XCTAssertFalse(report.reply(.english).hasPrefix("Stopped"))
        XCTAssertTrue(report.reply(.english).contains("(busy)"))
        // iOS stopping something that was still running does close it.
        XCTAssertTrue(ListeningStopReport(before: MicrophoneSnapshot(voiceMemoRecording: true), after: MicrophoneSnapshot(),
                                          release: .stoppedWhatWasRunning).stopped)
    }

    func testNothingOnSaysSoAndDraftsAreNamed() {
        let nothing = ListeningStopReport(before: MicrophoneSnapshot(), after: MicrophoneSnapshot(), release: .notNeeded)
        XCTAssertTrue(nothing.stopped)
        XCTAssertTrue(nothing.nothingWasOn)
        XCTAssertEqual(nothing.reply(.english), "Doddy wasn't listening. The microphone is off.")

        let drafts = ListeningStopReport(before: MicrophoneSnapshot(conversation: .listening, voiceMemoRecording: true), after: MicrophoneSnapshot(),
                                         release: .released, keptNoteDraft: true, keptMemoDraft: true)
        let reply = drafts.reply(.english)
        XCTAssertTrue(reply.contains("kept as a draft; nothing was saved"))
        XCTAssertTrue(reply.contains("The recording is kept with your note as a draft"))
    }

    func testEveryReplyHasPolish() {
        let reports = [
            ListeningStopReport(before: MicrophoneSnapshot(), after: MicrophoneSnapshot(), release: .notNeeded),
            ListeningStopReport(before: MicrophoneSnapshot(conversation: .listening, voiceMemoRecording: true),
                                after: MicrophoneSnapshot(), release: .released, keptNoteDraft: true),
            ListeningStopReport(before: MicrophoneSnapshot(conversation: .listening), after: MicrophoneSnapshot(conversation: .listening), release: .released),
            ListeningStopReport(before: MicrophoneSnapshot(conversation: .listening), after: MicrophoneSnapshot(), release: .failed("x")),
        ]
        for report in reports {
            XCTAssertNotEqual(report.reply(.polish), report.reply(.english))
        }
        XCTAssertTrue(reports[1].reply(.polish).hasPrefix("Zatrzymano."))
    }

    // MARK: The voice screen after Stop listening

    func testStopListeningKeepsOnlyTheNoteCardAsADraft() throws {
        let lines = [ConversationLog.Line(fromUser: true, text: "remember the gate code 4821")]
        XCTAssertNil(SessionRecovery.draft(lines: lines, pendingNote: nil, end: .stoppedListening, endedAt: t0), "what the user said last isn't offered back")
        let draft = try XCTUnwrap(SessionRecovery.draft(lines: lines, pendingNote: " Gate code 4821 ", end: .stoppedListening, endedAt: t0))
        XCTAssertEqual(draft.text, "Gate code 4821")
        XCTAssertEqual(draft.unanswered, [])

        XCTAssertFalse(VoiceSessionEnd.stoppedListening.isDrop)
        XCTAssertEqual(VoiceSessionEnd.stoppedListening.code, "stopped")
        XCTAssertEqual(SessionRecovery.status(.stoppedListening, connected: true).title, "Stopped listening")
        XCTAssertEqual(SessionRecovery.status(.stoppedListening, connected: true, language: .polish).title, "Przestano słuchać")
        // The next conversation isn't told it was cut off: the user stopped it.
        let log = ConversationLog(startedAt: t0, endedAt: t0 + 60, lines: lines, voiceProvider: "elevenlabs", ended: "stopped")
        XCTAssertNil(SessionRecovery.resumeNote(newest: log, now: t0 + 120))
    }
}
