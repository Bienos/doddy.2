import AVFAudio
import DoddyCore
import ElevenLabs
import Foundation
import Observation
import UIKit

/// One voice conversation with the ElevenLabs agent. State shown in the UI comes only from real
/// SDK events (connected, listening, speaking, disconnected), never from timers.
/// Tool calls are proposals. Lookups run on the phone. Anything that changes data, starts
/// something, or opens another app waits for the user's tap, and Doddy never sends a message.
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

    /// Something the agent proposed that waits for the user's tap on the card.
    enum PendingAction: Equatable {
        case memory(toolCallID: String, text: String)
        case event(toolCallID: String, draft: CalendarEventDraft)
        case reminder(toolCallID: String, draft: ReminderDraft)
        case timer(toolCallID: String, draft: TimerDraft)
        case map(toolCallID: String, place: String)
        case shortcut(toolCallID: String, name: String)
        /// `address` is the phone number or email from Contacts. It is shown on screen only.
        case message(toolCallID: String, draft: MessageDraft, address: String)
        /// Gmail draft or Todoist task. `preview` and `approvalID` come from Doddy's server for exactly
        /// these arguments; the approval works once and expires after two minutes.
        case cloud(toolCallID: String, call: CloudToolCall, preview: ToolPreview, approvalID: UUID, mode: ConnectedAppsMode)

        var toolCallID: String {
            switch self {
            case .memory(let id, _), .event(let id, _), .reminder(let id, _), .timer(let id, _),
                 .map(let id, _), .shortcut(let id, _), .message(let id, _, _), .cloud(let id, _, _, _, _):
                id
            }
        }
    }

    /// Contacts found by a lookup. Shown on screen only; the agent receives names.
    struct ContactCard: Equatable {
        let query: String
        let matches: [DeviceConnections.ContactMatch]
    }

    private(set) var phase: Phase = .idle { didSet { syncIsland() } }
    private(set) var lines: [Line] = []
    private(set) var pendingAction: PendingAction? { didSet { syncIsland() } }
    private(set) var contactCard: ContactCard?
    /// A function the agent asked for that is off or blocked. The screen offers to turn it on.
    private(set) var connectionNeeded: VoiceConnection?
    private(set) var isMuted = false { didSet { syncIsland() } }

    private let store: MemoryStore
    private let logs: ConversationLogStore
    private let island = VoiceLiveActivity()
    private let devices = DeviceConnections()
    private var conversation: Conversation?
    private var startedAt: Date?
    /// Notes the user tapped Save on in this conversation, for the island's "ended" card.
    private var savedThisConversation = 0

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

    /// `profile` is the user's approved introduction answers; it reaches the agent only when
    /// Settings → About you → "Use in voice conversations" is on.
    func start(_ mode: VoiceConnectionMode, profile: ApprovedProfile) async {
        guard !isLive else { return }
        lines = []
        pendingAction = nil
        contactCard = nil
        connectionNeeded = nil
        isMuted = false
        savedThisConversation = 0

        // Not set up: say so without asking for the microphone first.
        if case .notSetUp(let reason) = mode {
            fail(reason)
            return
        }
        guard await Self.microphoneAllowed() else {
            phase = .microphoneDenied
            return
        }
        startedAt = Date()
        phase = .connecting

        // The Dynamic Island / Lock Screen buttons reach this conversation through these.
        let actions = VoiceActivityActions.shared
        actions.endConversation = { [weak self] in
            await self?.stop()
            await self?.island.settle()
        }
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
                ProfilePrompt.variableName: ProfilePrompt.render(
                    profile, shared: UserDefaults.standard.bool(forKey: PreferenceKey.shareProfileWithVoice)),
            ],
            userId: Self.userID())
        // Voice, speed and expressiveness (Settings → Voice and personality). Only changed values
        // are sent; the agent must allow these TTS overrides (ADR-105).
        if let tts = VoiceStyle.stored().override {
            config.ttsOverrides = TTSOverrides(voiceId: tts.voiceID, stability: tts.stability, speed: tts.speed)
        }
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

        config.onAgentReady = {
            Task { @MainActor in
                if ref.value?.phase == .connecting { ref.value?.phase = .listening }
            }
        }
        config.onDisconnect = { _ in
            Task { @MainActor in ref.value?.disconnected() }
        }

        let auth: ElevenLabsConfiguration
        switch mode {
        case .publicAgent(let agentID):
            auth = .publicAgent(id: agentID)
        case .tokenServer(let endpoint, let accessCode):
            do throws(VoiceTokenError) {
                auth = .conversationToken(try await VoiceTokenClient(endpoint: endpoint, accessCode: accessCode).fetchToken())
            } catch {
                if phase == .connecting { fail(VoiceTokenServer.message(for: error)) }
                return
            }
        case .notSetUp(let reason):
            fail(reason)
            return
        }
        // Closed while the token was being fetched: don't open the microphone after all.
        guard phase == .connecting else { return }

        do {
            let started = try await ElevenLabs.startConversation(auth: auth, config: config)
            guard isLive else {
                // Closed while connecting: end it so nothing keeps listening.
                await started.endConversation()
                return
            }
            conversation = started
        } catch {
            // An agent that doesn't allow the voice overrides refuses the conversation.
            let voiceHint = config.ttsOverrides == nil ? "" : " If it keeps failing, choose \"Use Doddy's own voice\" in Settings → Voice and personality."
            fail("Couldn't connect to Doddy's voice. Check your internet connection and try again.\(voiceHint) (\(error.localizedDescription))")
        }
    }

    func stop() async {
        let active = conversation
        conversation = nil
        pendingAction = nil
        contactCard = nil
        connectionNeeded = nil
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

    /// The user tapped the card's confirm button: Save, Add, Start, Open or Run.
    func confirmPendingAction() async {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .memory(let id, let text):
            do {
                // rawText is the proposal the user reviewed, not a claimed verbatim transcript.
                let record = try await store.save(text: text, category: .other, source: .explicitVoice)
                savedThisConversation += 1
                await reply(id, VoiceToolReply.saved(record))
            } catch {
                await reply(id, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
            }
        case .event(let id, let draft):
            await reply(id, addEvent(draft))
        case .reminder(let id, let draft):
            await reply(id, addReminder(draft))
        case .timer(let id, let draft):
            await reply(id, await startTimer(draft))
        case .map(let id, let place):
            guard let url = OpenLinks.map(place: place) else {
                await reply(id, VoiceToolReply.notOpened("That place can't be opened in Maps."))
                return
            }
            let opened = await open(url)
            await reply(id, opened ? VoiceToolReply.mapOpened(place) : VoiceToolReply.notOpened("Maps didn't open."))
        case .shortcut(let id, let name):
            guard let url = OpenLinks.shortcut(name: name) else {
                await reply(id, VoiceToolReply.notOpened("That shortcut name can't be used."))
                return
            }
            let opened = await open(url)
            await reply(id, opened ? VoiceToolReply.shortcutRequested(name) : VoiceToolReply.notOpened("Shortcuts didn't open."))
        case .message(let id, let draft, let address):
            let url = draft.channel == .text
                ? OpenLinks.text(number: address, body: draft.body)
                : OpenLinks.email(address: address, body: draft.body)
            guard let url else {
                await reply(id, VoiceToolReply.notOpened("That address can't be used."))
                return
            }
            let opened = await open(url)
            await reply(id, opened
                ? VoiceToolReply.messageOpened(draft, recipient: draft.recipientName)
                : VoiceToolReply.notOpened("Messages or Mail didn't open."))
        case .cloud(let id, let call, _, let approvalID, _):
            await reply(id, await runConfirmedCloud(call, approvalID: approvalID))
        }
    }

    /// The user tapped the card's decline button. Nothing changes.
    func declinePendingAction() async {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .memory(let id, _): await reply(id, VoiceToolReply.declined)
        case .event(let id, _): await reply(id, VoiceToolReply.declinedEvent)
        case .reminder(let id, _): await reply(id, VoiceToolReply.declinedReminder)
        case .timer(let id, _): await reply(id, VoiceToolReply.declinedTimer)
        case .map(let id, _): await reply(id, VoiceToolReply.declinedMap)
        case .shortcut(let id, _): await reply(id, VoiceToolReply.declinedShortcut)
        case .message(let id, _, _): await reply(id, VoiceToolReply.declinedMessage)
        case .cloud(let id, let call, _, _, _): await reply(id, VoiceToolReply.cloudDeclined(call.name))
        }
    }

    func dismissContactCard() {
        contactCard = nil
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
        return .init(status: pendingAction == nil ? status : .needsConfirmation, isMuted: isMuted)
    }

    private func syncIsland() {
        if let state = islandState {
            island.show(state, startedAt: startedAt ?? .now)
        } else if phase == .ended {
            island.finish(savedCount: savedThisConversation)
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
        pendingAction = nil
    }

    private func disconnected() {
        conversation = nil
        pendingAction = nil
        keepLog()
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
            // Nothing is stored until the user taps Save on the card.
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
        case .setTimer(let draft):
            guard await devices.notificationAccess() == .granted else {
                await notConnected(call.toolCallId, .timers)
                return
            }
            propose(.timer(toolCallID: call.toolCallId, draft: draft), toolCallID: call.toolCallId)
        case .openMap(let place):
            propose(.map(toolCallID: call.toolCallId, place: place), toolCallID: call.toolCallId)
        case .runShortcut(let name):
            propose(.shortcut(toolCallID: call.toolCallId, name: name), toolCallID: call.toolCallId)
        case .draftMessage(let draft):
            guard devices.access(for: .contacts) == .granted else {
                await notConnected(call.toolCallId, .contacts)
                return
            }
            do {
                guard let match = try devices.findContacts(named: draft.recipientName).first else {
                    await reply(call.toolCallId, VoiceToolReply.contactMatches([], query: draft.recipientName))
                    return
                }
                let address = draft.channel == .text ? match.phoneNumbers.first : match.emailAddresses.first
                guard let address else {
                    await reply(call.toolCallId, VoiceToolReply.noAddress(match.name, channel: draft.channel), isError: true)
                    return
                }
                propose(.message(toolCallID: call.toolCallId, draft: draft, address: address), toolCallID: call.toolCallId)
            } catch {
                await reply(call.toolCallId, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
            }
        case .cloudTool(let cloud):
            await handleCloud(cloud, toolCallID: call.toolCallId)
        case .unsupported(let name):
            await reply(call.toolCallId, VoiceToolReply.unsupported(name), isError: true)
        case .invalid(_, let reason):
            await reply(call.toolCallId, VoiceToolReply.failed("The request was incomplete (\(reason))."), isError: true)
        }
    }

    /// Gmail, Drive, Notion and Todoist go through Doddy's server, which checks the tool's switch, the
    /// account connection and the grant. Reads answer at once; writes show a card first.
    private func handleCloud(_ cloud: CloudToolCall, toolCallID: String) async {
        guard let client = OnlineAccountsClientFactory.make() else {
            await reply(toolCallID, VoiceToolReply.cloudFailed(.notConfigured, tool: cloud.name), isError: true)
            return
        }
        do {
            if cloud.isWrite {
                let prepared = try await client.prepare(cloud)
                propose(
                    .cloud(toolCallID: toolCallID, call: cloud, preview: prepared.preview, approvalID: prepared.approvalId, mode: prepared.mode),
                    toolCallID: toolCallID)
            } else {
                let result = try await client.run(cloud, timeZone: TimeZone.current.identifier, approvalId: nil)
                await reply(toolCallID, VoiceToolReply.cloudResult(result))
            }
        } catch {
            await reply(toolCallID, VoiceToolReply.cloudFailed(error, tool: cloud.name), isError: true)
        }
    }

    /// The user tapped the card. The approval is for exactly the arguments the card showed.
    private func runConfirmedCloud(_ cloud: CloudToolCall, approvalID: UUID) async -> String {
        guard let client = OnlineAccountsClientFactory.make() else {
            return VoiceToolReply.cloudFailed(.notConfigured, tool: cloud.name)
        }
        do {
            let result = try await client.run(cloud, timeZone: TimeZone.current.identifier, approvalId: approvalID)
            return VoiceToolReply.cloudResult(result)
        } catch {
            return VoiceToolReply.cloudFailed(error, tool: cloud.name)
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

    private func startTimer(_ draft: TimerDraft) async -> String {
        guard await devices.notificationAccess() == .granted else {
            return VoiceToolReply.notAdded("Notifications are off for Doddy.")
        }
        do {
            switch try await devices.startTimer(draft) {
            case .verified:
                let endsAt = Date().addingTimeInterval(TimeInterval(draft.seconds))
                return VoiceToolReply.timerAdded(draft, endsAt: endsAt, calendar: .current)
            case .unconfirmed:
                return VoiceToolReply.addUnconfirmed
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

    private func open(_ url: URL) async -> Bool {
        await UIApplication.shared.open(url)
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
