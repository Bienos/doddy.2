import DoddyCore
import Foundation
import XCTest

/// DODDY Capture (ADR-588): models, recovery after a kill, the Live Activity's content, and the
/// microphone indicator.
final class CaptureSupportTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
    private let id = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - Models

    func testTheClockReadsLikeAClock() {
        XCTAssertEqual(RecordingClock.string(milliseconds: 0), "0:00")
        XCTAssertEqual(RecordingClock.string(milliseconds: 154_000), "2:34")
        XCTAssertEqual(RecordingClock.string(milliseconds: 3_723_000), "1:02:03")
        XCTAssertEqual(RecordingClock.string(milliseconds: -5), "0:00")
    }

    func testPartFileNamesAreMadeByDoddyAndNothingElseIsAccepted() {
        XCTAssertEqual(RecordingPart.fileName(index: 1), "part-0001.caf")
        XCTAssertEqual(RecordingPart.fileName(index: 24), "part-0024.caf")
        XCTAssertTrue(RecordingPart.isValidFileName("part-0007.caf"))
        for bad in ["part-0000.caf", "part-7.caf", "../part-0001.caf", "part-0001.m4a", "part-00a1.caf", "PART-0001.caf", "part-0001.caf/x", ""] {
            XCTAssertFalse(RecordingPart.isValidFileName(bad), bad)
        }
    }

    func testTheDefaultTitleIsDatedAndInTheUsersLanguage() {
        let date = Date(timeIntervalSince1970: 1_792_677_780) // 22 Oct 2026 14:03 UTC
        XCTAssertEqual(RecordingTitle.standard(startedAt: date, language: .english, calendar: utc), "Recording 22 Oct, 14:03")
        XCTAssertEqual(RecordingTitle.standard(startedAt: date, language: .polish, calendar: utc), "Nagranie 22 paź, 14:03")
        XCTAssertEqual(RecordingTitle.display("", startedAt: date, language: .english, calendar: utc), "Recording 22 Oct, 14:03")
        XCTAssertEqual(RecordingTitle.display("Budget call", startedAt: date, language: .english, calendar: utc), "Budget call")
    }

    func testATypedTitleIsOneCleanLine() {
        XCTAssertEqual(RecordingTitle.clean("  Budget\n\ncall \t with   Alex  "), "Budget call with Alex")
        XCTAssertEqual(RecordingTitle.clean("a\u{0007}b"), "a b")
        XCTAssertEqual(RecordingTitle.clean(String(repeating: "x", count: 500)).count, CaptureLimits.maxTitleCharacters)
        XCTAssertEqual(RecordingTitle.clean("   \n  "), "")
    }

    func testCategoriesCoverEveryKindOnce() {
        let tabs = RecordingCategory.allCases.filter { $0 != .all }
        let covered = tabs.flatMap { $0.kinds ?? [] }
        XCTAssertEqual(Set(covered), Set(RecordingKind.allCases))
        XCTAssertEqual(covered.count, RecordingKind.allCases.count, "no kind is in two tabs")
        XCTAssertNil(RecordingCategory.all.kinds)
    }

    func testOnlyShortcutStartsNeedALiveActivity() {
        XCTAssertFalse(CaptureOrigin.app.requiresLiveActivity)
        XCTAssertTrue(CaptureOrigin.intent.requiresLiveActivity)
        XCTAssertTrue(CaptureOrigin.control.requiresLiveActivity)
    }

    func testTheStatusLineNeverClaimsMoreThanIsTrue() {
        func line(_ phase: RecordingPhase, _ transcription: TranscriptionStatus, capturing: Bool = false) -> String {
            RecordingStatusText.line(Recording(id: id, origin: .app, phase: phase, languageCode: "pl-PL", startedAt: t0, transcription: transcription),
                                     isCapturingNow: capturing, .english)
        }
        XCTAssertEqual(line(.recording, .notStarted, capturing: true), "Recording")
        XCTAssertEqual(line(.recording, .notStarted, capturing: false), "Not finished", "an old unfinished row is not 'recording'")
        XCTAssertEqual(line(.lost, .notStarted), "Nothing could be saved")
        XCTAssertEqual(line(.saved, .done), "Transcript ready")
        XCTAssertEqual(line(.recovered, .noSpeech), "No speech found")
        XCTAssertTrue(line(.saved, .unsupportedLanguage).contains("can't write this language"))
        for transcription in [TranscriptionStatus.notStarted, .running, .done, .noSpeech, .unsupportedLanguage, .notAllowed, .failed] {
            XCTAssertFalse(RecordingStatusText.line(Recording(id: id, origin: .app, phase: .saved, languageCode: "en-GB", startedAt: t0, transcription: transcription), isCapturingNow: false, .polish).isEmpty)
        }
    }

    func testAGapIsShownOnlyWhenItIsHeard() {
        XCTAssertFalse(CaptureGap(atMilliseconds: 600_000, wallMilliseconds: 40, reason: .segmentRotation).isNoticeable)
        let call = CaptureGap(atMilliseconds: 60_000, wallMilliseconds: 192_000, reason: .interruption)
        XCTAssertTrue(call.isNoticeable)
        XCTAssertEqual(call.note(.english), "Recording was interrupted (3:12)")
    }

    func testStorageMathMatchesTheStatedHourlyCost() {
        let hour = CaptureLimits.estimatedBytes(seconds: 3600)
        XCTAssertEqual(hour, 14_400_000, "32 kbps is 14.4 MB an hour")
        XCTAssertGreaterThan(CaptureLimits.minFreeBytesToStart, CaptureLimits.estimatedBytes(seconds: CaptureLimits.maxSeconds),
                             "the start check leaves room for a whole capped recording")
    }

    // MARK: - Recovery

    private func part(_ index: Int, recorded: Int?, probed: Int?, modified: Date? = nil) -> UnfinishedPart {
        UnfinishedPart(index: index, fileName: RecordingPart.fileName(index: index), recordedMilliseconds: recorded, probedMilliseconds: probed, modifiedAt: modified)
    }

    func testRecoveryKeepsWhatCanBeReadAndSaysWhatCannot() {
        let unfinished = UnfinishedRecording(id: id, startedAt: t0, parts: [
            part(1, recorded: 600_000, probed: 600_100),
            part(2, recorded: 600_000, probed: nil),
            part(3, recorded: nil, probed: 95_000, modified: at(1500)),
        ])
        guard case .recover(let recovered) = CaptureRecovery.plan(unfinished) else { return XCTFail("expected recovery") }
        XCTAssertEqual(recovered.kept, [ClosedPart(index: 1, durationMilliseconds: 600_000), ClosedPart(index: 3, durationMilliseconds: 95_000)])
        XCTAssertEqual(recovered.lostPartIndices, [2])
        XCTAssertEqual(recovered.durationMilliseconds, 695_000)
        XCTAssertEqual(recovered.endedAt, at(1500))
        XCTAssertTrue(CaptureRecovery.notice(recovered, .english).contains("1 part(s) could not be read"))
    }

    func testRecoveryNeverClaimsMoreAudioThanTheFileShows() {
        let unfinished = UnfinishedRecording(id: id, startedAt: t0, parts: [part(1, recorded: 600_000, probed: 420_000)])
        guard case .recover(let recovered) = CaptureRecovery.plan(unfinished) else { return XCTFail("expected recovery") }
        XCTAssertEqual(recovered.durationMilliseconds, 420_000, "a truncated file is believed over the recorder's count")
    }

    func testAPartTheRecorderCountedButCannotBeReadIsNotKept() {
        let unfinished = UnfinishedRecording(id: id, startedAt: t0, parts: [part(1, recorded: 600_000, probed: nil)])
        XCTAssertEqual(CaptureRecovery.plan(unfinished), .lost(id: id, lostPartIndices: [1]))
    }

    func testNoAudioMeansLostNotDeleted() {
        let empty = UnfinishedRecording(id: id, startedAt: t0, parts: [])
        XCTAssertEqual(CaptureRecovery.plan(empty), .lost(id: id, lostPartIndices: []))
        let tiny = UnfinishedRecording(id: id, startedAt: t0, parts: [part(1, recorded: nil, probed: 300)])
        XCTAssertEqual(CaptureRecovery.plan(tiny), .lost(id: id, lostPartIndices: [1]))
    }

    func testTheRecordingBeingMadeRightNowIsLeftAlone() {
        let live = UnfinishedRecording(id: id, startedAt: t0, parts: [part(1, recorded: nil, probed: 5_000)])
        let other = UnfinishedRecording(id: UUID(), startedAt: t0, parts: [part(1, recorded: nil, probed: 5_000)])
        let decisions = CaptureRecovery.plan([live, other], activeID: id)
        XCTAssertEqual(decisions.count, 1)
        if case .recover(let recovered) = decisions[0] { XCTAssertEqual(recovered.id, other.id) } else { XCTFail("expected recovery") }
    }

    func testGapsPastTheRecoveredEndAreDropped() {
        let unfinished = UnfinishedRecording(id: id, startedAt: t0, parts: [part(1, recorded: nil, probed: 120_000)], gaps: [
            CaptureGap(atMilliseconds: 60_000, wallMilliseconds: 5_000, reason: .userPaused),
            CaptureGap(atMilliseconds: 900_000, wallMilliseconds: 5_000, reason: .interruption),
        ])
        guard case .recover(let recovered) = CaptureRecovery.plan(unfinished) else { return XCTFail("expected recovery") }
        XCTAssertEqual(recovered.gaps.map(\.atMilliseconds), [60_000])
    }

    func testOnlyFoldersNamedAfterARecordingAreEverCalledOrphans() {
        let known = UUID(), stray = UUID()
        let names = [known.uuidString.lowercased(), stray.uuidString.lowercased(), "Library", ".DS_Store", "notes", stray.uuidString]
        XCTAssertEqual(CaptureRecovery.orphanDirectories(onDisk: names, knownIDs: [known]), [stray.uuidString.lowercased()],
                       "other folders and upper-case look-alikes are never touched")
    }

    // MARK: - Live Activity content

    func testTheSnapshotFollowsTheState() {
        var machine = CaptureStateMachine()
        XCTAssertNil(CaptureActivitySnapshot.make(from: machine.state, now: at(0)))
        machine.handle(.startRequested(id: id, origin: .intent, at: at(0)))
        XCTAssertNil(CaptureActivitySnapshot.make(from: machine.state, now: at(0)), "a start in progress shows nothing")
        machine.handle(.preflightPassed(at: at(0)))
        machine.handle(.recorderStarted(partIndex: 1, at: at(1)))
        machine.handle(.activityUp)
        let recording = CaptureActivitySnapshot.make(from: machine.state, now: at(1))
        XCTAssertEqual(recording?.phase, .recording)
        XCTAssertEqual(recording?.anchor, at(1))

        machine.handle(.pauseRequested(at: at(61)))
        let paused = CaptureActivitySnapshot.make(from: machine.state, now: at(500))
        XCTAssertEqual(paused?.phase, .paused)
        XCTAssertEqual(paused?.capturedMilliseconds, 60_000, "paused time does not run")
        XCTAssertNil(paused?.anchor)

        machine.handle(.stopRequested(at: at(62)))
        XCTAssertEqual(CaptureActivitySnapshot.make(from: machine.state, now: at(62))?.phase, .saving)
    }

    func testTheTimerCountsAudioNotTheTimeSinceThePress() {
        let snapshot = CaptureActivitySnapshot(phase: .recording, capturedMilliseconds: 60_000, anchor: at(100))
        XCTAssertEqual(CapturePresentation.timerStart(snapshot), at(40), "one minute already captured when this stretch began")
        XCTAssertEqual(CapturePresentation.elapsedMilliseconds(snapshot, at: at(145)), 105_000)
        XCTAssertEqual(CapturePresentation.line(snapshot, at: at(145), .english), "Recording • 1:45")
        let paused = CaptureActivitySnapshot(phase: .paused, capturedMilliseconds: 75_000)
        XCTAssertNil(CapturePresentation.timerStart(paused))
        XCTAssertEqual(CapturePresentation.line(paused, at: at(9999), .english), "Paused • 1:15")
    }

    func testControlsAreOfferedOnlyWhereTheyDoSomething() {
        func controls(_ phase: CaptureActivitySnapshot.Phase) -> (pause: Bool, resume: Bool, stop: Bool) {
            let s = CaptureActivitySnapshot(phase: phase, capturedMilliseconds: 0)
            return (CapturePresentation.canPause(s), CapturePresentation.canResume(s), CapturePresentation.canStop(s))
        }
        XCTAssertTrue(controls(.recording) == (true, false, true))
        XCTAssertTrue(controls(.paused) == (false, true, true))
        XCTAssertTrue(controls(.interrupted) == (false, true, true))
        XCTAssertTrue(controls(.saving) == (false, false, false), "nothing to tap while it is being saved")
        XCTAssertTrue(controls(.saved) == (false, false, false))
    }

    func testEveryFailureHasASentenceInBothLanguages() {
        let all: [CaptureFailure] = [.microphoneDenied, .microphoneNotAsked, .microphoneBusy, .conversationRunning, .storageLow,
                                     .liveActivityUnavailable, .recorderCouldNotStart, .saveFailed, .databaseUnavailable, .appLocked, .noticeNotAccepted]
        for failure in all {
            XCTAssertGreaterThan(failure.message(.english).count, 20, "\(failure)")
            XCTAssertGreaterThan(failure.message(.polish).count, 20, "\(failure)")
            XCTAssertNotEqual(failure.message(.english), failure.message(.polish), "\(failure) is translated")
        }
        XCTAssertEqual(Set(all.map { $0.message(.english) }).count, all.count, "no two failures say the same thing")
    }

    func testTheNoticeIsReadOnceAndAgainWhenItsWordingChanges() {
        XCTAssertFalse(CaptureNotice.isAccepted(storedVersion: 0), "never accepted")
        XCTAssertTrue(CaptureNotice.isAccepted(storedVersion: CaptureNotice.version))
        XCTAssertFalse(CaptureNotice.isAccepted(storedVersion: CaptureNotice.version - 1), "an older wording is read again")
        for language in [NotificationLanguage.english, .polish] {
            XCTAssertEqual(CaptureNotice.points(language).count, 4)
            XCTAssertFalse(CaptureNotice.title(language).isEmpty)
            XCTAssertNotEqual(CaptureNotice.accept(language), CaptureNotice.decline(language))
        }
        let english = CaptureNotice.points(.english).joined(separator: " ")
        XCTAssertTrue(english.contains("orange microphone dot"), "the recording is shown, not hidden")
        XCTAssertTrue(english.contains("stay on this iPhone"))
        XCTAssertTrue(english.contains("does not become something Doddy remembers by itself"))
        XCTAssertFalse(english.lowercased().contains("legal to record"), "no claim about what the law says")
    }

    func testEveryButtonHasWordsInBothLanguages() {
        for action in [CapturePresentation.Action.pause, .resume, .stop, .open] {
            XCTAssertFalse(CapturePresentation.label(action, .english).isEmpty)
            XCTAssertFalse(CapturePresentation.label(action, .polish).isEmpty)
        }
        XCTAssertEqual(CapturePresentation.startedLine(.english), "Recording.")
        XCTAssertEqual(CapturePresentation.startedLine(.polish), "Nagrywam.")
    }

    func testTheLanguageOfARecordingFollowsTheUserNotAGuess() {
        XCTAssertEqual(CaptureLanguage.localeIdentifier(code: "pl", preferredLanguages: ["en-GB", "pl-PL"]), "pl-PL")
        XCTAssertEqual(CaptureLanguage.localeIdentifier(code: "pl", preferredLanguages: []), "pl-PL")
        XCTAssertEqual(CaptureLanguage.localeIdentifier(code: "en", preferredLanguages: ["en-US", "pl-PL"]), "en-US", "what the iPhone lists wins")
        XCTAssertEqual(CaptureLanguage.localeIdentifier(code: "en", preferredLanguages: ["pl-PL"]), "en-GB")
        XCTAssertEqual(CaptureLanguage.localeIdentifier(code: "pl", preferredLanguages: ["pl"]), "pl-PL", "a bare code gets its region")
        XCTAssertEqual(CaptureLanguage.localeIdentifier(code: "sv", preferredLanguages: []), "sv", "an unknown region is left to the recognizer")
        XCTAssertEqual(CaptureLanguage.code(conversationOverride: "pl", preferredLanguages: ["en-GB"]), "pl")
        XCTAssertEqual(CaptureLanguage.code(conversationOverride: nil, preferredLanguages: ["de-DE"]), "de")
        XCTAssertEqual(CaptureLanguage.code(conversationOverride: "", preferredLanguages: []), "en")
        XCTAssertEqual(CaptureLanguage.displayName("pl-PL"), "Polski")
        XCTAssertEqual(CaptureLanguage.displayName("en-GB"), "English")
        XCTAssertEqual(CapturePresentation.nearLimitNotice(minutesLeft: 10, .english), "The recording will stop and save in about 10 minutes.")
    }

    func testTheOrangeCueIsOnlyForAudioBeingCaptured() {
        for phase in [CaptureActivitySnapshot.Phase.paused, .interrupted, .saving, .saved] {
            XCTAssertFalse(CapturePresentation.isRecordingCue(CaptureActivitySnapshot(phase: phase, capturedMilliseconds: 0)), "\(phase)")
        }
        XCTAssertTrue(CapturePresentation.isRecordingCue(CaptureActivitySnapshot(phase: .recording, capturedMilliseconds: 0)))
    }

    /// The Lock Screen is visible to anyone, so the Live Activity's content holds no free text.
    func testTheSnapshotCarriesNoWordsFromTheRecording() throws {
        let snapshot = CaptureActivitySnapshot(phase: .interrupted, capturedMilliseconds: 12_000, anchor: at(1),
                                               interruption: .systemAudio, nearLimit: true, resumeFailed: true)
        let data = try JSONEncoder().encode(snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["phase", "capturedMilliseconds", "anchor", "interruption", "nearLimit", "resumeFailed"])
        let allowedWords: Set<String> = ["interrupted", "systemAudio"]
        for (key, value) in object {
            if let text = value as? String { XCTAssertTrue(allowedWords.contains(text), "\(key) holds free text: \(text)") }
        }
        XCTAssertEqual(try JSONDecoder().decode(CaptureActivitySnapshot.self, from: data), snapshot)
    }

    func testContentFromAnotherBuildStillDecodes() throws {
        let old = Data(#"{"phase":"recording"}"#.utf8)
        let decoded = try JSONDecoder().decode(CaptureActivitySnapshot.self, from: old)
        XCTAssertEqual(decoded, CaptureActivitySnapshot(phase: .recording, capturedMilliseconds: 0))
        let newer = Data(#"{"phase":"interrupted","interruption":"somethingNew","capturedMilliseconds":5}"#.utf8)
        let tolerant = try JSONDecoder().decode(CaptureActivitySnapshot.self, from: newer)
        XCTAssertEqual(tolerant.phase, .interrupted)
        XCTAssertNil(tolerant.interruption, "an unknown kind does not fail the whole decode")
    }

    // MARK: - The indicator and Stop listening

    func testTheIndicatorSaysARecordingIsOpenAndOnlyWhenItIs() throws {
        XCTAssertEqual(MicrophoneSnapshot(captureRecording: true).open, [.capture])
        XCTAssertNil(ListeningIndicator.current(MicrophoneSnapshot(captureRecording: false)))
        let indicator = try XCTUnwrap(ListeningIndicator.current(MicrophoneSnapshot(captureRecording: true)))
        XCTAssertEqual(indicator.kinds, [.capture])
        XCTAssertEqual(indicator.title(.english), "Doddy is recording")
        XCTAssertEqual(indicator.symbol, "record.circle.fill")
        let both = try XCTUnwrap(ListeningIndicator.current(MicrophoneSnapshot(conversation: .listening, captureRecording: true)))
        XCTAssertEqual(both.kinds, [.conversation, .capture])
    }

    func testStopListeningStopsARecordingAndOnlySaysSavedWhenItWas() {
        let before = MicrophoneSnapshot(captureRecording: true)
        let saved = ListeningStopReport(before: before, after: MicrophoneSnapshot(), release: .released, captureSaved: true)
        XCTAssertTrue(saved.stopped)
        XCTAssertEqual(saved.capture, .closed)
        XCTAssertTrue(saved.reply(.english).contains("saved in Recordings"))

        let unconfirmed = ListeningStopReport(before: before, after: MicrophoneSnapshot(), release: .released, captureSaved: false)
        XCTAssertFalse(unconfirmed.reply(.english).contains("is saved"), "stopped is not saved")
        XCTAssertTrue(unconfirmed.reply(.english).contains("hasn't confirmed"))

        let stuck = ListeningStopReport(before: before, after: before, release: .released)
        XCTAssertFalse(stuck.stopped)
        XCTAssertEqual(stuck.stillOpen, [.capture])
        XCTAssertTrue(stuck.reply(.english).contains("the recording"))
    }
}
