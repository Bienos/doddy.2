import XCTest
@testable import DoddyCore

/// Decision 2026-11-15-conversation-core-and-corrections: a change that ran although the person spoke over it is
/// told to the agent as a fact, so a correction doesn't become a second action.
final class VoiceInterruptedWritesTests: XCTestCase {
    func testTheAtOnceChangesAreDoddysOwnChangesWithNoCard() {
        let changes = VoiceInterruptedWrites.atOnceChanges
        for name in ["set_timer", "set_alarm", "create_reminder", "save_memory", "add_to_list", "check_off", "add_ingredients", VoiceToolName.textMe] {
            XCTAssertTrue(changes.contains(name), name)
        }
        // Reads, cards and session switches are not followed.
        for name in ["web_search", "search_memories", "read_list", "remove_from_list", "create_calendar_event", "send_email",
                     "call_places", VoiceToolName.startTranslator, VoiceToolName.stopTranslator, "draft_message", "open_map"] {
            XCTAssertFalse(changes.contains(name), name)
        }
        for name in changes {
            XCTAssertEqual(ToolCatalog.descriptor(name)?.approval, .runsNow, name)
        }
    }

    /// PL06 of the research's scenarios: "Ustaw minutnik na dziesięć… nie, na pięć minut."
    func testATimerSetWhileThePersonCorrectedItIsToldToTheAgent() {
        var writes = VoiceInterruptedWrites()
        writes.started(id: "t1", name: "set_timer")
        writes.personInterrupted()
        let note = writes.answered(id: "t1", result: "started: a 10-minute timer", isError: false)
        XCTAssertEqual(note, "(app) set_timer had already run when the user spoke, so it is done even if you were told it was abandoned. "
            + "Its result: started: a 10-minute timer. If the user's words corrected it, change or undo this one; never make a second one.")
        XCTAssertNil(writes.answered(id: "t1", result: "again", isError: false), "once per call")
    }

    func testNothingIsSaidWithoutAnInterruptionOrForAReadOrAnUnknownCall() {
        var writes = VoiceInterruptedWrites()
        writes.started(id: "r1", name: "create_reminder")
        XCTAssertNil(writes.answered(id: "r1", result: "added", isError: false), "no interruption: the agent has the result")
        writes.started(id: "w1", name: "web_search")
        writes.personInterrupted()
        XCTAssertNil(writes.answered(id: "w1", result: "five snippets", isError: false), "an abandoned read changed nothing")
        XCTAssertNil(writes.answered(id: "nope", result: "added", isError: false))
    }

    func testAChangeThatFinishedBeforeTheInterruptionIsNotMarked() {
        var writes = VoiceInterruptedWrites()
        writes.started(id: "a", name: "add_to_list")
        XCTAssertNil(writes.answered(id: "a", result: "added: milk", isError: false))
        writes.personInterrupted()
        writes.started(id: "b", name: "add_to_list")
        XCTAssertNil(writes.answered(id: "b", result: "added: oat milk", isError: false), "started after the interruption")
    }

    func testAFailedChangeIsToldAsNotDoneAndTheResultIsOneShortLine() {
        var writes = VoiceInterruptedWrites()
        writes.started(id: "x", name: "create_reminder")
        writes.personInterrupted()
        let long = String(repeating: "a", count: 400) + "\nsecond line"
        let note = writes.answered(id: "x", result: long, isError: true) ?? ""
        XCTAssertTrue(note.hasPrefix("(app) create_reminder was still running when the user spoke, and it did not go through: "))
        XCTAssertFalse(note.contains("\n"))
        XCTAssertTrue(note.hasSuffix("…"))
        XCTAssertLessThan(note.count, 400)
    }

    func testResetForgetsEverything() {
        var writes = VoiceInterruptedWrites()
        writes.started(id: "a", name: "set_alarm")
        writes.personInterrupted()
        writes.reset()
        XCTAssertNil(writes.answered(id: "a", result: "set", isError: false))
    }
}

/// Decision 2026-11-15-conversation-core-and-corrections: from the provider's interruption event to Doddy's voice
/// going quiet at the output.
final class VoiceInterruptSilenceTests: XCTestCase {
    private func push(_ silence: inout VoiceInterruptSilence, level: Double, from start: Double, count: Int) -> VoiceInterruptSilence.Result? {
        var found: VoiceInterruptSilence.Result?
        for index in 0..<count {
            if let result = silence.push(level: level, seconds: 0.01, at: start + Double(index) * 0.01) { found = result }
        }
        return found
    }

    func testTheVoiceStopsWhenTheLastLoudBufferCame() {
        var silence = VoiceInterruptSilence()
        silence.begin(at: 100)
        XCTAssertNil(push(&silence, level: 0.6, from: 100.0, count: 18), "still speaking")
        let result = push(&silence, level: 0.02, from: 100.18, count: 31)
        guard case .stopped(let seconds) = result else { return XCTFail("\(String(describing: result))") }
        XCTAssertEqual(seconds, 0.17, accuracy: 0.001)
        XCTAssertEqual(silence.result?.line,
                       "interruption to silence 0.17 s (from the provider's interruption event; the person's own start is not measured)")
    }

    func testAlreadyQuietIsZeroAndNoBuffersAtAllAreSeenByCheck() {
        var silence = VoiceInterruptSilence()
        silence.begin(at: 5)
        XCTAssertNil(silence.check(at: 5.1))
        XCTAssertEqual(silence.check(at: 5.31), .stopped(0))
    }

    func testStillSoundingAfterTheLimitIsSaidSoNotTimed() {
        var silence = VoiceInterruptSilence()
        silence.begin(at: 0)
        _ = push(&silence, level: 0.7, from: 0, count: 500)
        XCTAssertEqual(silence.check(at: 5.0), .stillSounding)
        XCTAssertTrue(silence.result?.line.hasPrefix("interruption to silence not reached in 5") ?? false)
    }

    func testNothingIsWatchedWithoutAnInterruption() {
        var silence = VoiceInterruptSilence()
        XCTAssertNil(silence.push(level: 0, seconds: 1, at: 1))
        XCTAssertNil(silence.check(at: 10))
        XCTAssertFalse(silence.isWatching)
    }
}
