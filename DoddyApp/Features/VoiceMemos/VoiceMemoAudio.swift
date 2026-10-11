import AVFoundation
import DoddyCore
import Foundation
import Observation

/// Records one voice memo (ADR-230) to a temporary file, at most `VoiceMemoLimits.maxSeconds`.
/// The microphone is on only between Record and Stop, and the recording never leaves the iPhone.
@MainActor
@Observable
final class VoiceMemoRecorder {
    enum State: Equatable {
        case idle
        case recording(startedAt: Date)
        case failed(String)
    }

    /// A finished recording, still in the temporary folder until the note is saved.
    struct Recording: Equatable {
        let url: URL
        let durationMilliseconds: Int
    }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    /// Set when recording stopped without Stop: the limit was reached, or iOS stopped it (a call).
    private(set) var stoppedByItself = false
    private var recorder: AVAudioRecorder?
    private var ticker: Task<Void, Never>?

    var isRecording: Bool { if case .recording = state { true } else { false } }
    /// The microphone is recording now, as AVAudioRecorder says (Stop listening, ADR-335).
    var isCapturing: Bool { recorder?.isRecording == true }

    /// Asks for the microphone once (the same permission as talking to Doddy), then records.
    func start() async {
        guard !isRecording else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .failed(NSLocalizedString("The microphone is off for Doddy. Turn it on in the Settings app to record.", comment: ""))
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DoddyMemo-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        // "Hey Doddy" listening (ADR-254) steps aside while a memo is recorded.
        WakeWordListener.shared.appSound(ObjectIdentifier(self), playing: true)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record(forDuration: TimeInterval(VoiceMemoLimits.maxSeconds)) else {
                throw CocoaError(.fileWriteUnknown)
            }
            self.recorder = recorder
            elapsed = 0
            stoppedByItself = false
            state = .recording(startedAt: Date())
            MicrophoneHolders.shared.recording(self, true)
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let self, let recorder = self.recorder else { return }
                    if recorder.isRecording {
                        self.elapsed = recorder.currentTime
                    } else {
                        // Stopped by itself at the limit (or by iOS, e.g. a phone call).
                        self.ticker = nil
                        self.stoppedByItself = true
                        return
                    }
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            WakeWordListener.shared.appSound(ObjectIdentifier(self), playing: false)
            state = .failed(NSLocalizedString("Recording couldn't start. If you're talking to Doddy or on a call, finish that first.", comment: ""))
        }
    }

    /// Stops and returns the recording, or nil for a mis-tap shorter than half a second.
    func stop() -> Recording? {
        ticker?.cancel()
        ticker = nil
        guard let recorder else { return nil }
        let seconds = recorder.isRecording ? recorder.currentTime : max(elapsed, recorder.currentTime)
        recorder.stop()
        self.recorder = nil
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        WakeWordListener.shared.appSound(ObjectIdentifier(self), playing: false)
        MicrophoneHolders.shared.recording(self, false)
        let milliseconds = min(Int((seconds * 1000).rounded()), VoiceMemoLimits.maxSeconds * 1000)
        guard MemoryAudio.isValidDuration(milliseconds), FileManager.default.fileExists(atPath: recorder.url.path) else {
            try? FileManager.default.removeItem(at: recorder.url)
            return nil
        }
        return Recording(url: recorder.url, durationMilliseconds: milliseconds)
    }

    /// Stop listening (ADR-335): the microphone stops now, and the note's screen keeps what was
    /// recorded as its draft, as when the 5-minute limit is reached (`stoppedByItself`). True when
    /// it is long enough to keep.
    func stopFromOutside() -> Bool {
        guard let recorder, recorder.isRecording else { return false }
        ticker?.cancel()
        ticker = nil
        let seconds = recorder.currentTime
        elapsed = seconds
        recorder.stop()
        state = .idle
        stoppedByItself = true
        return MemoryAudio.isValidDuration(min(Int((seconds * 1000).rounded()), VoiceMemoLimits.maxSeconds * 1000))
    }

    /// Stops and throws the recording away.
    func cancel() {
        if let recording = stop() { try? FileManager.default.removeItem(at: recording.url) }
    }
}

/// Plays one recording on this iPhone.
@MainActor
@Observable
final class VoiceMemoPlayer {
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var problem: String?
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    func toggle(_ url: URL) {
        if isPlaying {
            pause()
            return
        }
        do {
            if player?.url != url {
                player = try AVAudioPlayer(contentsOf: url)
                position = 0
            }
            // "Hey Doddy" listening (ADR-254) steps aside while a memo plays.
            WakeWordListener.shared.appSound(ObjectIdentifier(self), playing: true)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            guard player?.play() == true else { throw CocoaError(.fileReadUnknown) }
            problem = nil
            isPlaying = true
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard let self, let player = self.player else { return }
                    self.position = player.currentTime
                    if !player.isPlaying {
                        self.finished()
                        return
                    }
                }
            }
        } catch {
            problem = NSLocalizedString("This recording couldn't be played.", comment: "")
            isPlaying = false
            WakeWordListener.shared.appSound(ObjectIdentifier(self), playing: false)
        }
    }

    func pause() {
        player?.pause()
        ticker?.cancel()
        ticker = nil
        isPlaying = false
        WakeWordListener.shared.appSound(ObjectIdentifier(self), playing: false)
    }

    func stop() {
        player?.stop()
        player = nil
        ticker?.cancel()
        ticker = nil
        isPlaying = false
        position = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        WakeWordListener.shared.appSound(ObjectIdentifier(self), playing: false)
    }

    private func finished() {
        ticker = nil
        isPlaying = false
        position = 0
        player?.currentTime = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        WakeWordListener.shared.appSound(ObjectIdentifier(self), playing: false)
    }
}
