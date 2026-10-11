import AVFAudio
import DoddyCore
import Foundation
import os

enum OpenAIRealtimeStartError: LocalizedError {
    case badModel
    case refused(String)

    var errorDescription: String? {
        switch self {
        case .badModel: "The token server named a model the app can't use."
        case .refused(let message): message
        }
    }
}

/// One conversation with OpenAI Realtime, for comparing it with ElevenLabs (ADR-264, testing only).
/// A WebSocket to OpenAI opened with a one-conversation client secret from the token server; the
/// app sends Doddy's prompt and tools itself (`OpenAIRealtimeWire.sessionUpdate`), streams the
/// microphone as 24 kHz PCM, and plays Doddy's audio as it arrives. Tool calls go to the same
/// code as with ElevenLabs. What it reports comes only from OpenAI's events, never from timers.
/// Not compiled or heard on a device yet.
@MainActor
final class OpenAIRealtimeSession: LiveVoiceLink {
    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "voice-openai")
    /// Silence sent once when the microphone is muted mid-sentence, so voice detection sees the end.
    private static let muteSilenceMilliseconds = 800

    private let grant: OpenAIRealtimeGrant
    private let onEvent: @MainActor (RealtimeEvent) -> Void
    private var urlSession: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var audio: RealtimeAudioIO?
    private var receiveTask: Task<Void, Never>?
    private var ended = false
    private var microphoneMuted = false
    /// A response is running (from our response.create or OpenAI's own, until response.done).
    /// OpenAI refuses a second one meanwhile, so a reply asked for then waits in `responseWanted`.
    private var responseActive = false
    private var responseWanted = false
    /// This response's audio has started playing (reported once per response).
    private var responseAudioStarted = false
    /// OpenAI finished the response; "done" is reported once its audio has also played out.
    private var responseFinished = false
    /// The item the user cut off; its late audio deltas are dropped instead of played.
    private var cutItem: String?

    init(grant: OpenAIRealtimeGrant, onEvent: @escaping @MainActor (RealtimeEvent) -> Void) {
        self.grant = grant
        self.onEvent = onEvent
    }

    /// Connects, waits for OpenAI to accept the secret, sends Doddy's session, opens the
    /// microphone and asks for the greeting. Throws if any of that fails; nothing keeps listening.
    func start(sessionUpdate: String, greeting: String) async throws {
        guard let url = OpenAIRealtimeWire.socketURL(model: grant.model) else { throw OpenAIRealtimeStartError.badModel }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(grant.secret)", forHTTPHeaderField: "Authorization")
        let urlSession = URLSession(configuration: .ephemeral)
        let socket = urlSession.webSocketTask(with: request)
        // Audio deltas are large base64 strings; the default 1 MB limit is too small.
        socket.maximumMessageSize = 16 * 1024 * 1024
        self.urlSession = urlSession
        self.socket = socket
        socket.resume()

        do {
            let first = try await socket.receive()
            guard case .string(let text) = first else { throw OpenAIRealtimeStartError.refused("OpenAI sent an unexpected first message.") }
            switch OpenAIRealtimeWire.parse(text) {
            case .sessionCreated: break
            case .error(_, let message): throw OpenAIRealtimeStartError.refused("OpenAI refused the conversation: \(message)")
            default: throw OpenAIRealtimeStartError.refused("OpenAI sent an unexpected first message.")
            }
            // Ended while connecting (the user tapped End): stop before the microphone opens.
            guard !ended else { throw CancellationError() }
            try await socket.send(.string(sessionUpdate))
            guard !ended else { throw CancellationError() }

            let audio = RealtimeAudioIO(onDrained: { [weak self] in
                Task { @MainActor in self?.playbackDrained() }
            })
            self.audio = audio
            try audio.start(sendAudio: { [socket] pcm in
                socket.send(.string(OpenAIRealtimeWire.appendAudio(pcm))) { _ in }
            })
            receiveTask = Task { [weak self] in await self?.receiveLoop() }
            responseActive = true
            try await socket.send(.string(greeting))
        } catch {
            await endConversation()
            throw error
        }
        onEvent(.sessionReady)
    }

    // MARK: LiveVoiceLink

    func sendToolResult(for toolCallId: String, result: String, isError: Bool) async throws {
        try await send(OpenAIRealtimeWire.functionOutput(RealtimeFunctionOutput(callID: toolCallId, output: result, isError: isError)))
        try await askForResponse()
    }

    func setMuted(_ muted: Bool) async throws {
        let wasMuted = microphoneMuted
        microphoneMuted = muted
        audio?.setMicrophoneMuted(muted)
        // Muted mid-sentence (hold-to-talk released): without trailing silence OpenAI's voice
        // detection never hears the user stop, so nothing would be translated.
        if muted, !wasMuted {
            try await send(OpenAIRealtimeWire.silence(milliseconds: Self.muteSilenceMilliseconds))
        }
    }

    func sendMessage(_ text: String) async throws {
        try await send(OpenAIRealtimeWire.appMessage(text, respond: true))
        try await askForResponse()
    }

    func updateContext(_ context: String) async throws {
        try await send(OpenAIRealtimeWire.appMessage(context, respond: false))
    }

    func setAgentVolume(_ volume: Double) -> Double? {
        guard let audio else { return nil }
        audio.setVolume(volume)
        return volume
    }

    func endConversation() async {
        guard !ended else { return }
        ended = true
        receiveTask?.cancel()
        receiveTask = nil
        audio?.stop()
        audio = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    // MARK: Events

    private func send(_ event: String) async throws {
        guard let socket, !ended else { throw URLError(.notConnectedToInternet) }
        try await socket.send(.string(event))
    }

    /// One response at a time: asked for now, or as soon as the running one is done.
    private func askForResponse() async throws {
        guard !responseActive else {
            responseWanted = true
            return
        }
        responseActive = true
        try await send(OpenAIRealtimeWire.createResponse())
    }

    private func receiveLoop() async {
        while !ended, let socket {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await socket.receive()
            } catch {
                guard !ended else { return }
                let normal = socket.closeCode == .normalClosure
                await endConversation()
                onEvent(normal ? .ended : .error("The connection to OpenAI closed. (\(error.localizedDescription))"))
                return
            }
            guard case .string(let text) = message else { continue }
            handle(OpenAIRealtimeWire.parse(text))
        }
    }

    private func handle(_ event: OpenAIRealtimeServerEvent) {
        guard !ended else { return }
        switch event {
        case .sessionCreated, .sessionUpdated, .other, .unreadable:
            break
        case .speechStarted:
            // The user talks over Doddy: stop his audio now and tell OpenAI what was heard.
            if let cut = audio?.interrupt(), let socket {
                cutItem = cut.item
                socket.send(.string(OpenAIRealtimeWire.truncate(itemID: cut.item, playedSamples: cut.samples))) { _ in }
            }
            onEvent(.userSpeechStarted)
        case .speechStopped:
            onEvent(.userSpeechStopped)
        case .userTranscript(let text):
            onEvent(.userTranscript(text))
        case .responseCreated:
            responseActive = true
            responseAudioStarted = false
            responseFinished = false
            onEvent(.responseStarted)
        case .audioDelta(let itemID, let pcm):
            guard itemID != cutItem else { return }
            if !responseAudioStarted {
                responseAudioStarted = true
                onEvent(.audioStarted)
            }
            audio?.play(pcm16: pcm, item: itemID)
        case .assistantTranscript(_, let text):
            onEvent(.assistantTranscript(text))
        case .functionCall(let call):
            onEvent(.functionCall(call))
        case .responseDone(let failure):
            responseActive = false
            if let failure {
                Task {
                    await endConversation()
                    onEvent(.error("OpenAI couldn't answer: \(failure)"))
                }
                return
            }
            if responseWanted {
                responseWanted = false
                Task { try? await askForResponse() }
            }
            responseFinished = true
            if !(audio?.isPlaying ?? false) { playbackDrained() }
        case .error(let code, _):
            // About something the app sent; the conversation goes on. The message can echo what
            // was sent, so only the code is logged.
            Self.log.error("openai error \(code ?? "-", privacy: .public)")
        }
    }

    private func playbackDrained() {
        guard responseFinished, !ended else { return }
        responseFinished = false
        onEvent(.responseDone)
    }
}

/// Microphone in and Doddy's voice out for the OpenAI test voice. Called on audio threads, so all
/// state is behind `lock`. Voice processing (Apple's echo cancellation) is on, so Doddy doesn't
/// hear himself through the speaker and interrupt his own sentence. iOS stops the engine on a route
/// change (AirPods) or an interruption (a call, Siri); it is restarted when iOS allows, and audio
/// that arrives while it is stopped is dropped rather than queued forever.
final class RealtimeAudioIO: @unchecked Sendable {
    private final class Once: @unchecked Sendable { var done = false }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let lock = NSLock()
    private let wireFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(OpenAIRealtimeWire.sampleRate), channels: 1, interleaved: true)!
    private let playFormat = AVAudioFormat(standardFormatWithSampleRate: Double(OpenAIRealtimeWire.sampleRate), channels: 1)!
    private let onDrained: @Sendable () -> Void
    private var converter: AVAudioConverter?
    private var observers: [NSObjectProtocol] = []
    /// The player is attached to the engine (start got that far), so stopping it is safe.
    private var playerAttached = false
    private var microphoneMuted = false
    /// Item of each scheduled, not yet played buffer, oldest first.
    private var queue: [String] = []
    /// Samples heard per item, counted when each buffer has played.
    private var played: [String: Int] = [:]
    /// The item whose audio was heard last.
    private var lastPlayedItem: String?
    /// Bumped whenever the queue is thrown away, so callbacks of flushed buffers are ignored.
    private var generation = 0

    init(onDrained: @escaping @Sendable () -> Void) {
        self.onDrained = onDrained
    }

    var isPlaying: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !queue.isEmpty
    }

    func start(sendAudio: @escaping @Sendable (Data) -> Void) throws {
        // Same routes as the ElevenLabs call session, mixable so other apps don't stop Doddy (ADR-207).
        #if swift(>=6.2)
        let routes: AVAudioSession.CategoryOptions = [.allowBluetoothHFP, .allowBluetoothA2DP, .allowAirPlay]
        #else
        let routes: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
        #endif
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: routes.union([.defaultToSpeaker, .mixWithOthers]))
        try session.setActive(true)

        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playFormat)
        lock.lock()
        playerAttached = true
        lock.unlock()

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, let converter = AVAudioConverter(from: inputFormat, to: wireFormat) else {
            throw OpenAIRealtimeStartError.refused("The microphone isn't available right now.")
        }
        self.converter = converter
        input.installTap(onBus: 0, bufferSize: 2_400, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let pcm = self.convert(buffer) else { return }
            sendAudio(pcm)
        }
        engine.prepare()
        try engine.start()
        player.play()

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
                self?.restart()
            },
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if raw == AVAudioSession.InterruptionType.ended.rawValue { self?.restart() }
            },
        ]
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        engine.inputNode.removeTap(onBus: 0)
        lock.lock()
        let attached = playerAttached
        lock.unlock()
        if attached { player.stop() }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func setMicrophoneMuted(_ muted: Bool) {
        lock.lock()
        microphoneMuted = muted
        lock.unlock()
    }

    func setVolume(_ volume: Double) {
        player.volume = Float(max(0, min(1, volume)))
    }

    /// Schedules one PCM16 chunk of an assistant item. Dropped while iOS has the engine stopped.
    func play(pcm16: Data, item: String) {
        let frames = pcm16.count / 2
        guard frames > 0, engine.isRunning,
              let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: AVAudioFrameCount(frames)),
              let samples = buffer.floatChannelData?[0]
        else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        pcm16.withUnsafeBytes { raw in
            for i in 0..<frames {
                samples[i] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))) / 32_768
            }
        }
        lock.lock()
        queue.append(item)
        let scheduledGeneration = generation
        lock.unlock()
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.finishedPlaying(frames: frames, generation: scheduledGeneration)
        }
        if !player.isPlaying { player.play() }
    }

    /// Stops Doddy mid-sentence. Returns the item being heard and how much of it was heard, or
    /// nil when nothing was playing.
    func interrupt() -> (item: String, samples: Int)? {
        lock.lock()
        let hearing = queue.first ?? lastPlayedItem
        let wasPlaying = !queue.isEmpty
        let cut = hearing.map { (item: $0, samples: played[$0] ?? 0) }
        flushLocked()
        lock.unlock()
        guard wasPlaying else { return nil }
        // Drops everything scheduled; their callbacks carry the old generation and are ignored.
        player.stop()
        if engine.isRunning { player.play() }
        onDrained()
        return cut
    }

    /// After a route change or an interruption: whatever was queued is gone, start again.
    private func restart() {
        lock.lock()
        let hadQueue = !queue.isEmpty
        flushLocked()
        lock.unlock()
        player.stop()
        if !engine.isRunning { try? engine.start() }
        if engine.isRunning { player.play() }
        if hadQueue { onDrained() }
    }

    private func flushLocked() {
        generation += 1
        queue = []
        played = [:]
        lastPlayedItem = nil
    }

    private func finishedPlaying(frames: Int, generation scheduledGeneration: Int) {
        lock.lock()
        guard scheduledGeneration == generation, !queue.isEmpty else {
            lock.unlock()
            return
        }
        let item = queue.removeFirst()
        played[item, default: 0] += frames
        lastPlayedItem = item
        let drained = queue.isEmpty
        lock.unlock()
        if drained { onDrained() }
    }

    /// Microphone buffer → PCM16 mono 24 kHz, or nil while muted.
    private func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        lock.lock()
        let muted = microphoneMuted
        lock.unlock()
        guard !muted, let converter else { return nil }
        let ratio = wireFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: wireFormat, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) let input = buffer
        let once = Once()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if once.done {
                inputStatus.pointee = .noDataNow
                return nil
            }
            once.done = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0, let channel = output.int16ChannelData else { return nil }
        return Data(bytes: channel[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }
}
