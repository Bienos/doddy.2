import ActivityKit
import AVFoundation
import DoddyCore
import Foundation
import Observation
import UIKit
import os

/// DODDY Capture's recorder (ADR-579): the one owner of a recording session. Every way in (the
/// button, Siri, the control, the Action Button, the island's buttons) calls this, so there is one
/// recorder, one state and one source of truth for "are we recording?".
///
/// It decides nothing itself. `CaptureStateMachine` (DoddyCore, tested on Linux) decides what each
/// event means; this class does what the machine asks (open a file, start AVAudioRecorder, ask for a
/// Live Activity, write the database) and reports back what really happened. "Recording" is shown
/// only after the recorder has delivered audio and, for a start from a shortcut or control, the Live
/// Activity is up.
///
/// Compiled by the hosted Mac build (PR #124); never run on a device, and no test records. The first
/// real behaviour needs an iPhone (docs/implementation/CAPTURE_STATUS.md).
@MainActor
@Observable
final class RecordingCoordinator {
    static let shared = RecordingCoordinator()

    enum StartOutcome: Equatable {
        case started(UUID)
        case rejected(StartRejection)
        case failed(CaptureFailure)
    }

    /// What the last session ended in, for the screen to say. Cleared when a new one starts.
    enum Outcome: Equatable {
        case saved(UUID)
        case tooShort
        case failed(CaptureFailure)
    }

    private(set) var machine = CaptureStateMachine()
    private(set) var lastOutcome: Outcome?
    /// A sentence for the screen that belongs to no state: the cap is near, or a save needs a look.
    private(set) var notice: String?

    var isActive: Bool { machine.isActive }
    var isCapturingAudio: Bool { machine.isCapturingAudio }
    var session: CaptureSession? { machine.session }

    // MARK: Collaborators and bookkeeping (not for the screen)

    @ObservationIgnored private var overrideEnvironment: AppEnvironment?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recorderDelegate: RecorderDelegate?
    @ObservationIgnored private var openPartIndex: Int?
    /// The recording this process is making, from the start until everything is closed. The state
    /// machine forgets its session at the end; this is how an effect that runs after that still
    /// knows which recording to delete.
    @ObservationIgnored private var activeID: UUID?
    @ObservationIgnored private var activeOrigin: CaptureOrigin = .app
    @ObservationIgnored private var isSwitchingPart = false
    /// A recorder is being started (resume, or the retry after an interruption). A second request
    /// meanwhile is ignored: two recorders on one file would corrupt the part.
    @ObservationIgnored private var isStartingPart = false
    /// Pause or an interruption is still saving the part it closed. A Stop waits for it, or the part
    /// would be missing from the save and its audio removed.
    @ObservationIgnored private var closesInFlight = 0
    /// Parts whose row could not be written when they opened (part index → start offset).
    @ObservationIgnored private var openDebt: [Int: Int] = [:]
    @ObservationIgnored private var persistenceDebt: [Int: Int] = [:]
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private let activity = RecordingActivityController()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var installed = false
    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "capture")

    private init() {}

    /// For tests and previews.
    func configure(environment: AppEnvironment) { overrideEnvironment = environment }

    /// The notice before the first recording (`CaptureNotice`) has been accepted in the app.
    static var noticeAccepted: Bool {
        CaptureNotice.isAccepted(storedVersion: UserDefaults.standard.integer(forKey: CaptureNotice.preferenceKey))
    }

    static func acceptNotice() {
        UserDefaults.standard.set(CaptureNotice.version, forKey: CaptureNotice.preferenceKey)
    }

    private var environment: AppEnvironment { overrideEnvironment ?? AppEnvironment.shared }
    private var repository: (any RecordingRepository)? { environment.recordingRepository }
    private var files: RecordingFiles { environment.recordingFiles }

    /// Registers the island's buttons and the audio session's notifications. Called once, as the app starts.
    func install() {
        guard !installed else { return }
        installed = true
        let actions = CaptureActivityActions.shared
        actions.stop = { [weak self] in _ = await self?.stop() }
        actions.pause = { [weak self] in await self?.pause() }
        actions.resume = { [weak self] in await self?.resume() }
        activity.onEndedBySystem = { [weak self] in
            Task { @MainActor in await self?.send(.activityEnded) }
        }
        watchAudioSession()
    }

    // MARK: - What the screens and intents call

    /// Starts a recording and returns once the recorder has delivered audio, or has failed. A second
    /// call while one is going is rejected, never queued.
    func start(origin: CaptureOrigin) async -> StartOutcome {
        install()
        let id = UUID()
        let effects = machine.handle(.startRequested(id: id, origin: origin, at: .now))
        if effects.contains(.rejectStart(.alreadyActive)) { return .rejected(.alreadyActive) }
        activeID = id
        activeOrigin = origin
        lastOutcome = nil
        notice = nil
        startTicking()
        refreshIndicator()
        await run(effects)
        // The checks, the file and the Live Activity each take a moment; the machine moves on as
        // their answers arrive, or gives up by itself (`startTimeoutSeconds`).
        while case .preparing = machine.state { try? await Task.sleep(for: .milliseconds(100)) }
        if isCapturingAudio { return .started(id) }
        if case .failed(let failure) = lastOutcome { return .failed(failure) }
        return .failed(.recorderCouldNotStart)
    }

    /// Stops and saves. True only when the recording is saved and read back.
    @discardableResult
    func stop() async -> Bool {
        guard machine.isActive else {
            await activity.endLeftovers()
            return false
        }
        await send(.stopRequested(at: .now))
        let deadline = Date.now.addingTimeInterval(CaptureStateMachine.finalizeTimeoutSeconds + 5)
        while machine.isActive, Date.now < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        if case .saved = lastOutcome { return true }
        return false
    }

    func pause() async { await send(.pauseRequested(at: .now)) }
    func resume() async { await send(.resumeRequested(at: .now)) }

    // MARK: - The loop

    private func send(_ event: CaptureEvent) async {
        // A part switch is a few milliseconds of bookkeeping that must not be cut in half: a Stop that
        // arrived in the middle would close the old part and leave the new one running unregistered.
        if isSwitchingPart, Self.waitsForPartSwitch(event) {
            for _ in 0..<100 where isSwitchingPart { try? await Task.sleep(for: .milliseconds(20)) }
        }
        let effects = machine.handle(event)
        noteOutcome()
        await run(effects)
        if !machine.isActive { teardown() }
        refreshIndicator()
    }

    private static func waitsForPartSwitch(_ event: CaptureEvent) -> Bool {
        switch event {
        case .stopRequested, .pauseRequested, .resumeRequested, .interruptionBegan, .recorderStoppedUnexpectedly, .storageLow: true
        default: false
        }
    }

    private func run(_ effects: [CaptureEffect]) async {
        for effect in effects { await perform(effect) }
    }

    /// Copies an end state out for the screen, then lets the machine rest so the next start is never
    /// held up behind a screen that has not looked yet.
    private func noteOutcome() {
        switch machine.state {
        case .finished(.saved(let saved)):
            lastOutcome = .saved(saved.id)
            if let note = saved.reason.note(.current) { notice = note }
            machine.handle(.acknowledged)
            RecordingProcessor.shared.enqueue(saved.id)
        case .finished(.discardedTooShort):
            lastOutcome = .tooShort
            machine.handle(.acknowledged)
        case .failed(let failure):
            lastOutcome = .failed(failure)
            notice = failure.message(.current)
            machine.handle(.acknowledged)
        default:
            break
        }
    }

    private func perform(_ effect: CaptureEffect) async {
        switch effect {
        case .runPreflight(let origin):
            if let failure = await preflight(origin) {
                await send(.preflightFailed(failure))
            } else {
                await send(.preflightPassed(at: .now))
            }
        case .startRecorder(let index):
            guard !isStartingPart else { return }
            isStartingPart = true
            defer { isStartingPart = false }
            await startRecorderPart(index)
        case .startActivity:
            await requestActivity()
        case .updateActivity:
            await updateActivity()
        case .rotate(let closing, let opening):
            await rotate(closing: closing, opening: opening)
        case .closePart(let index):
            closesInFlight += 1
            defer { closesInFlight -= 1 }
            let milliseconds = await closeOpenPart(index)
            await persistClosed(index, milliseconds)
            await send(.partClosed(index: index, milliseconds: milliseconds, at: .now))
        case .finalize:
            await finalize()
        case .discard:
            await discardEverything()
        case .checkpoint:
            await checkpoint()
        case .warnNearLimit(let minutes):
            notice = CapturePresentation.nearLimitNotice(minutesLeft: minutes, .current)
            await updateActivity()
        case .rejectStart:
            break
        }
    }

    // MARK: - Checks before audio

    private func preflight(_ origin: CaptureOrigin) async -> CaptureFailure? {
        // An intent that opens Doddy runs while the app is still coming to the front, and iOS grants a
        // Live Activity and the microphone question only to an app that is on screen. Give it a moment.
        if origin != .app {
            for _ in 0..<50 where UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        guard !AppLock.shared.isLocked else { return .appLocked }
        // Read once in the app, before any start, so a start from Siri or a control is never the first notice.
        guard Self.noticeAccepted else { return .noticeNotAccepted }
        guard VoiceSessionController.runningConversation == nil else { return .conversationRunning }
        // A voice memo has the microphone: starting here would take the audio session from it.
        guard !MicrophoneHolders.shared.isRecording else { return .microphoneBusy }
        guard repository != nil, files.directory != nil else { return .databaseUnavailable }
        if origin.requiresLiveActivity, !ActivityAuthorizationInfo().areActivitiesEnabled { return .liveActivityUnavailable }
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            break
        case .denied:
            return .microphoneDenied
        case .undetermined:
            // iOS can only ask with Doddy on screen.
            guard UIApplication.shared.applicationState == .active else { return .microphoneNotAsked }
            guard await AVAudioApplication.requestRecordPermission() else { return .microphoneDenied }
        @unknown default:
            return .microphoneDenied
        }
        if let free = files.freeBytes(), free < CaptureLimits.minFreeBytesToStart { return .storageLow }
        return nil
    }

    // MARK: - Starting a part

    /// AAC at 16 kHz mono is clear for speech and about 14 MB an hour. Whether this iPhone accepts it
    /// in a .caf file is not known from here, so there are two fallbacks, each larger, rather than a
    /// recorder that refuses to start. Which one was used is logged.
    private static let settingsChain: [[String: Any]] = [
        [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: CaptureLimits.sampleRate, AVNumberOfChannelsKey: 1,
         AVEncoderBitRateKey: CaptureLimits.bitRate, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue],
        [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1,
         AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue],
        [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: CaptureLimits.sampleRate, AVNumberOfChannelsKey: 1,
         AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false],
    ]

    private static var routeOptions: AVAudioSession.CategoryOptions {
        #if swift(>=6.2)
        [.allowBluetoothHFP]
        #else
        [.allowBluetooth]
        #endif
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        // Record only: nothing here plays. Headsets work; other apps' sound is stopped, as for any recording.
        try session.setCategory(.record, mode: .default, options: Self.routeOptions)
        try session.setActive(true)
    }

    private func makeRecorder(id: UUID, fileName: String) throws -> (AVAudioRecorder, RecorderDelegate) {
        guard let url = files.url(recordingID: id, fileName: fileName) else { throw RecordingStoreError.badFileName }
        var lastError: any Error = CocoaError(.fileWriteUnknown)
        for (position, settings) in Self.settingsChain.enumerated() {
            do {
                let recorder = try AVAudioRecorder(url: url, settings: settings)
                let delegate = RecorderDelegate(owner: self)
                recorder.delegate = delegate
                guard recorder.prepareToRecord() else { throw CocoaError(.fileWriteUnknown) }
                Self.log.notice("recorder settings \(position, privacy: .public) accepted")
                return (recorder, delegate)
            } catch {
                lastError = error
                Self.log.notice("recorder settings \(position, privacy: .public) refused: \(LogSafeError.kind(of: error), privacy: .public)")
            }
        }
        throw lastError
    }

    /// Opens the part's row and file, starts the recorder, and waits until audio is really coming in.
    private func startRecorderPart(_ index: Int) async {
        guard let repository, let id = activeID else {
            await send(.recorderFailedToStart(.databaseUnavailable))
            return
        }
        do {
            if index == 1 {
                // The row first: a kill a moment later still leaves something to recover.
                _ = try await repository.begin(id: id, origin: activeOrigin, languageCode: Self.recordingLanguage(), startedAt: .now)
            }
            try activateSession()
            let offset = machine.session?.closedMilliseconds ?? 0
            let part = try await repository.openPart(recordingID: id, index: index, startOffsetMilliseconds: offset)
            try files.prepareFolder(for: id)
            let (newRecorder, delegate) = try makeRecorder(id: id, fileName: part.fileName)
            guard newRecorder.record() else { throw AudioStartError.refused }
            if let url = files.url(recordingID: id, fileName: part.fileName) {
                try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            }
            // record() returning true is not proof of audio: a call or another app can hold the microphone.
            var heard = false
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(100))
                guard newRecorder.isRecording else { break }
                if newRecorder.currentTime > 0.05 { heard = true; break }
            }
            guard heard else {
                newRecorder.stop()
                throw AudioStartError.noAudio
            }
            guard machineExpects(part: index) else {
                // Stop, the give-up or an interruption came while the recorder was starting: this audio
                // belongs to nobody. Telling the machine would make it throw the whole recording away.
                newRecorder.stop()
                Self.log.notice("a recorder started after the machine moved on; stopped")
                if !machine.isActive {
                    _ = try? await repository.discard(recordingID: id)
                    files.remove(recordingID: id)
                } else if openPartIndex != index {
                    files.remove(recordingID: id, fileNames: [part.fileName])
                }
                return
            }
            recorder = newRecorder
            recorderDelegate = delegate
            openPartIndex = index
            await send(.recorderStarted(partIndex: index, at: .now))
        } catch {
            Self.log.notice("recorder did not start: \(LogSafeError.kind(of: error), privacy: .public), code \((error as NSError).code, privacy: .public)")
            await send(.recorderFailedToStart(Self.failure(for: error)))
        }
    }

    private enum AudioStartError: Error { case refused, noAudio }

    /// Whether the machine is waiting for exactly this part to start.
    private func machineExpects(part index: Int) -> Bool {
        switch machine.state {
        case .preparing: index == 1
        case .paused(let s), .interrupted(let s, _): s.nextPartIndex == index
        default: false
        }
    }

    private static func failure(for error: any Error) -> CaptureFailure {
        if error is RecordingStoreError { return .databaseUnavailable }
        if error is AudioStartError { return .microphoneBusy }
        let code = (error as NSError).code
        let busy = [AVAudioSession.ErrorCode.cannotStartRecording.rawValue, AVAudioSession.ErrorCode.insufficientPriority.rawValue,
                    AVAudioSession.ErrorCode.isBusy.rawValue, AVAudioSession.ErrorCode.siriIsRecording.rawValue]
        return busy.contains(code) ? .microphoneBusy : .recorderCouldNotStart
    }

    /// The language the recording will be written out in: the one chosen for conversations, else the iPhone's.
    static func recordingLanguage() -> String {
        let code = CaptureLanguage.code(conversationOverride: ConversationLanguage.stored().overrideCode, preferredLanguages: Locale.preferredLanguages)
        return CaptureLanguage.localeIdentifier(code: code, preferredLanguages: Locale.preferredLanguages)
    }

    // MARK: - The Live Activity

    private func requestActivity() async {
        switch machine.state {
        case .preparing(let pending):
            // Only once the recorder has delivered audio, so the island never says "recording" first.
            // If it has not, nothing is shown and the start gives up by itself.
            guard let started = pending.recorderStartedAt else { return }
            let snapshot = CaptureActivitySnapshot(phase: .recording, capturedMilliseconds: 0, anchor: started)
            if activity.start(recordingID: pending.id, startedAt: started, snapshot: snapshot) {
                await send(.activityUp)
            } else {
                await send(.activityUnavailable)
            }
        case .recording, .paused, .interrupted:
            // A new one after iOS ended the old (the machine asked). Allowed only with Doddy on screen.
            guard !activity.isUp, let session = machine.session,
                  let snapshot = CaptureActivitySnapshot.make(from: machine.state, now: .now) else { return }
            if activity.start(recordingID: session.id, startedAt: session.startedAt, snapshot: snapshot) {
                await send(.activityUp)
            }
        default:
            break
        }
    }

    private func updateActivity() async {
        guard activity.isUp, let snapshot = CaptureActivitySnapshot.make(from: machine.state, now: .now) else { return }
        await activity.update(snapshot)
    }

    // MARK: - Parts

    /// Stops the recorder for the open part and returns how much audio the file holds.
    private func closeOpenPart(_ index: Int) async -> Int {
        let fallback = estimatedOpenPartMilliseconds()
        guard let closing = recorder, openPartIndex == index else { return fallback }
        let url = closing.url
        let seconds = closing.currentTime
        // Forget it before stopping: its "finished" callback is then known to be our own doing.
        recorder = nil
        recorderDelegate = nil
        openPartIndex = nil
        closing.stop()
        return files.probeDurationMilliseconds(url) ?? (seconds > 0 ? Int(seconds * 1000) : fallback)
    }

    private func estimatedOpenPartMilliseconds() -> Int {
        guard let open = machine.session?.openPart else { return 0 }
        return CaptureStateMachine.milliseconds(from: open.startedAt, to: open.endedAt ?? .now)
    }

    /// Ten minutes in: the next part is prepared first, so the gap is only the stop and the record call.
    private func rotate(closing: Int, opening: Int) async {
        guard let id = activeID, let old = recorder, openPartIndex == closing else {
            await send(.rotationAborted(at: .now))
            return
        }
        isSwitchingPart = true
        defer { isSwitchingPart = false }
        let next: (AVAudioRecorder, RecorderDelegate)
        do {
            next = try makeRecorder(id: id, fileName: RecordingPart.fileName(index: opening))
        } catch {
            Self.log.notice("next part not prepared: \(LogSafeError.kind(of: error), privacy: .public)")
            await send(.rotationAborted(at: .now))
            return
        }
        let oldURL = old.url
        let oldSeconds = old.currentTime
        recorder = nil
        recorderDelegate = nil
        old.stop()
        let stoppedAt = Date.now
        guard next.0.record(), next.0.isRecording else {
            openPartIndex = nil
            let milliseconds = files.probeDurationMilliseconds(oldURL) ?? Int(oldSeconds * 1000)
            await persistClosed(closing, milliseconds)
            await send(.rotationFailed(closedPart: closing, closedMilliseconds: milliseconds, at: .now))
            return
        }
        recorder = next.0
        recorderDelegate = next.1
        openPartIndex = opening
        let gap = CaptureStateMachine.milliseconds(from: stoppedAt, to: .now)
        let closedMilliseconds = files.probeDurationMilliseconds(oldURL) ?? Int(oldSeconds * 1000)
        let offset = (machine.session?.closedMilliseconds ?? 0) + closedMilliseconds
        await persistClosed(closing, closedMilliseconds)
        await persistOpened(opening, offset: offset)
        await send(.segmentRotated(closedPart: closing, closedMilliseconds: closedMilliseconds, newPart: opening, gapMilliseconds: gap, at: .now))
    }

    // MARK: - The database, with a second try

    private func persistClosed(_ index: Int, _ milliseconds: Int) async {
        guard let repository, let id = activeID else { return }
        for attempt in 0..<2 {
            do {
                try await repository.closePart(recordingID: id, index: index, durationMilliseconds: milliseconds)
                persistenceDebt[index] = nil
                return
            } catch {
                Self.log.notice("closing part \(index, privacy: .public) not saved (try \(attempt, privacy: .public)): \(LogSafeError.kind(of: error), privacy: .public)")
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        // The audio goes on. The save at the end tries again, and says so if it still cannot.
        persistenceDebt[index] = milliseconds
    }

    private func persistOpened(_ index: Int, offset: Int) async {
        guard let repository, let id = activeID else { return }
        for _ in 0..<2 {
            if (try? await repository.openPart(recordingID: id, index: index, startOffsetMilliseconds: offset)) != nil {
                openDebt[index] = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        // The audio goes on into a part with no row. It is tried again at the next checkpoint and
        // before the save; without the row the audio could not be found after a kill.
        openDebt[index] = offset
        Self.log.notice("opening part \(index, privacy: .public) not saved")
    }

    /// Writes what an earlier try could not: part rows first, then lengths.
    private func settleDebts(_ repository: any RecordingRepository, _ id: UUID) async {
        for (index, offset) in openDebt {
            if (try? await repository.openPart(recordingID: id, index: index, startOffsetMilliseconds: offset)) != nil {
                openDebt[index] = nil
            }
        }
        for (index, milliseconds) in persistenceDebt {
            if (try? await repository.closePart(recordingID: id, index: index, durationMilliseconds: milliseconds)) != nil {
                persistenceDebt[index] = nil
            }
        }
    }

    private func checkpoint() async {
        guard let repository, let id = activeID, let gaps = machine.session?.gaps else { return }
        if !openDebt.isEmpty || !persistenceDebt.isEmpty { await settleDebts(repository, id) }
        try? await repository.checkpoint(recordingID: id, gaps: gaps)
    }

    // MARK: - Ending

    private func finalize() async {
        guard let repository, let id = activeID else {
            await send(.finalizeFailed)
            return
        }
        // The microphone first: nothing below may keep it open, and iOS can take a while to answer an activity update.
        if let open = machine.session?.openPart, openPartIndex == open.index {
            let milliseconds = await closeOpenPart(open.index)
            await persistClosed(open.index, milliseconds)
            await send(.partClosed(index: open.index, milliseconds: milliseconds, at: .now))
        }
        // A pause or an interruption may still be saving the part it closed; its length has to be in before the save.
        for _ in 0..<100 where closesInFlight > 0 { try? await Task.sleep(for: .milliseconds(20)) }
        await updateActivity() // "Saving…"
        guard let session = machine.session, case .finalizing(_, let reason) = machine.state else { return }
        // Any row or length that did not reach the database is tried once more before the recording is called saved.
        await settleDebts(repository, id)
        do {
            let finished = try await repository.finish(
                recordingID: id, phase: .saved, endedAt: .now, endReason: reason, parts: session.closedParts, gaps: session.gaps)
            files.remove(recordingID: id, fileNames: finished.removedFileNames)
            let total = finished.recording.durationMilliseconds
            if total >= CaptureLimits.minMilliseconds {
                await activity.end(final: CaptureActivitySnapshot(phase: .saved, capturedMilliseconds: total), dismissAfter: 8)
            }
            await send(.finalized(parts: session.closedParts, at: .now))
        } catch {
            Self.log.notice("recording not saved: \(LogSafeError.kind(of: error), privacy: .public)")
            await activity.end(final: nil, dismissAfter: 0)
            // The row and the audio files stay: the next launch recovers them.
            await send(.finalizeFailed)
        }
    }

    /// Nothing worth keeping: stop everything, remove the row and the files, take the island down.
    private func discardEverything() async {
        let stopping = recorder
        recorder = nil
        recorderDelegate = nil
        openPartIndex = nil
        stopping?.stop()
        if let id = activeID {
            _ = try? await repository?.discard(recordingID: id)
            files.remove(recordingID: id)
        }
        await activity.end(final: nil, dismissAfter: 0)
    }

    /// Everything of this session is closed: the audio session is given back and the clock stops.
    private func teardown() {
        guard !machine.isActive else { return }
        ticker?.cancel()
        ticker = nil
        tickCount = 0
        activeID = nil
        persistenceDebt = [:]
        openDebt = [:]
        isSwitchingPart = false
        isStartingPart = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func refreshIndicator() {
        ListeningIndicatorModel.shared.refresh()
    }

    // MARK: - The clock, and checking that what the machine believes is true

    private func startTicking() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                await self.tickOnce()
            }
        }
    }

    private func tickOnce() async {
        tickCount += 1
        await healthCheck()
        if tickCount % 20 == 0, machine.isActive, let free = files.freeBytes() {
            await send(.storageLow(freeBytes: free, at: .now))
        }
        await send(.tick(at: .now))
    }

    /// The machine says audio is being written; the recorder has the last word.
    private func healthCheck() async {
        guard machine.isCapturingAudio, !isSwitchingPart else { return }
        if recorder?.isRecording != true {
            Self.log.notice("the recorder stopped by itself")
            await reportRecorderStopped()
        }
    }

    /// The recorder stopped and nobody said why. A call, an alarm or Siri is announced by iOS close to
    /// the moment the recorder stops, so the machine gets a moment to hear that first: otherwise it
    /// would retry into the call and spend its attempts before the interruption ends.
    private func reportRecorderStopped() async {
        try? await Task.sleep(for: .milliseconds(700))
        guard machine.isCapturingAudio, !isSwitchingPart, recorder?.isRecording != true else { return }
        await send(.recorderStoppedUnexpectedly(at: .now))
    }

    /// A recorder said it finished. Ours, deliberately closed, were forgotten first, so this is news.
    fileprivate func recorderFinished(_ key: ObjectIdentifier) {
        guard let recorder, ObjectIdentifier(recorder) == key, machine.isCapturingAudio, !isSwitchingPart else { return }
        Task { await reportRecorderStopped() }
    }

    // MARK: - iOS's audio notifications

    private func watchAudioSession() {
        let center = NotificationCenter.default
        let ref = CoordinatorRef(self)
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
                let info = note.userInfo
                let type = (info?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
                let reason = (info?[AVAudioSessionInterruptionReasonKey] as? UInt).flatMap(AVAudioSession.InterruptionReason.init(rawValue:))
                let options = (info?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:))
                Task { @MainActor in await ref.value?.audioInterruption(type: type, reason: reason, options: options) }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
                let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
                Task { @MainActor in await ref.value?.routeChanged(reasonCode: reason) }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in await ref.value?.send(.interruptionBegan(.mediaServicesReset, at: .now)) }
            },
        ]
    }

    fileprivate func audioInterruption(type: AVAudioSession.InterruptionType?, reason: AVAudioSession.InterruptionReason?,
                                       options: AVAudioSession.InterruptionOptions?) async {
        guard machine.isActive else { return }
        switch type {
        case .began:
            // iOS says little: a call, an alarm, Siri and another app's microphone all look alike.
            let kind: InterruptionKind
            switch reason {
            case .builtInMicMuted: kind = .builtInMicMuted
            case .routeDisconnected: kind = .routeDisconnected
            default: kind = .systemAudio
            }
            Self.log.notice("audio interrupted: \(kind.rawValue, privacy: .public)")
            await send(.interruptionBegan(kind, at: .now))
        case .ended:
            let shouldResume = options?.contains(.shouldResume) == true
            Self.log.notice("audio interruption ended, resume allowed: \(shouldResume, privacy: .public)")
            await send(.interruptionEnded(shouldResume: shouldResume, at: .now))
        default:
            break
        }
    }

    /// Headphones taken off, Bluetooth lost, another input chosen. Recording usually carries on from the
    /// iPhone's own microphone; if it did not, the check says so and the machine hears about it.
    fileprivate func routeChanged(reasonCode: UInt) async {
        guard machine.isCapturingAudio else { return }
        Self.log.notice("audio route changed, reason code \(reasonCode, privacy: .public)")
        try? await Task.sleep(for: .milliseconds(400))
        await healthCheck()
    }

    // MARK: - After Doddy was closed in the middle of a recording

    /// Finishes what a kill left half done: reads each unfinished recording's files, keeps what can be
    /// read, says what could not, and removes folders that belong to nothing. Runs once the first
    /// screen is up (`LaunchWork`). Never touches the recording being made now.
    func recoverUnfinished() async {
        guard let repository, !machine.isActive else { return }
        await activity.endLeftovers()
        let records = (try? await repository.unfinished()) ?? []
        for record in records where record.id != activeID {
            let parts = record.parts.map { part -> UnfinishedPart in
                let url = files.url(recordingID: record.id, fileName: part.fileName)
                return UnfinishedPart(
                    index: part.index, fileName: part.fileName, recordedMilliseconds: part.durationMilliseconds,
                    probedMilliseconds: url.flatMap(files.probeDurationMilliseconds), modifiedAt: url.flatMap(files.modifiedAt))
            }
            switch CaptureRecovery.plan(UnfinishedRecording(id: record.id, startedAt: record.startedAt, parts: parts, gaps: record.gaps)) {
            case .recover(let recovered):
                if let finished = try? await repository.finish(
                    recordingID: recovered.id, phase: .recovered, endedAt: recovered.endedAt, endReason: .recovered,
                    parts: recovered.kept, gaps: recovered.gaps) {
                    files.remove(recordingID: recovered.id, fileNames: finished.removedFileNames)
                    notice = CaptureRecovery.notice(recovered, .current)
                    RecordingProcessor.shared.enqueue(recovered.id)
                }
            case .lost(let id, _):
                try? await repository.markLost(recordingID: id, endedAt: .now)
                files.remove(recordingID: id)
            }
        }
        if let known = try? await repository.allIDs() {
            for name in CaptureRecovery.orphanDirectories(onDisk: files.folderNames(), knownIDs: known) {
                // A recording that began while this ran has a folder and, as far as `known` goes, no row.
                guard !machine.isActive, name != activeID?.uuidString.lowercased() else { continue }
                files.removeFolder(named: name)
            }
        }
        await RecordingProcessor.shared.resumePending()
    }
}

/// Lets a notification callback (which must be `@Sendable`) reach the coordinator without a cycle.
private final class CoordinatorRef: @unchecked Sendable {
    weak var value: RecordingCoordinator?
    init(_ value: RecordingCoordinator) { self.value = value }
}

/// AVAudioRecorder's callbacks arrive on an arbitrary thread; only the recorder's identity crosses.
private final class RecorderDelegate: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
    weak var owner: RecordingCoordinator?

    init(owner: RecordingCoordinator) { self.owner = owner }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let key = ObjectIdentifier(recorder)
        Task { @MainActor [owner = self.owner] in owner?.recorderFinished(key) }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        let key = ObjectIdentifier(recorder)
        Task { @MainActor [owner = self.owner] in owner?.recorderFinished(key) }
    }
}
