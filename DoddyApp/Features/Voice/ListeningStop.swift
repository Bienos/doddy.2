import AVFAudio
import DoddyCore
import Observation
import os

/// Stop listening (OP-024, ADR-361). Rules and words are in DoddyCore (ListeningPrivacy.swift); this
/// reads each microphone user's own state and stops them. The pill that showed above every screen
/// ("Doddy is listening · Stop listening") was removed on the owner's instruction on 9 Nov 2026
/// (decision 2026-11-09-no-listening-pill): iOS's own orange dot shows the microphone, and Siri's
/// "Stop listening in Doddy" still stops everything and says what it stopped.
@MainActor
enum ListeningStop {
    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "stop-listening")

    /// Who has the microphone open now, from each one's own state.
    static func snapshot() -> MicrophoneSnapshot {
        MicrophoneSnapshot(
            conversation: VoiceSessionController.microphone,
            voiceMemoRecording: MicrophoneHolders.shared.isRecording,
            captureRecording: RecordingCoordinator.shared.isCapturingAudio)
    }

    /// Ends the conversation and stops a voice memo, then reads each one
    /// again and asks iOS to let go of Doddy's audio. Nothing is saved by it.
    static func stopAll() async -> ListeningStopReport {
        let before = snapshot()
        var keptNoteDraft = false
        if let conversation = VoiceSessionController.current {
            keptNoteDraft = await conversation.stopListening()
        }
        let keptMemoDraft = MicrophoneHolders.shared.stopAll()
        // A DODDY Capture recording is stopped and saved (ADR-588); the report says "saved" only if it was read back.
        var captureSaved = false
        if before.open.contains(.capture) { captureSaved = await RecordingCoordinator.shared.stop() }
        var after = snapshot()
        let release: AudioRelease
        if before.open.isEmpty {
            release = .notNeeded
        } else if !after.open.isEmpty {
            // Still open: don't pull the audio from under it; the report says what is still on.
            release = .notNeeded
        } else {
            release = releaseAudio()
            after = snapshot()
        }
        let report = ListeningStopReport(before: before, after: after, release: release,
                                         keptNoteDraft: keptNoteDraft, keptMemoDraft: keptMemoDraft, captureSaved: captureSaved)
        log.notice("stop listening: still open \(report.stillOpen.map(\.rawValue), privacy: .public), release \(String(describing: release), privacy: .public)")
        ListeningIndicatorModel.shared.refresh()
        return report
    }

    /// Deactivating the session stops anything of Doddy's still recording or playing; iOS answers
    /// "busy" when it had to stop something, which still leaves the audio released.
    private static func releaseAudio() -> AudioRelease {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return .released
        } catch let error as NSError where error.code == AVAudioSession.ErrorCode.isBusy.rawValue {
            return .stoppedWhatWasRunning
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// Voice memo recorders that are recording now, so Stop listening can reach one on any screen.
@MainActor
final class MicrophoneHolders {
    static let shared = MicrophoneHolders()
    private var recorders: [ObjectIdentifier: WeakRecorder] = [:]

    private struct WeakRecorder { weak var recorder: VoiceMemoRecorder? }

    private init() {}

    var isRecording: Bool { recorders.values.contains { $0.recorder?.isCapturing == true } }

    func recording(_ recorder: VoiceMemoRecorder, _ on: Bool) {
        if on { recorders[ObjectIdentifier(recorder)] = WeakRecorder(recorder: recorder) } else { recorders[ObjectIdentifier(recorder)] = nil }
        ListeningIndicatorModel.shared.refresh()
    }

    /// Stops every recording; true when one was long enough to be kept as the note's draft.
    func stopAll() -> Bool {
        var kept = false
        for holder in recorders.values {
            if holder.recorder?.stopFromOutside() == true { kept = true }
        }
        recorders = recorders.filter { $0.value.recorder?.isCapturing == true }
        return kept
    }
}

/// Who is listening now and the answer to the last Stop listening. No longer drawn as a pill
/// (9 Nov 2026); kept so Stop listening and the recordings still report one state.
@MainActor
@Observable
final class ListeningIndicatorModel {
    static let shared = ListeningIndicatorModel()

    private(set) var indicator: ListeningIndicator?
    /// The answer to the last Stop listening, kept for a moment (or until dismissed when it failed).
    private(set) var result: ListeningStopReport?
    @ObservationIgnored private var clearResult: Task<Void, Never>?

    private init() {}

    func refresh() {
        indicator = ListeningIndicator.current(ListeningStop.snapshot())
    }

    /// Keeps the answer. "Stopped" goes away by itself; a failure stays until dismissed.
    func show(_ report: ListeningStopReport) {
        result = report
        clearResult?.cancel()
        if report.stopped {
            clearResult = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                self?.dismissResult()
            }
        }
        refresh()
    }

    func dismissResult() {
        result = nil
        refresh()
    }
}
