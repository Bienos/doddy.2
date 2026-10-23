import DoddyCore
import Foundation
import XCTest

/// DODDY Capture (ADR-579): the state machine that is the one source of truth for a recording.
final class CaptureStateMachineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
    private let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    /// A machine that is really recording, started at `at(0)`.
    private func recording(origin: CaptureOrigin = .app) -> CaptureStateMachine {
        var machine = CaptureStateMachine()
        machine.handle(.startRequested(id: id, origin: origin, at: at(0)))
        machine.handle(.preflightPassed(at: at(0)))
        machine.handle(.recorderStarted(partIndex: 1, at: at(0)))
        machine.handle(.activityUp)
        return machine
    }

    private func session(_ machine: CaptureStateMachine) -> CaptureSession {
        guard let session = machine.session else { XCTFail("no session in \(machine.state)"); return CaptureSession(id: id, origin: .app, startedAt: t0, activity: .up) }
        return session
    }

    // MARK: - Starting

    func testStartRunsTheChecksFirstAndClaimsNothing() {
        var machine = CaptureStateMachine()
        let effects = machine.handle(.startRequested(id: id, origin: .app, at: at(0)))
        XCTAssertEqual(effects, [.runPreflight(.app)])
        XCTAssertTrue(machine.isActive)
        XCTAssertFalse(machine.isCapturingAudio, "nothing says recording before the recorder does")
        if case .preparing = machine.state {} else { XCTFail("expected preparing, got \(machine.state)") }
    }

    func testRecordingNeedsTheRecorderAndTheLiveActivityForAShortcutStart() {
        var machine = CaptureStateMachine()
        machine.handle(.startRequested(id: id, origin: .intent, at: at(0)))
        XCTAssertEqual(machine.handle(.preflightPassed(at: at(0.1))), [.startRecorder(partIndex: 1), .startActivity])
        XCTAssertEqual(machine.handle(.recorderStarted(partIndex: 1, at: at(0.5))), [])
        XCTAssertFalse(machine.isCapturingAudio, "the recorder is going but the Live Activity is not up")
        XCTAssertEqual(machine.handle(.activityUp), [.checkpoint, .updateActivity])
        XCTAssertTrue(machine.isCapturingAudio)
        XCTAssertEqual(session(machine).startedAt, at(0.5), "the clock starts at the first verified audio")
    }

    func testTheOtherOrderWorksToo() {
        var machine = CaptureStateMachine()
        machine.handle(.startRequested(id: id, origin: .control, at: at(0)))
        machine.handle(.preflightPassed(at: at(0.1)))
        machine.handle(.activityUp)
        XCTAssertFalse(machine.isCapturingAudio)
        machine.handle(.recorderStarted(partIndex: 1, at: at(0.4)))
        XCTAssertTrue(machine.isCapturingAudio)
    }

    func testAStartInsideDoddyMayRecordWithoutALiveActivity() {
        var machine = CaptureStateMachine()
        machine.handle(.startRequested(id: id, origin: .app, at: at(0)))
        machine.handle(.preflightPassed(at: at(0)))
        machine.handle(.recorderStarted(partIndex: 1, at: at(0)))
        machine.handle(.activityUnavailable)
        XCTAssertTrue(machine.isCapturingAudio)
        XCTAssertEqual(session(machine).activity, .unavailable)
    }

    func testAShortcutStartDoesNotRecordWithoutALiveActivity() {
        for origin in [CaptureOrigin.intent, .control] {
            var machine = CaptureStateMachine()
            machine.handle(.startRequested(id: id, origin: origin, at: at(0)))
            machine.handle(.preflightPassed(at: at(0)))
            machine.handle(.recorderStarted(partIndex: 1, at: at(0)))
            let effects = machine.handle(.activityUnavailable)
            XCTAssertEqual(machine.state, .failed(.liveActivityUnavailable), "\(origin)")
            XCTAssertEqual(effects, [.discard], "the recorder that already started is stopped and thrown away")
            XCTAssertFalse(machine.isCapturingAudio)
        }
    }

    func testFailedChecksEndInAFailureWithASentence() {
        var machine = CaptureStateMachine()
        machine.handle(.startRequested(id: id, origin: .app, at: at(0)))
        XCTAssertEqual(machine.handle(.preflightFailed(.microphoneDenied)), [.discard])
        XCTAssertEqual(machine.state, .failed(.microphoneDenied))
        XCTAssertFalse(CaptureFailure.microphoneDenied.message(.english).isEmpty)
        XCTAssertFalse(CaptureFailure.microphoneDenied.message(.polish).isEmpty)
        XCTAssertFalse(machine.isActive, "a failure frees the next start")
    }

    func testAStartThatNeverReportsGivesUp() {
        var machine = CaptureStateMachine()
        machine.handle(.startRequested(id: id, origin: .app, at: at(0)))
        machine.handle(.preflightPassed(at: at(1)))
        XCTAssertEqual(machine.handle(.tick(at: at(10))), [])
        XCTAssertEqual(machine.handle(.tick(at: at(17))), [.discard])
        XCTAssertEqual(machine.state, .failed(.recorderCouldNotStart))
    }

    func testPermissionPromptsAreNotTimedOut() {
        var machine = CaptureStateMachine()
        machine.handle(.startRequested(id: id, origin: .app, at: at(0)))
        XCTAssertEqual(machine.handle(.tick(at: at(600))), [], "the checks may be waiting on the user")
        if case .preparing = machine.state {} else { XCTFail("still preparing") }
    }

    func testCancellingBeforeTheRecorderStartedLeavesNothingRunning() {
        var machine = CaptureStateMachine()
        machine.handle(.startRequested(id: id, origin: .app, at: at(0)))
        machine.handle(.preflightPassed(at: at(0)))
        XCTAssertEqual(machine.handle(.stopRequested(at: at(1))), [.discard])
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(machine.handle(.recorderStarted(partIndex: 1, at: at(2))), [.discard],
                       "a recorder that starts after the cancel is stopped, not left running unseen")
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - One session

    func testASecondStartIsRejectedInEveryActiveState() {
        var states: [CaptureStateMachine] = []
        var preparing = CaptureStateMachine()
        preparing.handle(.startRequested(id: id, origin: .app, at: at(0)))
        states.append(preparing)
        states.append(recording())
        var paused = recording(); paused.handle(.pauseRequested(at: at(5))); states.append(paused)
        var interrupted = recording(); interrupted.handle(.interruptionBegan(.systemAudio, at: at(5))); states.append(interrupted)
        var finalizing = recording(); finalizing.handle(.stopRequested(at: at(5))); states.append(finalizing)

        for var machine in states {
            let before = machine.state
            let effects = machine.handle(.startRequested(id: UUID(), origin: .control, at: at(6)))
            XCTAssertEqual(effects, [.rejectStart(.alreadyActive)], "\(before)")
            XCTAssertEqual(machine.state, before, "the running session is left alone")
        }
    }

    func testANewStartIsAllowedAfterASavedOrFailedSession() {
        var saved = recording()
        saved.handle(.stopRequested(at: at(30)))
        saved.handle(.finalized(parts: [ClosedPart(index: 1, durationMilliseconds: 30_000)], at: at(31)))
        XCTAssertEqual(saved.handle(.startRequested(id: UUID(), origin: .app, at: at(32))), [.runPreflight(.app)],
                       "the screen need not acknowledge the last one first")

        var failed = CaptureStateMachine(state: .failed(.storageLow))
        XCTAssertEqual(failed.handle(.startRequested(id: UUID(), origin: .app, at: at(0))), [.runPreflight(.app)])
    }

    // MARK: - Pause and resume

    func testPauseTurnsTheMicrophoneOffAndIsNeverResumedByTheSystem() {
        var machine = recording()
        XCTAssertEqual(machine.handle(.pauseRequested(at: at(10))), [.closePart(index: 1), .updateActivity])
        XCTAssertFalse(machine.isCapturingAudio)
        machine.handle(.partClosed(index: 1, milliseconds: 10_000, at: at(10)))
        XCTAssertEqual(session(machine).closedMilliseconds, 10_000)

        XCTAssertEqual(machine.handle(.interruptionEnded(shouldResume: true, at: at(20))), [], "a pause is the user's to end")
        XCTAssertEqual(machine.handle(.interruptionBegan(.systemAudio, at: at(21))), [])
        if case .paused = machine.state {} else { XCTFail("still paused, got \(machine.state)") }
    }

    func testResumeStartsTheNextPartAndRecordsTheGap() {
        var machine = recording()
        machine.handle(.pauseRequested(at: at(10)))
        machine.handle(.partClosed(index: 1, milliseconds: 10_000, at: at(10)))
        XCTAssertEqual(machine.handle(.resumeRequested(at: at(40))), [.startRecorder(partIndex: 2)])
        XCTAssertFalse(machine.isCapturingAudio, "resuming is not recording until the recorder says so")
        machine.handle(.recorderStarted(partIndex: 2, at: at(40)))
        XCTAssertTrue(machine.isCapturingAudio)
        let s = session(machine)
        XCTAssertEqual(s.gaps, [CaptureGap(atMilliseconds: 10_000, wallMilliseconds: 30_000, reason: .userPaused)])
        XCTAssertEqual(s.capturedMilliseconds(at: at(50)), 20_000, "the 30 s pause is not in the recording")
    }

    func testCapturedTimeStandsStillWhilePaused() {
        var machine = recording()
        machine.handle(.pauseRequested(at: at(10)))
        XCTAssertEqual(session(machine).capturedMilliseconds(at: at(10)), 10_000)
        XCTAssertEqual(session(machine).capturedMilliseconds(at: at(500)), 10_000)
    }

    func testAFailedResumeKeepsThePauseAndCountsTheTry() {
        var machine = recording()
        machine.handle(.pauseRequested(at: at(10)))
        machine.handle(.partClosed(index: 1, milliseconds: 10_000, at: at(10)))
        machine.handle(.resumeRequested(at: at(20)))
        XCTAssertEqual(machine.handle(.recorderFailedToStart(.microphoneBusy)), [.updateActivity])
        let s = session(machine)
        XCTAssertEqual(s.resumeAttempts, 1)
        XCTAssertEqual(s.lastResumeFailure, .microphoneBusy)
        if case .paused = machine.state {} else { XCTFail("still paused") }
    }

    func testAPartWhoseLengthNeverArrivedIsKeptByTheClock() {
        var machine = recording()
        machine.handle(.pauseRequested(at: at(10)))
        machine.handle(.resumeRequested(at: at(20)))
        machine.handle(.recorderStarted(partIndex: 2, at: at(20)))
        XCTAssertEqual(session(machine).closedParts, [ClosedPart(index: 1, durationMilliseconds: 10_000)])
    }

    // MARK: - Interruptions

    func testACallStopsTheRecordingAndWaitsForIOS() {
        var machine = recording()
        XCTAssertEqual(machine.handle(.interruptionBegan(.systemAudio, at: at(60))), [.closePart(index: 1), .updateActivity])
        machine.handle(.partClosed(index: 1, milliseconds: 60_000, at: at(60)))
        XCTAssertFalse(machine.isCapturingAudio)
        XCTAssertEqual(machine.handle(.interruptionEnded(shouldResume: false, at: at(120))), [], "iOS did not say to resume")
        XCTAssertEqual(machine.handle(.interruptionEnded(shouldResume: true, at: at(121))), [.startRecorder(partIndex: 2)])
        machine.handle(.recorderStarted(partIndex: 2, at: at(121)))
        XCTAssertEqual(session(machine).gaps, [CaptureGap(atMilliseconds: 60_000, wallMilliseconds: 61_000, reason: .interruption)])
    }

    func testLosingHeadphonesCarriesOnAtOnce() {
        var machine = recording()
        XCTAssertEqual(machine.handle(.interruptionBegan(.routeDisconnected, at: at(30))),
                       [.closePart(index: 1), .startRecorder(partIndex: 2), .updateActivity])
    }

    func testARecorderThatStopsByItselfIsAnInterruptionNotARecording() {
        var machine = recording()
        let effects = machine.handle(.recorderStoppedUnexpectedly(at: at(30)))
        XCTAssertEqual(effects, [.closePart(index: 1), .startRecorder(partIndex: 2), .updateActivity])
        XCTAssertFalse(machine.isCapturingAudio, "the screen must not keep saying recording")
        if case .interrupted(_, .recorderStopped) = machine.state {} else { XCTFail("got \(machine.state)") }
    }

    func testResumeTriesStopAfterThreeFailures() {
        var machine = recording()
        machine.handle(.interruptionBegan(.routeDisconnected, at: at(30)))
        machine.handle(.partClosed(index: 1, milliseconds: 30_000, at: at(30)))
        for _ in 0..<CaptureLimits.maxResumeAttempts { machine.handle(.recorderFailedToStart(.microphoneBusy)) }
        XCTAssertEqual(machine.handle(.interruptionEnded(shouldResume: true, at: at(40))), [], "no more tries by itself")
        XCTAssertEqual(machine.handle(.resumeRequested(at: at(41))), [.startRecorder(partIndex: 2)], "the user can still ask")
    }

    func testAMutedMicrophoneNeedsTheUser() {
        var machine = recording()
        machine.handle(.interruptionBegan(.builtInMicMuted, at: at(30)))
        machine.handle(.partClosed(index: 1, milliseconds: 30_000, at: at(30)))
        XCTAssertEqual(machine.handle(.interruptionEnded(shouldResume: true, at: at(40))), [])
    }

    func testAGiveUpSavesWhatThereIs() {
        var machine = recording()
        machine.handle(.interruptionBegan(.systemAudio, at: at(30)))
        machine.handle(.partClosed(index: 1, milliseconds: 30_000, at: at(30)))
        XCTAssertEqual(machine.handle(.tick(at: at(30 + 3500))), [])
        XCTAssertEqual(machine.handle(.tick(at: at(30 + 3601))), [.finalize])
        if case .finalizing(_, .idleTimeout) = machine.state {} else { XCTFail("got \(machine.state)") }
    }

    func testThePolicyHasWordsForEveryKind() {
        for kind in [InterruptionKind.systemAudio, .builtInMicMuted, .routeDisconnected, .mediaServicesReset, .recorderStopped, .rotationFailed] {
            XCTAssertFalse(InterruptionPolicy.message(kind, .english).isEmpty)
            XCTAssertFalse(InterruptionPolicy.message(kind, .polish).isEmpty)
        }
    }

    // MARK: - Rotation

    func testAPartIsClosedEveryTenMinutes() {
        var machine = recording()
        XCTAssertEqual(machine.handle(.tick(at: at(599))), [])
        XCTAssertEqual(machine.handle(.tick(at: at(601))), [.rotate(closing: 1, opening: 2)])
        XCTAssertEqual(machine.handle(.tick(at: at(602))), [], "one rotation at a time")
        XCTAssertEqual(machine.handle(.segmentRotated(closedPart: 1, closedMilliseconds: 600_900, newPart: 2, gapMilliseconds: 40, at: at(601.1))), [.checkpoint])
        let s = session(machine)
        XCTAssertEqual(s.closedParts, [ClosedPart(index: 1, durationMilliseconds: 600_900)])
        XCTAssertEqual(s.gaps, [CaptureGap(atMilliseconds: 600_900, wallMilliseconds: 40, reason: .segmentRotation)])
        XCTAssertEqual(s.openPart?.index, 2)
        XCTAssertFalse(s.gaps[0].isNoticeable, "milliseconds are not shown to the user")
        XCTAssertEqual(machine.handle(.tick(at: at(1200))), [], "the new part has its own ten minutes")
        XCTAssertEqual(machine.handle(.tick(at: at(1202))), [.rotate(closing: 2, opening: 3)])
    }

    func testAnAbortedRotationBacksOffAndTriesAgain() {
        var machine = recording()
        machine.handle(.tick(at: at(601)))
        machine.handle(.rotationAborted(at: at(601)))
        XCTAssertEqual(machine.handle(.tick(at: at(610))), [])
        XCTAssertEqual(machine.handle(.tick(at: at(632))), [.rotate(closing: 1, opening: 2)])
    }

    func testAFailedRotationIsAnInterruptionThatRetries() {
        var machine = recording()
        machine.handle(.tick(at: at(601)))
        let effects = machine.handle(.rotationFailed(closedPart: 1, closedMilliseconds: 601_000, at: at(601)))
        XCTAssertEqual(effects, [.startRecorder(partIndex: 2), .updateActivity])
        XCTAssertFalse(machine.isCapturingAudio)
        XCTAssertEqual(session(machine).closedParts, [ClosedPart(index: 1, durationMilliseconds: 601_000)])
    }

    // MARK: - Limits

    func testTheFourHourCapSavesTheRecording() {
        var machine = recording()
        let limit = TimeInterval(CaptureLimits.maxSeconds)
        XCTAssertEqual(machine.handle(.tick(at: at(limit + 1))), [.finalize])
        if case .finalizing(_, .durationLimit) = machine.state {} else { XCTFail("got \(machine.state)") }
        XCTAssertNotNil(CaptureEndReason.durationLimit.note(.english))
    }

    func testTheCapIsWarnedAboutOnce() {
        var machine = recording()
        let warnAt = TimeInterval(CaptureLimits.maxSeconds - CaptureLimits.warnBeforeMaxSeconds)
        XCTAssertTrue(machine.handle(.tick(at: at(warnAt + 1))).contains(.warnNearLimit(minutesLeft: 10)))
        XCTAssertFalse(machine.handle(.tick(at: at(warnAt + 2))).contains(.warnNearLimit(minutesLeft: 10)))
    }

    func testTheCapStaysWellUnderALiveActivitysEightHours() {
        XCTAssertLessThan(CaptureLimits.maxWallSeconds, 8 * 3600)
        XCTAssertLessThan(CaptureLimits.maxSeconds, CaptureLimits.maxWallSeconds)
    }

    func testPausesDoNotStretchTheActivityPastItsLife() {
        var machine = recording()
        machine.handle(.pauseRequested(at: at(60)))
        machine.handle(.partClosed(index: 1, milliseconds: 60_000, at: at(60)))
        XCTAssertEqual(machine.handle(.tick(at: at(TimeInterval(CaptureLimits.maxWallSeconds) + 1))), [.finalize])
        if case .finalizing(_, .activityLifetime) = machine.state {} else { XCTFail("got \(machine.state)") }
    }

    func testLowStorageStopsAndSavesButOnlyBelowTheLine() {
        var machine = recording()
        XCTAssertEqual(machine.handle(.storageLow(freeBytes: 500 * 1024 * 1024, at: at(5))), [])
        XCTAssertEqual(machine.handle(.storageLow(freeBytes: 10 * 1024 * 1024, at: at(6))), [.finalize])
        if case .finalizing(_, .storageLow) = machine.state {} else { XCTFail("got \(machine.state)") }
    }

    // MARK: - Finishing

    func testStopSavesWithTheRecordersOwnDurations() {
        var machine = recording()
        machine.handle(.tick(at: at(601)))
        machine.handle(.segmentRotated(closedPart: 1, closedMilliseconds: 600_900, newPart: 2, gapMilliseconds: 40, at: at(601.1)))
        XCTAssertEqual(machine.handle(.stopRequested(at: at(700))), [.finalize])
        XCTAssertFalse(machine.isCapturingAudio)
        machine.handle(.finalized(parts: [ClosedPart(index: 2, durationMilliseconds: 98_000), ClosedPart(index: 1, durationMilliseconds: 600_900)], at: at(701)))
        guard case .finished(.saved(let saved)) = machine.state else { return XCTFail("got \(machine.state)") }
        XCTAssertEqual(saved.id, id)
        XCTAssertEqual(saved.durationMilliseconds, 698_900, "the recorder's lengths, not the clock's")
        XCTAssertEqual(saved.parts.map(\.index), [1, 2])
        XCTAssertEqual(saved.reason, .userStopped)
        XCTAssertEqual(saved.gaps.count, 1)
    }

    func testAMisTapIsNotKept() {
        var machine = recording()
        machine.handle(.stopRequested(at: at(0.4)))
        XCTAssertEqual(machine.handle(.finalized(parts: [ClosedPart(index: 1, durationMilliseconds: 400)], at: at(0.5))), [.discard])
        XCTAssertEqual(machine.state, .finished(.discardedTooShort))
    }

    func testASaveThatFailsKeepsTheFilesForRecovery() {
        var machine = recording()
        machine.handle(.stopRequested(at: at(30)))
        let effects = machine.handle(.finalizeFailed)
        XCTAssertEqual(machine.state, .failed(.saveFailed))
        XCTAssertFalse(effects.contains(.discard), "nothing is deleted when the save failed")
    }

    func testASaveThatHangsGivesUpWithoutDeletingAnything() {
        var machine = recording()
        machine.handle(.stopRequested(at: at(30)))
        XCTAssertEqual(machine.handle(.tick(at: at(100))), [])
        XCTAssertEqual(machine.handle(.tick(at: at(30 + CaptureStateMachine.finalizeTimeoutSeconds + 1))), [])
        XCTAssertEqual(machine.state, .failed(.saveFailed))
    }

    func testStoppingWhileAPartIsStillClosingKeepsEverything() {
        var machine = recording()
        machine.handle(.pauseRequested(at: at(10)))
        machine.handle(.stopRequested(at: at(11)))
        XCTAssertEqual(machine.handle(.partClosed(index: 1, milliseconds: 10_000, at: at(11))), [])
        XCTAssertEqual(session(machine).closedMilliseconds, 10_000)
    }

    func testTheLiveActivityBeingDismissedAsksForANewOne() {
        var machine = recording(origin: .intent)
        XCTAssertEqual(machine.handle(.activityEnded), [.startActivity])
        XCTAssertTrue(machine.isCapturingAudio, "the audio goes on; iOS may stop it, and the recorder will say so")
    }

    func testTheEndNotesAreHonest() {
        XCTAssertNil(CaptureEndReason.userStopped.note(.english))
        for reason in [CaptureEndReason.durationLimit, .storageLow, .idleTimeout, .activityLifetime, .recovered] {
            XCTAssertNotNil(reason.note(.english)); XCTAssertNotNil(reason.note(.polish))
        }
        XCTAssertTrue(CaptureEndReason.recovered.note(.english)!.contains("may be missing"))
    }

    // MARK: - Fuzz

    /// Thousands of random events, from many seeds. Whatever order they arrive in, these hold.
    func testInvariantsHoldForAnyOrderOfEvents() {
        var visited = Set<String>()
        var rotations = 0, resumedFromQuiet = 0, saved = 0
        defer {
            // A fuzz that never gets anywhere proves nothing: it has to reach every state.
            for name in ["preparing", "recording", "paused", "interrupted", "finalizing", "finished", "failed"] {
                XCTAssertTrue(visited.contains(name), "the fuzz never reached \(name)")
            }
            XCTAssertGreaterThan(rotations, 0, "no rotation happened")
            XCTAssertGreaterThan(resumedFromQuiet, 0, "nothing ever resumed")
            XCTAssertGreaterThan(saved, 0, "nothing was ever saved")
        }
        for seed in 1...40 {
            var rng = SplitMix(seed: UInt64(seed))
            var machine = CaptureStateMachine()
            var now = t0
            var knownIDs = Set<UUID>()
            for step in 0..<1500 {
                now = now.addingTimeInterval(Double(rng.next() % 90) / 3)
                let before = machine.state
                let event = randomEvent(&rng, machine, now)
                let effects = machine.handle(event)
                let after = machine.state
                visited.insert(Self.name(after))
                if case .segmentRotated = event, case .recording = after { rotations += 1 }
                switch (before, after) {
                case (.paused, .recording), (.interrupted, .recording): resumedFromQuiet += 1
                default: break
                }
                if case .finished(.saved) = after, !isFinishedSaved(before) { saved += 1 }

                if case .recording = after {
                    var enteredHere = false
                    if case .recording = before {} else { enteredHere = true }
                    if enteredHere {
                        switch event {
                        case .recorderStarted, .activityUp, .activityUnavailable: break
                        default: XCTFail("seed \(seed) step \(step): entered recording on \(event)")
                        }
                        if case .preparing(let p) = before {
                            XCTAssertTrue(p.recorderStartedAt != nil || { if case .recorderStarted = event { true } else { false } }(),
                                          "seed \(seed): recording without a verified recorder")
                        }
                    }
                }
                if case .startRequested = event, before != .idle, !isResting(before) {
                    XCTAssertEqual(effects, [.rejectStart(.alreadyActive)], "seed \(seed) step \(step)")
                    XCTAssertEqual(after, before)
                }
                if let s = machine.session {
                    knownIDs.insert(s.id)
                    XCTAssertEqual(s.closedParts.map(\.index), s.closedParts.map(\.index).sorted(), "seed \(seed): parts out of order")
                    XCTAssertEqual(Set(s.closedParts.map(\.index)).count, s.closedParts.count, "seed \(seed): a part counted twice")
                    XCTAssertEqual(s.gaps.map(\.atMilliseconds), s.gaps.map(\.atMilliseconds).sorted(), "seed \(seed): gaps out of order")
                    XCTAssertGreaterThanOrEqual(s.capturedMilliseconds(at: now), 0)
                    if let open = s.openPart { XCTAssertFalse(s.closedParts.contains { $0.index == open.index }, "seed \(seed): open part is also closed") }
                    if case .recording = after { XCTAssertNotNil(s.openPart, "seed \(seed): recording with no part") }
                } else {
                    XCTAssertFalse(machine.isCapturingAudio)
                }
                if !machine.isActive { XCTAssertNil(machine.session) }
            }
            _ = knownIDs
        }
    }

    private static func name(_ state: CaptureState) -> String {
        switch state {
        case .idle: "idle"
        case .preparing: "preparing"
        case .recording: "recording"
        case .paused: "paused"
        case .interrupted: "interrupted"
        case .finalizing: "finalizing"
        case .finished: "finished"
        case .failed: "failed"
        }
    }

    private func isFinishedSaved(_ state: CaptureState) -> Bool {
        if case .finished(.saved) = state { true } else { false }
    }

    private func isResting(_ state: CaptureState) -> Bool {
        switch state {
        case .idle, .finished, .failed: true
        default: false
        }
    }

    private func randomEvent(_ rng: inout SplitMix, _ machine: CaptureStateMachine, _ now: Date) -> CaptureEvent {
        let part = machine.session?.openPart?.index ?? machine.session?.closedParts.last?.index ?? 1
        let next = machine.session?.nextPartIndex ?? 1
        let kinds: [InterruptionKind] = [.systemAudio, .builtInMicMuted, .routeDisconnected, .mediaServicesReset, .recorderStopped, .rotationFailed]
        let failures: [CaptureFailure] = [.microphoneBusy, .recorderCouldNotStart, .storageLow]
        switch rng.next() % 26 {
        case 0, 1: return .startRequested(id: UUID(), origin: [.app, .intent, .control][Int(rng.next() % 3)], at: now)
        case 2, 3: return .preflightPassed(at: now)
        case 4: return .preflightFailed(failures[Int(rng.next() % 3)])
        case 5, 6: return .recorderStarted(partIndex: rng.next() % 4 == 0 ? Int(rng.next() % 5) : next, at: now)
        case 7: return .recorderFailedToStart(failures[Int(rng.next() % 3)])
        case 8, 9: return .activityUp
        case 10: return .activityUnavailable
        case 11: return .activityEnded
        case 12: return .pauseRequested(at: now)
        case 13, 14: return .resumeRequested(at: now)
        case 15: return .stopRequested(at: now)
        case 16, 17, 18: return .tick(at: now)
        case 19: return .segmentRotated(closedPart: part, closedMilliseconds: Int(rng.next() % 700_000), newPart: next, gapMilliseconds: Int(rng.next() % 200), at: now)
        case 20: return .partClosed(index: part, milliseconds: Int(rng.next() % 700_000), at: now)
        case 21: return .interruptionBegan(kinds[Int(rng.next() % 6)], at: now)
        case 22: return .interruptionEnded(shouldResume: rng.next() % 2 == 0, at: now)
        case 23: return .recorderStoppedUnexpectedly(at: now)
        case 24: return rng.next() % 2 == 0
            ? .finalized(parts: [ClosedPart(index: part, durationMilliseconds: Int(rng.next() % 900_000))], at: now)
            : .finalizeFailed
        default: return rng.next() % 2 == 0 ? .acknowledged : .storageLow(freeBytes: Int64(rng.next() % 300) * 1024 * 1024, at: now)
        }
    }
}

/// A small seeded generator, so a failing seed can be rerun.
struct SplitMix: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
