import AVFAudio
import DoddyCore
import ElevenLabs
import Foundation
import Observation

/// One voice conversation with the ElevenLabs agent. State shown in the UI comes only from real
/// SDK events (connected, listening, speaking, disconnected), never from timers.
/// Tool calls are proposals: searches and lookups run on the phone, and anything that changes
/// data (a note, an event, a reminder) waits for the user's tap.
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

    /// Something the agent proposed that waits for the user's tap on the card.
    enum PendingAction: Equatable {
        case memory(toolCallID: String, text: String)
        case event(toolCallID: String, draft: CalendarEventDraft)
        case reminder(toolCallID: String, draft: ReminderDraft)

        var toolCallID: String {
            switch self {
            case .memory(let id, _), .event(let id, _), .reminder(let id, _): id
            }
        }
    }

    /// Contacts found by a lookup. Shown on screen only; the agent receives names.
    struct ContactCard: Equatable {
        let query: String
        let matches: [DeviceConnections.ContactMatch]
    }

    private(set) var phase: Phase = .idle
    private(set) var lines: [Line] = []
    private(set) var pendingAction: PendingAction?
    private(set) var contactCard: ContactCard?
    /// A function the agent asked for that is off or blocked. The screen offers to turn it on.
    private(set) var connectionNeeded: VoiceConnection?
    private(set) var isMuted = false

    private let store: MemoryStore
    private let devices = DeviceConnections()
    private var conversation: Conversation?

    init(store: MemoryStore) {
        self.store = store
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
        contactCard = nil
        connectionNeeded = nil
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
        contactCard = nil
        connectionNeeded = nil
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

    /// The user tapped Save or Add on the card.
    func confirmPendingAction() async {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .memory(let id, let text):
            do {
                let record = try await store.save(text: text, category: .other)
                await reply(id, VoiceToolReply.saved(record))
            } catch {
                await reply(id, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
            }
        case .event(let id, let draft):
            await reply(id, addEvent(draft))
        case .reminder(let id, let draft):
            await reply(id, addReminder(draft))
        }
    }

    /// The user tapped "Don't save" or "Don't add". Nothing changes.
    func declinePendingAction() async {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .memory(let id, _): await reply(id, VoiceToolReply.declined)
        case .event(let id, _): await reply(id, VoiceToolReply.declinedEvent)
        case .reminder(let id, _): await reply(id, VoiceToolReply.declinedReminder)
        }
    }

    func dismissContactCard() {
        contactCard = nil
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
        if let connection = VoiceConnection.serving(call.toolName), !isOn(connection) {
            await notConnected(call.toolCallId, connection)
            return
        }
        switch VoiceToolRequest.parse(name: call.toolName, parametersJSON: call.parametersData) {
        case .searchMemories(let query):
            do {
                let outcome = try await store.recall(query)
                await reply(call.toolCallId, VoiceToolReply.search(outcome))
            } catch {
                await reply(call.toolCallId, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
            }
        case .saveMemory(let text):
            propose(.memory(toolCallID: call.toolCallId, text: text), toolCallID: call.toolCallId)
        case .readCalendar(let range):
            guard devices.access(for: .calendar) == .granted else {
                await notConnected(call.toolCallId, .calendar)
                return
            }
            let events = devices.events(in: range)
            await reply(call.toolCallId, VoiceToolReply.calendarEvents(events, range: range, calendar: .current))
        case .createCalendarEvent(let draft):
            propose(.event(toolCallID: call.toolCallId, draft: draft), toolCallID: call.toolCallId)
        case .createReminder(let draft):
            propose(.reminder(toolCallID: call.toolCallId, draft: draft), toolCallID: call.toolCallId)
        case .lookupContact(let name):
            guard devices.access(for: .contacts) == .granted else {
                await notConnected(call.toolCallId, .contacts)
                return
            }
            do {
                let matches = try devices.findContacts(named: name)
                contactCard = ContactCard(query: name, matches: matches)
                await reply(call.toolCallId, VoiceToolReply.contactMatches(matches.map(\.name), query: name))
            } catch {
                await reply(call.toolCallId, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
            }
        case .unsupported(let name):
            await reply(call.toolCallId, VoiceToolReply.unsupported(name), isError: true)
        case .invalid(_, let reason):
            await reply(call.toolCallId, VoiceToolReply.failed("The request was incomplete (\(reason))."), isError: true)
        }
    }

    /// Shows one card at a time. A second proposal while one is waiting is refused, so no tool
    /// call is left without an answer.
    private func propose(_ action: PendingAction, toolCallID: String) {
        guard pendingAction == nil else {
            Task { await reply(toolCallID, VoiceToolReply.failed("Another item is waiting for the user's answer.")) }
            return
        }
        pendingAction = action
    }

    private func addEvent(_ draft: CalendarEventDraft) -> String {
        guard devices.access(for: .calendar) == .granted else {
            return VoiceToolReply.notAdded("Calendar isn't connected.")
        }
        do {
            switch try devices.addEvent(draft) {
            case .verified: return VoiceToolReply.eventAdded(draft, calendar: .current)
            case .unconfirmed: return VoiceToolReply.addUnconfirmed
            }
        } catch {
            return VoiceToolReply.notAdded(UserFacingError.message(for: error))
        }
    }

    private func addReminder(_ draft: ReminderDraft) -> String {
        guard devices.access(for: .reminders) == .granted else {
            return VoiceToolReply.notAdded("Reminders isn't connected.")
        }
        do {
            switch try devices.addReminder(draft, calendar: .current) {
            case .verified: return VoiceToolReply.reminderAdded(draft, calendar: .current)
            case .unconfirmed: return VoiceToolReply.addUnconfirmed
            }
        } catch {
            return VoiceToolReply.notAdded(UserFacingError.message(for: error))
        }
    }

    private func notConnected(_ toolCallID: String, _ connection: VoiceConnection) async {
        connectionNeeded = connection
        await reply(toolCallID, VoiceToolReply.notConnected(connection))
    }

    /// Called after the Connections sheet closes: the prompt goes away once the switch is on.
    func refreshConnectionNeeded() {
        guard let needed = connectionNeeded, isOn(needed) else { return }
        connectionNeeded = nil
    }

    private func isOn(_ connection: VoiceConnection) -> Bool {
        UserDefaults.standard.bool(forKey: connection.preferenceKey)
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
