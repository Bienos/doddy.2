import AVFoundation
import DoddyCore
import Foundation
import Observation
import Speech

/// The mic in Messages: the person talks and the words appear in the box, to read and fix before they tap
/// Send. Recognition is required to run on this iPhone, so the audio is not sent to Apple or anyone else and
/// nothing is saved; only the words reach the draft, and the draft goes to Doddy's server only when sent as
/// a normal message. It lives in this folder because audio and speech code may only be here (ADR-230).
///
/// It refuses to start while a conversation with Doddy, a voice memo or a Capture recording holds the
/// microphone, because all of them share one audio session.
@MainActor
@Observable
final class MessageDictation {
    enum State: Equatable {
        case idle
        case starting
        case listening
        /// Why it didn't start or had to stop, in words for the person.
        case failed(String)
    }

    private(set) var state: State = .idle
    var isListening: Bool { state == .listening }

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var sink: BufferSink?
    @ObservationIgnored private var limit: Task<Void, Never>?
    /// Bumped on every start and stop so a late callback from an earlier dictation is ignored.
    @ObservationIgnored private var generation = 0

    /// - Parameters:
    ///   - isOtherMicrophoneBusy: true while a conversation, memo or recording has the microphone.
    ///   - onText: everything heard since the mic was tapped (it grows and is corrected while they talk).
    func start(isOtherMicrophoneBusy: Bool, onText: @escaping @MainActor (String) -> Void) async {
        guard state != .starting, !isListening else { return }
        guard !isOtherMicrophoneBusy else {
            state = .failed(NSLocalizedString("Doddy is already listening or recording. Finish that first.", comment: ""))
            return
        }
        state = .starting
        generation += 1
        let mine = generation
        guard await Self.authorizeSpeech() else {
            if mine == generation {
                state = .failed(NSLocalizedString("Speech recognition is off for Doddy. Turn it on in the Settings app to dictate.", comment: ""))
            }
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            if mine == generation {
                state = .failed(NSLocalizedString("The microphone is off for Doddy. Turn it on in the Settings app to dictate.", comment: ""))
            }
            return
        }
        guard mine == generation else { return }
        guard let locale = VoiceMemoTranscriber.languages().first,
              let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition
        else {
            state = .failed(NSLocalizedString(
                "This iPhone can't write your language out on the device, so Doddy didn't listen. Nothing was sent anywhere.", comment: ""))
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        // Never sent to Apple's servers. The capability guard checks this line stays.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        let engine = AVAudioEngine()
        let sink = BufferSink(request)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            Self.installTap(on: engine.inputNode, feeding: sink)
            engine.prepare()
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            state = .failed(NSLocalizedString("Dictation couldn't start. If you're talking to Doddy or on a call, finish that first.", comment: ""))
            return
        }
        self.engine = engine
        self.sink = sink
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let spoken = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            Task { @MainActor [weak self] in
                guard let self, self.generation == mine else { return }
                if let spoken { onText(spoken) }
                if isFinal || (error != nil && spoken == nil) { self.stop() }
            }
        }
        state = .listening
        limit = Task { [weak self] in
            try? await Task.sleep(for: .seconds(DictationRules.maxSeconds))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    /// Stops listening. The words already heard stay in the box.
    func stop() {
        generation += 1
        limit?.cancel()
        limit = nil
        sink?.finish()
        sink = nil
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        task?.cancel()
        task = nil
        if state == .listening || state == .starting {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            state = .idle
        }
    }

    func clearFailure() {
        if case .failed = state { state = .idle }
    }

    // The next two are nonisolated on purpose. iOS calls their callbacks on a background thread, and a
    // callback written inside this @MainActor class is checked for the main thread at run time and stops
    // the app (seen on a device on 29 Oct: `_dispatch_assert_queue_fail` when asking for speech access).

    nonisolated private static func authorizeSpeech() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { @Sendable status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default: return false
        }
    }

    /// The tap's block runs on the audio thread.
    nonisolated private static func installTap(on input: AVAudioInputNode, feeding sink: BufferSink) {
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { @Sendable buffer, _ in
            sink.append(buffer)
        }
    }
}

/// Hands microphone buffers to the recognizer from the audio thread.
private final class BufferSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest

    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }

    func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }

    func finish() { request.endAudio() }
}
