import DoddyCore
import Foundation
import Observation
import Speech
import UIKit
import os

/// Writes a recording's words out on this iPhone (ADR-588), part by part, with the time of each word.
/// On-device recognition is required: if this iPhone cannot do it for the language, nothing is
/// written out and nothing is sent to Apple or anyone else. There is no cloud fallback in this
/// slice (CLAUDE.md rule 6: cloud AI needs its own approval). Same API and same invariant as voice
/// memos (`VoiceMemoTranscriber`, ADR-230); the capability guard checks both.
///
/// `SpeechAnalyzer` (iOS 26) is not used yet. It cannot be compiled or tried here, and which
/// languages it supports (Polish especially) has to be read on a device. A second implementation
/// would sit beside this one and be chosen in `RecordingProcessor.process`.
enum RecordingTranscriber {
    enum Outcome: Equatable {
        case words([TranscriptWord])
        /// Ran and found nothing said.
        case noSpeech
        /// This iPhone can't write this language out without sending the audio, so it didn't.
        case notOnDevice
        /// Speech recognition is off for Doddy in Settings.
        case notAllowed
        case failed
    }

    /// Whether this iPhone can write this language out on the device.
    static func supportsOnDevice(_ localeIdentifier: String) -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))?.supportsOnDeviceRecognition == true
    }

    static func transcribe(_ url: URL, localeIdentifier: String, partSeconds: Int) async -> Outcome {
        guard await authorize() else { return .notAllowed }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.supportsOnDeviceRecognition else { return .notOnDevice }
        let request = SFSpeechURLRecognitionRequest(url: url)
        // Never sent to Apple's servers. The capability guard checks this line stays.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        let once = RecognitionOnce<Outcome>()
        let timeout = max(120, partSeconds / 2 + 60)
        return await withCheckedContinuation { continuation in
            once.set(continuation)
            // Kept until the answer comes, so iOS can't free them mid-way.
            once.keep(recognizer)
            once.keep(recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let words = result.bestTranscription.segments.map { piece in
                        TranscriptWord(
                            text: piece.substring,
                            startMilliseconds: Int((piece.timestamp * 1000).rounded()),
                            durationMilliseconds: Int((piece.duration * 1000).rounded()),
                            confidence: Double(piece.confidence))
                    }
                    once.resume(words.isEmpty ? .noSpeech : .words(words))
                } else if let error {
                    // "No speech detected" comes back as an error too (code 1110).
                    once.resume((error as NSError).code == 1110 ? .noSpeech : .failed)
                }
            })
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                once.resume(.failed)
            }
        }
    }

    private static func authorize() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }
}

/// Resumes a continuation exactly once, whichever callback comes first.
private final class RecognitionOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var kept: [AnyObject] = []

    func keep(_ object: AnyObject) {
        lock.lock(); defer { lock.unlock() }
        if continuation != nil { kept.append(object) }
    }

    func set(_ continuation: CheckedContinuation<Value, Never>) {
        lock.lock(); defer { lock.unlock() }
        self.continuation = continuation
    }

    func resume(_ value: Value) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let finished = kept
        kept = []
        lock.unlock()
        (finished.first { $0 is SFSpeechRecognitionTask } as? SFSpeechRecognitionTask)?.cancel()
        continuation?.resume(returning: value)
    }
}

/// Keeps Doddy running a little longer after he goes to the background, to finish writing words out.
/// iOS gives about thirty seconds, so a long recording usually finishes when Doddy is next opened:
/// anything left "writing out" is started again at launch (`RecordingProcessor.resumePending`).
@MainActor
private final class BackgroundWork {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    func begin() {
        guard identifier == .invalid else { return }
        identifier = UIApplication.shared.beginBackgroundTask(withName: "doddy-write-out-recording") { [weak self] in
            // iOS ends the app if the task is still open when this returns, so it is ended here, not later.
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

/// Writes out saved recordings one at a time. A recording or a part is never started while another
/// recording is being made (the two would compete for the same cores and battery); a part already
/// being written out when a recording starts is allowed to finish.
@MainActor
@Observable
final class RecordingProcessor {
    static let shared = RecordingProcessor()

    /// The recording being written out now, for the screen.
    private(set) var processing: UUID?

    @ObservationIgnored private var queue: [UUID] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "capture")

    private init() {}

    private var repository: (any RecordingRepository)? { AppEnvironment.shared.recordingRepository }
    private var files: RecordingFiles { AppEnvironment.shared.recordingFiles }

    func enqueue(_ id: UUID) {
        guard processing != id, !queue.contains(id) else { return }
        queue.append(id)
        startWorker()
    }

    /// After a launch: anything a kill left half done, or never started.
    func resumePending() async {
        guard let repository else { return }
        let items = (try? await repository.recordings(category: .all, limit: 200, offset: 0)) ?? []
        for item in items where item.recording.phase == .saved || item.recording.phase == .recovered {
            switch item.recording.transcription {
            case .notStarted, .running: enqueue(item.recording.id)
            default: break
            }
        }
    }

    /// "Write out again", optionally in another language.
    func retry(_ id: UUID, languageCode: String? = nil) async {
        if let languageCode { _ = try? await repository?.setLanguage(id: id, languageCode: languageCode) }
        try? await repository?.setTranscriptionStatus(id: id, .notStarted)
        enqueue(id)
    }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, let next = self.takeNext() {
                // A recording being made comes first.
                while RecordingCoordinator.shared.isActive { try? await Task.sleep(for: .seconds(5)) }
                await self.process(next)
            }
            self?.worker = nil
        }
    }

    private func takeNext() -> UUID? { queue.isEmpty ? nil : queue.removeFirst() }

    private func process(_ id: UUID) async {
        guard let repository,
              let recording = try? await repository.recording(id: id),
              recording.phase == .saved || recording.phase == .recovered else { return }
        processing = id
        let background = BackgroundWork()
        background.begin()
        defer {
            processing = nil
            background.end()
        }
        try? await repository.setTranscriptionStatus(id: id, .running)
        let parts = (try? await repository.parts(recordingID: id)) ?? []
        var assembly: [AssemblyPart] = []
        for part in parts {
            while RecordingCoordinator.shared.isActive { try? await Task.sleep(for: .seconds(5)) }
            guard let duration = part.durationMilliseconds, let url = files.url(recordingID: id, fileName: part.fileName),
                  FileManager.default.fileExists(atPath: url.path) else {
                // A part whose file is gone is not skipped quietly: the words would then be missing from the middle.
                Self.log.notice("a part's file is missing; not writing out")
                try? await repository.setTranscriptionStatus(id: id, .failed)
                return
            }
            switch await RecordingTranscriber.transcribe(url, localeIdentifier: recording.languageCode, partSeconds: duration / 1000) {
            case .words(let words):
                assembly.append(AssemblyPart(offsetMilliseconds: part.startOffsetMilliseconds, durationMilliseconds: duration,
                                             segments: TranscriptSegmenter.group(words)))
            case .noSpeech:
                assembly.append(AssemblyPart(offsetMilliseconds: part.startOffsetMilliseconds, durationMilliseconds: duration, segments: []))
            case .notOnDevice:
                try? await repository.setTranscriptionStatus(id: id, .unsupportedLanguage)
                return
            case .notAllowed:
                try? await repository.setTranscriptionStatus(id: id, .notAllowed)
                return
            case .failed:
                try? await repository.setTranscriptionStatus(id: id, .failed)
                return
            }
        }
        let segments = TranscriptAssembler.assemble(assembly)
        do {
            try await repository.saveTranscript(recordingID: id, segments: segments, status: segments.isEmpty ? .noSpeech : .done)
        } catch {
            Self.log.notice("words not saved: \(LogSafeError.kind(of: error), privacy: .public)")
            try? await repository.setTranscriptionStatus(id: id, .failed)
        }
    }
}
