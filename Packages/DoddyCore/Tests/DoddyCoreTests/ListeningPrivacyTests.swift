import XCTest
@testable import DoddyCore

/// OP-024, ADR-361: one indicator while anything in Doddy has the microphone open, and a Stop
/// listening that says "Stopped" only when each one says it is closed and iOS let go of the audio.
final class ListeningPrivacyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_630_000)

    // MARK: Who has the microphone

    func testOnlyWhatIsActuallyOpenCounts() {
        XCTAssertEqual(MicrophoneSnapshot().open, [])
        XCTAssertEqual(MicrophoneSnapshot(conversation: .muted).open, [.conversation], "muted may still capture (OpenAI test voice)")
        XCTAssertEqual(MicrophoneSnapshot(heyDoddy: .listening, heyDoddyRunning: true).open, [.heyDoddy])
        // The switch is on but iOS hasn't let it start: nothing is open, but it could start by itself.
        let waiting = MicrophoneSnapshot(heyDoddy: .waitingForApp)
        XCTAssertEqual(waiting.open, [])
        XCTAssertTrue(waiting.heyDoddyCouldListen)
        XCTAssertFalse(MicrophoneSnapshot(heyDoddy: .off).heyDoddyCouldListen)
        XCTAssertFalse(MicrophoneSnapshot(heyDoddy: .microphoneDenied).heyDoddyCouldListen)
        XCTAssertTrue(MicrophoneSnapshot(heyDoddy: .off, heyDoddyRunning: true).heyDoddyCouldListen, "a running engine always counts")
        XCTAssertEqual(MicrophoneSnapshot(voiceMemoRecording: true).open, [.voiceMemo])
    }

    // MARK: The indicator

    func testTheIndicatorShowsOnlyWhileSomethingListens() throws {
        XCTAssertNil(ListeningIndicator.current(MicrophoneSnapshot()))
        XCTAssertNil(ListeningIndicator.current(MicrophoneSnapshot(heyDoddy: .paused(.lowPowerMode))), "paused isn't listening")
        XCTAssertNil(ListeningIndicator.current(MicrophoneSnapshot(heyDoddy: .waitingForApp)))

        let wake = try XCTUnwrap(ListeningIndicator.current(MicrophoneSnapshot(heyDoddy: .listening, heyDoddyRunning: true)))
        XCTAssertEqual(wake.title(.english), "Listening for “Hey Doddy”")
        XCTAssertEqual(wake.detail(.english), "On this iPhone only; nothing is kept or sent until you say it.")
        XCTAssertEqual(wake.symbol, "ear")

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
            .init(voiceMemoRecording: true), .init(heyDoddy: .listening, heyDoddyRunning: true),
        ]
        for snapshot in kinds {
            let indicator = try XCTUnwrap(ListeningIndicator.current(snapshot))
            XCTAssertNotEqual(indicator.title(.polish), indicator.title(.english))
            XCTAssertNotEqual(indicator.detail(.polish), indicator.detail(.english))
        }
        XCTAssertEqual(ListeningIndicator.stopLabel(.polish), "Przestań słuchać")
    }

    // MARK: Stop listening

    func testStoppedOnlyWhenEachSaysItIsClosed() {
        let before = MicrophoneSnapshot(conversation: .listening)
        let report = ListeningStopReport(before: before, after: MicrophoneSnapshot(), release: .released)
        XCTAssertTrue(report.stopped)
        XCTAssertEqual(report.conversation, .closed)
        XCTAssertEqual(report.heyDoddy, .wasOff)
        XCTAssertEqual(report.reply(.english), "Stopped. Doddy isn't listening. The conversation is ended.")

        // The conversation still says it is live after being stopped: never "Stopped".
        let stuck = ListeningStopReport(before: before, after: MicrophoneSnapshot(conversation: .listening), release: .released)
        XCTAssertFalse(stuck.stopped)
        XCTAssertEqual(stuck.stillOpen, [.conversation])
        XCTAssertFalse(stuck.reply(.english).contains("Stopped"))
        XCTAssertTrue(stuck.reply(.english).hasPrefix("Doddy couldn't stop the conversation. Try again"))
    }

    func testHeyDoddyMustBeSwitchedOffNotJustPaused() {
        let before = MicrophoneSnapshot(heyDoddy: .listening, heyDoddyRunning: true)
        // The engine stopped but the switch is still on: it would start again by itself.
        let paused = ListeningStopReport(before: before, after: MicrophoneSnapshot(heyDoddy: .waitingForApp), release: .released)
        XCTAssertEqual(paused.heyDoddy, .stillOpen)
        XCTAssertFalse(paused.stopped)

        let off = ListeningStopReport(before: before, after: MicrophoneSnapshot(heyDoddy: .off), release: .released)
        XCTAssertEqual(off.heyDoddy, .closed)
        XCTAssertEqual(off.reply(.english), "Stopped. Doddy isn't listening. “Hey Doddy” is off; turn it back on in Settings.")

        // Switched on but not listening yet (waiting for Doddy to open) is turned off too.
        let waiting = ListeningStopReport(before: MicrophoneSnapshot(heyDoddy: .paused(.conversation)), after: MicrophoneSnapshot(heyDoddy: .off), release: .notNeeded)
        XCTAssertEqual(waiting.heyDoddy, .closed)
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
            ListeningStopReport(before: MicrophoneSnapshot(conversation: .listening, heyDoddy: .paused(.conversation), voiceMemoRecording: true),
                                after: MicrophoneSnapshot(heyDoddy: .off), release: .released, keptNoteDraft: true),
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
