import AVFAudio
import DoddyCore
import ElevenLabs
import Foundation
import Observation

/// One voice conversation with the ElevenLabs agent. State shown in the UI comes only from real
/// SDK events (connected, listening, speaking, disconnected), never from timers.
/// Tool calls are proposals: searches run against the local store, saves wait for the user.
@MainActor
@Observable
final class VoiceSessionController {
    enum Phase: Equatable {
        case idle, connecting, listening, thinking, speaking, ended
        case microphoneDenied
        case failed(String)
    }

    struct Line: Identifiable, Equatable {
        let id = UUID()
        let fromUser: Bool
        var text: String
    }

    struct PendingSave: Equatable {
        let toolCallID: String
        let text: String
    }

    private(set) var phase: Phase = .idle
    private(set) var lines: [Line] = []
    private(set) var pendingSave: PendingSave?
    private(set) var isMuted = false
    /// True while the Dynamic Island / Lock Screen activity is actually showing.
    private(set) var islandActive = false
    /// Why the Dynamic Island isn't showing (Live Activities off, request refused), if it isn't.
    private(set) var islandProblem: String?

    private let store: MemoryStore
    private let island = VoiceLiveActivity()
    private var conversation: Conversation?

    init(store: MemoryStore) {
        self.store = store
        island.onRemovedBySystem = { [weak self] in
            // The activity is gone, so nothing tells the user the microphone is open: end it.
            guard let self else { return }
            self.islandActive = false
            Task { await self.stop() }
        }
    }

    var isLive: Bool {
        switch phase {
        case .connecting, .listening, .thinking, .speaking: true
        default: false
        }
    }

    func start(agentID: String) async {
        guard !isLive else { return }
        lines = []
        pendingSave = nil
        isMuted = false

        guard await Self.microphoneAllowed() else {
            transition(to: .microphoneDenied)
            return
        }
        VoiceActivityBridge.shared.register { [weak self] command in
            switch command {
            case .end: await self?.stop()
            case .toggleMute: await self?.toggleMute()
            }
        }
        transition(to: .connecting)

        let ref = WeakRef(self)
        var config = ConversationConfig()
        config.onAgentStateChange = { state in
            Task { @MainActor in ref.value?.apply(state) }
        }
        config.onUserTranscript = { text, _ in
            Task { @MainActor in ref.value?.append(text, fromUser: true) }
        }
        config.onAgentResponse = { text, _ in
            Task { @MainActor in ref.value?.append(text, fromUser: false) }
        }
        config.onAgentResponseCorrection = { original, corrected, _ in
            Task { @MainActor in ref.value?.correct(original, to: corrected) }
        }
        config.onUnhandledClientToolCall = { call in
            Task { @MainActor in await ref.value?.handle(call) }
        }
        config.onError = { error in
            Task { @MainActor in ref.value?.fail(error.errorDescription ?? "Something went wrong.") }
        }

        do {
            conversation = try await ElevenLabs.startConversation(
                agentId: agentID,
                config: config,
                onAgentReady: {
                    Task { @MainActor in
                        if ref.value?.phase == .connecting { ref.value?.transition(to: .listening) }
                    }
                },
                onDisconnect: { _ in
                    Task { @MainActor in ref.value?.disconnected() }
                })
        } catch {
            fail("Couldn't connect to Doddy's voice. Check your internet connection and try again. (\(error.localizedDescription))")
        }
    }

    func stop() async {
        let active = conversation
        conversation = nil
        pendingSave = nil
        if isLive { transition(to: .ended) } else { endIsland() }
        await active?.endConversation()
    }

    func toggleMute() async {
        guard let conversation else { return }
        do {
            try await conversation.setMuted(!isMuted)
            isMuted.toggle()
            syncIsland()
        } catch {
            // Keep the previous state; the UI shows what is actually set.
        }
    }

    /// The user approved the note shown on screen.
    func confirmSave() async {
        guard let pending = pendingSave else { return }
        pendingSave = nil
        do {
            let record = try await store.save(text: pending.text, category: .other)
            await reply(pending.toolCallID, VoiceToolReply.saved(record))
        } catch {
            await reply(pending.toolCallID, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
        }
    }

    func declineSave() async {
        guard let pending = pendingSave else { return }
        pendingSave = nil
        await reply(pending.toolCallID, VoiceToolReply.declined)
    }

    // MARK: Events

    private func apply(_ state: ElevenLabs.AgentState) {
        guard isLive else { return }
        switch state {
        case .listening: transition(to: .listening)
        case .speaking: transition(to: .speaking)
        case .thinking: transition(to: .thinking)
        }
    }

    private func append(_ text: String, fromUser: Bool) {
        guard !text.allSatisfy(\.isWhitespace) else { return }
        lines.append(Line(fromUser: fromUser, text: text))
    }

    private func correct(_ original: String, to corrected: String) {
        guard let index = lines.lastIndex(where: { !$0.fromUser && $0.text == original }) else { return }
        lines[index].text = corrected
    }

    private func fail(_ message: String) {
        transition(to: .failed(message))
        pendingSave = nil
    }

    private func disconnected() {
        conversation = nil
        pendingSave = nil
        if case .failed = phase { endIsland(); return }
        transition(to: .ended)
    }

    // MARK: Dynamic Island

    /// Every phase change goes through here so the island can never disagree with the screen.
    private func transition(to newPhase: Phase) {
        phase = newPhase
        syncIsland()
    }

    private func syncIsland() {
        let shown: VoiceActivityAttributes.ContentState.Phase
        switch phase {
        case .connecting: shown = .connecting
        case .listening: shown = .listening
        case .thinking: shown = .thinking
        case .speaking: shown = .speaking
        case .idle, .ended, .microphoneDenied, .failed:
            endIsland()
            return
        }
        islandProblem = island.show(.init(phase: shown, isMuted: isMuted))
        islandActive = island.isRunning
    }

    private func endIsland() {
        island.end()
        islandActive = false
        VoiceActivityBridge.shared.clear()
    }

    private func handle(_ call: ClientToolCallEvent) async {
        switch VoiceToolRequest.parse(name: call.toolName, parametersJSON: call.parametersData) {
        case .searchMemories(let query):
            do {
                let outcome = try await store.recall(query)
                await reply(call.toolCallId, VoiceToolReply.search(outcome))
            } catch {
                await reply(call.toolCallId, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
            }
        case .saveMemory(let text):
            // Nothing is stored until the user taps Save on the card.
            pendingSave = PendingSave(toolCallID: call.toolCallId, text: text)
        case .unsupported(let name):
            await reply(call.toolCallId, VoiceToolReply.unsupported(name), isError: true)
        case .invalid(_, let reason):
            await reply(call.toolCallId, VoiceToolReply.failed("The request was incomplete (\(reason))."), isError: true)
        }
    }

    private func reply(_ toolCallID: String, _ text: String, isError: Bool = false) async {
        try? await conversation?.sendToolResult(for: toolCallID, result: text, isError: isError)
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined: return await AVAudioApplication.requestRecordPermission()
        @unknown default: return false
        }
    }
}

/// Lets SDK callbacks (which must be `@Sendable`) reach the controller without a retain cycle.
private final class WeakRef<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
