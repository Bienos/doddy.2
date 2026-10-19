import AVFAudio
import DoddyCore
import Foundation
import Speech
import os

/// The "Hey Doddy" detector (ADR-472): Apple's speech recognition, on this iPhone, written out as
/// text and checked for the wake phrase (`WakePhraseMatcher`). Nothing it hears is kept or sent:
/// every request sets `requiresOnDeviceRecognition = true` (scripts/check_forbidden_capabilities.sh
/// checks that line stays), and an iPhone that can't recognize English on the device doesn't listen
/// at all rather than fall back to Apple's servers.
///
/// Why this and not a wake-word library: no vendor, key or licence to bring, so the app can be
/// sold. The price is battery (speech recognition runs all the time while it listens) and some
/// missed or false wake-ups, which the listener's gate limits (`WakeGate`).
///
/// One recognition request lasts about a minute at most, so the request is renewed every
/// `renewAfter` seconds while the microphone keeps running; a phrase spoken exactly while it
/// changes over can be missed. A request that ends by itself starts again after a short pause, and
/// if that keeps failing the engine stops and says so rather than spin.
///
/// Called from the main actor, but its callbacks come on audio and recognition threads, so all
/// state is behind `lock`. Not verified on a device: see docs/implementation/HEY_DODDY_STATUS.md.
final class SpeechWakeEngine: @unchecked Sendable {
    enum StartError: Error, Equatable {
        case speechNotAllowed
        case unavailable
        case audio(String)
    }

    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "hey-doddy")
    private static let renewAfter: TimeInterval = 45
    private static let restartDelay: TimeInterval = 0.4
    private static let failureWindow: TimeInterval = 20
    private static let maxFailuresInWindow = 5

    private let lock = NSLock()
    private let audioEngine = AVAudioEngine()
    private let onDetection: @Sendable () -> Void
    private let onFailure: @Sendable (String) -> Void
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var running = false
    /// Bumped whenever a request starts or the engine stops, so late callbacks of an old request
    /// are ignored.
    private var generation = 0
    private var failures: [Date] = []
    private var observers: [NSObjectProtocol] = []

    init(onDetection: @escaping @Sendable () -> Void, onFailure: @escaping @Sendable (String) -> Void) {
        self.onDetection = onDetection
        self.onFailure = onFailure
    }

    // MARK: What this iPhone can do

    /// An English recognizer that works without sending sound to Apple, if there is one.
    private static func makeRecognizer() -> SFSpeechRecognizer? {
        for identifier in ["en-US", "en-GB"] {
            if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)),
               recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }
        return nil
    }

    /// Speech recognition as the listener's rules need it (`WakeConditions.speech`).
    static var availability: WakeConditions.Speech {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined: .notAsked
        case .authorized: makeRecognizer() == nil ? .unavailable : .allowed
        default: .denied
        }
    }

    /// Whether "Hey Doddy" could work on this iPhone: not refused, and possible on the device.
    static var isPossible: Bool {
        switch availability {
        case .allowed, .notAsked: true
        case .denied, .unavailable: false
        }
    }

    /// Asks iOS for speech recognition when it hasn't been asked. Call it with Doddy on screen,
    /// where the user can answer. The answer shows in `availability`.
    static func requestAuthorization() async {
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
        }
    }

    // MARK: Start and stop

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return }
        switch Self.availability {
        case .denied, .notAsked: throw StartError.speechNotAllowed
        case .unavailable: throw StartError.unavailable
        case .allowed: break
        }
        guard let recognizer = Self.makeRecognizer(), recognizer.isAvailable else { throw StartError.unavailable }
        do {
            try configureSession()
            try startAudioLocked()
        } catch {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            if let known = error as? StartError { throw known }
            throw StartError.audio(error.localizedDescription)
        }
        self.recognizer = recognizer
        running = true
        failures = []
        beginRecognitionLocked()
        observers = [
            NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: nil
            ) { [weak self] _ in
                self?.audioConfigurationChanged()
            },
        ]
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        guard running else { return }
        running = false
        generation += 1
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        endRecognitionLocked()
        recognizer = nil
    }

    // MARK: Audio

    /// Playing and recording, mixable, so other apps' sound isn't stopped by listening.
    private func configureSession() throws {
        #if swift(>=6.2)
        let routes: AVAudioSession.CategoryOptions = [.allowBluetoothHFP, .allowBluetoothA2DP, .allowAirPlay]
        #else
        let routes: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
        #endif
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: routes.union([.defaultToSpeaker, .mixWithOthers]))
        try session.setActive(true)
    }

    /// Installs the microphone tap and starts the engine. The lock is held by the caller.
    private func startAudioLocked() throws {
        let input = audioEngine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw StartError.audio("The microphone isn't available right now.")
        }
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
            self?.feed(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func feed(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        request?.append(buffer)
        lock.unlock()
    }

    /// iOS reconfigured the audio (AirPods connected, a route changed) and stopped the engine.
    private func audioConfigurationChanged() {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        do {
            try startAudioLocked()
            lock.unlock()
        } catch {
            stopLocked()
            lock.unlock()
            Self.log.error("couldn't restart the microphone: \(error.localizedDescription, privacy: .public)")
            onFailure("The microphone stopped (\(error.localizedDescription)). Open Doddy to try again.")
        }
    }

    // MARK: Recognition

    /// Starts a fresh request and task. The lock is held by the caller.
    private func beginRecognitionLocked() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        // Never sent to Apple's servers. The capability guard checks this line stays.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        request.taskHint = .search
        request.contextualStrings = ["Hey Doddy", "Doddy"]
        generation += 1
        let mine = generation
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let ended = (result?.isFinal ?? false) || error != nil
            self?.handle(generation: mine, text: text, ended: ended)
        }
        // Renew before iOS ends the request by itself.
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.renewAfter) { [weak self] in
            self?.restart(ifGeneration: mine)
        }
    }

    private func endRecognitionLocked() {
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func restart(ifGeneration expected: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard running, expected == generation else { return }
        endRecognitionLocked()
        beginRecognitionLocked()
    }

    private func handle(generation mine: Int, text: String?, ended: Bool) {
        lock.lock()
        guard running, mine == generation else {
            lock.unlock()
            return
        }
        if let text, WakePhraseMatcher.containsWakePhrase(text) {
            // Start over with an empty transcript, so one phrase can't be heard twice, then tell
            // the listener. If it rejects the wake-up (too soon after starting), listening goes on.
            endRecognitionLocked()
            beginRecognitionLocked()
            lock.unlock()
            onDetection()
            return
        }
        guard ended else {
            lock.unlock()
            return
        }
        let now = Date()
        failures.append(now)
        failures.removeAll { now.timeIntervalSince($0) > Self.failureWindow }
        if failures.count >= Self.maxFailuresInWindow {
            stopLocked()
            lock.unlock()
            Self.log.error("speech recognition keeps ending; stopped")
            onFailure("Speech recognition keeps stopping. Open Doddy to try again.")
            return
        }
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.restartDelay) { [weak self] in
            self?.restart(ifGeneration: mine)
        }
    }
}
