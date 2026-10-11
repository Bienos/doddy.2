import AVFAudio
import DoddyCore
import ElevenLabs
import Foundation
import LiveKit
import Observation
import UIKit
import os

/// One voice conversation with the ElevenLabs agent, or with OpenAI Realtime when Home's test
/// switch says so (ADR-265; same prompt, notes and tools, see `LiveVoiceLink`). State shown in the
/// UI comes only from real provider events (connected, listening, speaking, disconnected), never
/// from timers.
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
        /// "Set this alarm?" (ADR-260), iOS 26 and later.
        case alarm(toolCallID: String, draft: AlarmDraft)
        /// "Turn off this alarm?" (ADR-283), one of Doddy's alarms.
        case cancelAlarm(toolCallID: String, alarm: AlarmEntry)
        case map(toolCallID: String, place: String)
        case shortcut(toolCallID: String, name: String)
        /// `address` is the phone number or email from Contacts. It is shown on screen only.
        case message(toolCallID: String, draft: MessageDraft, address: String)
        /// Gmail draft or Todoist task. `preview` and `approvalID` come from Doddy's server for exactly
        /// these arguments; the approval works once and expires after two minutes.
        case cloud(toolCallID: String, call: CloudToolCall, preview: ToolPreview, approvalID: UUID, mode: ConnectedAppsMode)
        /// Doddy's own reminder about one saved note (ADR-198). `noteText` is the stored note the
        /// agent's quote matched, shown exactly with when it was saved; nothing is set until the
        /// user taps Set reminder. The user can change the time, or arrive/leave, on the card.
        case noteReminder(toolCallID: String, memoryID: UUID, noteText: String, savedAt: Date?, target: NoteReminderCardTarget)
        /// "Start translating?" (ADR-215). The user can change either language on the card.
        case translator(toolCallID: String, setup: TranslatorSetup)
        /// "Start a new list?" (ADR-216, L2). The user can fix the name on the card.
        case createList(toolCallID: String, name: String, items: [String])
        /// "Change this event?" (ADR-229): the event as it is now and as it will be.
        case changeEvent(toolCallID: String, plan: EventChangePlan)
        /// "Change this reminder?" or "Mark this reminder done?" (ADR-229).
        case changeReminder(toolCallID: String, reminder: ReminderSnapshot, draft: ReminderChangeDraft)
        /// "Delete this event?" (ADR-259): one occurrence, exactly as Calendar has it.
        case deleteEvent(toolCallID: String, event: CalendarEventSummary)
        /// "Delete this reminder?" (ADR-259): one open reminder, exactly as Reminders has it.
        case deleteReminder(toolCallID: String, reminder: ReminderSnapshot)
        /// Several changes on one card (ADR-280). `verb` is "deleted" or "moved"; `skipped` are
        /// reminders left out because their time doesn't exist on the new day.
        case bulk(toolCallID: String, items: [BulkItem], verb: String, skipped: [String])
        /// Several changes on one card (ADR-204). `blocked` steps are shown but can't be ticked.
        case plan(toolCallID: String, steps: [PlanStep], blocked: [Int: PlanBlock])

        var toolCallID: String {
            switch self {
            case .memory(let id, _), .event(let id, _), .reminder(let id, _), .timer(let id, _), .alarm(let id, _), .cancelAlarm(let id, _),
                 .map(let id, _), .shortcut(let id, _), .message(let id, _, _), .cloud(let id, _, _, _, _),
                 .noteReminder(let id, _, _, _, _), .translator(let id, _), .createList(let id, _, _), .plan(let id, _, _),
                 .changeEvent(let id, _), .changeReminder(let id, _, _), .deleteEvent(let id, _), .deleteReminder(let id, _), .bulk(let id, _, _, _):
                id
            }
        }
    }

    /// What a note-reminder card offers: the checked moment, or Apple Maps results to pick from.
    enum NoteReminderCardTarget: Equatable {
        case time(Date, timeZoneID: String, repeats: ReminderRepeat? = nil)
        case place(results: [PlaceSearchResult], onArrival: Bool)
    }

    /// The reminder the user confirmed on a note-reminder card, exactly as it was shown.
    struct ConfirmedNoteReminder: Equatable {
        enum When: Equatable {
            case time(Date, timeZoneID: String, repeats: ReminderRepeat? = nil)
            case place(ReminderPlace)
        }
        let memoryID: UUID
        let noteText: String
        let when: When
    }

    /// The receipt after Set reminder on a note-reminder card (ADR-198), read back from the store.
    /// It stays on screen after the conversation ends, like the Reminders receipt.
    enum NoteReminderStatus: Equatable {
        case setting(ConfirmedNoteReminder)
        case done(ConfirmedNoteReminder, NoteReminderReceipt)
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

    /// What Doddy's server prepared for one online-account step of a plan (ADR-209).
    struct PlanCloudApproval: Equatable {
        let preview: ToolPreview
        let approvalID: UUID
        let mode: ConnectedAppsMode
        let preparedAt: Date
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
    private(set) var reminderStatus: ReminderStatus? {
        didSet {
            // Reminders confirmed it (added, or already there): the island says so briefly (ADR-240).
            // An unknown result is never shown as set.
            if case .done(_, let outcome) = reminderStatus {
                switch outcome {
                case .added, .alreadyThere: flashIsland(.reminderSet)
                default: break
                }
            }
            syncIsland()
        }
    }
    private(set) var noteReminderStatus: NoteReminderStatus?
    /// Which steps of the plan card are ticked. Every step that can run starts ticked.
    private(set) var planTicked: Set<Int> = []
    /// Steps the user changed on the card (ADR-205); the agent is told when it gets the results.
    private(set) var planChanged: Set<Int> = []
    /// Gmail and Todoist steps on the plan card: the server's preview and its one-time approval
    /// for exactly these arguments (ADR-209).
    private(set) var planCloud: [Int: PlanCloudApproval] = [:]
    private(set) var planStatus: PlanStatus? { didSet { syncIsland() } }
    /// Which Apple Maps result the user picked on a place card (the first until they tap another).
    private(set) var selectedPlaceIndex = 0
    /// A function the agent asked for that is off or blocked. The screen offers to turn it on.
    private(set) var connectionNeeded: VoiceConnection?
    private(set) var isMuted = false { didSet { syncIsland() } }
    /// The last list change made by voice (ADR-216): what changed, its Undo, and items Doddy
    /// couldn't tell apart, to tap. Shown on screen until dismissed or the next change.
    private(set) var listReceipt: ListReceipt?
    /// The last change Doddy made in Calendar or Reminders, with Undo (ADR-258).
    private(set) var changeReceipt: ChangeReceipt?
    /// Translator mode (ADR-215), in memory only. While it is set the app runs no tool and the
    /// conversation is private.
    private(set) var translator: TranslatorSession? {
        // The island follows the mode and its languages (ADR-244), not each line heard.
        didSet { if oldValue?.setup != translator?.setup { syncIsland() } }
    }
    /// The end screen after translating: the text stays in memory for five minutes for Copy or
    /// "Save the facts as a note", then it is dropped (T3).
    private(set) var translatorSummary: TranslatorSummary?
    /// What happened when the user tapped "Save the facts as a note".
    private(set) var translatorFactsSaved: Result<String, TranslatorSaveError>?
    /// Noisy place: the microphone is muted except while a hold-to-talk button is held (T4).
    private(set) var holdToTalk = false
    private(set) var heldSide: TranslatorDirection?
    /// Opened from Home's Translate: Doddy's greeting comes first, then the app asks for the disclosure.
    private var translatorNeedsHello = false
    /// Listen only: "Read aloud" off sets Doddy's voice to silent on this iPhone (the lines still
    /// show). `readAloudProblem` is set when the silence couldn't be checked.
    private(set) var readsAloud = true
    private(set) var readAloudProblem: String?
    /// Opened from the morning check-in (ADR-220): after the greeting, the app asks for the briefing.
    private var checkInNeedsBriefing = false
    /// How this conversation was started, and whether it started with the saved notes, profile and
    /// lists in the agent's context (not from Home's Translate). Translating then starts a fresh
    /// conversation, because that context can't be taken back out (review H3).
    private var startedMode: VoiceConnectionMode?
    private var sharedOwnerContext = false

    private let store: MemoryStore
    private let logs: ConversationLogStore
    private let activity: ActivityLogStore
    /// What each open tool call asked for, until its reply is sent and logged.
    private var asked: [String: ActivityRequest] = [:]
    /// Changes the user confirmed that are running now, logged "in progress" before they ran.
    private var started: [String: ActivityEntry] = [:]
    /// Plan cards waiting for the user's answer, so their steps are logged if the conversation ends.
    private var askedPlans: [String: [PlanStep]] = [:]
    /// Shared with "Hey Doddy" listening, which may have started it (ADR-254).
    private let island = VoiceLiveActivity.shared
    /// True once this conversation has shown its state on the island, so only it ends it.
    private var ownsIsland = false
    /// "Hey Pat, what's up?" when the wake word started this conversation (ADR-254). Shown on
    /// the island until the user first speaks.
    private(set) var wakeGreeting: String? { didSet { syncIsland() } }
    /// The wake word started this conversation: it ends by itself if the user says nothing.
    private var startedByWakeWord = false
    private var silentWakeTimer: Task<Void, Never>?
    /// True while iOS has paused Doddy's audio because another app took the audio session
    /// (`AVAudioSession` interruption). Real system events only, never a guess.
    private(set) var audioPausedByOtherApp = false
    /// What iOS last said about the audio session (reason and session setup), shown in small print
    /// on the voice screen so a failure can be read without Xcode. No speech or notes in it.
    private(set) var audioNote: String?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    private static let audioLog = Logger(subsystem: "com.bienos.doddy2.dev", category: "voice-audio")
    private let devices = DeviceConnections()
    private var conversation: (any LiveVoiceLink)?
    /// Who runs the conversation now (Home's test switch, read when it starts; ADR-265).
    private(set) var provider: VoiceProvider = .elevenLabs
    private var startedAt: Date?
    /// Private conversation (PRD item 6, ADR-170): when on at the end, nothing of it is kept on the
    /// phone, so it never comes back as "recent conversations". Explicit saves still need a tap.
    var isPrivate = false {
        didSet { if privacyLocked { isPrivate = true } }
    }
    /// Set once translator mode is on (ADR-215): the conversation stays private to the end.
    private(set) var privacyLocked = false
    /// Notes the user tapped Save on in this conversation, for the island's "ended" card.
    private var savedThisConversation = 0
    /// A finished moment the island shows for a few seconds ("Note saved", "Reminder set").
    private var islandFlash: (moment: DoddyVoiceAttributes.ContentState.Moment, until: Date)? {
        didSet { syncIsland() }
    }
    @ObservationIgnored private var islandFlashClear: Task<Void, Never>?
    /// How long "Note saved" and "Reminder set" stay on the island.
    static let islandFlashSeconds: TimeInterval = 8
    /// Every note text Doddy put on a save card or plan in this conversation, saved or declined,
    /// so the end-of-conversation suggestions never offer them again (ADR-247).
    private var proposedNoteTexts: [String] = []
    /// "Worth keeping?" after the conversation ends (ADR-247). Nothing ticked, nothing saved
    /// until the user taps Save.
    private(set) var saveSuggestions: SaveSuggestionCard?
    /// Suggestions are worked out once per conversation, so a dismissed card doesn't come back.
    private var suggestionsOffered = false

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
    /// Settings → About you → "Use in voice conversations" is on. `wakeGreeting` is set when
    /// "Hey Doddy" started the conversation (ADR-254): Doddy says it first and the island shows it.
    func start(
        _ mode: VoiceConnectionMode, profile: ApprovedProfile, translator preset: TranslatorSetup? = nil,
        checkIn: MorningBriefing? = nil, wakeGreeting: String? = nil
    ) async {
        guard !isLive else { return }
        // This start's number (review H1): a start that was ended and replaced while it waited
        // never opens, keeps or hears a conversation.
        startAttempt += 1
        let attempt = startAttempt
        isOffline = false
        offlineSaved = nil
        // A note being read aloud would fight the conversation for the speaker (ADR-243).
        ReadAloudController.shared.stop()
        startedByWakeWord = wakeGreeting != nil
        self.wakeGreeting = wakeGreeting
        silentWakeTimer?.cancel()
        silentWakeTimer = nil
        lines = []
        // A translator start sends no notes or lists, so it never carries a check-in too.
        let checkIn = preset == nil ? checkIn : nil
        checkInNeedsBriefing = checkIn != nil
        translator = nil
        listReceipt = nil
        changeReceipt = nil
        translatorSummary = nil
        translatorFactsSaved = nil
        holdToTalk = false
        heldSide = nil
        translatorNeedsHello = false
        readsAloud = true
        readAloudProblem = nil
        privacyLocked = false
        pendingAction = nil
        contactCard = nil
        reminderStatus = nil
        noteReminderStatus = nil
        planStatus = nil
        connectionNeeded = nil
        isMuted = false
        savedThisConversation = 0
        islandFlash = nil
        proposedNoteTexts = []
        saveSuggestions = nil
        suggestionsOffered = false
        audioPausedByOtherApp = false
        audioNote = nil

        // Not set up: say so without asking for the microphone first.
        if case .notSetUp(let reason) = mode {
            fail(reason)
            return
        }
        guard await Self.microphoneAllowed() else {
            if attempt == startAttempt { phase = .microphoneDenied }
            return
        }
        guard attempt == startAttempt else { return }
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
        // Ended (or ended and started again) while the notes loaded.
        guard attempt == startAttempt, phase == .connecting else { return }
        var notes = VoiceContext.savedNotes(store.memories)
        var recent = logs.isEnabled
            ? VoiceContext.recentConversations(logs.logs)
            : VoiceContext.Rendered(text: "(remembering recent conversations is switched off in Settings)", includedCount: 0, truncated: false)
        var listsText = ListsPrompt.render(store.lists)
        var profileText = ProfilePrompt.render(profile, shared: UserDefaults.standard.bool(forKey: PreferenceKey.shareProfileWithVoice))
        startedMode = mode
        sharedOwnerContext = preset == nil
        // Opened from Home's Translate: the agent gets no notes, conversations or profile at all,
        // so it has nothing of the owner's to repeat to the other person.
        if let preset {
            let none = "(not shared: this conversation is only for translating)"
            notes = VoiceContext.Rendered(text: none, includedCount: 0, truncated: false)
            recent = VoiceContext.Rendered(text: none, includedCount: 0, truncated: false)
            profileText = none
            listsText = none
            isPrivate = true
            privacyLocked = true
            translator = TranslatorSession(setup: preset, startedAt: Date())
            translatorNeedsHello = true
        }

        let ref = AttemptRef(self, attempt: attempt)
        let variables: [String: String] = [
            "saved_notes": notes.text,
            "saved_notes_count": "\(notes.includedCount)",
            "saved_notes_truncated": notes.truncated ? "yes" : "no",
            "recent_conversations": recent.text,
            // Style only (Settings → Doddy's personality). The agent prompt's {{doddy_personality}}
            // placeholder defaults to the persona defaults, so a build that sends nothing still works.
            PersonalityPrompt.variableName: PersonalityPrompt.render(.stored(), nickname: Nickname.stored()),
            ProfilePrompt.variableName: profileText,
            TranslatorPrompt.variableName: TranslatorPrompt.render(preset),
            ListsPrompt.variableName: listsText,
            MorningCheckInPrompt.variableName: MorningCheckInPrompt.render(checkIn),
            // What Doddy says first (ADR-254): the greeting after "Hey Doddy", otherwise his
            // usual opening. Used once the agent's first message is {{opening_line}}
            // (voice-agent/session.json); an agent without it ignores the variable.
            WakeGreeting.variableName: wakeGreeting ?? WakeGreeting.openingLine(
                afterWakeWord: false, name: nil, polish: ConversationLanguage.stored() == .polish),
        ]
        provider = VoiceProvider(stored: UserDefaults.standard.string(forKey: VoiceProvider.preferenceKey))
        if provider == .openAIRealtime {
            await startOpenAI(mode, variables: variables)
            return
        }
        var config = ConversationConfig(dynamicVariables: variables, userId: Self.userID())
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
            let offline = Offline.isNoConnection(error)
            Task { @MainActor in
                if offline { ref.value?.failOffline() } else { ref.value?.fail(error.errorDescription ?? "Something went wrong.") }
            }
        }

        config.onAgentReady = {
            Task { @MainActor in
                if ref.value?.phase == .connecting { ref.value?.phase = .listening }
                ref.value?.startSilentWakeTimer()
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
                if attempt == startAttempt, phase == .connecting {
                    if error == .offline { failOffline() } else { fail(VoiceTokenServer.message(for: error)) }
                }
                return
            }
        case .notSetUp(let reason):
            fail(reason)
            return
        }
        // Closed (or closed and started again) while the token was being fetched: don't open the
        // microphone after all.
        guard attempt == startAttempt, phase == .connecting else { return }

        Self.allowOtherAppsAudio()
        do {
            let started = try await ElevenLabs.startConversation(auth: auth, config: config)
            guard attempt == startAttempt, isLive else {
                // Closed (or closed and started again) while connecting: end it so nothing keeps
                // listening and its tool calls stop (review H1).
                await started.endConversation()
                return
            }
            conversation = started
            watchAudioInterruptions()
            Self.audioLog.notice("conversation started. \(Self.describeAudioSession(), privacy: .public)")
        } catch {
            // A replaced start's failure isn't the new conversation's.
            guard attempt == startAttempt else { return }
            if Offline.isNoConnection(error) {
                failOffline()
                return
            }
            // An agent that doesn't allow the voice overrides refuses the conversation.
            let voiceHint = config.ttsOverrides == nil && config.agentOverrides == nil
                ? ""
                : " If it keeps failing, choose \"Use Doddy's own voice\" and language \"Automatic\" in Settings → Voice and personality."
            fail("Couldn't connect to Doddy's voice. Check your internet connection and try again.\(voiceHint) (\(error.localizedDescription))")
        }
    }

    // MARK: OpenAI Realtime (testing, ADR-265)

    /// The bundled copy of voice-agent/ (prompt, tools, session), the same spec the live
    /// ElevenLabs agent is synced from, so both providers get the same Doddy.
    private struct OpenAISpec {
        let template: String
        let tools: Data
        let session: Data
        /// Tools ElevenLabs runs on its servers (place lookup, weather, Wikipedia); not available here.
        let webTools: Set<String>

        static func bundled() -> OpenAISpec? {
            guard let instructionsURL = Bundle.main.url(forResource: "instructions", withExtension: "md"),
                  let toolsURL = Bundle.main.url(forResource: "tools", withExtension: "json"),
                  let sessionURL = Bundle.main.url(forResource: "session", withExtension: "json"),
                  let template = try? String(contentsOf: instructionsURL, encoding: .utf8),
                  let tools = try? Data(contentsOf: toolsURL),
                  let session = try? Data(contentsOf: sessionURL),
                  let catalog = try? RealtimeToolCatalog.decode(tools)
            else { return nil }
            return OpenAISpec(template: template, tools: tools, session: session,
                              webTools: Set(catalog.filter { $0.runsOn == .web }.map(\.name)))
        }
    }

    /// Web tools of the running OpenAI conversation (empty for ElevenLabs, which runs them itself).
    private var openAIWebTools: Set<String> = []
    /// Counts starts and ends, so a start that was ended and replaced while it waited (for the
    /// token server or the provider) never opens a second microphone (review H1). `AttemptRef`
    /// reads it, so it is fileprivate.
    fileprivate var startAttempt = 0

    /// Same start as ElevenLabs from here on: same notes, conversations, lists and profile
    /// (`variables`), same tools and cards. Needs the token server: the OpenAI key stays there.
    private func startOpenAI(_ mode: VoiceConnectionMode, variables: [String: String]) async {
        let attempt = startAttempt
        guard case .tokenServer(let endpoint, let accessCode) = mode else {
            fail("The OpenAI test voice needs Doddy's token server. Add it in Settings → Voice, or switch Home back to ElevenLabs.")
            return
        }
        guard let spec = OpenAISpec.bundled() else {
            fail("This build is missing Doddy's voice spec, so the OpenAI test voice can't start. Switch Home back to ElevenLabs.")
            return
        }
        let sessionUpdate: String
        do {
            let instructions = try RealtimeInstructions.render(spec.template, variables: variables)
            sessionUpdate = try OpenAIRealtimeWire.sessionUpdate(instructions: instructions, toolsJSON: spec.tools, eagerness: .high)
        } catch {
            fail("Doddy's prompt couldn't be prepared for OpenAI (\(error)). Switch Home back to ElevenLabs.")
            return
        }
        // The same opening the ElevenLabs agent gets (ADR-254: the "Hey Doddy" greeting or his usual one).
        let greetingLine = variables[WakeGreeting.variableName]
            ?? OpenAIRealtimeWire.greetingLine(sessionJSON: spec.session, languageCode: ConversationLanguage.stored().overrideCode)

        let grant: OpenAIRealtimeGrant
        do throws(VoiceTokenError) {
            grant = try await VoiceTokenClient(endpoint: endpoint, accessCode: accessCode).fetchOpenAIGrant()
        } catch {
            if attempt == startAttempt, phase == .connecting { fail(Self.openAITokenMessage(error)) }
            return
        }
        // Closed (or closed and started again) while the secret was being fetched: don't open
        // the microphone for this attempt.
        guard attempt == startAttempt, phase == .connecting else { return }

        openAIWebTools = spec.webTools
        let ref = AttemptRef(self, attempt: attempt)
        let session = OpenAIRealtimeSession(grant: grant) { event in ref.value?.applyOpenAI(event) }
        // Set first, so End while connecting closes it and the first tool call can be answered.
        conversation = session
        do {
            try await session.start(sessionUpdate: sessionUpdate, greeting: OpenAIRealtimeWire.greeting(greetingLine))
        } catch {
            if conversation === session { conversation = nil }
            if attempt == startAttempt, isLive { fail("Couldn't connect to OpenAI's voice. Check your internet connection and try again. (\(error.localizedDescription))") }
            return
        }
        guard attempt == startAttempt, isLive else {
            await session.endConversation()
            if conversation === session { conversation = nil }
            return
        }
        watchAudioInterruptions()
        Self.audioLog.notice("openai conversation started. \(Self.describeAudioSession(), privacy: .public)")
    }

    private static func openAITokenMessage(_ error: VoiceTokenError) -> String {
        switch error {
        case .badResponse:
            "The token server doesn't offer the OpenAI test voice yet. Redeploy server/voice-token and set OPENAI_API_KEY there, or switch Home back to ElevenLabs."
        case .serverNotConfigured:
            "OPENAI_API_KEY isn't set on the token server, so the OpenAI test voice can't start. Switch Home back to ElevenLabs to talk now."
        default:
            VoiceTokenServer.message(for: error)
        }
    }

    /// OpenAI's events, already in Realtime terms (`RealtimeEvent`), onto the same screen state.
    private func applyOpenAI(_ event: RealtimeEvent) {
        guard isLive else { return }
        switch event {
        case .sessionReady:
            if phase == .connecting { phase = .listening }
        case .userSpeechStarted, .responseDone:
            phase = .listening
        case .userSpeechStopped, .responseStarted:
            phase = .thinking
        case .audioStarted:
            apply(.speaking)
        case .userTranscript(let text):
            append(text, fromUser: true)
        case .assistantTranscript(let text):
            append(text, fromUser: false)
        case .assistantTranscriptCorrected(let original, let corrected):
            correct(original, to: corrected)
        case .functionCall(let call):
            Task { await handleOpenAICall(call) }
        case .error(let message):
            fail(message)
            Task { await stop() }
        case .ended:
            disconnected()
        }
    }

    /// Into the same tool handling as ElevenLabs. Web tools get a plain "not here" so Doddy says
    /// so instead of making up an answer.
    private func handleOpenAICall(_ call: RealtimeFunctionCall) async {
        if openAIWebTools.contains(call.name) {
            await reply(call.callID, "Weather and Wikipedia don't work in the OpenAI voice test. Tell the user that in one sentence, and that switching Home back to ElevenLabs brings them back.", isError: true)
            return
        }
        await handle(ClientToolCallEvent(toolName: call.name, toolCallId: call.callID, parametersData: call.argumentsData, eventId: 0, expectsResponse: true))
    }

    /// Keeps the conversation going when the user opens another app that plays or records sound
    /// (ADR-207). The SDK's default call session is not mixable, so another app starting its own
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
        // From here, a start still connecting ends itself and late events of this conversation
        // are dropped (review H1).
        startAttempt += 1
        endTranslator()
        stopSilentWakeTimer()
        stopWatchingAudioInterruptions()
        let active = conversation
        conversation = nil
        pendingAction = nil
        contactCard = nil
        connectionNeeded = nil
        if isLive { phase = .ended }
        keepLog()
        offerSaveSuggestions()
        await active?.endConversation()
        // Only now may "Hey Doddy" take the microphone again (ADR-254).
        WakeWordListener.shared.conversationAudioReleased()
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
        logs.append(ConversationLog(startedAt: startedAt, endedAt: Date(), lines: kept, voiceProvider: provider.rawValue))
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
                // Only after the store returned the saved record (ADR-240).
                flashIsland(.noteSaved)
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
        case .alarm(let id, let draft):
            await reply(id, await setAlarm(draft))
        case .cancelAlarm(let id, let alarm):
            guard isOn(.timers) else {
                connectionNeeded = .timers
                await reply(id, VoiceToolReply.failed("Timers and alarms are switched off. Nothing changed."))
                return
            }
            await reply(id, AlarmScheduler.cancel(alarm.id) ? VoiceToolReply.alarmCancelled(alarm) : VoiceToolReply.alarmCancelUnconfirmed)
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
        case .noteReminder(let id, let memoryID, let noteText, _, let target):
            guard let confirmed = confirmedNoteReminder(memoryID: memoryID, noteText: noteText, target: target) else {
                await reply(id, VoiceToolReply.noteReminderFailed("That place can't be used."))
                return
            }
            let receipt = await setNoteReminder(confirmed)
            await reply(id, Self.noteReminderReply(receipt, note: noteText))
        case .changeEvent(let id, let plan):
            await reply(id, changeEvent(plan))
        case .changeReminder(let id, let reminder, let draft):
            await reply(id, changeReminder(reminder, draft))
        case .deleteEvent(let id, let event):
            await reply(id, deleteEvent(event))
        case .deleteReminder(let id, let reminder):
            await reply(id, deleteReminder(reminder))
        case .bulk(let id, let items, let verb, let skipped):
            let ticked = items.filter { !bulkUnticked.contains($0.id) }
            bulkUnticked = []
            await reply(id, runBulk(ticked, verb: verb, skipped: skipped))
        case .translator(let id, let setup):
            // This conversation's agent already has the saved notes, profile and lists (review H3):
            // translating goes on in a new conversation that gets none of them, as from Home's
            // Translate. Private like a translator conversation, so nothing of this one is kept.
            if translatorStartsNewConversation, let mode = startedMode {
                isPrivate = true
                await reply(id, "stopped: translator mode starts in a new conversation that has none of the user's notes, profile or lists. This conversation ends now; say nothing more.")
                await stop()
                await start(mode, profile: .empty, translator: setup)
                return
            }
            beginTranslator(setup)
            await reply(id, VoiceToolReply.translatorStarted(setup))
        case .createList(let id, let name, let items):
            do {
                let list = try await store.createList(name: name, items: items, source: .voice)
                listReceipt = ListReceipt(listID: list.id, title: "New list: \(list.name)", lines: list.items.map { .added($0.text) })
                await reply(id, VoiceToolReply.listCreated(list))
            } catch ListError.nameTaken(let taken) {
                await reply(id, VoiceToolReply.listNameTaken(taken))
            } catch {
                await reply(id, VoiceToolReply.listFailed(UserFacingError.listMessage(for: error)), isError: true)
            }
        case .plan(let id, let steps, let blocked):
            await runPlan(id, steps: steps, blocked: blocked)
        }
    }

    func selectPlace(_ index: Int) {
        guard case .noteReminder(_, _, _, _, .place(let results, _)) = pendingAction, results.indices.contains(index) else { return }
        selectedPlaceIndex = index
    }

    /// The user changed the time on the card. The card shows it, and Set reminder uses it.
    func changeNoteReminderTime(_ date: Date) {
        guard case .noteReminder(let id, let memoryID, let text, let savedAt, .time(_, let zone, let repeats)) = pendingAction else { return }
        pendingAction = .noteReminder(
            toolCallID: id, memoryID: memoryID, noteText: text, savedAt: savedAt, target: .time(date, timeZoneID: zone, repeats: repeats))
    }

    /// The user switched arriving/leaving on the card (the agent may have misheard).
    func setNoteReminderOnArrival(_ onArrival: Bool) {
        guard case .noteReminder(let id, let memoryID, let text, let savedAt, .place(let results, _)) = pendingAction else { return }
        pendingAction = .noteReminder(toolCallID: id, memoryID: memoryID, noteText: text, savedAt: savedAt, target: .place(results: results, onArrival: onArrival))
    }

    /// The card's current content, as the reminder to set.
    private func confirmedNoteReminder(memoryID: UUID, noteText: String, target: NoteReminderCardTarget) -> ConfirmedNoteReminder? {
        switch target {
        case .time(let date, let zone, let repeats):
            return ConfirmedNoteReminder(memoryID: memoryID, noteText: noteText, when: .time(date, timeZoneID: zone, repeats: repeats))
        case .place(let results, let onArrival):
            guard !results.isEmpty else { return nil }
            let choice = results[min(selectedPlaceIndex, results.count - 1)]
            guard let place = try? ReminderPlace(
                name: String(choice.name.prefix(ReminderPlace.maxNameLength)),
                latitude: choice.coordinate.latitude, longitude: choice.coordinate.longitude,
                radiusMeters: ReminderPlace.defaultRadius, onArrival: onArrival)
            else { return nil }
            return ConfirmedNoteReminder(memoryID: memoryID, noteText: noteText, when: .place(place))
        }
    }

    /// Sets the reminder through the same store as the note screen and shows the store's receipt:
    /// a scheduled request, Doddy-only, or why nothing was set.
    private func setNoteReminder(_ confirmed: ConfirmedNoteReminder) async -> NoteReminderReceipt {
        guard let reminders = store.noteReminders, reminders.isAvailable else {
            let receipt = NoteReminderReceipt.failed("Reminders on notes aren't available on this iPhone right now.")
            noteReminderStatus = .done(confirmed, receipt)
            return receipt
        }
        noteReminderStatus = .setting(confirmed)
        // The user just tapped Set reminder, so this is the moment to ask iOS, once.
        if reminders.authorization == .notDetermined { await reminders.requestAuthorization() }
        switch confirmed.when {
        case .time(let date, let zone, let repeats):
            await reminders.set(
                memoryID: confirmed.memoryID, at: date, timeZone: TimeZone(identifier: zone) ?? .autoupdatingCurrent, repeats: repeats)
        case .place(let place):
            if reminders.locationReadiness == .notDetermined { await reminders.requestLocation() }
            await reminders.set(memoryID: confirmed.memoryID, place: place)
        }
        let receipt = reminders.receipts[confirmed.memoryID] ?? .failed("Doddy couldn't set the reminder.")
        // The voice screen shows this receipt; the note screen shouldn't repeat it later.
        reminders.clearReceipt(memoryID: confirmed.memoryID)
        noteReminderStatus = .done(confirmed, receipt)
        return receipt
    }

    private static func noteReminderReply(_ receipt: NoteReminderReceipt, note: String) -> String {
        switch receipt {
        case .scheduled(let reminder): VoiceToolReply.noteReminderSet(reminder, note: note)
        case .inAppOnly(let reminder): VoiceToolReply.noteReminderInDoddyOnly(reminder, note: note)
        case .failed(let message), .needsSettings(let message): VoiceToolReply.noteReminderFailed(message)
        }
    }

    /// Try again on a failed receipt: the same reminder the user confirmed, set once more on their
    /// tap. The agent's tool call is already answered, so only the screen shows the new result.
    func retryNoteReminder() async {
        guard case .done(let confirmed, .failed) = noteReminderStatus else { return }
        _ = await setNoteReminder(confirmed)
    }

    func dismissNoteReminderStatus() {
        guard case .done = noteReminderStatus else { return }
        noteReminderStatus = nil
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
        case .alarm(let id, _): await reply(id, VoiceToolReply.declinedAlarm)
        case .cancelAlarm(let id, _): await reply(id, VoiceToolReply.alarmCancelDeclined)
        case .map(let id, _): await reply(id, VoiceToolReply.declinedMap)
        case .shortcut(let id, _): await reply(id, VoiceToolReply.declinedShortcut)
        case .message(let id, _, _): await reply(id, VoiceToolReply.declinedMessage)
        case .cloud(let id, let call, _, _, _): await reply(id, VoiceToolReply.cloudDeclined(call.name))
        case .noteReminder(let id, _, _, _, _): await reply(id, VoiceToolReply.declinedNoteReminder)
        case .translator(let id, _): await reply(id, VoiceToolReply.translatorDeclined)
        case .createList(let id, _, _): await reply(id, VoiceToolReply.declinedList)
        case .changeEvent(let id, _), .changeReminder(let id, _, _): await reply(id, VoiceToolReply.changeDeclined)
        case .deleteEvent(let id, _), .deleteReminder(let id, _): await reply(id, VoiceToolReply.deleteDeclined)
        case .bulk(let id, _, _, _):
            bulkUnticked = []
            await reply(id, VoiceToolReply.bulkDeclined)
        case .plan(let id, let steps, _):
            askedPlans[id] = nil
            let planID = UUID()
            for step in steps {
                logPlanStep(step, reply: PlanReply.declined, plan: ActivityPlanRef(id: planID, step: step.number, count: steps.count))
            }
            await reply(id, PlanReply.declined)
        }
    }

    // MARK: Lists (ADR-216)

    /// The list the agent named, matched exactly; on no match or several, the agent gets the
    /// list names and asks. Nothing changes in either case.
    private func resolveList(_ name: String, toolCallID: String) async -> DoddyList? {
        await store.reload()
        switch ListMatch.list(named: name, in: store.lists) {
        case .one(let list):
            return list
        case .none:
            await reply(toolCallID, VoiceToolReply.listNotFound(name, lists: store.lists))
        case .several(let lists):
            await reply(toolCallID, VoiceToolReply.listAmbiguous(name, lists: lists))
        }
        return nil
    }

    /// L1: the user asked, so the items go straight on, read back, with a receipt and Undo.
    private func addToList(_ request: ListVoiceRequest, toolCallID: String) async {
        guard let list = await resolveList(request.list, toolCallID: toolCallID) else { return }
        do {
            let result = try await store.addToList(request.items, listID: list.id, source: .voice)
            var lines = result.added.map { ListReceipt.Line.added($0.text) }
            lines += result.alreadyThere.map { .note("\($0) · already on the list, not added again") }
            lines += result.tooLong.map { .note("too long to add: \($0.prefix(40))…") }
            lines += result.noRoom.map { .note("\($0) · the list is full") }
            listReceipt = ListReceipt(
                listID: list.id, title: result.added.isEmpty ? "Nothing new for \(list.name)" : "Added to \(list.name)",
                lines: lines, undo: result.added.isEmpty ? nil : store.listUndo)
            await reply(toolCallID, VoiceToolReply.listAdded(result, list: list.name))
        } catch {
            await reply(toolCallID, VoiceToolReply.listFailed(UserFacingError.listMessage(for: error)), isError: true)
        }
    }

    private func readList(_ name: String, toolCallID: String) async {
        guard let list = await resolveList(name, toolCallID: toolCallID) else { return }
        listReceipt = ListReceipt(listID: list.id, title: "\(list.name) · \(list.summary)", lines: list.open.map { .open($0.text) })
        await reply(toolCallID, VoiceToolReply.listRead(list))
    }

    /// Ticks or removes only clear matches; items that match several are offered to tap.
    private func changeList(_ request: ListVoiceRequest, tick: Bool, toolCallID: String) async {
        guard let list = await resolveList(request.list, toolCallID: toolCallID) else { return }
        let pool = tick ? list.open : list.items
        var matched: [ListItem] = [], notFound: [String] = [], ambiguous: [(said: String, options: [ListItem])] = []
        for phrase in request.items {
            switch ListMatch.item(phrase, in: pool) {
            case .one(let item): if !matched.contains(item) { matched.append(item) }
            case .none: notFound.append(phrase)
            case .several(let options): ambiguous.append((said: phrase, options: options))
            }
        }
        do {
            var changed: [ListItem] = []
            if !matched.isEmpty {
                if tick {
                    changed = try await store.setDone(matched, done: true, listID: list.id)
                } else {
                    changed = try await store.removeFromList(matched, listID: list.id)
                }
            }
            let verb = tick ? "ticked" : "removed"
            listReceipt = ListReceipt(
                listID: list.id, title: "\(tick ? "Ticked on" : "Removed from") \(list.name)",
                lines: changed.map { tick ? .ticked($0.text) : .removed($0.text) } + notFound.map { .note("not on the list: \($0)") },
                undo: changed.isEmpty ? nil : store.listUndo,
                choices: ambiguous.first.map { ListReceipt.Choices(said: $0.said, options: $0.options, tick: tick) })
            await reply(toolCallID, VoiceToolReply.listChanged(verb: verb, changed: changed, list: list.name, notFound: notFound, ambiguous: ambiguous))
        } catch {
            await reply(toolCallID, VoiceToolReply.listFailed(UserFacingError.listMessage(for: error)), isError: true)
        }
    }

    /// The user tapped one of the items Doddy couldn't tell apart.
    func pickListChoice(_ item: ListItem) async {
        guard var receipt = listReceipt, let choices = receipt.choices else { return }
        do {
            let changed: [ListItem]
            if choices.tick {
                changed = try await store.setDone([item], done: true, listID: receipt.listID)
            } else {
                changed = try await store.removeFromList([item], listID: receipt.listID)
            }
            receipt.lines += changed.map { choices.tick ? .ticked($0.text) : .removed($0.text) }
            receipt.choices = nil
            receipt.undo = store.listUndo
            receipt.problem = nil
            listReceipt = receipt
        } catch {
            receipt.problem = UserFacingError.listMessage(for: error)
            listReceipt = receipt
        }
    }

    /// Undo on the receipt: takes back exactly that change.
    func undoListReceipt() async {
        guard var receipt = listReceipt, let undo = receipt.undo else { return }
        do {
            try await store.undoListChange(undo)
            receipt.undo = nil
            receipt.title = "Undone: \(undo.message.prefix(1).lowercased() + undo.message.dropFirst())"
            receipt.problem = nil
            listReceipt = receipt
        } catch {
            receipt.problem = "Couldn't undo. " + UserFacingError.listMessage(for: error)
            listReceipt = receipt
        }
    }

    func dismissListReceipt() {
        listReceipt = nil
    }

    /// The user fixed the name on the "Start a new list?" card.
    func changeNewListName(_ name: String) {
        guard case .createList(let id, _, let items) = pendingAction else { return }
        pendingAction = .createList(toolCallID: id, name: name, items: items)
    }

    // MARK: Translator mode (ADR-215)

    /// The owner's language when the agent didn't say: Settings' starting language, else the iPhone's.
    static var ownerLanguage: TranslatorLanguage {
        TranslatorLanguages.ownerDefault(
            settingCode: ConversationLanguage.stored().overrideCode,
            deviceCode: Locale.current.language.languageCode?.identifier)
    }

    /// The user changed a language on the "Start translating?" card.
    func changeTranslatorProposal(owner: TranslatorLanguage, other: TranslatorLanguage?, kind: TranslatorKind) {
        guard case .translator(let id, _) = pendingAction,
              let setup = TranslatorSetup(kind: kind, owner: owner, other: other) else { return }
        pendingAction = .translator(toolCallID: id, setup: setup)
    }

    /// Start on the "Start translating?" card ends this conversation and starts a fresh one (review H3).
    var translatorStartsNewConversation: Bool {
        sharedOwnerContext && startedMode != nil
    }

    private func beginTranslator(_ setup: TranslatorSetup) {
        // Private from here on: nothing of this conversation is kept on the iPhone.
        isPrivate = true
        privacyLocked = true
        translatorSummary = nil
        translatorFactsSaved = nil
        translator = TranslatorSession(setup: setup, startedAt: Date())
    }

    /// Ends the mode (the conversation may go on) and keeps the text in memory for five minutes.
    private func endTranslator() {
        guard let session = translator else { return }
        translator = nil
        translatorNeedsHello = false
        if !readsAloud { setReadAloud(true) }
        if holdToTalk {
            holdToTalk = false
            heldSide = nil
            if isMuted { Task { await setMicrophone(muted: false) } }
        }
        let summary = session.summary(endedAt: Date())
        translatorSummary = summary
        translatorFactsSaved = nil
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(TranslatorSummary.keepFor))
            self?.dropTranslatorSummary(endedAt: summary.endedAt)
        }
    }

    private func dropTranslatorSummary(endedAt: Date) {
        guard translatorSummary?.endedAt == endedAt else { return }
        translatorSummary = nil
        translatorFactsSaved = nil
    }

    /// Done on the end screen: the text is gone now.
    func dismissTranslatorSummary() {
        translatorSummary = nil
        translatorFactsSaved = nil
    }

    /// End on the translator screen: the conversation ends too.
    func endTranslating() async {
        await stop()
    }

    /// Copy the text, only while the five minutes last. Returns false when it is already gone.
    func copyTranslatorText() -> Bool {
        guard let summary = translatorSummary, summary.isAvailable(at: Date()) else {
            translatorSummary = nil
            return false
        }
        UIPasteboard.general.string = summary.transcript
        return true
    }

    /// "Save the facts as a note": the exact facts, saved only on this tap and read back from the store.
    func saveTranslatorFacts() async {
        guard let summary = translatorSummary, summary.isAvailable(at: Date()) else {
            translatorSummary = nil
            return
        }
        guard let text = summary.factsNote(calendar: .current) else {
            translatorFactsSaved = .failure(.nothingToSave)
            return
        }
        do {
            let record = try await store.save(text: text, category: .other, source: .explicitText)
            translatorFactsSaved = .success(record.currentText)
        } catch {
            translatorFactsSaved = .failure(.failed(UserFacingError.message(for: error)))
        }
    }

    /// Listen only: Doddy's spoken translation on or off. Only the playback on this iPhone changes
    /// (LiveKit's local volume for the agent's track, or the OpenAI player's volume); the provider
    /// still makes the audio. Read back; if there is no voice yet, it is applied when Doddy first speaks.
    func setReadAloud(_ on: Bool) {
        readsAloud = on
        applyReadAloud()
    }

    private func applyReadAloud() {
        let wanted: Double = readsAloud ? 1 : 0
        guard let actual = conversation?.setAgentVolume(wanted) else {
            readAloudProblem = nil
            return
        }
        readAloudProblem = abs(actual - wanted) < 0.01
            ? nil
            : "Doddy's voice couldn't be turned off here. Turn the iPhone's volume down instead."
    }

    /// Noisy place: mute the microphone except while a hold-to-talk button is held.
    func setHoldToTalk(_ on: Bool) async {
        guard translator?.setup.kind == .faceToFace, conversation != nil else { return }
        holdToTalk = on
        heldSide = nil
        await setMicrophone(muted: on)
    }

    /// `side` is whose button is held: `.toOwner` for the owner's half, `.toOther` for theirs.
    func beginHold(_ side: TranslatorDirection) async {
        guard holdToTalk, let setup = translator?.setup else { return }
        heldSide = side
        translator?.held = side
        let who = side == .toOwner
            ? "the user, in \(setup.owner.englishName)"
            : "the other person\(setup.other.map { ", in \($0.englishName)" } ?? "")"
        try? await conversation?.updateContext("\(TranslatorSession.appMessagePrefix) The next words are from \(who). Translate them for the other side.")
        await setMicrophone(muted: false)
    }

    func endHold() async {
        guard holdToTalk else { return }
        heldSide = nil
        await setMicrophone(muted: true)
    }

    /// Say it again: Doddy repeats his last translation to them.
    func sayTranslationAgain() async {
        await sendToAgent("Say your last translation to them again, word for word.")
    }

    /// "Say it to them" on a quiet word: Doddy says his suggestion to them, in their language.
    func sayAsideToThem() async {
        guard let other = translator?.setup.other else { return }
        await sendToAgent("Say the sentence you suggested to them now, in \(other.englishName), exactly as you wrote it. Then go on translating.")
    }

    /// Messages from the app (never shown as something said; see `TranslatorSession.heard`).
    private func sendToAgent(_ text: String) async {
        try? await conversation?.sendMessage("\(TranslatorSession.appMessagePrefix) \(text)")
    }

    private func setMicrophone(muted: Bool) async {
        guard let conversation else { return }
        do {
            try await conversation.setMuted(muted)
            isMuted = muted
        } catch {
            // Keep the previous state; the UI shows what is actually set.
        }
    }

    /// Ticks or unticks one step of the plan card. Blocked steps stay unticked.
    func togglePlanStep(_ number: Int) {
        guard case .plan(_, let steps, let blocked) = pendingAction,
              steps.contains(where: { $0.number == number }), blocked[number] == nil else { return }
        if planTicked.contains(number) { planTicked.remove(number) } else { planTicked.insert(number) }
    }

    /// "Change" on a step: the edit was already checked by `PlanStepForm.apply`. The kind of step,
    /// and so its app and its block, stay the same.
    func replacePlanStep(_ step: PlanStep) {
        guard case .plan(let id, var steps, let blocked) = pendingAction,
              let index = steps.firstIndex(where: { $0.number == step.number }),
              steps[index].toolName == step.toolName, blocked[step.number] == nil else { return }
        steps[index] = step
        planChanged.insert(step.number)
        pendingAction = .plan(toolCallID: id, steps: steps, blocked: blocked)
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
        var state = DoddyVoiceAttributes.ContentState(
            status: pendingAction == nil ? status : .needsConfirmation, isMuted: isMuted,
            greeting: wakeGreeting, conversationStartedAt: startedAt)
        state.moment = islandMoment
        state.islandStyle = IslandStyle.stored(UserDefaults.standard.string(forKey: PreferenceKey.islandStyle))
        return state
    }

    /// What is happening inside the conversation that has its own island (ADR-240): a card
    /// waiting for the user, translator mode (ADR-244), a plan running, a reminder being added,
    /// or a few seconds of "saved" / "set" after the store or Reminders confirmed it. Kinds,
    /// counts and language codes only.
    private var islandMoment: DoddyVoiceAttributes.ContentState.Moment? {
        switch pendingAction {
        case .memory: return .noteWaiting
        case .plan(_, let steps, _): return .planWaiting(steps: steps.count)
        case .reminder, .noteReminder: return .reminderWaiting
        case .some: return nil
        case nil: break
        }
        // Translating (ADR-244): the language codes only, never a phrase. No tool runs in this
        // mode, so no plan, reminder or "saved" moment can be hidden by it.
        if let setup = translator?.setup {
            let theirs = setup.other?.code ?? "?"
            switch setup.kind {
            case .faceToFace: return .translating(from: setup.owner.code, to: theirs, bothWays: true)
            case .listen: return .translating(from: theirs, to: setup.owner.code, bothWays: false)
            }
        }
        if let plan = planStatus, plan.isRunning, !plan.steps.isEmpty {
            return .planRunning(step: min(plan.results.count + 1, plan.steps.count), of: plan.steps.count)
        }
        if case .adding = reminderStatus { return .reminderAdding }
        if let flash = islandFlash, flash.until > Date() { return flash.moment }
        return nil
    }

    private func flashIsland(_ moment: DoddyVoiceAttributes.ContentState.Moment) {
        islandFlash = (moment, Date().addingTimeInterval(Self.islandFlashSeconds))
        islandFlashClear?.cancel()
        islandFlashClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.islandFlashSeconds))
            guard !Task.isCancelled else { return }
            self?.islandFlash = nil
        }
    }

    private func syncIsland() {
        if let state = islandState {
            ownsIsland = true
            island.show(state, startedAt: startedAt ?? .now)
            return
        }
        // Only a conversation that showed itself on the island ends it: "Hey Doddy" listening
        // may be using it while this one is idle (ADR-254).
        guard ownsIsland else { return }
        ownsIsland = false
        // "Hey Doddy" listening carries on in the same island when it can start again.
        if WakeWordListener.shared.takeIslandBack() { return }
        if phase == .ended {
            island.finish(savedCount: savedThisConversation)
        } else {
            island.end()
        }
    }

    // MARK: "Hey Doddy" (ADR-254)

    /// A conversation the wake word started ends by itself if the user says nothing for
    /// `WakeGate.silentWakeTimeout` after Doddy is ready: most likely the word was heard by
    /// mistake, and an open conversation keeps the microphone and ElevenLabs running.
    private func startSilentWakeTimer() {
        guard startedByWakeWord, silentWakeTimer == nil, isLive else { return }
        silentWakeTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(WakeGate.silentWakeTimeout))
            guard !Task.isCancelled, let self, self.isLive, !self.lines.contains(where: \.fromUser) else { return }
            await self.stop()
        }
    }

    private func stopSilentWakeTimer() {
        silentWakeTimer?.cancel()
        silentWakeTimer = nil
    }

    // MARK: Events

    private func apply(_ state: ElevenLabs.AgentState) {
        guard isLive else { return }
        switch state {
        case .listening: phase = .listening
        case .speaking:
            phase = .speaking
            if !readsAloud { applyReadAloud() }
        case .thinking: phase = .thinking
        }
    }

    private func append(_ text: String, fromUser: Bool) {
        guard !text.allSatisfy(\.isWhitespace) else { return }
        // Translating: the lines belong to the translator screen, never to the conversation log.
        if translator != nil {
            if fromUser {
                translator?.heard(text)
            } else {
                translator?.said(text)
                if translatorNeedsHello {
                    translatorNeedsHello = false
                    Task { await sendToAgent("Translator mode is on. Do what the translator_start section says now.") }
                }
            }
            return
        }
        lines.append(Line(fromUser: fromUser, text: text))
        if !fromUser, checkInNeedsBriefing {
            checkInNeedsBriefing = false
            Task { await sendToAgent("Morning check-in: give the briefing now, as the morning check-in section says.") }
        }
        // The greeting stays on the island only until the user answers.
        if fromUser, wakeGreeting != nil { wakeGreeting = nil }
    }

    private func correct(_ original: String, to corrected: String) {
        if translator != nil {
            translator?.correct(original, to: corrected)
            return
        }
        guard let index = lines.lastIndex(where: { !$0.fromUser && $0.text == original }) else { return }
        lines[index].text = corrected
    }

    // MARK: Offline (ADR-289)

    /// The conversation couldn't start or stopped because there's no internet.
    private(set) var isOffline = false
    /// The note saved while offline, as read back; shown on the offline card.
    private(set) var offlineSaved: String?

    private func failOffline() {
        isOffline = true
        fail(NSLocalizedString("You're offline. Doddy's voice needs the internet.", comment: ""))
    }

    /// Saves a note written or dictated while offline, on this iPhone, read back by the store.
    /// Returns what went wrong, or nil.
    func saveOfflineNote(_ text: String) async -> String? {
        do {
            try MemoryTextValidator.validate(text)
            let record = try await store.save(text: text, category: .other, source: .explicitText)
            guard store.record(id: record.id) != nil else { return NSLocalizedString("The note couldn't be confirmed. Check your notes.", comment: "") }
            offlineSaved = record.currentText
            return nil
        } catch {
            return UserFacingError.message(for: error)
        }
    }

    private func fail(_ message: String) {
        stopSilentWakeTimer()
        stopWatchingAudioInterruptions()
        phase = .failed(message)
        pendingAction = nil
        // After an error the SDK may keep the microphone (review H2), so the conversation is
        // ended here as stop() does, instead of waiting for a disconnect that may not come.
        guard let active = conversation else { return }
        conversation = nil
        endTranslator()
        keepLog()
        Task {
            await active.endConversation()
            WakeWordListener.shared.conversationAudioReleased()
        }
    }

    private func disconnected() {
        endTranslator()
        stopSilentWakeTimer()
        stopWatchingAudioInterruptions()
        conversation = nil
        pendingAction = nil
        keepLog()
        if case .failed = phase { return }
        phase = .ended
        offerSaveSuggestions()
    }

    // MARK: End-of-conversation save suggestions (ADR-247)

    /// Picks what the user said that may be worth keeping, on the phone, from their own lines only.
    /// Not for a private conversation, not when switched off, not when notes can't be saved.
    private func offerSaveSuggestions() {
        guard !suggestionsOffered, phase == .ended else { return }
        suggestionsOffered = true
        guard !isPrivate, store.isStorageAvailable,
              UserDefaults.standard.object(forKey: PreferenceKey.suggestSavesAfterConversation) as? Bool ?? true
        else { return }
        let found = SaveSuggestions.suggest(
            userLines: lines.filter(\.fromUser).map(\.text),
            alreadyProposed: proposedNoteTexts,
            existingNotes: store.memories)
        saveSuggestions = found.isEmpty ? nil : SaveSuggestionCard(found)
    }

    func toggleSaveSuggestion(_ id: Int) {
        saveSuggestions?.toggle(id)
    }

    func changeSaveSuggestion(_ id: Int, to text: String) {
        saveSuggestions?.setText(id, text)
    }

    /// Saves the ticked suggestions one by one through the normal checked save (read back before
    /// it counts). A failed one says why and is never shown as saved.
    func saveTickedSuggestions() async {
        guard var card = saveSuggestions, card.tickedCount > 0, !card.isSaving else { return }
        let batch = card.beginSaving()
        saveSuggestions = card
        for (id, text) in batch {
            do {
                let record = try await store.save(text: text, category: .other, source: .explicitVoice)
                saveSuggestions?.finish(id, .success(record))
            } catch {
                saveSuggestions?.finish(id, .failure(SaveSuggestionFailure(message: UserFacingError.message(for: error))))
            }
        }
    }

    func dismissSaveSuggestions() {
        guard saveSuggestions?.isSaving != true else { return }
        saveSuggestions = nil
    }

    private func handle(_ call: ClientToolCallEvent) async {
        let request = VoiceToolRequest.parse(name: call.toolName, parametersJSON: call.parametersData)
        // Translating: no tool runs at all, a plan card included (ADR-215). Checked before anything
        // is looked up or logged.
        if translator != nil, !TranslatorPolicy.allows(request) {
            await reply(call.toolCallId, VoiceToolReply.translatorRefused(call.toolName))
            return
        }
        if call.toolName == VoiceToolName.proposePlan {
            await handlePlan(call)
            return
        }
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
                await reply(call.toolCallId, VoiceToolReply.search(outcome, question: query))
            } catch {
                await reply(call.toolCallId, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
            }
        case .saveMemory(let text):
            // Nothing is stored until the user taps Save on the card.
            proposedNoteTexts.append(text)
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
        case .changeCalendarEvent(let draft):
            await proposeEventChange(draft, toolCallID: call.toolCallId)
        case .changeReminder(let draft):
            await proposeReminderChange(draft, toolCallID: call.toolCallId)
        case .deleteCalendarEvent(let draft):
            await proposeEventDelete(draft, toolCallID: call.toolCallId)
        case .deleteReminder(let title):
            await proposeReminderDelete(title, toolCallID: call.toolCallId)
        case .deleteCalendarEvents(let range):
            await proposeBulkEventDelete(range, toolCallID: call.toolCallId)
        case .moveReminders(let dueBy, let to):
            await proposeBulkReminderMove(dueBy: dueBy, to: to, toolCallID: call.toolCallId)
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
        case .listAlarms:
            // Read on the phone (ADR-283): times and labels Doddy set, nothing else.
            await reply(call.toolCallId, VoiceToolReply.alarms(AlarmScheduler.current()))
        case .cancelAlarm(let clock, let label):
            switch AlarmMatch.match(clock: clock, label: label, in: AlarmScheduler.current()) {
            case .none: await reply(call.toolCallId, VoiceToolReply.alarmNotFound(clock))
            case .several(let found): await reply(call.toolCallId, VoiceToolReply.alarmAmbiguous(found))
            case .one(let alarm): propose(.cancelAlarm(toolCallID: call.toolCallId, alarm: alarm), toolCallID: call.toolCallId)
            }
        case .setAlarm(let draft):
            // Said now, before a card that could only fail: an older iOS, or alarms refused.
            switch AlarmScheduler.support() {
            case .needsNewerIOS: await reply(call.toolCallId, VoiceToolReply.alarmNeedsNewerIOS)
            case .notAllowed: await reply(call.toolCallId, VoiceToolReply.alarmNotAllowed)
            case .available: propose(.alarm(toolCallID: call.toolCallId, draft: draft), toolCallID: call.toolCallId)
            }
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
        case .startTranslator(let proposal):
            guard let setup = proposal.setup(ownerDefault: Self.ownerLanguage) else {
                await reply(call.toolCallId, VoiceToolReply.failed("Both languages are the same. Ask the user which language the other person speaks."), isError: true)
                return
            }
            propose(.translator(toolCallID: call.toolCallId, setup: setup), toolCallID: call.toolCallId)
        case .addToList(let request):
            await addToList(request, toolCallID: call.toolCallId)
        case .readList(let name):
            await readList(name, toolCallID: call.toolCallId)
        case .checkOff(let request):
            await changeList(request, tick: true, toolCallID: call.toolCallId)
        case .removeFromList(let request):
            await changeList(request, tick: false, toolCallID: call.toolCallId)
        case .createList(let request):
            await store.reload()
            if case .one(let existing) = ListMatch.list(named: request.list, in: store.lists),
               ListMatch.key(existing.name) == ListMatch.key(request.list) {
                await reply(call.toolCallId, VoiceToolReply.listNameTaken(existing.name))
                return
            }
            guard store.lists.count < ListLimits.lists else {
                await reply(call.toolCallId, VoiceToolReply.listFailed(UserFacingError.listMessage(for: ListError.tooManyLists(maximum: ListLimits.lists))))
                return
            }
            propose(.createList(toolCallID: call.toolCallId, name: request.list, items: request.items), toolCallID: call.toolCallId)
        case .stopTranslator:
            guard translator != nil else {
                await reply(call.toolCallId, VoiceToolReply.translatorNotOn)
                return
            }
            endTranslator()
            await reply(call.toolCallId, VoiceToolReply.translatorStopped)
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
        proposedNoteTexts += steps.compactMap { step in
            if case .saveMemory(let text) = step.request { text } else { nil }
        }
        guard pendingAction == nil else {
            // One card at a time, as in propose(_:toolCallID:).
            await reply(call.toolCallId, VoiceToolReply.failed("Another item is waiting for the user's answer."))
            return
        }
        var blocked: [Int: PlanBlock] = [:]
        planCloud = [:]
        for step in steps {
            if let block = await planBlock(for: step) {
                blocked[step.number] = block
                if connectionNeeded == nil, case .notConnected(let connection) = block { connectionNeeded = connection }
            } else if let call = step.cloudCall {
                // As a single card: the server checks the switch, the connection and the arguments,
                // and returns the preview the card shows with an approval for exactly these.
                switch await prepareCloud(call) {
                case .ready(let approval): planCloud[step.number] = approval
                case .blocked(let block): blocked[step.number] = block
                }
            }
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
        planChanged = []
        askedPlans[call.toolCallId] = steps
        propose(.plan(toolCallID: call.toolCallId, steps: steps, blocked: blocked), toolCallID: call.toolCallId)
    }

    /// Ticked steps run one after another, each through the same path as its single card, and each
    /// gets its own result. A step that fails doesn't stop the others; none is retried.
    private func runPlan(_ toolCallID: String, steps: [PlanStep], blocked: [Int: PlanBlock]) async {
        askedPlans[toolCallID] = nil
        let ticked = planTicked
        let changed = planChanged
        let approvals = planCloud
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
                text = await runPlanStep(step, approval: approvals[step.number])
            }
            planStatus?.results[step.number] = logPlanStep(step, reply: text, plan: ref, replacing: startedEntry)
            results.append((step, text))
        }
        planStatus?.isRunning = false
        await reply(toolCallID, PlanReply.summary(results, changed: changed))
    }

    /// Checked again at the tap: the user may have paused or switched off the app while the card waited.
    private func runPlanStep(_ step: PlanStep, approval: PlanCloudApproval?) async -> String {
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
        case .cloudTool(let call):
            return await runPlanCloud(call, approval: approval)
        case .addToList(let request):
            // Matched now, exactly as a single add_to_list would be; nothing changes on no match.
            await store.reload()
            switch ListMatch.list(named: request.list, in: store.lists) {
            case .none: return VoiceToolReply.listNotFound(request.list, lists: store.lists)
            case .several(let lists): return VoiceToolReply.listAmbiguous(request.list, lists: lists)
            case .one(let list):
                do {
                    let result = try await store.addToList(request.items, listID: list.id, source: .voice)
                    return VoiceToolReply.listAdded(result, list: list.name)
                } catch {
                    return VoiceToolReply.listFailed(UserFacingError.listMessage(for: error))
                }
            }
        default:
            // PlanProposal only makes the kinds above.
            return VoiceToolReply.notAdded("This step can't run in a plan.")
        }
    }

    private enum CloudPrepared {
        case ready(PlanCloudApproval)
        /// Why the server didn't prepare the step, for the card and the agent.
        case blocked(PlanBlock)
    }

    private func prepareCloud(_ call: CloudToolCall) async -> CloudPrepared {
        guard let client = OnlineAccountsClientFactory.make() else {
            return .blocked(.onlineAccount(
                screen: OnlineAccountsError.notConfigured.userMessage,
                reply: VoiceToolReply.cloudFailed(.notConfigured, tool: call.name)))
        }
        do {
            let prepared = try await client.prepare(call)
            return .ready(PlanCloudApproval(preview: prepared.preview, approvalID: prepared.approvalId, mode: prepared.mode, preparedAt: Date()))
        } catch {
            return .blocked(.onlineAccount(screen: error.userMessage, reply: VoiceToolReply.cloudFailed(error, tool: call.name)))
        }
    }

    /// The server's approval works once and lasts two minutes. If the card waited longer, a fresh
    /// one is asked for the same arguments the user saw; the server checks them again.
    private func runPlanCloud(_ call: CloudToolCall, approval: PlanCloudApproval?) async -> String {
        guard let client = OnlineAccountsClientFactory.make() else {
            return VoiceToolReply.cloudFailed(.notConfigured, tool: call.name)
        }
        do {
            var approvalID = approval?.approvalID
            if approval == nil || Date().timeIntervalSince(approval?.preparedAt ?? .distantPast) > 90 {
                approvalID = try await client.prepare(call).approvalId
            }
            let result = try await client.run(call, timeZone: TimeZone.current.identifier, approvalId: approvalID)
            return VoiceToolReply.cloudResult(result)
        } catch {
            return VoiceToolReply.cloudFailed(error, tool: call.name)
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
        let record: MemoryRecord
        if draft.isList {
            // A list (ADR-256), matched exactly like the list tools; otherwise the agent asks.
            guard let list = await resolveList(draft.noteText, toolCallID: toolCallID) else { return }
            record = list.record
        } else {
            guard let note = NoteQuoteMatch.find(draft.noteText, in: store.memories) else {
                await reply(toolCallID, VoiceToolReply.noteNotFound())
                return
            }
            record = note
        }
        switch draft.target {
        case .time(let date, let zone):
            propose(.noteReminder(toolCallID: toolCallID, memoryID: record.id, noteText: record.currentText,
                                  savedAt: record.capturedAt, target: .time(date, timeZoneID: zone, repeats: draft.repeats)),
                    toolCallID: toolCallID)
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
                                  savedAt: record.capturedAt, target: .place(results: Array(results.prefix(5)), onArrival: onArrival)),
                    toolCallID: toolCallID)
        }
    }

    /// The note-reminder card is about a list (ADR-256), read from the store by its id.
    var isListReminder: Bool {
        guard case .noteReminder(_, let memoryID, _, _, _) = pendingAction else { return false }
        return store.list(id: memoryID) != nil
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

    // MARK: Changing events and reminders (ADR-229)

    /// Exactly one event with the title and start the agent read; otherwise the agent asks.
    private func proposeEventChange(_ draft: EventChangeDraft, toolCallID: String) async {
        guard devices.access(for: .calendar) == .granted else {
            await notConnected(toolCallID, .calendar)
            return
        }
        let events = devices.events(in: EventChange.searchRange(draft, calendar: .current))
        switch EventChange.match(draft, in: events, calendar: .current) {
        case .none:
            await reply(toolCallID, VoiceToolReply.eventNotFound(draft.title))
        case .several(let found):
            await reply(toolCallID, VoiceToolReply.eventAmbiguous(found, calendar: .current))
        case .one(let event):
            let place = draft.newLocation == nil ? nil : devices.eventLocation(event)
            guard let plan = EventChange.plan(draft, for: event, locationBefore: place, calendar: .current) else {
                await reply(toolCallID, VoiceToolReply.eventChangeInvalid)
                return
            }
            propose(.changeEvent(toolCallID: toolCallID, plan: plan), toolCallID: toolCallID)
        }
    }

    /// Exactly one open reminder with that title; otherwise the agent asks.
    private func proposeReminderChange(_ draft: ReminderChangeDraft, toolCallID: String) async {
        guard devices.access(for: .reminders) == .granted else {
            await notConnected(toolCallID, .reminders)
            return
        }
        do {
            let open = try await devices.incompleteReminders()
            switch EventChange.matchReminder(draft.title, in: open) {
            case .none:
                await reply(toolCallID, VoiceToolReply.reminderNotFound(draft.title))
            case .several(let found):
                await reply(toolCallID, VoiceToolReply.reminderAmbiguous(found))
            case .one(let reminder):
                if !draft.markDone, EventChange.sameDue(reminder.due, draft.newDue) {
                    await reply(toolCallID, VoiceToolReply.changeNothingNew)
                    return
                }
                propose(.changeReminder(toolCallID: toolCallID, reminder: reminder, draft: draft), toolCallID: toolCallID)
            }
        } catch {
            await reply(toolCallID, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
        }
    }

    /// Checked again at the tap: permission, the time, and that the event still looks as shown.
    private func changeEvent(_ plan: EventChangePlan) -> String {
        guard isOn(.calendar), devices.access(for: .calendar) == .granted else {
            connectionNeeded = .calendar
            return VoiceToolReply.failed("Calendar isn't connected. Nothing changed.")
        }
        if EventChange.startPassed(plan, now: Date(), calendar: .current) { return VoiceToolReply.eventChangeTimePassed }
        do {
            switch try devices.changeEvent(plan) {
            case .verified:
                changeReceipt = ChangeReceipt(kind: .event(plan), message: ChangeReceipt.message(for: plan))
                return VoiceToolReply.eventChanged(plan, calendar: .current)
            case .changedElsewhere: return VoiceToolReply.eventChangedElsewhere
            case .unconfirmed: return VoiceToolReply.eventChangeUnconfirmed
            }
        } catch {
            return VoiceToolReply.failed(UserFacingError.message(for: error))
        }
    }

    private func changeReminder(_ reminder: ReminderSnapshot, _ draft: ReminderChangeDraft) -> String {
        guard isOn(.reminders), devices.access(for: .reminders) == .granted else {
            connectionNeeded = .reminders
            return VoiceToolReply.failed("Reminders isn't connected. Nothing changed.")
        }
        if EventChange.duePassed(draft.newDue, now: Date(), local: .current) { return VoiceToolReply.eventChangeTimePassed }
        do {
            switch try devices.changeReminder(reminder, draft.markDone ? .complete : .due(draft.newDue)) {
            case .verified:
                if let after = devices.reminderSnapshot(id: reminder.id) {
                    changeReceipt = ChangeReceipt(
                        kind: .reminder(before: reminder, after: after),
                        message: ChangeReceipt.message(reminder: after, completed: draft.markDone))
                }
                return draft.markDone
                    ? VoiceToolReply.reminderCompleted(reminder.title)
                    : VoiceToolReply.reminderChanged(reminder.title, due: draft.newDue)
            case .changedElsewhere: return VoiceToolReply.reminderChangedElsewhere
            case .unconfirmed: return VoiceToolReply.reminderChangeUnconfirmed
            }
        } catch {
            return VoiceToolReply.failed(UserFacingError.message(for: error))
        }
    }

    // MARK: Several changes on one card (ADR-280)

    /// Items the user unticked on the several-changes card. Everything starts ticked.
    private(set) var bulkUnticked: Set<String> = []

    func toggleBulkItem(_ id: String) {
        if bulkUnticked.contains(id) { bulkUnticked.remove(id) } else { bulkUnticked.insert(id) }
    }

    private func proposeBulkEventDelete(_ range: VoiceTimeRange, toolCallID: String) async {
        guard devices.access(for: .calendar) == .granted else {
            await notConnected(toolCallID, .calendar)
            return
        }
        let events = BulkChange.eventsToDelete(devices.events(in: range), in: range)
        await proposeBulk(events.map(BulkItem.deleteEvent), verb: "deleted", skipped: [], toolCallID: toolCallID)
    }

    private func proposeBulkReminderMove(dueBy: ReminderDue, to: ReminderDue, toolCallID: String) async {
        guard devices.access(for: .reminders) == .granted else {
            await notConnected(toolCallID, .reminders)
            return
        }
        do {
            let open = try await devices.incompleteReminders()
            let (moves, skipped) = BulkChange.remindersToMove(open, dueBy: dueBy, to: to, local: .current)
            await proposeBulk(moves, verb: "moved", skipped: skipped, toolCallID: toolCallID)
        } catch {
            await reply(toolCallID, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
        }
    }

    private func proposeBulk(_ items: [BulkItem], verb: String, skipped: [String], toolCallID: String) async {
        guard !items.isEmpty else { return await reply(toolCallID, VoiceToolReply.bulkNothing) }
        guard items.count <= BulkChange.maxItems else { return await reply(toolCallID, VoiceToolReply.bulkTooMany(items.count)) }
        bulkUnticked = []
        propose(.bulk(toolCallID: toolCallID, items: items, verb: verb, skipped: skipped), toolCallID: toolCallID)
    }

    /// Each ticked item on its own: checked unchanged, changed, read back (ADR-280).
    private func runBulk(_ items: [BulkItem], verb: String, skipped: [String]) -> String {
        guard isOn(.calendar) || isOn(.reminders) else {
            return VoiceToolReply.failed("Calendar and Reminders aren't connected. Nothing changed.")
        }
        guard !items.isEmpty else { return VoiceToolReply.bulkDeclined }
        var results: [(BulkItem, BulkResult)] = []
        for item in items {
            let outcome: DeviceConnections.ChangeOutcome?
            switch item {
            case .deleteEvent(let event):
                outcome = isOn(.calendar) ? try? devices.deleteEvent(event) : nil
            case .moveReminder(let reminder, let due):
                outcome = isOn(.reminders) && !EventChange.duePassed(due, now: Date(), local: .current)
                    ? try? devices.changeReminder(reminder, .due(due)) : nil
            }
            switch outcome {
            case .verified: results.append((item, .done))
            case .changedElsewhere: results.append((item, .changedElsewhere))
            case .unconfirmed: results.append((item, .unconfirmed))
            case nil: results.append((item, .failed))
            }
        }
        return VoiceToolReply.bulkResult(results, verb: verb, skipped: skipped)
    }

    // MARK: Deleting events and reminders (ADR-259)

    /// Exactly one event with the title and start the agent read; otherwise the agent asks.
    private func proposeEventDelete(_ draft: EventChangeDraft, toolCallID: String) async {
        guard devices.access(for: .calendar) == .granted else {
            await notConnected(toolCallID, .calendar)
            return
        }
        let events = devices.events(in: EventChange.searchRange(draft, calendar: .current))
        switch EventChange.match(draft, in: events, calendar: .current) {
        case .none: await reply(toolCallID, VoiceToolReply.eventNotFound(draft.title))
        case .several(let found): await reply(toolCallID, VoiceToolReply.eventAmbiguous(found, calendar: .current))
        case .one(let event): propose(.deleteEvent(toolCallID: toolCallID, event: event), toolCallID: toolCallID)
        }
    }

    /// Exactly one open reminder with that title; otherwise the agent asks.
    private func proposeReminderDelete(_ title: String, toolCallID: String) async {
        guard devices.access(for: .reminders) == .granted else {
            await notConnected(toolCallID, .reminders)
            return
        }
        do {
            let open = try await devices.incompleteReminders()
            switch EventChange.matchReminder(title, in: open) {
            case .none: await reply(toolCallID, VoiceToolReply.reminderNotFound(title))
            case .several(let found): await reply(toolCallID, VoiceToolReply.reminderAmbiguous(found))
            case .one(let reminder): propose(.deleteReminder(toolCallID: toolCallID, reminder: reminder), toolCallID: toolCallID)
            }
        } catch {
            await reply(toolCallID, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
        }
    }

    /// Checked again at the tap: permission, and that the event still looks as shown. "Deleted"
    /// only when Calendar no longer has it.
    private func deleteEvent(_ event: CalendarEventSummary) -> String {
        guard isOn(.calendar), devices.access(for: .calendar) == .granted else {
            connectionNeeded = .calendar
            return VoiceToolReply.failed("Calendar isn't connected. Nothing was deleted.")
        }
        do {
            switch try devices.deleteEvent(event) {
            case .verified: return VoiceToolReply.eventDeleted(event, calendar: .current)
            case .changedElsewhere: return VoiceToolReply.eventChangedElsewhere
            case .unconfirmed: return VoiceToolReply.deleteUnconfirmed
            }
        } catch {
            return VoiceToolReply.failed(UserFacingError.message(for: error))
        }
    }

    private func deleteReminder(_ reminder: ReminderSnapshot) -> String {
        guard isOn(.reminders), devices.access(for: .reminders) == .granted else {
            connectionNeeded = .reminders
            return VoiceToolReply.failed("Reminders isn't connected. Nothing was deleted.")
        }
        do {
            switch try devices.deleteReminder(reminder) {
            case .verified: return VoiceToolReply.reminderDeleted(reminder.title)
            case .changedElsewhere: return VoiceToolReply.reminderChangedElsewhere
            case .unconfirmed: return VoiceToolReply.deleteUnconfirmed
            }
        } catch {
            return VoiceToolReply.failed(UserFacingError.message(for: error))
        }
    }

    /// Undo on the change receipt (ADR-258): the same checked change, backwards. The item must
    /// still look exactly as Doddy left it; the result is read back and Doddy is told.
    func undoLastChange(now: Date = .now) async {
        guard var receipt = changeReceipt, receipt.state == .available else { return }
        guard now.timeIntervalSince(receipt.madeAt) <= ChangeReceipt.undoFor else {
            receipt.state = .failed(NSLocalizedString("It's too late to undo here. Change it in Calendar or Reminders.", comment: ""))
            changeReceipt = receipt
            return
        }
        receipt.state = .working
        changeReceipt = receipt
        let outcome: DeviceConnections.ChangeOutcome
        do {
            switch receipt.kind {
            case .event(let plan):
                outcome = try devices.changeEvent(EventChange.reversed(plan))
            case .reminder(let before, let after):
                let change: ReminderChange = after.isCompleted != before.isCompleted
                    ? (after.isCompleted ? .reopen : .complete) : .due(before.due)
                outcome = try devices.changeReminder(after, change)
            }
        } catch {
            receipt.state = .failed(UserFacingError.message(for: error))
            changeReceipt = receipt
            return
        }
        switch outcome {
        case .verified:
            receipt.state = .undone
            await sendToAgent("The user tapped Undo on screen: \(receipt.agentUndoText) It was checked. Don't change it again unless they ask.")
        case .changedElsewhere:
            receipt.state = .failed(NSLocalizedString("It was changed elsewhere since, so Doddy left it alone. Check it in Calendar or Reminders.", comment: ""))
        case .unconfirmed:
            receipt.state = .failed(NSLocalizedString("It may not have gone back. Check it in Calendar or Reminders.", comment: ""))
            await sendToAgent("The user tapped Undo, but the app couldn't confirm it. Don't say it was undone.")
        }
        changeReceipt = receipt
    }

    func dismissChangeReceipt() { changeReceipt = nil }

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

    /// Checked again at the tap: the switch, and that the time hasn't passed while the card waited.
    private func setAlarm(_ draft: AlarmDraft) async -> String {
        guard isOn(.timers) else {
            connectionNeeded = .timers
            return VoiceToolReply.failed("Timers and alarms are switched off. Nothing was set.")
        }
        if draft.repeats == nil, let late = ReminderDueRules.passed(draft.first, now: Date()) {
            return VoiceToolReply.clarification(late, tool: VoiceToolName.setAlarm)
        }
        do {
            switch try await AlarmScheduler.schedule(draft) {
            case .verified: return VoiceToolReply.alarmSet(draft)
            case .unconfirmed: return VoiceToolReply.alarmUnconfirmed
            case .needsNewerIOS: return VoiceToolReply.alarmNeedsNewerIOS
            case .notAllowed: return VoiceToolReply.alarmNotAllowed
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

/// What a list change by voice did, shown on the conversation screen (canvas 4, 6, 7).
struct ListReceipt: Equatable {
    enum Line: Equatable {
        case added(String), ticked(String), removed(String), open(String), note(String)
    }
    struct Choices: Equatable {
        let said: String
        let options: [ListItem]
        let tick: Bool
    }
    let listID: UUID
    var title: String
    var lines: [Line]
    var undo: ListUndo?
    var choices: Choices?
    var problem: String?

    init(listID: UUID, title: String, lines: [Line], undo: ListUndo? = nil, choices: Choices? = nil) {
        self.listID = listID
        self.title = title
        self.lines = lines
        self.undo = undo
        self.choices = choices
    }
}

/// Why "Save the facts as a note" saved nothing.
enum TranslatorSaveError: Error, Equatable {
    case nothingToSave
    case failed(String)
}

/// Lets SDK callbacks (which must be `@Sendable`) reach the controller without a retain cycle.
private final class WeakRef<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

/// Like `WeakRef`, but only while `attempt` is still the controller's latest start (review H1):
/// events of a conversation that was ended, or replaced while it connected, never reach the next one.
private final class AttemptRef: @unchecked Sendable {
    private weak var controller: VoiceSessionController?
    private let attempt: Int

    init(_ controller: VoiceSessionController, attempt: Int) {
        self.controller = controller
        self.attempt = attempt
    }

    @MainActor var value: VoiceSessionController? {
        guard let controller, controller.startAttempt == attempt else { return nil }
        return controller
    }
}

private extension VoiceSessionController.PendingAction {
    /// Saves, adds or starts something. Opening Maps, Shortcuts or a draft only hands over to another app.
    var changesSomething: Bool {
        switch self {
        case .memory, .event, .reminder, .timer, .alarm, .cancelAlarm, .cloud, .noteReminder, .createList, .changeEvent, .changeReminder,
             .deleteEvent, .deleteReminder, .bulk: true
        // Each step of a plan is logged on its own (runPlan), not the plan as a whole.
        case .map, .shortcut, .message, .translator, .plan: false
        }
    }
}

/// A change Doddy made in Calendar or Reminders this conversation, shown with Undo (ADR-258).
struct ChangeReceipt: Equatable, Identifiable {
    enum Kind: Equatable {
        case event(EventChangePlan)
        /// The reminder before the change and as it was read back after it.
        case reminder(before: ReminderSnapshot, after: ReminderSnapshot)
    }
    enum UndoState: Equatable {
        case available, working, undone
        case failed(String)
    }

    /// Undo is offered this long after the change.
    static let undoFor: TimeInterval = 10 * 60

    let id = UUID()
    let kind: Kind
    let message: String
    let madeAt = Date()
    var state: UndoState = .available

    static func message(for plan: EventChangePlan) -> String {
        let when = plan.after.allDay
            ? plan.after.start.formatted(date: .abbreviated, time: .omitted)
            : plan.after.start.formatted(date: .abbreviated, time: .shortened)
        return String(format: NSLocalizedString("Changed “%@”: now %@.", comment: ""), plan.after.title, when)
    }

    static func message(reminder: ReminderSnapshot, completed: Bool) -> String {
        completed
            ? String(format: NSLocalizedString("Marked “%@” done in Reminders.", comment: ""), reminder.title)
            : String(format: NSLocalizedString("“%@” is now due %@.", comment: ""), reminder.title, ReminderText.due(reminder.due))
    }

    /// For the agent, in English.
    var agentUndoText: String {
        switch kind {
        case .event(let plan): "the event \"\(plan.before.title)\" is back as it was before Doddy changed it."
        case .reminder(let before, _): "the reminder \"\(before.title)\" is back as it was before Doddy changed it."
        }
    }
}
