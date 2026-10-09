import AVFAudio
import DoddyCore
import ElevenLabs
import Foundation
import Observation

/// One voice conversation with the ElevenLabs agent. State shown in the UI comes only from real
/// SDK events (connected, listening, speaking, disconnected), never from timers.
/// Tool calls are proposals: searches and calendar/contact reads run locally (only when
/// connected); saves, events and reminders wait for the user to tap on screen.
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

    /// Something the agent proposed that only the user's tap can make happen.
    struct PendingAction: Equatable {
        enum Kind: Equatable {
            case saveMemory(String)
            case addEvent(EventDraft)
            case addReminder(ReminderDraft)
        }
        let toolCallID: String
        let kind: Kind
    }

    /// Shown on screen after a verified (or unconfirmed) action.
    struct Receipt: Equatable {
        let text: String
        let verified: Bool
    }

    private(set) var phase: Phase = .idle
    private(set) var lines: [Line] = []
    private(set) var pendingAction: PendingAction?
    private(set) var contactResults: [ContactMatch] = []
    private(set) var receipt: Receipt?
    private(set) var isMuted = false

    private let store: MemoryStore
    private let connections: ConnectionsStore
    private var conversation: Conversation?

    init(store: MemoryStore, connections: ConnectionsStore) {
        self.store = store
        self.connections = connections
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
        pendingAction = nil
        contactResults = []
        receipt = nil
        isMuted = false

        guard await Self.microphoneAllowed() else {
            phase = .microphoneDenied
            return
        }
        phase = .connecting

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
        pendingAction = nil
        if isLive { phase = .ended }
        await active?.endConversation()
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

    /// The user tapped the confirm button on the card shown on screen.
    func confirmPending() async {
        guard let pending = pendingAction else { return }
        pendingAction = nil
        let timeZone = TimeZone.current
        switch pending.kind {
        case .saveMemory(let text):
            do {
                let record = try await store.save(text: text, category: .other)
                receipt = Receipt(text: "Saved on this iPhone: \(record.currentText)", verified: true)
                await reply(pending.toolCallID, VoiceToolReply.saved(record))
            } catch {
                await reply(pending.toolCallID, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
            }
        case .addEvent(let draft):
            do {
                let event = try await connections.addEvent(draft)
                receipt = Receipt(text: "Added to Calendar: \(event.title), \(VoiceView.when(event.start, allDay: event.isAllDay)) (\(event.calendarTitle))", verified: true)
                await reply(pending.toolCallID, VoiceToolReply.eventCreated(event, timeZone: timeZone))
            } catch ConnectionError.unverified {
                receipt = Receipt(text: "Sent to Calendar but not confirmed. Check Calendar before trying again.", verified: false)
                await reply(pending.toolCallID, VoiceToolReply.actionUnverified(.createCalendarEvent))
            } catch {
                await reply(pending.toolCallID, VoiceToolReply.actionFailed(ConnectionsCopy.message(for: error)), isError: true)
            }
        case .addReminder(let draft):
            do {
                let item = try await connections.addReminder(draft)
                let due = item.due.map { ", " + VoiceView.when($0, allDay: !item.dueIncludesTime) } ?? ""
                receipt = Receipt(text: "Added to Reminders: \(item.title)\(due) (\(item.listTitle))", verified: true)
                await reply(pending.toolCallID, VoiceToolReply.reminderCreated(item, timeZone: timeZone))
            } catch ConnectionError.unverified {
                receipt = Receipt(text: "Sent to Reminders but not confirmed. Check Reminders before trying again.", verified: false)
                await reply(pending.toolCallID, VoiceToolReply.actionUnverified(.createReminder))
            } catch {
                await reply(pending.toolCallID, VoiceToolReply.actionFailed(ConnectionsCopy.message(for: error)), isError: true)
            }
        }
    }

    func declinePending() async {
        guard let pending = pendingAction else { return }
        pendingAction = nil
        switch pending.kind {
        case .saveMemory: await reply(pending.toolCallID, VoiceToolReply.declined)
        case .addEvent: await reply(pending.toolCallID, VoiceToolReply.actionDeclined(.createCalendarEvent))
        case .addReminder: await reply(pending.toolCallID, VoiceToolReply.actionDeclined(.createReminder))
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
        pendingAction = nil
    }

    private func disconnected() {
        conversation = nil
        pendingAction = nil
        if case .failed = phase { return }
        phase = .ended
    }

    private func handle(_ call: ClientToolCallEvent) async {
        let timeZone = TimeZone.current
        switch VoiceToolRequest.parse(name: call.toolName, parametersJSON: call.parametersData, now: Date(), timeZone: timeZone) {
        case .searchMemories(let query):
            do {
                let outcome = try await store.recall(query)
                await reply(call.toolCallId, VoiceToolReply.search(outcome))
            } catch {
                await reply(call.toolCallId, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
            }
        case .saveMemory(let text):
            // Nothing is stored until the user taps Save on the card.
            propose(call.toolCallId, .saveMemory(text))
        case .readCalendar(let from, let to):
            guard connections.state(.calendar).canRead else {
                await reply(call.toolCallId, VoiceToolReply.notConnected(.calendar))
                return
            }
            do {
                let events = try await connections.events(from: from, to: to)
                await reply(call.toolCallId, VoiceToolReply.calendar(events, from: from, to: to, timeZone: timeZone))
            } catch {
                await reply(call.toolCallId, VoiceToolReply.readFailed(ConnectionsCopy.message(for: error)), isError: true)
            }
        case .createCalendarEvent(let draft):
            guard connections.state(.calendar).canWrite else {
                await reply(call.toolCallId, VoiceToolReply.notConnected(.calendar))
                return
            }
            propose(call.toolCallId, .addEvent(draft))
        case .createReminder(let draft):
            guard connections.state(.reminders).canWrite else {
                await reply(call.toolCallId, VoiceToolReply.notConnected(.reminders))
                return
            }
            propose(call.toolCallId, .addReminder(draft))
        case .lookupContact(let name):
            guard connections.state(.contacts).canRead else {
                await reply(call.toolCallId, VoiceToolReply.notConnected(.contacts))
                return
            }
            do {
                let matches = try await connections.lookupContacts(name)
                contactResults = matches
                await reply(call.toolCallId, VoiceToolReply.contacts(matches, query: name))
            } catch {
                await reply(call.toolCallId, VoiceToolReply.readFailed(ConnectionsCopy.message(for: error)), isError: true)
            }
        case .unsupported(let name):
            await reply(call.toolCallId, VoiceToolReply.unsupported(name), isError: true)
        case .invalid(_, let reason):
            await reply(call.toolCallId, VoiceToolReply.failed("The request was incomplete (\(reason))."), isError: true)
        }
    }

    /// Shows a confirmation card. Only one at a time, so a tap always answers the card on screen.
    private func propose(_ toolCallID: String, _ kind: PendingAction.Kind) {
        if pendingAction != nil {
            Task { await reply(toolCallID, VoiceToolReply.busy, isError: true) }
            return
        }
        receipt = nil
        pendingAction = PendingAction(toolCallID: toolCallID, kind: kind)
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
