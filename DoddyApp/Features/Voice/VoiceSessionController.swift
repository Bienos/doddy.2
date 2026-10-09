import AVFAudio
import DoddyCore
import ElevenLabs
import Foundation
import Observation

/// One voice conversation with the ElevenLabs agent. State shown in the UI comes only from real
/// SDK events (connected, listening, speaking, disconnected), never from timers.
/// Tool calls are proposals: searches run against the local store, saves wait for the user.
/// At start the app hands the agent the saved notes and the last few conversations (dynamic
/// variables); at the end the transcript lines are kept locally in `ConversationLogStore`.
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

    private(set) var phase: Phase = .idle { didSet { syncIsland() } }
    private(set) var lines: [Line] = []
    private(set) var pendingSave: PendingSave? { didSet { syncIsland() } }
    private(set) var isMuted = false { didSet { syncIsland() } }

    private let store: MemoryStore
    private let logs: ConversationLogStore
    private let island = VoiceLiveActivity()
    private var conversation: Conversation?
    private var startedAt: Date?

    init(store: MemoryStore, logs: ConversationLogStore = .shared) {
        self.store = store
        self.logs = logs
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
            phase = .microphoneDenied
            return
        }
        startedAt = Date()
        phase = .connecting

        // The Dynamic Island / Lock Screen buttons reach this conversation through these.
        let actions = VoiceActivityActions.shared
        actions.endConversation = { [weak self] in await self?.stop() }
        actions.toggleMute = { [weak self] in await self?.toggleMute() }

        // What Doddy knows at the start: the saved notes and, if the user keeps it on, the last
        // few conversations. Both are bounded and say when they were cut.
        await store.reload()
        let notes = VoiceContext.savedNotes(store.memories)
        let recent = logs.isEnabled
            ? VoiceContext.recentConversations(logs.logs)
            : VoiceContext.Rendered(text: "(remembering recent conversations is switched off in Settings)", includedCount: 0, truncated: false)

        let ref = WeakRef(self)
        var config = ConversationConfig(
            dynamicVariables: [
                "saved_notes": notes.text,
                "saved_notes_count": "\(notes.includedCount)",
                "saved_notes_truncated": notes.truncated ? "yes" : "no",
                "recent_conversations": recent.text,
                // Style only (Settings → Doddy's personality). The agent prompt's {{doddy_personality}}
                // placeholder defaults to the persona defaults, so a build that sends nothing still works.
                PersonalityPrompt.variableName: PersonalityPrompt.render(.stored()),
            ],
            userId: Self.userID())
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
                        if ref.value?.phase == .connecting { ref.value?.phase = .listening }
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
        if isLive { phase = .ended }
        keepLog()
        await active?.endConversation()
    }

    /// Keeps the transcript lines of this conversation on the phone, once, so the next
    /// conversation can continue from it. Nothing is kept when there were no lines or when the
    /// user switched "Remember recent conversations" off.
    private func keepLog() {
        guard let startedAt else { return }
        self.startedAt = nil
        let kept = lines.map { ConversationLog.Line(fromUser: $0.fromUser, text: $0.text) }
        logs.append(ConversationLog(startedAt: startedAt, endedAt: Date(), lines: kept))
    }

    /// A random, stable id for this install, so ElevenLabs can tell the owner's conversations
    /// apart without knowing who they are.
    private static func userID() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: PreferenceKey.voiceUserID), !existing.isEmpty { return existing }
        let fresh = UUID().uuidString.lowercased()
        defaults.set(fresh, forKey: PreferenceKey.voiceUserID)
        return fresh
    }

    func toggleMute() async {
        guard let conversation else { return }
        do {
            try await conversation.setMuted(!isMuted)
            isMuted.toggle()
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

    // MARK: Dynamic Island

    /// What the Live Activity shows, or nil when no conversation is running.
    private var islandState: DoddyVoiceAttributes.ContentState? {
        let status: DoddyVoiceAttributes.ContentState.Status
        switch phase {
        case .connecting: status = .connecting
        case .listening: status = .listening
        case .thinking: status = .thinking
        case .speaking: status = .speaking
        case .idle, .ended, .microphoneDenied, .failed: return nil
        }
        return .init(status: pendingSave == nil ? status : .needsConfirmation, isMuted: isMuted)
    }

    private func syncIsland() {
        if let state = islandState {
            island.show(state, startedAt: startedAt ?? .now)
        } else {
            island.end()
        }
    }

    // MARK: Events

    private func apply(_ state: ElevenLabs.AgentState) {
        guard isLive else { return }
        switch state {
        case .listening: phase = .listening
        case .speaking: phase = .speaking
        case .thinking: phase = .thinking
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
        phase = .failed(message)
        pendingSave = nil
    }

    private func disconnected() {
        conversation = nil
        pendingSave = nil
        keepLog()
        if case .failed = phase { return }
        phase = .ended
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
