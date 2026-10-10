import AVFAudio
import DoddyCore
import ElevenLabs
import Foundation
import LiveKit
import Observation
import UIKit
import os

/// One voice conversation with the ElevenLabs agent. State shown in the UI comes only from real
/// SDK events (connected, listening, speaking, disconnected), never from timers.
/// Tool calls are proposals. Lookups run on the phone. Anything that changes data, starts
/// something, or opens another app waits for the user's tap, and Doddy never sends a message.
/// At start the app hands the agent the saved notes and the last few conversations (dynamic
/// variables); at the end the transcript lines are kept locally in `ConversationLogStore`.
/// Every tool call and its verified result is recorded in "What Doddy did" (`ActivityLogStore`).
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
        /// Doddy's own reminder about one saved note (ADR-198). `noteText` is the stored note the
        /// agent's quote matched, shown exactly; nothing is set until the user taps Set reminder.
        case noteReminder(toolCallID: String, memoryID: UUID, noteText: String, target: NoteReminderCardTarget)
        /// Several changes on one card (ADR-204). `blocked` steps are shown but can't be ticked.
        case plan(toolCallID: String, steps: [PlanStep], blocked: [Int: PlanBlock])

        var toolCallID: String {
            switch self {
            case .memory(let id, _), .event(let id, _), .reminder(let id, _), .timer(let id, _),
                 .map(let id, _), .shortcut(let id, _), .message(let id, _, _), .cloud(let id, _, _, _, _),
                 .noteReminder(let id, _, _, _), .plan(let id, _, _):
                id
            }
        }
    }

    /// What a note-reminder card offers: the checked moment, or Apple Maps results to pick from.
    enum NoteReminderCardTarget: Equatable {
        case time(Date, timeZoneID: String)
        case place(results: [PlaceSearchResult], onArrival: Bool)
    }

    /// Contacts found by a lookup. Shown on screen only; the agent receives names.
    struct ContactCard: Equatable {
        let query: String
        let matches: [DeviceConnections.ContactMatch]
    }

    /// Each step of a confirmed plan with its own result, as logged in "What Doddy did". It stays
    /// on screen after the conversation ends, like the reminder receipt.
    struct PlanStatus: Equatable {
        let steps: [PlanStep]
        var results: [Int: ActivityEntry] = [:]
        var isRunning = true
    }

    /// The receipt after the user tapped Add on a reminder card (M4). It stays on screen after
    /// the conversation ends, because the agent may never hear the answer (its wait can time out).
    enum ReminderStatus: Equatable {
        case adding(ReminderDraft)
        case done(ReminderDraft, ReminderOutcome)
    }

    private(set) var phase: Phase = .idle {
        didSet {
            Self.conversationInProgress = isLive
            syncIsland()
        }
    }
    /// True while any conversation holds the microphone (the island keeps it alive in other
    /// screens). Voice samples in Settings don't play then, so they never take over its audio.
    static private(set) var conversationInProgress = false
    private(set) var lines: [Line] = []
    private(set) var pendingAction: PendingAction? { didSet { syncIsland() } }
    /// The type the user picks on the "Save this note?" card. Starts as Other for every proposal;
    /// the agent is never told or asked (ADR-202).
    var pendingMemoryCategory: MemoryCategory = .other
    private(set) var contactCard: ContactCard?
    private(set) var reminderStatus: ReminderStatus?
    /// Which steps of the plan card are ticked. Every step that can run starts ticked.
    private(set) var planTicked: Set<Int> = []
    private(set) var planStatus: PlanStatus?
    /// Which Apple Maps result the user picked on a place card (the first until they tap another).
    private(set) var selectedPlaceIndex = 0
    /// A function the agent asked for that is off or blocked. The screen offers to turn it on.
    private(set) var connectionNeeded: VoiceConnection?
    private(set) var isMuted = false { didSet { syncIsland() } }

    private let store: MemoryStore
    private let logs: ConversationLogStore
    private let activity: ActivityLogStore
    /// What each open tool call asked for, until its reply is sent and logged.
    private var asked: [String: ActivityRequest] = [:]
    /// Changes the user confirmed that are running now, logged "in progress" before they ran.
    private var started: [String: ActivityEntry] = [:]
    /// Plan cards waiting for the user's answer, so their steps are logged if the conversation ends.
    private var askedPlans: [String: [PlanStep]] = [:]
    private let island = VoiceLiveActivity()
    /// True while iOS has paused Doddy's audio because another app took the audio session
    /// (`AVAudioSession` interruption). Real system events only, never a guess.
    private(set) var audioPausedByOtherApp = false
    /// What iOS last said about the audio session (reason and session setup), shown in small print
    /// on the voice screen so a failure can be read without Xcode. No speech or notes in it.
    private(set) var audioNote: String?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    private static let audioLog = Logger(subsystem: "com.bienos.doddy2.dev", category: "voice-audio")
    private let devices = DeviceConnections()
    private var conversation: Conversation?
    private var startedAt: Date?
    /// Private conversation (PRD item 6, ADR-170): when on at the end, nothing of it is kept on the
    /// phone, so it never comes back as "recent conversations". Explicit saves still need a tap.
    var isPrivate = false
    /// Notes the user tapped Save on in this conversation, for the island's "ended" card.
    private var savedThisConversation = 0

    init(store: MemoryStore, logs: ConversationLogStore = .shared, activity: ActivityLogStore = .shared) {
        self.store = store
        self.logs = logs
        self.activity = activity
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
        reminderStatus = nil
        planStatus = nil
        connectionNeeded = nil
        isMuted = false
        savedThisConversation = 0
        audioPausedByOtherApp = false
        audioNote = nil

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
                PersonalityPrompt.variableName: PersonalityPrompt.render(.stored(), nickname: Nickname.stored()),
                ProfilePrompt.variableName: ProfilePrompt.render(
                    profile, shared: UserDefaults.standard.bool(forKey: PreferenceKey.shareProfileWithVoice)),
            ],
            userId: Self.userID())
        // Voice, speed and expressiveness (Settings → Voice and personality). Only changed values
        // are sent; the agent must allow these TTS overrides (ADR-105).
        if let tts = VoiceStyle.stored().override {
            config.ttsOverrides = TTSOverrides(voiceId: tts.voiceID, stability: tts.stability, speed: tts.speed)
        }
        // Starting language (ADR-132): only sent when the user picked one; needs the agent to
        // allow the `agent.language` override. Auto keeps the agent's own language detection.
        if let code = ConversationLanguage.stored().overrideCode, let language = Language(rawValue: code) {
            config.agentOverrides = AgentOverrides(language: language)
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

        Self.allowOtherAppsAudio()
        do {
            let started = try await ElevenLabs.startConversation(auth: auth, config: config)
            guard isLive else {
                // Closed while connecting: end it so nothing keeps listening.
                await started.endConversation()
                return
            }
            conversation = started
            watchAudioInterruptions()
            Self.audioLog.notice("conversation started. \(Self.describeAudioSession(), privacy: .public)")
        } catch {
            // An agent that doesn't allow the voice overrides refuses the conversation.
            let voiceHint = config.ttsOverrides == nil && config.agentOverrides == nil
                ? ""
                : " If it keeps failing, choose \"Use Doddy's own voice\" and language \"Automatic\" in Settings → Voice and personality."
            fail("Couldn't connect to Doddy's voice. Check your internet connection and try again.\(voiceHint) (\(error.localizedDescription))")
        }
    }

    /// Keeps the conversation going when the user opens another app that plays or records sound
    /// (ADR-205). The SDK's default call session is not mixable, so another app starting its own
    /// audio session pauses Doddy at once and nothing brings him back. A mixable session is not
    /// paused that way. Cost: the other app's sound plays along with Doddy's, and the microphone
    /// can hear it (headphones avoid that). Same options as the SDK's own speaker preset plus
    /// `.mixWithOthers`. Not verified on a device.
    private static func allowOtherAppsAudio() {
        #if swift(>=6.2)
        let routes: AVAudioSession.CategoryOptions = [.allowBluetoothHFP, .allowBluetoothA2DP, .allowAirPlay]
        #else
        let routes: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
        #endif
        AudioManager.shared.sessionConfiguration = AudioSessionConfiguration(
            category: .playAndRecord,
            categoryOptions: routes.union([.defaultToSpeaker, .mixWithOthers]),
            mode: .videoChat)
    }

    /// Reports iOS audio interruptions (for example another app opening its own audio) as they
    /// happen: on screen, in the log, and as `audioPausedByOtherApp`.
    private func watchAudioInterruptions() {
        guard interruptionObserver == nil else { return }
        let ref = WeakRef(self)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { note in
            let info = note.userInfo
            let began = (info?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            let reason = (info?[AVAudioSessionInterruptionReasonKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionReason.init(rawValue:))
                .map { "\($0)" } ?? "not given"
            Task { @MainActor in ref.value?.audioInterruption(began: began, reason: reason) }
        }
    }

    private func stopWatchingAudioInterruptions() {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        audioPausedByOtherApp = false
    }

    private func audioInterruption(began: Bool, reason: String) {
        guard isLive else { return }
        audioPausedByOtherApp = began
        let note = "\(began ? "iOS paused Doddy's audio" : "iOS gave Doddy's audio back") (reason: \(reason)). Session: \(Self.describeAudioSession())."
        audioNote = note
        Self.audioLog.notice("\(note, privacy: .public)")
    }

    private static func describeAudioSession() -> String {
        let session = AVAudioSession.sharedInstance()
        let mixing = session.categoryOptions.contains(.mixWithOthers) ? "mixing with other apps ON" : "mixing with other apps OFF"
        return "\(session.category.rawValue), mode \(session.mode.rawValue), \(mixing), other app audio playing: \(session.isOtherAudioPlaying)"
    }

    func stop() async {
        stopWatchingAudioInterruptions()
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
    /// conversation can continue from it. Nothing is kept when there were no lines, when the
    /// user switched "Remember recent conversations" off, or when this conversation is private.
    private func keepLog() {
        logUnanswered()
        guard let startedAt else { return }
        self.startedAt = nil
        guard ConversationRetention.shouldKeep(rememberRecent: logs.isEnabled, isPrivate: isPrivate, lineCount: lines.count) else { return }
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
        // On disk before the change runs: if Doddy is closed mid-way, the next launch shows it
        // as "Not sure" instead of nothing (ActivityLog.recoverInterrupted).
        if action.changesSomething, let request = asked[action.toolCallID] {
            let entry = ActivityEntry.started(request, at: Date())
            activity.append(entry)
            started[action.toolCallID] = entry
        }
        switch action {
        case .memory(let id, let text):
            do {
                // rawText is the proposal the user reviewed, not a claimed verbatim transcript.
                let record = try await store.save(text: text, category: pendingMemoryCategory, source: .explicitVoice)
                pendingMemoryCategory = .other
                savedThisConversation += 1
                await reply(id, VoiceToolReply.saved(record))
            } catch {
                await reply(id, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
            }
        case .event(let id, let draft):
            await reply(id, addEvent(draft))
        case .reminder(let id, let draft):
            // The card is already gone (pendingAction is nil), so a second tap does nothing.
            reminderStatus = .adding(draft)
            let outcome = await addReminder(draft)
            reminderStatus = .done(draft, outcome)
            await reply(id, VoiceToolReply.reminder(outcome))
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
        case .noteReminder(let id, let memoryID, let noteText, let target):
            await reply(id, await setNoteReminder(memoryID: memoryID, noteText: noteText, target: target))
        case .plan(let id, let steps, let blocked):
            await runPlan(id, steps: steps, blocked: blocked)
        }
    }

    func selectPlace(_ index: Int) {
        guard case .noteReminder(_, _, _, .place(let results, _)) = pendingAction, results.indices.contains(index) else { return }
        selectedPlaceIndex = index
    }

    /// Sets the reminder through the same store as the note screen, then tells the agent only what
    /// the store verified (a scheduled request, Doddy-only, or why nothing was set).
    private func setNoteReminder(memoryID: UUID, noteText: String, target: NoteReminderCardTarget) async -> String {
        guard let reminders = store.noteReminders, reminders.isAvailable else {
            return VoiceToolReply.noteReminderFailed("Reminders on notes aren't available on this iPhone right now.")
        }
        // The user just tapped Set reminder, so this is the moment to ask iOS, once.
        if reminders.authorization == .notDetermined { await reminders.requestAuthorization() }
        switch target {
        case .time(let date, let zone):
            await reminders.set(memoryID: memoryID, at: date, timeZone: TimeZone(identifier: zone) ?? .autoupdatingCurrent)
        case .place(let results, let onArrival):
            let choice = results[min(selectedPlaceIndex, results.count - 1)]
            guard let place = try? ReminderPlace(
                name: String(choice.name.prefix(ReminderPlace.maxNameLength)),
                latitude: choice.coordinate.latitude, longitude: choice.coordinate.longitude,
                radiusMeters: ReminderPlace.defaultRadius, onArrival: onArrival)
            else { return VoiceToolReply.noteReminderFailed("That place can't be used.") }
            if reminders.locationReadiness == .notDetermined { await reminders.requestLocation() }
            await reminders.set(memoryID: memoryID, place: place)
        }
        switch reminders.receipts[memoryID] {
        case .scheduled(let reminder): return VoiceToolReply.noteReminderSet(reminder, note: noteText)
        case .inAppOnly(let reminder): return VoiceToolReply.noteReminderInDoddyOnly(reminder, note: noteText)
        case .failed(let message), .needsSettings(let message): return VoiceToolReply.noteReminderFailed(message)
        case nil: return VoiceToolReply.noteReminderFailed("Doddy couldn't set the reminder.")
        }
    }

    /// The user tapped the card's decline button. Nothing changes.
    func declinePendingAction() async {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .memory(let id, _):
            pendingMemoryCategory = .other
            await reply(id, VoiceToolReply.declined)
        case .event(let id, _): await reply(id, VoiceToolReply.declinedEvent)
        case .reminder(let id, _): await reply(id, VoiceToolReply.declinedReminder)
        case .timer(let id, _): await reply(id, VoiceToolReply.declinedTimer)
        case .map(let id, _): await reply(id, VoiceToolReply.declinedMap)
        case .shortcut(let id, _): await reply(id, VoiceToolReply.declinedShortcut)
        case .message(let id, _, _): await reply(id, VoiceToolReply.declinedMessage)
        case .cloud(let id, let call, _, _, _): await reply(id, VoiceToolReply.cloudDeclined(call.name))
        case .noteReminder(let id, _, _, _): await reply(id, VoiceToolReply.declinedNoteReminder)
        case .plan(let id, let steps, _):
            askedPlans[id] = nil
            let planID = UUID()
            for step in steps {
                logPlanStep(step, reply: PlanReply.declined, plan: ActivityPlanRef(id: planID, step: step.number, count: steps.count))
            }
            await reply(id, PlanReply.declined)
        }
    }

    /// Ticks or unticks one step of the plan card. Blocked steps stay unticked.
    func togglePlanStep(_ number: Int) {
        guard case .plan(_, let steps, let blocked) = pendingAction,
              steps.contains(where: { $0.number == number }), blocked[number] == nil else { return }
        if planTicked.contains(number) { planTicked.remove(number) } else { planTicked.insert(number) }
    }

    func dismissPlanStatus() {
        guard planStatus?.isRunning == false else { return }
        planStatus = nil
    }

    func dismissContactCard() {
        contactCard = nil
    }

    func dismissReminderStatus() {
        guard case .done = reminderStatus else { return }
        reminderStatus = nil
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
        stopWatchingAudioInterruptions()
        phase = .failed(message)
        pendingAction = nil
    }

    private func disconnected() {
        stopWatchingAudioInterruptions()
        conversation = nil
        pendingAction = nil
        keepLog()
        if case .failed = phase { return }
        phase = .ended
    }

    private func handle(_ call: ClientToolCallEvent) async {
        if call.toolName == VoiceToolName.proposePlan {
            await handlePlan(call)
            return
        }
        let request = VoiceToolRequest.parse(name: call.toolName, parametersJSON: call.parametersData)
        asked[call.toolCallId] = ActivityRequest.describe(request, calendar: .current)
        // Settings → Pause all: no other app or account is used; notes still work.
        if UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey), ConnectionPause.applies(to: request) {
            await reply(call.toolCallId, ConnectionPause.reply)
            return
        }
        if let connection = VoiceConnection.serving(call.toolName), !isOn(connection) {
            await notConnected(call.toolCallId, connection)
            return
        }
        switch request {
        case .searchMemories(let query):
            do {
                let outcome = try await store.recall(query)
                await reply(call.toolCallId, VoiceToolReply.search(outcome))
            } catch {
                await reply(call.toolCallId, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
            }
        case .saveMemory(let text):
            // Nothing is stored until the user taps Save on the card.
            pendingMemoryCategory = .other
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
            // Blocked by iOS: say so now instead of showing a card that can only fail.
            guard devices.access(for: .reminders) == .granted else {
                await notConnected(call.toolCallId, .reminders)
                return
            }
            propose(.reminder(toolCallID: call.toolCallId, draft: draft), toolCallID: call.toolCallId)
        case .remindAboutNote(let draft):
            await proposeNoteReminder(draft, toolCallID: call.toolCallId)
        case .needsClarification(let name, let clarification):
            // Unclear, past or clock-change time: the agent asks the user; no card, nothing added.
            await reply(call.toolCallId, VoiceToolReply.clarification(clarification, tool: name))
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

    // MARK: Plan card (ADR-204)

    /// Every step is parsed and checked as if asked on its own. A step the app can't run (paused,
    /// switched off, no iOS permission) is shown with the reason instead of being dropped.
    private func handlePlan(_ call: ClientToolCallEvent) async {
        let steps: [PlanStep]
        switch PlanProposal.parse(parametersJSON: call.parametersData) {
        case .refused(let text):
            await reply(call.toolCallId, text)
            return
        case .plan(let parsed):
            steps = parsed
        }
        guard pendingAction == nil else {
            // One card at a time, as in propose(_:toolCallID:).
            await reply(call.toolCallId, VoiceToolReply.failed("Another item is waiting for the user's answer."))
            return
        }
        var blocked: [Int: PlanBlock] = [:]
        for step in steps {
            guard let block = await planBlock(for: step) else { continue }
            blocked[step.number] = block
            if connectionNeeded == nil, case .notConnected(let connection) = block { connectionNeeded = connection }
        }
        // Nothing could run: answer now instead of showing a card with nothing to tick.
        guard blocked.count < steps.count else {
            let planID = UUID()
            var results: [(step: PlanStep, reply: String)] = []
            for step in steps {
                let text = blocked[step.number]?.reply ?? PlanReply.unticked
                logPlanStep(step, reply: text, plan: ActivityPlanRef(id: planID, step: step.number, count: steps.count))
                results.append((step, text))
            }
            await reply(call.toolCallId, PlanReply.summary(results))
            return
        }
        planTicked = Set(steps.map(\.number)).subtracting(blocked.keys)
        askedPlans[call.toolCallId] = steps
        propose(.plan(toolCallID: call.toolCallId, steps: steps, blocked: blocked), toolCallID: call.toolCallId)
    }

    /// Ticked steps run one after another, each through the same path as its single card, and each
    /// gets its own result. A step that fails doesn't stop the others; none is retried.
    private func runPlan(_ toolCallID: String, steps: [PlanStep], blocked: [Int: PlanBlock]) async {
        askedPlans[toolCallID] = nil
        let ticked = planTicked
        let planID = UUID()
        planStatus = PlanStatus(steps: steps)
        var results: [(step: PlanStep, reply: String)] = []
        for step in steps {
            let ref = ActivityPlanRef(id: planID, step: step.number, count: steps.count)
            var startedEntry: ActivityEntry?
            let text: String
            if let block = blocked[step.number] {
                text = block.reply
            } else if !ticked.contains(step.number) {
                text = PlanReply.unticked
            } else {
                // On disk before it runs, like a single card (ActivityLog.recoverInterrupted).
                if let request = step.activity(calendar: .current) {
                    let entry = ActivityEntry.started(request, at: Date(), plan: ref)
                    activity.append(entry)
                    startedEntry = entry
                }
                text = await runPlanStep(step)
            }
            planStatus?.results[step.number] = logPlanStep(step, reply: text, plan: ref, replacing: startedEntry)
            results.append((step, text))
        }
        planStatus?.isRunning = false
        await reply(toolCallID, PlanReply.summary(results))
    }

    /// Checked again at the tap: the user may have paused or switched off the app while the card waited.
    private func runPlanStep(_ step: PlanStep) async -> String {
        if let block = await planBlock(for: step) { return block.reply }
        switch step.request {
        case .saveMemory(let text):
            do {
                let record = try await store.save(text: text, category: .other, source: .explicitVoice)
                savedThisConversation += 1
                return VoiceToolReply.saved(record)
            } catch {
                return VoiceToolReply.failed(UserFacingError.message(for: error))
            }
        case .createCalendarEvent(let draft):
            return addEvent(draft)
        case .createReminder(let draft):
            return VoiceToolReply.reminder(await addReminder(draft))
        case .setTimer(let draft):
            return await startTimer(draft)
        default:
            // PlanProposal only makes the four kinds above.
            return VoiceToolReply.notAdded("This step can't run in a plan.")
        }
    }

    private func planBlock(for step: PlanStep) async -> PlanBlock? {
        if UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey), ConnectionPause.applies(to: step.request) {
            return .paused
        }
        guard let connection = step.connection else { return nil }
        guard isOn(connection) else { return .notConnected(connection) }
        let access: DeviceConnections.Access
        if connection == .timers {
            access = await devices.notificationAccess()
        } else {
            access = devices.access(for: connection)
        }
        return access == .granted ? nil : .notConnected(connection)
    }

    @discardableResult
    private func logPlanStep(_ step: PlanStep, reply text: String, plan: ActivityPlanRef, replacing started: ActivityEntry? = nil) -> ActivityEntry? {
        guard let request = step.activity(calendar: .current) else { return nil }
        let entry = ActivityEntry(id: started?.id ?? UUID(), request: request, reply: text, at: started?.at ?? Date(), plan: plan)
        if started != nil { activity.replace(entry) } else { activity.append(entry) }
        return entry
    }

    /// Gmail, Drive, Notion, Todoist and web search go through Doddy's server, which checks the tool's
    /// switch (and, for accounts, the connection and the grant). Reads answer at once; writes show a card first.
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

    /// Finds the quoted note and, for a place, looks it up in Apple Maps before showing the card.
    private func proposeNoteReminder(_ draft: NoteReminderVoiceDraft, toolCallID: String) async {
        guard store.noteReminders?.isAvailable == true else {
            await reply(toolCallID, VoiceToolReply.noteReminderFailed("Reminders on notes aren't available on this iPhone right now."), isError: true)
            return
        }
        await store.reload()
        guard let record = NoteQuoteMatch.find(draft.noteText, in: store.memories) else {
            await reply(toolCallID, VoiceToolReply.noteNotFound())
            return
        }
        switch draft.target {
        case .time(let date, let zone):
            propose(.noteReminder(toolCallID: toolCallID, memoryID: record.id, noteText: record.currentText,
                                  target: .time(date, timeZoneID: zone)), toolCallID: toolCallID)
        case .place(let query, let onArrival):
            let results: [PlaceSearchResult]
            do {
                results = try await PlaceLocation.shared.search(query, near: nil)
            } catch {
                await reply(toolCallID, VoiceToolReply.noteReminderFailed("Couldn't search Apple Maps. Check the internet connection."))
                return
            }
            guard !results.isEmpty else {
                await reply(toolCallID, VoiceToolReply.placeNotFound(query))
                return
            }
            selectedPlaceIndex = 0
            propose(.noteReminder(toolCallID: toolCallID, memoryID: record.id, noteText: record.currentText,
                                  target: .place(results: Array(results.prefix(5)), onArrival: onArrival)), toolCallID: toolCallID)
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
        // The start may have passed while the card waited (ADR-128): ask again, add nothing.
        if let late = draft.passed(now: Date(), calendar: .current) {
            return VoiceToolReply.clarification(late, tool: VoiceToolName.createCalendarEvent)
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

    /// Look first, write once, read back (DoddyCore `ReminderAction`). Permission is checked again
    /// at the tap, since the user may have changed it while the card waited.
    private func addReminder(_ draft: ReminderDraft) async -> ReminderOutcome {
        guard isOn(.reminders), devices.access(for: .reminders) == .granted else {
            connectionNeeded = .reminders
            return .notAdded(.notAllowed)
        }
        let outcome = await ReminderAction.add(draft, to: devices, now: Date())
        if outcome == .notAdded(.notAllowed) { connectionNeeded = .reminders }
        return outcome
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
        if let request = asked.removeValue(forKey: toolCallID) {
            if let entry = started.removeValue(forKey: toolCallID) {
                activity.replace(ActivityEntry(id: entry.id, request: request, reply: text, at: entry.at))
            } else {
                activity.append(ActivityEntry(request: request, reply: text, at: Date()))
            }
        }
        try? await conversation?.sendToolResult(for: toolCallID, result: text, isError: isError)
    }

    /// Requests still waiting on a card when the conversation ends: nothing happened.
    private func logUnanswered() {
        // Confirmed changes still running keep their entry; their result replaces it when it arrives.
        for (toolCallID, request) in asked where started[toolCallID] == nil {
            var entry = ActivityEntry(request: request, reply: "", at: Date())
            entry.outcome = .notDone
            entry.note = "The conversation ended before you answered."
            activity.append(entry)
            asked[toolCallID] = nil
        }
        for (_, steps) in askedPlans {
            let planID = UUID()
            for step in steps {
                guard let request = step.activity(calendar: .current) else { continue }
                var entry = ActivityEntry(request: request, reply: "", at: Date(), plan: ActivityPlanRef(id: planID, step: step.number, count: steps.count))
                entry.outcome = .notDone
                entry.note = "The conversation ended before you answered."
                activity.append(entry)
            }
        }
        askedPlans = [:]
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

private extension VoiceSessionController.PendingAction {
    /// Saves, adds or starts something. Opening Maps, Shortcuts or a draft only hands over to another app.
    var changesSomething: Bool {
        switch self {
        case .memory, .event, .reminder, .timer, .cloud, .noteReminder: true
        // Each step of a plan is logged on its own (runPlan), not the plan as a whole.
        case .map, .shortcut, .message, .plan: false
        }
    }
}
