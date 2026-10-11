import AVFoundation
import DoddyCore
import Foundation

/// Records one "Listen until I finish" turn (ADR-364) to a temporary file while the conversation's
/// microphone is muted. It uses the audio session the conversation already set up and leaves it
/// as it is: deactivating it here would stop Doddy's voice too. The file never leaves the iPhone;
/// the caller deletes it once the words are sent or the turn is dropped.
@MainActor
final class LongTurnRecorder {
    private var recorder: AVAudioRecorder?
    /// AVAudioRecorder's own time is 0 once it stopped at the limit, so the length is kept here.
    private var startedAt: Date?

    /// The microphone is recording now, as AVAudioRecorder says.
    var isCapturing: Bool { recorder?.isRecording == true }

    /// False when recording couldn't start; nothing is left behind then.
    func start() -> Bool {
        guard recorder == nil else { return false }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DoddyTurn-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings),
              recorder.record(forDuration: LongTurn.maxSeconds) else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        self.recorder = recorder
        startedAt = Date()
        return true
    }

    /// Stops and returns the file with its length, or nil when there is none.
    func stop() -> (url: URL, seconds: TimeInterval)? {
        guard let recorder else { return nil }
        let seconds = min(LongTurn.maxSeconds, startedAt.map { Date().timeIntervalSince($0) } ?? recorder.currentTime)
        recorder.stop()
        self.recorder = nil
        startedAt = nil
        guard FileManager.default.fileExists(atPath: recorder.url.path) else { return nil }
        return (recorder.url, seconds)
    }

    /// Stops and deletes the recording.
    func cancel() {
        if let file = stop() { try? FileManager.default.removeItem(at: file.url) }
    }
}
