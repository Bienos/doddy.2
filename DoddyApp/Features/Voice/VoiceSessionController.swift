import AVFAudio
import DoddyCore
import ElevenLabs
import Foundation
import LiveKit
import Observation
import UIKit
import os

/// One voice conversation with the ElevenLabs agent (the only voice since 9 Nov 2026; OpenAI Realtime
/// was removed). State shown in the UI comes only from real provider events (connected, listening,
/// speaking, disconnected), never from timers.
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
        case map(toolCallID: String, trip: MapTrip)
        case shortcut(toolCallID: String, name: String)
        /// `address` is the phone number or email from Contacts. It is shown on screen only.
        case message(toolCallID: String, draft: MessageDraft, address: String)
        /// A BLIK phone transfer to send in the user's bank app (ADR-510). `contactName` and
        /// `numbers` come from Contacts when iOS allows it, and are shown on screen only. Doddy
        /// never sends money; "I'll send it myself" only keeps the details on screen.
        case blik(toolCallID: String, draft: BlikTransferDraft, contactName: String?, numbers: [BlikPhoneNumber])
        /// Gmail draft or Todoist task. `preview` and `approvalID` come from Doddy's server for exactly
        /// these arguments; the approval works once and expires after two minutes.
        case cloud(toolCallID: String, call: CloudToolCall, preview: ToolPreview, approvalID: UUID, mode: ConnectedAppsMode)
        /// Doddy's own reminder about one saved note (ADR-198). `noteText` is the stored note the
        /// agent's quote matched, shown exactly with when it was saved; nothing is set until the
        /// user taps Set reminder. The user can change the time, or arrive/leave, on the card.
        case noteReminder(toolCallID: String, memoryID: UUID, noteText: String, savedAt: Date?, target: NoteReminderCardTarget)
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
        /// "Undo that" (ADR-271): the newest undoable change from this conversation, from What Doddy did.
        case undo(toolCallID: String, entry: ActivityEntry)
        /// "Save your parking spot here?" (ADR-301): the position read just now, and the user's note.
        case parking(toolCallID: String, spot: ParkingSpot)
        /// "Remind me when to leave" (ADR-335): the place Maps found, the travel time and when to leave.
        case leaveBy(toolCallID: String, plan: LeaveByPlan)
        /// A dish's ingredients with ticks (ADR-305); `alreadyOpen` start unticked.
        case ingredients(toolCallID: String, listID: UUID, listName: String, dish: String, items: [String], alreadyOpen: Set<Int>)
        /// "Call you later?" (ADR-754): from Doddy's number to the user's own verified number `to`,
        /// at `draft.at`, saying `draft.reason` first. The tap approves that with the card's
        /// quiet-hours switch (`callLaterAllowQuiet`).
        case callLater(toolCallID: String, draft: CallLaterDraft, to: String, quietHours: CallQuietHours)
        /// "Call you now?" (decision 2026-11-10-call-me-now-by-voice): from Doddy's number to the user's own
        /// verified number `to`, at once. The tap approves exactly that; nothing is placed before it.
        case callNow(toolCallID: String, to: String)
        /// "Call these places for you?" (decision 2026-11-09-restaurant-calls-one-tap): the server's preview of
        /// every place and the task digest the one tap approves.
        case callTask(toolCallID: String, preview: CallTaskPreview)
        /// ASK-01 (ADR-483): "Doddy wants to …" before a tool with no card of its own runs. A read
        /// runs on a tap or the user's own spoken yes; a change (`needsTap`) only on a tap. The
        /// call is kept as it came, and handled again after the yes.
        case ask(toolCallID: String, card: AskCard, needsTap: Bool, toolName: String, parameters: Data)
        /// ASK-01: an online-account read or web search. `preview` and `approvalID` come from
        /// Doddy's server, which read nothing to make them and runs nothing without the approval.
        case cloudRead(toolCallID: String, call: CloudToolCall, preview: ToolPreview, approvalID: UUID, mode: ConnectedAppsMode)
        /// "Make this presentation?" (ADR-567): every slide as it will be in the file. Nothing is
        /// made until the user taps Make presentation.
        case presentation(toolCallID: String, draft: PresentationDraft)
        /// "Open the camera?" (ADR-569). The camera opens only on the tap.
        case camera(toolCallID: String)
        /// "Turn off Lamp in Bedroom?" (HomeCommand.swift): the one accessory or scene HomeKit
        /// matched, named in HomeKit's words. It runs only on the tap.
        case home(toolCallID: String, command: HomeCommand)

        var toolCallID: String {
            switch self {
            case .memory(let id, _), .event(let id, _), .reminder(let id, _), .timer(let id, _), .alarm(let id, _), .cancelAlarm(let id, _),
                 .map(let id, _), .shortcut(let id, _), .message(let id, _, _), .blik(let id, _, _, _), .cloud(let id, _, _, _, _),
                 .noteReminder(let id, _, _, _, _), .createList(let id, _, _), .plan(let id, _, _),
                 .changeEvent(let id, _), .changeReminder(let id, _, _), .deleteEvent(let id, _), .deleteReminder(let id, _),
                 .undo(let id, _), .bulk(let id, _, _, _), .parking(let id, _), .leaveBy(let id, _),
                 .ingredients(let id, _, _, _, _, _), .ask(let id, _, _, _, _), .cloudRead(let id, _, _, _, _),
                 .presentation(let id, _), .camera(let id), .home(let id, _), .callLater(let id, _, _, _), .callNow(let id, _), .callTask(let id, _):
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
        /// "Ring like an alarm" as the card showed it at the tap (ADR-651).
        var rings = false
    }

    /// The receipt after Set reminder on a note-reminder card (ADR-198), read back from the store.
    /// It stays on screen after the conversation ends, like the Reminders receipt.
    enum NoteReminderStatus: Equatable {
        case setting(ConfirmedNoteReminder)
        case done(ConfirmedNoteReminder, NoteReminderReceipt)
    }

    /// The permission sheet (ADR-566): which connection, what Doddy was asked to do, and the call
    /// kept exactly as it came. `askCard` is set for a read, whose Allow also answers its ask.
    struct PermissionRequest: Identifiable, Equatable {
        let toolCallID: String
        let connection: VoiceConnection
        let kind: PermissionAsk.Kind
        let reason: String?
        let askCard: AskCard?
        let toolName: String
        let parameters: Data

        var id: String { toolCallID }
    }

    /// What a photo search found (ADR-569), shown on screen only.
    struct PhotoResults: Equatable {
        let request: PhotoSearchRequest
        let summary: PhotoSearchSummary
        let identifiers: [String]
    }

    /// A presentation file written and read back on this iPhone (ADR-567).
    struct PresentationReady: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let title: String
        let slideCount: Int
    }

    /// A BLIK transfer to send in the bank app (ADR-510), as shown on its card.
    struct BlikCard: Equatable {
        let draft: BlikTransferDraft
        let contactName: String?
        let numbers: [BlikPhoneNumber]
    }

    /// "I lost my wallet" (ADR-692): the official steps, as shown. `done` holds only the steps the
    /// person ticked themselves; Doddy never ticks one and can't see whether a step was done.
    struct LostWalletCard: Equatable {
        let situation: LostWalletSituation
        let steps: [LostWalletStep]
        var done: Set<LostWalletStepID> = []
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
            // The same phase again (the SDK repeats states) changes nothing; skip the work (ADR-604).
            guard phase != oldValue else { return }
            Self.conversationInProgress = isLive
            if !isLive { turnFeedback.reset() }
            if isLive { Self.current = self } else if Self.current === self { Self.current = nil }
            ListeningIndicatorModel.shared.refresh()
            switch phase {
            case .listening, .thinking, .speaking: connectedOnce = true
            default: break
            }
            syncIsland()
            updateVoiceMeter()
            // Doddy started speaking: the island may open up for a moment (ADR-577).
            if phase == .speaking, oldValue != .speaking { expandIslandIfDue() }
            if phase == .speaking, let began = firstSpeechRequestedAt {
                firstSpeechRequestedAt = nil
                let took = VoiceStartTimeline.text(ProcessInfo.processInfo.systemUptime - began)
                let source = tokenSource?.rawValue ?? "no token"
                Self.audioLog.notice("voice first speaking event after start: \(took, privacy: .public), \(source, privacy: .public)")
            }
            // Listening comes only from the provider's own event: this conversation really
            // connected. Counted once per conversation, for when the "Open Doddy faster" card
            // returns after "Later" (ADR-559; it was the Hey Doddy card's, ADR-328).
            if phase == .listening, !countedAsConnected {
                countedAsConnected = true
                let defaults = UserDefaults.standard
                defaults.set(defaults.integer(forKey: PreferenceKey.connectedConversations) + 1,
                             forKey: PreferenceKey.connectedConversations)
            }
            // Listening comes only from the provider's own event, so this marks a conversation
            // that really connected, not a tap that failed (ADR-326).
            if phase == .listening, !UserDefaults.standard.bool(forKey: PreferenceKey.hadFirstConversation) {
                UserDefaults.standard.set(true, forKey: PreferenceKey.hadFirstConversation)
            }
        }
    }
    private var countedAsConnected = false
    /// True while any conversation holds the microphone (the island keeps it alive in other
    /// screens). Voice samples in Settings don't play then, so they never take over its audio.
    static private(set) var conversationInProgress = false
    /// The conversation that is connecting or live, for Stop listening (ADR-361).
    static private(set) weak var current: VoiceSessionController?

    /// What the listening indicator says about the conversation (ADR-361).
    static var microphone: MicrophoneSnapshot.Conversation {
        guard let current, current.isLive else { return .none }
        if current.phase == .connecting { return .connecting }
        if current.longTurn.isListening { return .longTurn }
        return current.isMuted ? .muted : .listening
    }
    private(set) var lines: [Line] = []
    private(set) var pendingAction: PendingAction? {
        didSet {
            syncIsland()
            // ADR-616: a new card opens the island up while Doddy isn't on screen.
            if oldValue == nil, pendingAction != nil { expandIslandForCard() }
        }
    }
    /// ASK-01 (ADR-483): which calls the user said yes to. Checked right before a tool runs.
    private var askLedger = AskLedger()
    /// The payment card the voice agent asked for (ADR-736). Only a page address came from the agent; the card
    /// shows Doddy's server's own terms. Kept after the outcome until the person closes the card.
    private(set) var paymentApproval: PaymentApprovalModel?
    /// The type the user picks on the "Save this note?" card. Starts as Other for every proposal;
    /// the agent is never told or asked (ADR-202).
    var pendingMemoryCategory: MemoryCategory = .other
    private(set) var contactCard: ContactCard?
    /// The saved parking spot, shown with Open in Maps after "where did I park?" (ADR-301).
    private(set) var parkingCard: ParkingSpot?
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
    /// The note-reminder card's "Ring like an alarm" switch (ADR-651): the agent's proposal, or what
    /// the note had; the user can flip it before the tap.
    private(set) var noteReminderRings = false
    /// The access card (ADR-578): a function the agent asked for is off, or iOS hasn't allowed it.
    /// The screen asks "Allow Doddy to use …?"; nothing turns on without the user's tap there.
    private(set) var accessRequest: ConnectionApprovalCard? { didSet { syncIsland() } }
    /// The function the access card is about. The paths that find one off or blocked set it; a
    /// card already up for the same function is kept as it is (it may be waiting for iOS).
    private(set) var connectionNeeded: VoiceConnection? {
        get { accessRequest?.connection }
        set {
            guard newValue != accessRequest?.connection else { return }
            accessRequest = newValue.map { ConnectionApprovalCard(connection: $0, permission: systemPermissionNow($0)) }
        }
    }
    /// "Let Doddy use Calendar?" (ADR-566): a call held while the sheet asks the user.
    private(set) var permissionRequest: PermissionRequest? { didSet { syncIsland() } }
    /// Connections the user said Not now to in this conversation: not asked for again.
    private var declinedPermissions: Set<VoiceConnection> = []
    /// DOD-07: whether text from outside (an email, a page, the screen, Wikipedia) has reached this conversation, and
    /// what the user said last. After it has, the few tools that run at once and could carry it out ask for a tap
    /// (`AskFirst.need(for:in:)`). A new value for every conversation: reset where one starts and where it ends.
    private var outsideContent = OutsideContentSession()
    /// The searches of Contacts this conversation made for a text, email or BLIK draft, before any
    /// card: at most `ContactSearchBudget.perConversation` (ADR-717).
    private var contactSearches = ContactSearchBudget()
    /// Each call as it came, until it is answered, so one held for the permission sheet can be
    /// handled again from the start once the user allows it.
    private var callsAsReceived: [String: (toolName: String, parameters: Data)] = [:]
    /// The presentation made in this conversation (ADR-567), for the share sheet and its card.
    private(set) var presentationReady: PresentationReady?
    /// The last photo search's results (ADR-569): counts and pictures, on this screen only.
    private(set) var photoResults: PhotoResults?
    /// Set when the user tapped Open camera (ADR-569); the screen shows the camera while it is set.
    private(set) var cameraRequest: UUID?
    /// Set when the user tapped Open on the training plan card (ADR-626); the screen shows the plan screen while it is
    /// set. It holds a goal and maybe days and minutes, never a safety answer: those are asked on that screen.
    private(set) var planRequest: PlanAskRequest?
    /// ADR-563: an online account (Gmail, Notion, …) the agent needed that isn't connected. The
    /// screen offers Connect right here; the sign-in sheet opens over the conversation.
    struct AccountNeeded: Equatable {
        /// The server's toolkit ID, e.g. "gmail".
        let toolkit: String
        /// "Gmail"
        let title: String
    }
    private(set) var accountNeeded: AccountNeeded? { didSet { syncIsland() } }
    private(set) var isConnectingAccount = false
    /// What went wrong the last time Connect was tapped, for the card.
    private(set) var accountMessage: String?
    /// ADR-564: files Claude is making in this conversation, newest first. Each opens by its link.
    private(set) var documents: [RunDocument] = []
    /// What each file in `documents` is about, by its link: the request the agent gave `make_document`
    /// (`ThreadDelivery.madeFileBrief`). In memory only, like `documents`.
    private(set) var documentBriefs: [URL: String] = [:]
    /// A file still being made (owner, 13 Nov 2026, decision 2026-11-13-file-being-made-island-note): instead of the
    /// pop-up card, Home's island drops a small note saying what Doddy is making, for `MadeFileStart.noteSeconds`.
    /// Nothing on it needs a tap; the file arrives in Messages when the server says it is ready.
    struct MadeFileNote: Equatable, Identifiable {
        let id = UUID()
        let document: RunDocument
        /// False in a private conversation: nothing from it reaches Messages, so the file opens from the transcript.
        let keptInMessages: Bool
    }
    private(set) var madeFileNote: MadeFileNote?
    @ObservationIgnored private var madeFileNoteClear: Task<Void, Never>?
    /// find_flights: the latest search's flights on Kiwi.com, as buttons (never read out by the agent).
    private(set) var flightLinks: [RunLink] = []
    private(set) var isMuted = false {
        didSet {
            syncIsland()
            ListeningIndicatorModel.shared.refresh()
        }
    }
    /// The last list change made by voice (ADR-216): what changed, its Undo, and items Doddy
    /// couldn't tell apart, to tap. Shown on screen until dismissed or the next change.
    private(set) var listReceipt: ListReceipt?
    /// True from the tap on Send text until its result (ADR-750 U2): the card is gone by then.
    private(set) var textSending = false
    /// The user's first name for this conversation's call_places cards; empty when About you has none.
    private var callerFirstName = ""
    /// The "Call even in quiet hours" switch on a call-later card (ADR-754); off for each new card.
    var callLaterAllowQuiet = false
    /// True from the tap on Book call until the server's answer.
    private(set) var callBooking = false
    /// True from the tap on Call me until the server's answer (decision 2026-11-10-call-me-now-by-voice).
    private(set) var callPlacing = false
    /// The last change Doddy made in Calendar or Reminders, with Undo (ADR-258).
    private(set) var changeReceipt: ChangeReceipt?
    /// The BLIK transfer the user said they'll send (ADR-510). It stays on screen until dismissed
    /// or the next conversation, so the amount and number are there while they use their bank
    /// app. In memory only; Doddy never sends it.
    private(set) var blikCard: BlikCard?
    /// The lost-wallet checklist (ADR-692). It stays on screen until dismissed or the next
    /// conversation, so the steps are there while the person uses mObywatel or their bank. In
    /// memory only: what was lost and the ticks are never saved or sent.
    private(set) var lostWalletCard: LostWalletCard?
    /// The invoice being dictated (ADR-677): what the person said and the draft made from it. Kept on
    /// this iPhone between conversations (ADR-678, `InvoiceDraftFile`, read back after every write)
    /// until the card is closed or Delete all; never sent. Issuing in inFakt is the card's own tap
    /// (ADR-640), not offered yet.
    private(set) var invoiceSession = InvoiceVoiceSession()
    /// An earlier draft's file couldn't be read and was set aside; the next draft reply says so once.
    @ObservationIgnored private var invoiceDraftWasSetAside = false
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
    /// "Listen until I finish" (OP-019, ADR-364): the user ends the turn; only the words are sent.
    private(set) var longTurn: LongTurnPhase = .off {
        didSet { ListeningIndicatorModel.shared.refresh() }
    }
    @ObservationIgnored private let longTurnRecorder = LongTurnRecorder()
    /// The recording waiting to be written out (again); deleted once sent or dropped.
    @ObservationIgnored private var longTurnFile: URL?
    @ObservationIgnored private var mutedBeforeLongTurn = false
    @ObservationIgnored private var longTurnLimit: Task<Void, Never>?
    private(set) var heldSide: TranslatorDirection?
    /// Listen only: "Read aloud" off sets Doddy's voice to silent on this iPhone (the lines still
    /// show). `readAloudProblem` is set when the silence couldn't be checked.
    private(set) var readsAloud = true
    private(set) var readAloudProblem: String?
    /// Opened from the morning check-in (ADR-220): after the greeting, the app asks for the briefing.
    private var checkInNeedsBriefing = false
    /// The user's first conversation (ADR-401): after the greeting, the app asks for the short tour.
    private var firstConversationNeedsTour = false
    /// "Ask me about it" (ADR-403): after the greeting, the app names the note.
    private var noteQuestion: String?
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
    /// The start each open tool call came from (ADR-458): a card or result is shown or sent only
    /// while that start is still `startAttempt`, so a lookup that finishes after End and a new
    /// Start never reaches the new conversation.
    private var callOwners = ToolCallOwners()
    /// What earlier tries of a reminder or event meant when its card was shown (ADR-319).
    private var retryChecks: [String: ActionRetryDecision] = [:]
    /// The app's read-back and whether it was asked to write, for the entry logged with the reply.
    private var writeResults: [String: WriteResult] = [:]
    /// The island the conversation shows itself on.
    private let island = VoiceLiveActivity.shared
    /// True once this conversation has shown its state on the island, so only it ends it.
    private var ownsIsland = false
    /// "Hey Pat, what's up?" when a Talk to Doddy shortcut started this conversation (ADR-254,
    /// ADR-549). Shown on the island until the user first speaks.
    private(set) var wakeGreeting: String? { didSet { syncIsland() } }
    /// True while iOS has paused Doddy's audio because another app took the audio session
    /// (`AVAudioSession` interruption). Real system events only, never a guess.
    private(set) var audioPausedByOtherApp = false
    /// What iOS last said about the audio session (reason and session setup), shown in small print
    /// on the voice screen so a failure can be read without Xcode. No speech or notes in it.
    private(set) var audioNote: String?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    /// Media services reset and Doddy coming back to the front: both can settle an interruption.
    @ObservationIgnored private var interruptionFollowUps: [NSObjectProtocol] = []
    /// When iOS took the audio, while it still has it (ADR-696).
    @ObservationIgnored private var audioPausedSince: Date?
    /// Ends the conversation if iOS keeps the audio past the grace time and no `.ended` comes.
    @ObservationIgnored private var pauseCheck: Task<Void, Never>?
    private static let audioLog = Logger(subsystem: "com.bienos.doddy2.dev", category: "voice-audio")
    /// Tool calls dropped because their conversation ended (ADR-458). Tool names only, no content.
    private static let toolLog = Logger(subsystem: "com.bienos.doddy2.dev", category: "voice-tools")
    /// Calendar, Reminders, Contacts and timers; a fake in tests (AppTests review finding 2).
    private let devices: any DeviceConnecting
    /// HomeKit for `control_home`; a fake in tests.
    private let homeKit: any HomeControlling
    private let alarmWriter = AlarmKitWriter()
    private let leaveByWriter = LeaveByScheduler()
    private var conversation: (any LiveVoiceLink)?
    /// The conversation Home's island extension is reading the loudness of his voice from
    /// (ADR-655), kept so the meter is detached from it even after `conversation` is cleared.
    @ObservationIgnored private var meteredConversation: (any LiveVoiceLink)?
    /// When the current start began (the press or tap); a repeat press reads it (ADR-579).
    private(set) var startedAt: Date?
    /// The last start without opening Doddy failed because iOS refused the island or the
    /// microphone in the background, not because of the conversation: opening Doddy fixes it (ADR-579).
    private(set) var backgroundStartRefused = false
    /// A start without opening Doddy has its Live Activity and audio session up: what the Action
    /// Button's intent waits for before it returns (decision 2026-11-10-action-button-start).
    private(set) var backgroundStartReady = false
    /// A start without opening Doddy took the audio session itself, so LiveKit leaves it alone until
    /// this conversation is over (`ConversationAudioSession`, decision 2026-11-12-action-button-audio-and-island).
    @ObservationIgnored private var audioHold: ConversationAudioHolds.Hold?
    /// Where this start's voice token came from, for the timing line only.
    private(set) var tokenSource: VoiceTokenSource?
    /// Monotonic, from Home's tap (including its access check), or start() for other entry points.
    /// Cleared at the first real SDK speaking event; no transcript or credential enters the log.
    @ObservationIgnored private var firstSpeechRequestedAt: Double?
    /// The words under Doddy while he works, the tap when the person's words arrive and the time of
    /// each turn in the log (decision `2026-11-12-voice-turn-feedback`).
    let turnFeedback = VoiceTurnFeedback()
    /// The last state the provider reported, which a held "Working on it…" can differ from.
    @ObservationIgnored private var providerState: ElevenLabs.AgentState?
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
    /// When the island opens up into the big island while Doddy talks (ADR-577). Set at each start.
    @ObservationIgnored private var islandExpansion = IslandExpansion(isOn: true)
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
    /// This conversation's id for the learning loop (ADR-440): lets repeated sequences be told apart
    /// by conversation. An identifier only; nothing of what was said.
    private var conversationID = UUID().uuidString

    init(
        store: MemoryStore, logs: ConversationLogStore = .shared, activity: ActivityLogStore = .shared,
        devices: any DeviceConnecting = DeviceConnections(), homeKit: any HomeControlling = HomeKitClient.shared
    ) {
        self.store = store
        self.logs = logs
        self.activity = activity
        self.devices = devices
        self.homeKit = homeKit
    }

    #if DEBUG
    /// Test seam only (AppTests review finding 2): shows `action` as if the agent had proposed it,
    /// with `link` standing in for the provider so a test can read the reply. The app never calls it.
    func showCardForTesting(_ action: PendingAction, link: any LiveVoiceLink) {
        conversation = link
        callOwners.record(action.toolCallID, attempt: startAttempt)
        pendingAction = action
    }

    /// Test seam only (audit 2026-10-12 §5 #10): a conversation that is live, as `start` leaves
    /// it, with `link` standing in for the provider and no microphone. A new start number, like
    /// every real start.
    func beginForTesting(link: any LiveVoiceLink) {
        startAttempt += 1
        callOwners.forget(before: startAttempt)
        conversation = link
        phase = .listening
    }

    /// Test seam only: Doddy starts speaking, as the provider's own event says (the voice meter
    /// attaches then, ADR-655).
    func speakForTesting() {
        guard isLive else { return }
        phase = .speaking
    }

    /// Test seam only (ADR-821, the screens run): a line of the transcript, as the provider's own
    /// events add one, so a photographed conversation shows what was said before its card.
    func addLineForTesting(_ text: String, fromUser: Bool) {
        lines.append(Line(fromUser: fromUser, text: text))
    }

    /// Test seam only: the provider's disconnect.
    func disconnectForTesting(_ kind: VoiceSessionEnd.Disconnect) {
        disconnected(kind)
    }

    /// Test seam only: iOS's audio interruption notification, as the observer hands it on (ADR-696).
    func audioInterruptionForTesting(began: Bool, shouldResume: Bool) {
        audioInterruption(began: began, shouldResume: shouldResume, reason: "test")
    }

    /// Test seam only: iOS restarted its media services (ADR-696).
    func mediaServicesResetForTesting() {
        audioServicesWereReset()
    }

    /// Test seam only: a tool call from the provider. The start it arrived in is taken now, as the
    /// ElevenLabs callbacks do, and the returned task runs it.
    @discardableResult
    func receiveToolCallForTesting(name: String, id: String, parameters: String) -> Task<Void, Never> {
        let attempt = startAttempt
        let call = ClientToolCallEvent(
            toolName: name, toolCallId: id, parametersData: Data(parameters.utf8), eventId: 0, expectsResponse: true)
        return Task { await handle(call, attempt: attempt) }
    }
    #endif

    var isLive: Bool {
        switch phase {
        case .connecting, .listening, .thinking, .speaking: true
        default: false
        }
    }

    /// `profile` is the user's approved introduction answers; it reaches the agent only when
    /// Settings → About you → "Use in voice conversations" is on. `wakeGreeting` is set for
    /// "Talk to Doddy" (Back Tap and the other shortcuts): Doddy says it first and the island shows it.
    /// `withoutOpeningApp`: "Talk in the Island" started it with Doddy in the background (ADR-577).
    func start(
        _ mode: VoiceConnectionMode, profile: ApprovedProfile, translator preset: TranslatorSetup? = nil,
        checkIn: MorningBriefing? = nil, wakeGreeting: String? = nil, aboutNote: UUID? = nil,
        withoutOpeningApp: Bool = false, requestedAt: Double? = nil
    ) async {
        guard !isLive else { return }
        // One owner of the audio session (ADR-695): while a Capture recording (ADR-588), a voice memo,
        // Messages dictation or a call rehearsal has the microphone, a conversation started now would
        // reconfigure the session under it and break it without a word. What only plays (a note read
        // aloud, a memo, a sample) is stopped for the conversation instead.
        if case .refused(let holder) = AudioSessionOwner.shared.claim(.conversation, by: self) {
            Self.audioLog.notice("a conversation was not started: \(holder.rawValue, privacy: .public) has the audio session")
            phase = .failed(AudioTalkRefusal.message(by: holder))
            return
        }
        // Another controller's conversation is starting or live: don't open a second microphone.
        guard Self.gate.request(self, isBusy: { $0.isBusy }) == .go else {
            Self.audioLog.notice("a second conversation was not started: another one is starting or live")
            return
        }
        startsInProgress += 1
        defer { startsInProgress -= 1 }
        firstSpeechRequestedAt = requestedAt ?? ProcessInfo.processInfo.systemUptime
        // The previous conversation's lines and unanswered cards are kept before they're cleared,
        // even when it ended in a failure nothing else recorded (ADR-360).
        keepLog()
        // This start's number (review H1): a start that was ended and replaced while it waited
        // never opens, keeps or hears a conversation.
        startAttempt += 1
        let attempt = startAttempt
        callOwners.forget(before: attempt)
        // "Dzwonię w imieniu …" for call_places: the first word of the approved name in About you, as
        // Settings, Phone calls, Calls for you starts from (decision 2026-11-09-restaurant-calls-one-tap).
        callerFirstName = profile.value(.name)?.split(separator: " ").first.map(String.init) ?? ""
        isOffline = false
        offlineSaved = nil
        sessionEnd = nil
        recovery = nil
        recoverySaved = nil
        userAskedToEnd = false
        connectedOnce = false
        // A note being read aloud would fight the conversation for the speaker (ADR-243).
        ReadAloudController.shared.stop()
        self.wakeGreeting = wakeGreeting
        lines = []
        // A translator start sends no notes or lists, so it never carries a check-in too.
        let checkIn = preset == nil ? checkIn : nil
        checkInNeedsBriefing = checkIn != nil
        // Only a plain conversation, and never a private note (ADR-310).
        noteQuestion = nil
        if preset == nil, checkIn == nil, let aboutNote,
           let record = store.memories.first(where: { $0.id == aboutNote }),
           NoteQuestion.canAsk(about: record, privateNotes: PrivateNotesStore.current()) {
            noteQuestion = NoteQuestion.appMessage(for: record)
        }
        let isFirstConversation = FirstConversationPrompt.isFirst(
            hadConversationBefore: UserDefaults.standard.bool(forKey: PreferenceKey.hadFirstConversation),
            translator: preset != nil, morningCheckIn: checkIn != nil)
            && noteQuestion == nil  // "Ask me about it" comes first; no tour then
        firstConversationNeedsTour = isFirstConversation
        translator = nil
        listReceipt = nil
        changeReceipt = nil
        blikCard = nil
        lostWalletCard = nil
        restoreInvoiceDraft()
        translatorSummary = nil
        translatorFactsSaved = nil
        holdToTalk = false
        heldSide = nil
        readsAloud = true
        readAloudProblem = nil
        privacyLocked = false
        pendingAction = nil
        contactCard = nil
        parkingCard = nil
        reminderStatus = nil
        noteReminderStatus = nil
        planStatus = nil
        connectionNeeded = nil
        permissionRequest = nil
        declinedPermissions = []
        outsideContent = OutsideContentSession()
        contactSearches = ContactSearchBudget()
        callsAsReceived = [:]
        presentationReady = nil
        photoResults = nil
        cameraRequest = nil
        planRequest = nil
        accountNeeded = nil
        accountMessage = nil
        isMuted = false
        savedThisConversation = 0
        islandFlash = nil
        // Settings › Dynamic Island › "Open up when Doddy speaks" (ADR-579; was Back Tap's "Small island").
        islandExpansion = IslandExpansion(isOn: LaunchPreferencesMigration.islandExpands(
            UserDefaults.standard.object(forKey: LaunchPreferencesMigration.islandExpandsKey) as? Bool))
        backgroundStartRefused = false
        backgroundStartReady = false
        ConversationAudioSession.release(takeAudioHold())
        tokenSource = nil
        proposedNoteTexts = []
        saveSuggestions = nil
        suggestionsOffered = false
        conversationID = UUID().uuidString
        activity.sessionID = conversationID
        store.learning?.clearAnsweredCards()
        audioPausedByOtherApp = false
        audioNote = nil

        // Not set up: say so without asking for the microphone first.
        if case .notSetUp(let reason) = mode {
            fail(reason)
            return
        }
        guard VoiceProviderConsent.isGranted() else {
            fail("Open Talk to Doddy to review voice data sharing before starting a conversation.")
            return
        }
        guard await Self.microphoneAllowed() else {
            if attempt == startAttempt { phase = .microphoneDenied }
            return
        }
        guard attempt == startAttempt else { return }
        startedAt = Date()
        countedAsConnected = false
        phase = .connecting
        // From here, not only once connected: a call that rings while Doddy connects counts too (ADR-696).
        watchAudioInterruptions()
        // For a phone log of a start that never got going (STATUS "Known problems"): which start,
        // what started it, and whether Doddy was in the background. No notes or speech in it.
        let inBackground = UIApplication.shared.applicationState == .background
        let startNote = "starting a conversation: attempt \(attempt), in background \(inBackground), without opening \(withoutOpeningApp)"
        Self.audioLog.notice("\(startNote, privacy: .public)")
        // "Talk in the Island" (ADR-577): the Action Button or a control (ADR-632), or the Shortcuts
        // app, without opening Doddy.
        // iOS keeps a recording started that way only while its Live Activity is up (requested by
        // `phase = .connecting` above), and the microphone can start only if the app can take the
        // audio session now. Both are checked before anything is fetched or connected, so a refusal
        // is said plainly instead of a conversation that can't hear the user.
        if withoutOpeningApp {
            guard island.isShowing else {
                let noIsland = "no island for a start without opening: attempt \(attempt)"
                Self.audioLog.notice("\(noIsland, privacy: .public)")
                backgroundStartRefused = true
                fail(NSLocalizedString("Doddy couldn't show himself in the Dynamic Island, so he can't listen without opening. Open Doddy to talk.", comment: ""))
                return
            }
            if let problem = Self.takeAudioSessionWithoutOpening() {
                backgroundStartRefused = true
                fail(problem)
                return
            }
            audioHold = ConversationAudioSession.takenByDoddy()
            backgroundStartReady = true
        }

        // The Dynamic Island / Lock Screen buttons reach this conversation through these.
        let actions = VoiceActivityActions.shared
        actions.endConversation = { [weak self] in
            await self?.stop()
            await self?.island.settle()
        }
        actions.toggleMute = { [weak self] in await self?.toggleMute() }

        // The voice token is asked for now and used below (ADR-686), so the wait for the notes and
        // the rest of the context below overlaps with the wait for the server instead of adding to
        // it. Only ElevenLabs through the token server, after consent and the microphone check.
        // Translating talks to its own agent, which has no tools at all (owner, 12 Nov 2026: the agent must not
        // use any function while translating; decision 2026-11-12-translator-agent).
        let agentKind = VoiceAgentKind.forTranslatorStart(preset != nil)
        var earlyToken: Task<Result<String, VoiceTokenError>, Never>?
        if case .tokenServer(let endpoint) = mode {
            // One fetched ahead (VoiceTokenWarmer) is used once; it is gone from the shelf either way, so a
            // start that fails to connect with it fetches a fresh one next time, never the same again. A
            // translator start never uses it: it is for the main agent, so a translator token is fetched now.
            earlyToken = Task { () -> Result<String, VoiceTokenError> in
                do throws(VoiceTokenError) {
                    if agentKind == .translator {
                        let value = try await VoiceTokenWarmer.shared.translatorToken(endpoint: endpoint)
                        if attempt == startAttempt { tokenSource = .fetched }
                        return .success(value)
                    }
                    let token = try await VoiceTokenWarmer.shared.token(endpoint: endpoint)
                    if attempt == startAttempt { tokenSource = token.source }
                    return .success(token.value)
                } catch {
                    return .failure(error)
                }
            }
        }
        defer { earlyToken?.cancel() }

        // What Doddy knows at the start: the saved notes and, if the user keeps it on, the last
        // few conversations. Both are bounded and say when they were cut.
        let contextInterval = LaunchWork.signposter.beginInterval("Voice startup context")
        // A bounded, coherent read instead of loading the screens' whole store, correction history,
        // media and reminders. Translator starts read none of the owner's personal storage.
        let startup: VoiceStartupSnapshot?
        if preset == nil {
            startup = try? await store.environment.memoryRepository.voiceStartupSnapshot(excluding: PrivateNotesStore.current().ids)
        } else {
            startup = nil
        }
        LaunchWork.signposter.endInterval("Voice startup context", contextInterval)
        // Ended (or ended and started again) while the notes loaded.
        guard attempt == startAttempt, phase == .connecting else { return }
        // Private notes (ADR-310) never reach the voice agent.
        let privateIDs = PrivateNotesStore.current().ids
        var notes = startup?.notesContext(excluding: privateIDs) ?? VoiceStartupSnapshot.unavailableNotes
        // After a drop the agent is told it was cut off (ADR-360), within the same switch.
        var recent = logs.isEnabled
            ? SessionRecovery.withResumeNote(VoiceContext.recentConversations(logs.logs), logs: logs.logs, now: Date())
            : VoiceContext.Rendered(text: "(remembering recent conversations is switched off in Settings)", includedCount: 0, truncated: false)
        // After a call cut the last conversation off, Doddy opens by saying where it stopped (ADR-696).
        // Only for a plain conversation (a translator or a check-in has its own opening and sends no
        // earlier conversations), and only when remembering conversations is on.
        let interruptedOpening = logs.isEnabled && preset == nil && checkIn == nil
            ? SessionRecovery.interruptedOpening(logs: logs.logs, now: Date(), polish: ConversationLanguage.stored() == .polish)
            : nil
        var listsText = startup?.listsContext(excluding: privateIDs) ?? VoiceStartupSnapshot.unavailableLists
        if let templates = ListTemplateStore.current().promptLine { listsText += "\n" + templates }
        var profileText = ProfilePrompt.render(profile, shared: UserDefaults.standard.bool(forKey: PreferenceKey.shareProfileWithVoice))
        startedMode = mode
        sharedOwnerContext = preset == nil
        // What Doddy learned and the user confirmed (ADR-440), only when they switched it on.
        var learnedText = preset == nil ? (store.learning?.cachedVoiceContext() ?? LearningPrompt.notShared) : LearningPrompt.notShared
        // Tasks handed to Doddy's background worker (ADR-570): titles, states, the start of a result.
        var errandsText = preset == nil ? ErrandsModel.shared.cachedPromptText() : "(not shared: translating)"
        // Opened from Home's Translate: the agent gets no notes, conversations or profile at all,
        // so it has nothing of the owner's to repeat to the other person.
        if let preset {
            let none = "(not shared: this conversation is only for translating)"
            notes = VoiceContext.Rendered(text: none, includedCount: 0, truncated: false)
            recent = VoiceContext.Rendered(text: none, includedCount: 0, truncated: false)
            profileText = none
            listsText = none
            learnedText = none
            errandsText = none
            isPrivate = true
            privacyLocked = true
            translator = TranslatorSession(setup: preset, startedAt: Date())
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
            LearningPrompt.variableName: learnedText,
            TranslatorPrompt.variableName: TranslatorPrompt.render(preset),
            ListsPrompt.variableName: listsText,
            ErrandsPrompt.variableName: errandsText,
            MorningCheckInPrompt.variableName: MorningCheckInPrompt.render(checkIn),
            FirstConversationPrompt.variableName: FirstConversationPrompt.render(isFirst: isFirstConversation),
            // What Doddy says first (ADR-254): the shortcut greeting ("Hey Pat, what's up?"), otherwise his
            // usual opening ("Hi, I'm Doddy. What's on your mind?" the first time, then "I'm here.
            // What's up?", ADR-556). Used once the agent's first message is {{opening_line}}
            // (voice-agent/session.json); an agent without it ignores the variable.
            // Translating (9 Nov 2026): Doddy opens with the disclosure to them, or one short line, never "I'm
            // here. What's up?" followed by an app message (that message made him start the mode again).
            WakeGreeting.variableName: preset.map(TranslatorPrompt.openingLine) ?? interruptedOpening ?? wakeGreeting ?? WakeGreeting.openingLine(
                afterWakeWord: false, name: nil, polish: ConversationLanguage.stored() == .polish,
                firstConversation: isFirstConversation),
        ]
        var config = ConversationConfig(dynamicVariables: variables, userId: Self.userID())
        config.onStartupStateChange = { state in
            let metrics: ConversationStartupMetrics
            switch state {
            case .active(_, let value), .failed(_, let value): metrics = value
            default: return
            }
            let timing = VoiceTransportTiming(room: metrics.roomConnect, agent: metrics.agentReady,
                                               initialization: metrics.conversationInit, total: metrics.total)
            Task { @MainActor in
                guard ref.value != nil else { return }
                Self.audioLog.notice("voice transport timing: \(timing.line, privacy: .public)")
            }
        }
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
        // Doddy speaking and thinking (ADR-604). The SDK calls `onAgentStateChange` only in its
        // event-based mode: with no configuration (ElevenLabs Swift SDK 3.3.1, `Conversation.
        // setupAgentStateManager` returns early) the callback never fires, so the island, Home's
        // waves and his talking pose stayed on "Listening" while he spoke. The defaults use the
        // agent's own events and the room's speaking detection; no `vad_score` events are needed.
        // 1 s instead of the SDK's 0.5 s before a quiet Doddy counts as listening (12 Nov 2026): the room
        // reports him quiet in the pauses between his sentences, so each answer flipped speaking and
        // listening several times, and Home's strip and the island grew and shrank with every flip. The
        // user speaking or interrupting still switches at once (their own SDK signals).
        config.agentStateConfiguration = AgentStateConfiguration(speakingToListeningDelay: 1.0)
        config.onAgentStateChange = { state in
            Task { @MainActor in ref.value?.apply(state) }
        }
        config.onUserTranscript = { text, _ in
            Task { @MainActor in
                // The person's words arrived: the turn starts here (decision 2026-11-12-voice-turn-feedback).
                if let controller = ref.value, controller.isLive {
                    controller.turnFeedback.userFinished(tap: controller.phase != .speaking && controller.translator == nil)
                }
                ref.value?.append(text, fromUser: true)
            }
        }
        // Tools the agent runs itself (web tools) reach the app only as these two events; the app's
        // own tools are also counted in `handle` and `reply`, once per call id.
        config.onAgentToolRequest = { event in
            let id = event.toolCallId, name = event.toolName
            Task { @MainActor in
                ref.value?.turnFeedback.toolStarted(id: id, name: name)
                // Wikipedia and the weather are read by ElevenLabs: the app can't see the result, only that it was asked for.
                ref.value?.outsideContent.noteRunByProvider(name)
            }
        }
        config.onAgentToolResponse = { event in
            let id = event.toolCallId
            Task { @MainActor in ref.value?.turnFeedback.toolAnswered(id: id) }
        }
        config.onInterruption = { _ in
            Task { @MainActor in ref.value?.turnInterrupted() }
        }
        config.onAgentResponse = { text, _ in
            Task { @MainActor in ref.value?.append(text, fromUser: false) }
        }
        config.onAgentResponseCorrection = { original, corrected, _ in
            Task { @MainActor in ref.value?.correct(original, to: corrected) }
        }
        config.onUnhandledClientToolCall = { call in
            Task { @MainActor in await ref.value?.handle(call, attempt: attempt) }
        }
        config.onError = { error in
            let offline = Offline.isNoConnection(error)
            let slow = Offline.isServerSlow(error)
            // The SDK reports a failed start here as well as throwing it (3.3.1, `handleStartupFailure`).
            // A refused developer connection is handled where the start throws it
            // (`developerConnectionRefused`); failing here too, before or after that, would show the
            // SDK's English words and stop the retry through the token server.
            if DeveloperVoiceConnection.isRefusal(error.localizedDescription) { return }
            Task { @MainActor in
                if offline {
                    ref.value?.failOffline()
                } else if slow {
                    ref.value?.fail(Offline.slowServerMessage)
                } else {
                    ref.value?.fail(error.errorDescription ?? "Something went wrong.")
                }
            }
        }

        config.onAgentReady = {
            Task { @MainActor in
                if ref.value?.phase == .connecting { ref.value?.phase = .listening }
            }
        }
        config.onDisconnect = { reason in
            // `.agent`: the connection was closed from the other side (ADR-360).
            let kind: VoiceSessionEnd.Disconnect = switch reason {
            case .user: .user
            case .agent: .agent
            case .error: .error
            }
            Task { @MainActor in ref.value?.disconnected(kind) }
        }

        await connectElevenLabs(mode, agent: agentKind, config: config, attempt: attempt, earlyToken: earlyToken)
    }

    /// Gets the credential for `mode` and opens the ElevenLabs conversation. When the agent refuses a
    /// Debug build's developer connection (its authentication is on, as since 8 Nov 2026), the same
    /// start carries on through the token server if this iPhone has a voice session, and otherwise
    /// asks for sign-in, instead of showing the SDK's English text.
    private func connectElevenLabs(
        _ mode: VoiceConnectionMode, agent: VoiceAgentKind, config: ConversationConfig, attempt: Int,
        earlyToken: Task<Result<String, VoiceTokenError>, Never>?
    ) async {
        let auth: ElevenLabsConfiguration
        // The account-derived user id the voice server sent with the token, when it sent one (decision
        // 2026-11-12-voice-conversations-per-account). Deleting the account finds the conversations by it.
        var accountUserID: String?
        switch mode {
        case .tokenServer(let endpoint):
            let fetched: Result<String, VoiceTokenError>
            if let earlyToken {
                fetched = await earlyToken.value
            } else {
                do throws(VoiceTokenError) {
                    if agent == .translator {
                        fetched = .success(try await VoiceTokenWarmer.shared.translatorToken(endpoint: endpoint))
                    } else {
                        let token = try await VoiceTokenWarmer.shared.token(endpoint: endpoint)
                        if attempt == startAttempt { tokenSource = token.source }
                        fetched = .success(token.value)
                    }
                } catch {
                    fetched = .failure(error)
                }
            }
            switch fetched {
            case .success(let token):
                auth = .conversationToken(token)
                accountUserID = VoiceTokenUserIDs.shared.take(forToken: token)
            case .failure(let error):
                let tokenNote = "voice token not received: attempt \(attempt), \(LogSafeError.kind(of: error))"
                Self.audioLog.notice("\(tokenNote, privacy: .public)")
                if attempt == startAttempt, phase == .connecting {
                    if error == .offline { failOffline() } else { fail(VoiceTokenServer.message(for: error)) }
                }
                return
            }
        case .directAgent(let agentID):
            // Debug builds only (ADR-551): no token, no DODDY voice account. Translating has its own agent here too.
            auth = .publicAgent(id: agent == .translator ? VoiceConfig.translatorDirectAgentID : agentID)
        case .notSetUp(let reason):
            fail(reason)
            return
        }
        // Closed (or closed and started again) while the token was being fetched: don't open the
        // microphone after all.
        guard attempt == startAttempt, phase == .connecting else { return }

        Self.allowOtherAppsAudio()
        // Before LiveKit's engine starts: it sets the session up itself unless a start without opening holds it.
        ConversationAudioSession.beforeConnect(audioHold)
        let sessionNote = audioHold == nil ? "set up by LiveKit" : "held by Doddy: \(Self.describeAudioSession())"
        let connectNote = "connecting to ElevenLabs: attempt \(attempt), audio session \(sessionNote)"
        Self.audioLog.notice("\(connectNote, privacy: .public)")
        // This iPhone's own id, unless the server sent an account id this app accepts (`VoiceUserIDPolicy`). A `let`:
        // the start below captures it in a concurrent closure.
        let startConfig: ConversationConfig = {
            var withUser = config
            if let accountID = VoiceUserIDPolicy.accepted(accountUserID) { withUser.userId = accountID }
            return withUser
        }()
        do {
            // At most `StartLimit.seconds` (ADR-686). One that connects after the limit anyway is
            // ended here, so nothing keeps listening.
            let started = try await StartLimit.run {
                try await ElevenLabs.startConversation(auth: auth, config: startConfig)
            } onTimeout: { [weak self] in
                // Block late SDK events before the deadline resumes the waiting start.
                guard let self, attempt == self.startAttempt else { return }
                self.startAttempt += 1
                self.fail(StartLimit.message)
            } lateResult: { late in
                let lateNote = "a start that connected after the limit was ended: attempt \(attempt)"
                Self.audioLog.notice("\(lateNote, privacy: .public)")
                await late.endConversation()
            }
            guard attempt == startAttempt, isLive else {
                // Closed (or closed and started again) while connecting: end it so nothing keeps
                // listening and its tool calls stop (review H1).
                let replacedNote = "a replaced start connected and was ended: attempt \(attempt)"
                Self.audioLog.notice("\(replacedNote, privacy: .public)")
                await started.endConversation()
                return
            }
            conversation = started
            watchAudioInterruptions()
            Self.audioLog.notice("conversation started. \(Self.describeAudioSession(), privacy: .public)")
        } catch {
            let failedNote = "ElevenLabs conversation didn't start: attempt \(attempt), \(LogSafeError.kind(of: error))"
            Self.audioLog.notice("\(failedNote, privacy: .public)")
            // A replaced start's failure isn't the new conversation's.
            guard attempt == startAttempt else { return }
            if error is StartLimit.TimedOut { return }
            if Offline.isNoConnection(error) {
                failOffline()
                return
            }
            if Offline.isServerSlow(error) {
                fail(Offline.slowServerMessage)
                return
            }
            if case .directAgent = mode, DeveloperVoiceConnection.isRefusal(error.localizedDescription) {
                await developerConnectionRefused(config: config, attempt: attempt, agent: agent)
                return
            }
            // Translated before it reaches the card, which shows its text as given.
            var message = NSLocalizedString("Couldn't connect to Doddy's voice. Check your internet connection and try again.", comment: "")
            // An agent that doesn't allow the voice overrides refuses the conversation.
            if config.ttsOverrides != nil || config.agentOverrides != nil {
                // The choice of voice and its "Use Doddy's own voice" button are gone (decision 2026-11-12-one-voice): what is
                // still sent is the speed, the expressiveness and the language.
                message += " " + NSLocalizedString("If it keeps failing, set Speed to Normal, Expressiveness to Natural and Starts in to Automatic in Settings → Voice and personality.", comment: "")
            }
            #if DEBUG
            // The SDK's own words, in English, for the developer; Release builds keep them in the log only.
            message += "\n(\(error.localizedDescription))"
            #endif
            fail(message)
        }
    }

    /// The agent refused the developer connection (Debug builds, ADR-551): its authentication is on.
    /// The Debug switch goes off so later starts use the token server too, and this start carries on
    /// through it when there is a voice session to ask with.
    private func developerConnectionRefused(config: ConversationConfig, attempt: Int, agent: VoiceAgentKind) async {
        Self.audioLog.notice("the agent refused the developer connection: attempt \(attempt, privacy: .public)")
        VoiceConfig.directAgentRefused()
        let auth = VoiceAuthSession.shared
        switch DeveloperVoiceConnection.afterRefusal(
            tokenServer: VoiceConfig.connectionMode,
            signedIn: auth.isSignedIn || auth.hasSavedSession
        ) {
        case .retry(let next):
            // A translator restarted later uses the connection that worked.
            startedMode = next
            await connectElevenLabs(next, agent: agent, config: config, attempt: attempt, earlyToken: nil)
        case .signInNeeded:
            fail(NSLocalizedString("Doddy's voice now needs you to be signed in. Close this screen and tap Talk to Doddy to sign in.", comment: ""))
        case .notSetUp(let reason):
            fail(reason)
        }
    }

    /// Counts starts and ends, so a start that was ended and replaced while it waited (for the
    /// token server or the provider) never opens a second microphone (review H1). `AttemptRef`
    /// reads it, so it is fileprivate.
    fileprivate var startAttempt = 0
    /// One conversation at a time across the app (ADR-496): the voice screen and a shortcut each
    /// make their own controller, so `guard !isLive` alone can't stop two at once.
    private static var gate = VoiceConversationGate<VoiceSessionController>()
    /// Starts still running (waiting for the microphone, the token or the provider). A counter, not
    /// a flag, so "Talk again" tapped twice can't clear it while the second start still runs.
    private var startsInProgress = 0
    private var isBusy: Bool { startsInProgress > 0 || isLive }
    /// The conversation starting or live anywhere in the app, if any: the voice screen shows it
    /// instead of starting a second.
    static var runningConversation: VoiceSessionController? { gate.running { $0.isBusy } }

    /// Keeps the conversation going when the user opens another app that plays or records sound
    /// (ADR-207). The SDK's default call session is not mixable, so another app starting its own
    /// audio session pauses Doddy at once and nothing brings him back. A mixable session is not
    /// paused that way. Cost: the other app's sound plays along with Doddy's, and the microphone
    /// can hear it (headphones avoid that). Same options as the SDK's own speaker preset plus
    /// `.mixWithOthers`. Not verified on a device.
    /// LiveKit 2.19 doesn't read `sessionConfiguration` when it sets the session up (and since 2.17 its
    /// own preset no longer mixes), so this changes nothing today; a start without opening Doddy keeps
    /// its mixable session through `ConversationAudioSession` (decision 2026-11-12-action-button-audio-and-island).
    private static func allowOtherAppsAudio() {
        AudioManager.shared.sessionConfiguration = AudioSessionConfiguration(
            category: .playAndRecord,
            categoryOptions: conversationAudioOptions,
            mode: .videoChat)
    }

    /// The conversation's audio options: headsets, AirPlay, the speaker, and other apps' sound
    /// mixed in rather than stopped.
    private static var conversationAudioOptions: AVAudioSession.CategoryOptions {
        #if swift(>=6.2)
        let routes: AVAudioSession.CategoryOptions = [.allowBluetoothHFP, .allowBluetoothA2DP, .allowAirPlay]
        #else
        let routes: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
        #endif
        return routes.union([.defaultToSpeaker, .mixWithOthers])
    }

    /// "Talk in the Island" (ADR-577): takes the audio session with the conversation's own settings
    /// before connecting, because a start without the app on screen gets the microphone only if
    /// iOS lets the app take the session now. Returns what to tell the user, or nil when iOS
    /// agreed. The SDK then uses the session as it is.
    private static func takeAudioSessionWithoutOpening() -> String? {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .videoChat, options: conversationAudioOptions)
            try session.setActive(true)
            audioLog.notice("audio session taken without opening. \(describeAudioSession(), privacy: .public)")
            return nil
        } catch {
            // The code is AVAudioSession's number for the refusal (no text, nothing said).
            let refused = "audio session refused without opening: \(LogSafeError.kind(of: error)), code \((error as NSError).code)"
            audioLog.notice("\(refused, privacy: .public)")
            return NSLocalizedString("iOS didn't let Doddy start the microphone without opening him. Open Doddy to talk.", comment: "")
        }
    }

    /// This conversation's hold on the audio session, handed over once (decision 2026-11-12-action-button-audio-and-island).
    private func takeAudioHold() -> ConversationAudioHolds.Hold? {
        defer { audioHold = nil }
        return audioHold
    }

    /// Watches iOS audio interruptions (a phone call, an alarm, Siri, another app's audio) and
    /// follows `VoiceInterruptionPolicy` (ADR-696). Neither voice SDK reacts to them, so without this
    /// a call left the conversation "listening" with a microphone that heard nothing, and every tap
    /// on Doddy went back to it. Also shown on screen, in the log, and as `audioPausedByOtherApp`.
    private func watchAudioInterruptions() {
        guard interruptionObserver == nil else { return }
        let ref = WeakRef(self)
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { note in
            let info = note.userInfo
            let began = (info?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            let shouldResume = (info?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            let reason = (info?[AVAudioSessionInterruptionReasonKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionReason.init(rawValue:))
                .map { "\($0)" } ?? "not given"
            Task { @MainActor in ref.value?.audioInterruption(began: began, shouldResume: shouldResume, reason: reason) }
        }
        interruptionFollowUps = [
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in ref.value?.audioServicesWereReset() }
            },
            // iOS doesn't promise an `.ended`; coming back to Doddy after a call settles it too.
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in ref.value?.checkPausedAudio() }
            },
        ]
    }

    private func stopWatchingAudioInterruptions() {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        for observer in interruptionFollowUps { NotificationCenter.default.removeObserver(observer) }
        interruptionFollowUps = []
        pauseCheck?.cancel()
        pauseCheck = nil
        audioPausedSince = nil
        audioPausedByOtherApp = false
    }

    private func audioInterruption(began: Bool, shouldResume: Bool, reason: String) {
        guard isLive else { return }
        let note = "\(began ? "iOS paused Doddy's audio" : "iOS gave Doddy's audio back") (reason: \(reason), resume allowed: \(shouldResume)). Session: \(Self.describeAudioSession())."
        audioNote = note
        Self.audioLog.notice("\(note, privacy: .public)")
        if began {
            guard VoiceInterruptionPolicy.began(isLive: isLive) == .markPaused else { return }
            audioPausedByOtherApp = true
            // The first `.began` counts: a second one doesn't buy more time.
            if audioPausedSince == nil { audioPausedSince = Date() }
            schedulePauseCheck()
            return
        }
        switch VoiceInterruptionPolicy.ended(pausedSince: audioPausedSince, shouldResume: shouldResume, now: Date(), isLive: isLive) {
        case .resume:
            resumeAfterInterruption()
        case .endAsDrop:
            endForInterruption()
        case .ignore, .markPaused:
            audioPausedByOtherApp = false
        }
    }

    /// iOS gave the audio back in time: the session is activated again so the microphone hears.
    /// If iOS refuses, the conversation ends as a drop instead of staying deaf.
    private func resumeAfterInterruption() {
        pauseCheck?.cancel()
        pauseCheck = nil
        audioPausedSince = nil
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            audioPausedByOtherApp = false
            Self.audioLog.notice("audio session active again after an interruption. \(Self.describeAudioSession(), privacy: .public)")
        } catch {
            let refused = "audio session not reactivated after an interruption: \(LogSafeError.kind(of: error)), code \((error as NSError).code)"
            Self.audioLog.notice("\(refused, privacy: .public)")
            endForInterruption()
        }
    }

    private func schedulePauseCheck() {
        pauseCheck?.cancel()
        let attempt = startAttempt
        pauseCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(VoiceInterruptionPolicy.resumeGraceSeconds + 0.5))
            guard !Task.isCancelled, let self, attempt == self.startAttempt else { return }
            self.checkPausedAudio()
        }
    }

    private func checkPausedAudio() {
        guard VoiceInterruptionPolicy.stillPaused(pausedSince: audioPausedSince, now: Date(), isLive: isLive) == .endAsDrop else { return }
        endForInterruption()
    }

    private func audioServicesWereReset() {
        guard VoiceInterruptionPolicy.mediaServicesReset(isLive: isLive) == .endAsDrop else { return }
        Self.audioLog.notice("iOS reset its media services during a conversation")
        endForInterruption()
    }

    /// Ends the conversation as `.dropped(.audioInterrupted)`. `fail` ends the SDK's conversation and
    /// frees the microphone, the gate, the island and the pill; the transcript and the recovery
    /// draft are kept, and the next conversation is told it was cut off.
    private func endForInterruption() {
        guard isLive else { return }
        Self.audioLog.notice("conversation ended: iOS kept the audio past the grace time or refused to give it back")
        if sessionEnd == nil { sessionEnd = .dropped(.audioInterrupted) }
        fail(SessionRecovery.status(.dropped(.audioInterrupted), connected: connectedOnce, language: .current).detail ?? "")
    }

    private static func describeAudioSession() -> String {
        let session = AVAudioSession.sharedInstance()
        let mixing = session.categoryOptions.contains(.mixWithOthers) ? "mixing with other apps ON" : "mixing with other apps OFF"
        return "\(session.category.rawValue), mode \(session.mode.rawValue), \(mixing), other app audio playing: \(session.isOtherAudioPlaying)"
    }

    /// `reason`: why it ends. Anything already known (a drop or failure) is kept.
    func stop(_ reason: VoiceSessionEnd = .userEnded) async {
        // From here, a start still connecting ends itself and late events of this conversation
        // are dropped (review H1).
        startAttempt += 1
        userAskedToEnd = true
        // Taken now, before the await below: a start during it must keep its own hold.
        let hold = takeAudioHold()
        if sessionEnd == nil { sessionEnd = reason }
        dropLongTurn()
        endTranslator()
        stopWatchingAudioInterruptions()
        let active = conversation
        conversation = nil
        pendingAction = nil
        askLedger.clear()
        contactCard = nil
        parkingCard = nil
        outsideContent = OutsideContentSession()
        connectionNeeded = nil
        // A call held for the permission sheet goes with its conversation (ADR-566).
        permissionRequest = nil
        callsAsReceived = [:]
        accountNeeded = nil
        accountMessage = nil
        let endedLive = isLive
        if endedLive { phase = .ended }
        keepLog()
        offerSaveSuggestions()
        // The learning card (ADR-440) after End too, not only when Doddy hangs up: disconnected()
        // offers it, but the startAttempt bump above drops the SDK's disconnect for this conversation
        // (engineering audit, 7 Nov 2026). Only when this stop ended a live conversation, so an End
        // after Doddy already hung up doesn't offer it twice.
        if endedLive {
            offerLearning()
            activity.sessionID = nil
        }
        await active?.endConversation()
        ConversationAudioSession.release(hold)
        // Prepare the next tap while Home is idle; never open another room or microphone here.
        VoiceTokenWarmer.shared.warmIfDue()
    }

    /// Stop listening from Siri or the indicator (OP-024, ADR-361): ends the conversation like End,
    /// but keeps a "Save this note?" card that was showing as a draft. True when it kept one.
    func stopListening() async -> Bool {
        if sessionEnd == nil { sessionEnd = .stoppedListening }
        keepRecoveryDraft()
        await stop(.stoppedListening)
        return recovery != nil
    }

    /// Keeps the transcript lines of this conversation on the phone, once, so the next
    /// conversation can continue from it. Nothing is kept when there were no lines, when the
    /// user switched "Remember recent conversations" off, or when this conversation is private.
    private func keepLog() {
        logUnanswered()
        guard let startedAt else { return }
        self.startedAt = nil
        let kept = lines.map { ConversationLog.Line(fromUser: $0.fromUser, text: $0.text) }
        let log = ConversationLog(startedAt: startedAt, endedAt: Date(), lines: kept, voiceProvider: "elevenlabs", ended: sessionEnd?.code)
        // Doddy's server keeps it as text for a year, only if the person turned that on in Settings › Doddy on
        // the web, and never a private conversation (ADR-603). That is separate from what this iPhone remembers.
        let isPrivate = self.isPrivate
        Task { await WebMemory.shared.sendConversation(log, language: WebMemory.language(), isPrivate: isPrivate) }
        // Logbook (ADR-602): its times, how it ended and its language, never its words; not a private one.
        Logbook.conversationEnded(startedAt: log.startedAt, endedAt: log.endedAt, ended: log.ended,
                                  language: WebMemory.language(), isPrivate: isPrivate)
        // A recap note of what was discussed, written on this iPhone, only with "Remember what we talked
        // about" on and never for a Private conversation (decision 2026-11-09-conversation-recaps).
        let recapLines = kept.map { RecapModelIO.Line(speaker: $0.fromUser ? .person : .doddy, text: $0.text) }
        let memories = store
        Task { await RecapKeeper.recapConversation(lines: recapLines, startedAt: log.startedAt, endedAt: log.endedAt,
                                                   isPrivate: isPrivate, conversationID: log.id, store: memories) }
        guard ConversationRetention.shouldKeep(rememberRecent: logs.isEnabled, isPrivate: isPrivate, lineCount: lines.count) else { return }
        logs.append(log)
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
        // During "Listen until I finish" the microphone stays muted until Done or Cancel.
        guard let conversation, longTurn == .off else { return }
        do {
            try await conversation.setMuted(!isMuted)
            isMuted.toggle()
        } catch {
            // Keep the previous state; the UI shows what is actually set.
        }
    }

    // MARK: Listen until I finish (OP-019, ADR-364)

    /// Mutes the conversation so the voice service hears nothing and can't end the turn, and
    /// records the turn on this iPhone until Done.
    func startLongTurn() async {
        guard isLive, let conversation, longTurn == .off, translator == nil else { return }
        mutedBeforeLongTurn = isMuted
        if !isMuted {
            do { try await conversation.setMuted(true) } catch {
                longTurn = .draft(LongTurn.draft(for: .recordingFailed))
                return
            }
            isMuted = true
        }
        guard longTurnRecorder.start() else {
            await restoreMuteAfterLongTurn()
            longTurn = .draft(LongTurn.draft(for: .recordingFailed))
            return
        }
        longTurn = .listening(since: Date())
        // At the limit it finishes as if Done was tapped.
        longTurnLimit = Task { [weak self] in
            try? await Task.sleep(for: .seconds(LongTurn.maxSeconds))
            guard !Task.isCancelled else { return }
            await self?.finishLongTurn()
        }
    }

    /// Done: the user has finished. Written out on this iPhone, then only the words are sent.
    func finishLongTurn() async {
        guard longTurn.isListening else { return }
        longTurnLimit?.cancel()
        longTurnLimit = nil
        guard let file = longTurnRecorder.stop() else {
            await restoreMuteAfterLongTurn()
            longTurn = .draft(LongTurn.draft(for: .recordingFailed))
            return
        }
        guard file.seconds >= LongTurn.minSeconds else {
            try? FileManager.default.removeItem(at: file.url)
            await restoreMuteAfterLongTurn()
            longTurn = .draft(LongTurn.draft(for: .tooShort))
            return
        }
        longTurnFile = file.url
        await writeOutLongTurn()
    }

    /// Cancel while listening: the recording is deleted and nothing is sent.
    func cancelLongTurn() async {
        guard longTurn.isListening else { return }
        dropLongTurn()
        await restoreMuteAfterLongTurn()
    }

    /// Try again on a draft: writes the recording out again, or sends the text it holds.
    func retryLongTurn() async {
        guard case .draft(let draft) = longTurn else { return }
        if !draft.text.allSatisfy(\.isWhitespace) {
            await sendLongTurn(draft.text)
        } else if draft.canWriteOutAgain, longTurnFile != nil {
            await writeOutLongTurn()
        }
    }

    func editLongTurn(_ text: String) {
        guard case .draft(var draft) = longTurn else { return }
        draft.text = text
        longTurn = .draft(draft)
    }

    /// Discard on a draft: the recording and the text go; nothing is sent.
    func discardLongTurn() async {
        guard case .draft = longTurn else { return }
        dropLongTurn()
        await restoreMuteAfterLongTurn()
    }

    private func writeOutLongTurn() async {
        guard let file = longTurnFile else { return }
        longTurn = .writingOut
        let available = VoiceMemoTranscriber.languages().map(\.identifier)
        guard let identifier = LongTurn.locale(conversationCode: ConversationLanguage.stored().overrideCode, onDevice: available) else {
            await draftLongTurn(LongTurn.draft(for: .notOnDevice))
            return
        }
        switch await VoiceMemoTranscriber.transcribe(file, locale: Locale(identifier: identifier)) {
        case .text(let result):
            if let message = LongTurn.message(result.text) {
                await sendLongTurn(message)
            } else {
                await draftLongTurn(LongTurn.draft(for: .nothingHeard))
            }
        case .noSpeech: await draftLongTurn(LongTurn.draft(for: .nothingHeard))
        case .notOnDevice: await draftLongTurn(LongTurn.draft(for: .notOnDevice))
        case .notAllowed: await draftLongTurn(LongTurn.draft(for: .notAllowed))
        case .failed: await draftLongTurn(LongTurn.draft(for: .writeOutFailed))
        }
    }

    /// The words go as one message, shown as the user's line; then the recording is deleted.
    private func sendLongTurn(_ text: String) async {
        guard let message = LongTurn.message(text) else {
            await draftLongTurn(LongTurn.draft(for: .nothingHeard))
            return
        }
        guard isLive, let conversation else {
            await draftLongTurn(LongTurn.draft(for: .couldNotSend, text: message))
            return
        }
        do {
            try await conversation.sendMessage(message)
        } catch {
            await draftLongTurn(LongTurn.draft(for: .couldNotSend, text: message))
            return
        }
        lines.append(Line(fromUser: true, text: message))
        dropLongTurn()
        await restoreMuteAfterLongTurn()
    }

    /// Not sent: kept as a draft on the screen, and the microphone goes back to how the user had
    /// it, so the conversation carries on while the draft waits.
    private func draftLongTurn(_ draft: LongTurnDraft) async {
        // A recording that can't be written out again isn't kept a moment longer.
        if !draft.canWriteOutAgain, let file = longTurnFile {
            try? FileManager.default.removeItem(at: file)
            longTurnFile = nil
        }
        longTurn = .draft(draft)
        await restoreMuteAfterLongTurn()
    }

    /// Stops any recording and deletes the file. Used by every way out, the end included.
    private func dropLongTurn() {
        longTurnLimit?.cancel()
        longTurnLimit = nil
        longTurnRecorder.cancel()
        if let file = longTurnFile { try? FileManager.default.removeItem(at: file) }
        longTurnFile = nil
        if longTurn != .off { longTurn = .off }
    }

    /// The microphone goes back to how the user had it before the long turn.
    private func restoreMuteAfterLongTurn() async {
        guard let conversation, isMuted, !mutedBeforeLongTurn else { return }
        if (try? await conversation.setMuted(false)) != nil { isMuted = false }
    }

    /// The user tapped the card's confirm button: Save, Add, Start, Open or Run.
    func confirmPendingAction() async {
        guard let action = pendingAction else { return }
        pendingAction = nil
        // The conversation the card belongs to. The change runs to the end even if the user taps
        // End meanwhile; what it shows on screen after an await is shown only if this one is
        // still on screen (ADR-458).
        let attempt = startAttempt
        // On disk before the change runs: if Doddy is closed mid-way, the next launch shows it
        // as "Not sure" instead of nothing (ActivityLog.recoverInterrupted).
        if action.changesSomething { markStarted(action.toolCallID) }
        switch action {
        case .memory(let id, let text):
            let retry = retryChecks.removeValue(forKey: id)
            // After an unconfirmed try: the note may be saved already (ADR-321). Look, don't save twice.
            if let since = retry?.uncheckedSince, let existing = NoteIdempotency.savedSince(since, text: text, in: store.memories) {
                let result = WriteResult(
                    reply: VoiceToolReply.noteAlreadySaved(existing), receipt: ActivityReceipt(note: existing, readAt: Date()), attempted: false)
                writeResults[id] = result
                await reply(id, result.reply)
            } else {
                do {
                    // rawText is the proposal the user reviewed, not a claimed verbatim transcript.
                    let record = try await store.save(text: text, category: pendingMemoryCategory, source: .explicitVoice)
                    if onScreen(attempt) {
                        pendingMemoryCategory = .other
                        savedThisConversation += 1
                        // Only after the store returned the saved record (ADR-240).
                        flashIsland(.noteSaved)
                    }
                    // What Doddy did can delete it again for a day, if it's left untouched (ADR-277).
                    writeResults[id] = WriteResult(
                        reply: VoiceToolReply.saved(record), receipt: ActivityReceipt(note: record, readAt: Date()), attempted: true,
                        undo: .savedNote(id: record.id, text: record.currentText))
                    await reply(id, VoiceToolReply.saved(record))
                } catch {
                    writeResults[id] = WriteResult(reply: "", attempted: true)
                    await reply(id, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
                }
            }
        case .event(let id, let draft):
            let result = eventResult(addEvent(draft), draft: draft, retry: retryChecks.removeValue(forKey: id))
            writeResults[id] = result
            await reply(id, result.reply)
        case .reminder(let id, let draft):
            // The card is already gone (pendingAction is nil), so a second tap does nothing.
            reminderStatus = .adding(draft)
            let outcome = await addReminder(draft, attempt: attempt)
            if onScreen(attempt) { reminderStatus = .done(draft, outcome) }
            // Undo removes only a reminder Doddy wrote, found by its marker (ADR-268).
            let result = reminderResult(outcome, draft: draft, retry: retryChecks.removeValue(forKey: id))
            writeResults[id] = result
            await reply(id, result.reply)
        case .timer(let id, let draft):
            let result = await timerResult(draft, retry: retryChecks.removeValue(forKey: id))
            writeResults[id] = result
            await reply(id, result.reply)
        case .alarm(let id, let draft):
            let result = await alarmResult(draft, retry: retryChecks.removeValue(forKey: id))
            writeResults[id] = result
            await reply(id, result.reply)
        case .cancelAlarm(let id, let alarm):
            guard isOn(.timers) else {
                connectionNeeded = .timers
                await reply(id, VoiceToolReply.failed("Timers and alarms are switched off. Nothing changed."))
                return
            }
            await reply(id, AlarmScheduler.cancel(alarm.id) ? VoiceToolReply.alarmCancelled(alarm) : VoiceToolReply.alarmCancelUnconfirmed)
        case .map(let id, let trip):
            guard let url = trip.url else {
                await reply(id, VoiceToolReply.notOpened("That place can't be opened in Maps."))
                return
            }
            let opened = await open(url)
            let said = trip.isRoute ? VoiceToolReply.routeOpened(trip) : VoiceToolReply.mapOpened(trip.place)
            await reply(id, opened ? said : VoiceToolReply.notOpened("Maps didn't open."))
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
        case .blik(let id, let draft, let contactName, let numbers):
            // Nothing runs (ADR-510): the details stay on screen and the user sends it in their bank app.
            if onScreen(attempt) { blikCard = BlikCard(draft: draft, contactName: contactName, numbers: numbers) }
            await reply(id, VoiceToolReply.blikShown(draft, contactName: contactName))
        case .presentation(let id, let draft):
            // ADR-567: written on this iPhone and read back; the share sheet hands it to Keynote.
            do {
                let url = try PresentationFiles.write(draft, created: Date())
                // Also kept for a week under "Files Doddy made for you" in Messages. Whatever the screen shows
                // below, and even if the conversation ended meanwhile; Doddy says "in Messages" only when the
                // copy read back complete.
                let inMessages = LocalMadeFilesStore.shared.add(copying: url, title: draft.title, kind: "deck")
                if onScreen(attempt) {
                    presentationReady = PresentationReady(url: url, title: draft.title, slideCount: draft.slideCount)
                    // ADR-616: written and read back, so it is ready; Show opens its card.
                    flashIsland(.resultReady(.presentation))
                }
                await reply(id, VoiceToolReply.presentationMade(draft, inMessages: inMessages))
            } catch {
                await reply(id, VoiceToolReply.presentationFailed(UserFacingError.message(for: error)), isError: true)
            }
        case .home(let id, let command):
            // The tap approved exactly this command (it is the card's own value). Only what HomeKit
            // confirmed is reported as changed; no answer is `unknown` and is never retried here.
            let outcome = await homeKit.run(command)
            let text = VoiceToolReply.home(command, outcome: outcome)
            writeResults[id] = WriteResult(reply: text, attempted: true)
            await reply(id, text, isError: outcome != .confirmed)
        case .camera(let id):
            // ADR-569: the camera opens on this screen; a kept photo goes into a new note.
            if onScreen(attempt) { cameraRequest = UUID() }
            await reply(id, VoiceToolReply.cameraOpened)
        case .ask(let id, _, _, let toolName, _):
            guard askLedger.answer(.tapped, for: id, at: Date()) == .granted else {
                await reply(id, AskFirst.notAsked(toolName))
                return
            }
            await runAsked(action, attempt: attempt)
        case .cloudRead(let id, let call, _, _, _):
            guard askLedger.answer(.tapped, for: id, at: Date()) == .granted else {
                await reply(id, AskFirst.notAsked(call.name))
                return
            }
            await runAsked(action, attempt: attempt)
        case .cloud(let id, let call, _, let approvalID, _):
            retryChecks[id] = nil
            let record = await runConfirmedCloud(call, approvalID: approvalID, app: asked[id]?.app ?? .gmail)
            writeResults[id] = WriteResult(reply: record.reply, receipt: record.receipt, attempted: record.attempted)
            await reply(id, record.reply)
        case .callTask(let id, let preview):
            let outcome = await approveCallTask(preview)
            writeResults[id] = WriteResult(reply: outcome.reply, attempted: outcome.attempted)
            await reply(id, outcome.reply)
        case .callNow(let id, _):
            callPlacing = true
            let outcome = await placeCallNow()
            callPlacing = false
            // Refused means the server answered that nothing was placed; requested or unknown may ring.
            var attempted = true
            if case .refused = outcome { attempted = false }
            writeResults[id] = WriteResult(reply: VoiceToolReply.callNow(outcome), attempted: attempted)
            await reply(id, VoiceToolReply.callNow(outcome))
        case .callLater(let id, let draft, let to, let quietHours):
            callBooking = true
            let result = await bookCall(draft, to: to, quietHours: quietHours, allowQuietHours: callLaterAllowQuiet)
            callBooking = false
            callLaterAllowQuiet = false
            writeResults[id] = WriteResult(reply: result.reply, attempted: result.attempted)
            await reply(id, result.reply)
        case .noteReminder(let id, let memoryID, let noteText, _, let target):
            guard let confirmed = confirmedNoteReminder(memoryID: memoryID, noteText: noteText, target: target) else {
                await reply(id, VoiceToolReply.noteReminderFailed("That place can't be used."))
                return
            }
            // A note has one reminder, so this one replaces any it has (review C3). Read before
            // setting; the card showed it, and the reply names it to the agent.
            let previous = store.noteReminders?.reminder(forMemory: memoryID)
            let receipt = await setNoteReminder(confirmed, attempt: attempt)
            var text = Self.noteReminderReply(receipt, note: noteText, replacing: previous)
            if confirmed.rings, text.hasPrefix("added") {
                // Inserted before the data block, so the note's words stay last.
                let ring = VoiceToolReply.noteReminderRingLine(confirmed: store.noteReminders?.ringing.contains(memoryID) == true)
                if let newline = text.firstIndex(of: "\n") { text.insert(contentsOf: ring, at: newline) } else { text += ring }
            }
            await reply(id, text)
        case .changeEvent(let id, let plan):
            // Kept only if the reply says the change was checked (ActivityEntry).
            await reply(id, changeEvent(plan), undo: .changedEvent(plan))
        case .undo(let id, let entry):
            await reply(id, await undoFromVoice(entry, attempt: attempt))
        case .ingredients(let id, let listID, let listName, let dish, let items, _):
            // Only the ticked ones, through the same add as add_to_list (ADR-305).
            let ticked = items.indices.filter { !ingredientsUnticked.contains($0) }.map { items[$0] }
            let leftOut = items.indices.filter { ingredientsUnticked.contains($0) }.map { items[$0] }
            ingredientsUnticked = []
            ingredientsAtHome = []
            guard !ticked.isEmpty else {
                await reply(id, VoiceToolReply.ingredientsNoneTicked)
                return
            }
            do {
                let result = try await store.addToList(ticked, listID: listID, source: .voice)
                if onScreen(attempt) {
                    listReceipt = ListReceipt(
                        listID: listID, title: result.added.isEmpty ? "Nothing new for \(listName)" : "Added to \(listName)",
                        lines: result.added.map { .added($0.text) } + result.alreadyThere.map { .note("\($0) · already on the list, not added again") },
                        undo: result.added.isEmpty ? nil : store.listUndo)
                }
                let undo: ActivityUndo? = result.added.isEmpty ? nil : .listAdded(listID: listID, list: listName, items: result.added)
                await reply(id, VoiceToolReply.ingredientsAdded(result, list: listName, dish: dish, leftOut: leftOut), undo: undo)
            } catch {
                await reply(id, VoiceToolReply.listFailed(UserFacingError.listMessage(for: error)), isError: true)
            }
        case .leaveBy(let id, let plan):
            // A local notification at the leave time, read back from iOS (ADR-335). Doddy looks for
            // the same one first, so asking again never sets a second (LeaveByActions).
            let outcome = await LeaveBySetAction.set(plan, with: leaveByWriter)
            var result = WriteResult(reply: VoiceToolReply.leaveBy(outcome, plan: plan, calendar: .current), attempted: outcome.attemptedWrite)
            switch outcome {
            case .set(let pending), .alreadySet(let pending):
                result.receipt = ActivityReceipt(leaveBy: pending, plan: plan, calendar: .current, readAt: Date())
            default:
                break
            }
            writeResults[id] = result
            await reply(id, result.reply)
        case .parking(let id, let spot):
            // Kept on this iPhone, then read back (ADR-301).
            let saved = ParkingStore.save(spot)
            // The parking widget (ADR-315) shows when it was saved and the note.
            WidgetSync.shared.refresh()
            await reply(id, saved ? VoiceToolReply.parkingSaved(spot, now: Date(), calendar: .current) : VoiceToolReply.parkingNotSaved)
        case .changeReminder(let id, let reminder, let draft) where draft.changesDetails:
            // A note, priority or list (ADR-302): one save, read back. Undo isn't offered for these.
            await reply(id, changeReminderDetails(reminder, draft))
        case .changeReminder(let id, let reminder, let draft):
            let undo = ActivityUndo.changedReminder(
                id: reminder.id, title: reminder.title, oldDue: reminder.due,
                newDue: draft.markDone ? nil : draft.newDue, markedDone: draft.markDone)
            await reply(id, changeReminder(reminder, draft), undo: undo)
        case .deleteEvent(let id, let event):
            await reply(id, deleteEvent(event))
        case .deleteReminder(let id, let reminder):
            await reply(id, deleteReminder(reminder))
        case .bulk(let id, let items, let verb, let skipped):
            let ticked = items.filter { !bulkUnticked.contains($0.id) }
            bulkUnticked = []
            await reply(id, runBulk(ticked, verb: verb, skipped: skipped))
        case .createList(let id, let name, let items):
            retryChecks[id] = nil
            do {
                let list = try await store.createList(name: name, items: items, source: .voice)
                if onScreen(attempt) {
                    listReceipt = ListReceipt(listID: list.id, title: "New list: \(list.name)", lines: list.items.map { .added($0.text) })
                }
                writeResults[id] = WriteResult(
                    reply: "", receipt: ActivityReceipt(list: list.name, listID: list.id, lines: list.items.map { "Added: \($0.text)" }, readAt: Date()),
                    attempted: true)
                await reply(id, VoiceToolReply.listCreated(list))
            } catch ListError.nameTaken(let taken) {
                // Refused before anything was written.
                writeResults[id] = WriteResult(reply: "", attempted: false)
                await reply(id, VoiceToolReply.listNameTaken(taken))
            } catch {
                writeResults[id] = WriteResult(reply: "", attempted: true)
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

    /// The card's "Ring like an alarm" switch (ADR-651).
    func setNoteReminderRings(_ rings: Bool) {
        guard case .noteReminder(_, _, _, _, .time) = pendingAction else { return }
        noteReminderRings = rings
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
            let canRing = ReminderRinger.isAvailable && ReminderRing.support(repeats: repeats, isPlace: false) == .supported
            return ConfirmedNoteReminder(
                memoryID: memoryID, noteText: noteText, when: .time(date, timeZoneID: zone, repeats: repeats),
                rings: noteReminderRings && canRing)
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
    private func setNoteReminder(_ confirmed: ConfirmedNoteReminder, attempt: Int) async -> NoteReminderReceipt {
        guard let reminders = store.noteReminders, reminders.isAvailable else {
            let receipt = NoteReminderReceipt.failed("Reminders on notes aren't available on this iPhone right now.")
            if onScreen(attempt) { noteReminderStatus = .done(confirmed, receipt) }
            return receipt
        }
        if onScreen(attempt) { noteReminderStatus = .setting(confirmed) }
        // The user just tapped Set reminder, so this is the moment to ask iOS, once.
        if reminders.authorization == .notDetermined { await reminders.requestAuthorization() }
        switch confirmed.when {
        case .time(let date, let zone, let repeats):
            // The card's switch, exactly as shown: on sets the alarm with the reminder, off ends one.
            ReminderRinger.setWish(confirmed.memoryID, rings: confirmed.rings)
            await reminders.set(
                memoryID: confirmed.memoryID, at: date, timeZone: TimeZone(identifier: zone) ?? .autoupdatingCurrent, repeats: repeats)
        case .place(let place):
            if reminders.locationReadiness == .notDetermined { await reminders.requestLocation() }
            await reminders.set(memoryID: confirmed.memoryID, place: place)
        }
        let receipt = reminders.receipts[confirmed.memoryID] ?? .failed("Doddy couldn't set the reminder.")
        // The voice screen shows this receipt; the note screen shouldn't repeat it later.
        reminders.clearReceipt(memoryID: confirmed.memoryID)
        if onScreen(attempt) { noteReminderStatus = .done(confirmed, receipt) }
        return receipt
    }

    private static func noteReminderReply(_ receipt: NoteReminderReceipt, note: String, replacing previous: MemoryReminder?) -> String {
        switch receipt {
        case .scheduled(let reminder): VoiceToolReply.noteReminderSet(reminder, note: note, replacing: previous)
        case .inAppOnly(let reminder): VoiceToolReply.noteReminderInDoddyOnly(reminder, note: note, replacing: previous)
        case .failed(let message), .needsSettings(let message): VoiceToolReply.noteReminderFailed(message)
        }
    }

    /// Try again on a failed receipt: the same reminder the user confirmed, set once more on their
    /// tap. The agent's tool call is already answered, so only the screen shows the new result.
    func retryNoteReminder() async {
        guard case .done(let confirmed, .failed) = noteReminderStatus else { return }
        _ = await setNoteReminder(confirmed, attempt: startAttempt)
    }

    func dismissNoteReminderStatus() {
        guard case .done = noteReminderStatus else { return }
        noteReminderStatus = nil
    }

    /// The user tapped the card's decline button. Nothing changes.
    func declinePendingAction() async {
        guard let action = pendingAction else { return }
        pendingAction = nil
        await settleUnanswered(action, replaced: false)
    }

    /// A card closed without a yes: the user's No, or a newer ask that took its place (owner, 10 Nov
    /// 2026: a card the user couldn't see blocked every later card). Nothing runs either way. When
    /// replaced, the state shared between cards (ticks, the note's type) already belongs to the new
    /// card, so it is left alone.
    private func settleUnanswered(_ action: PendingAction, replaced: Bool) async {
        func answer(_ id: String, _ text: String) async {
            await reply(id, replaced ? VoiceToolReply.replacedByNewerAsk : text)
        }
        switch action {
        case .memory(let id, _):
            if !replaced { pendingMemoryCategory = .other }
            await answer(id, VoiceToolReply.declined)
        case .event(let id, _): await answer(id, VoiceToolReply.declinedEvent)
        case .reminder(let id, _): await answer(id, VoiceToolReply.declinedReminder)
        case .timer(let id, _): await answer(id, VoiceToolReply.declinedTimer)
        case .alarm(let id, _): await answer(id, VoiceToolReply.declinedAlarm)
        case .cancelAlarm(let id, _): await answer(id, VoiceToolReply.alarmCancelDeclined)
        case .map(let id, _): await answer(id, VoiceToolReply.declinedMap)
        case .shortcut(let id, _): await answer(id, VoiceToolReply.declinedShortcut)
        case .message(let id, _, _): await answer(id, VoiceToolReply.declinedMessage)
        case .blik(let id, _, _, _): await answer(id, VoiceToolReply.blikDeclined)
        case .callTask(let id, let preview):
            // Nothing was dialled; the server deletes the places' briefs now instead of when they lapse.
            if let client = Self.messagingClient() { try? await client.cancelCallTask(preview.taskId) }
            await answer(id, VoiceToolReply.callTaskDeclined)
        case .callLater(let id, _, _, _):
            if !replaced { callLaterAllowQuiet = false }
            await answer(id, VoiceToolReply.callDeclined)
        case .callNow(let id, _):
            await answer(id, VoiceToolReply.callNowDeclined)
        case .presentation(let id, _): await answer(id, VoiceToolReply.presentationDeclined)
        case .camera(let id): await answer(id, VoiceToolReply.cameraDeclined)
        case .home(let id, _): await answer(id, VoiceToolReply.homeDeclined)
        case .cloud(let id, let call, _, _, _): await answer(id, VoiceToolReply.cloudDeclined(call.name))
        case .ask(let id, _, _, let toolName, _):
            _ = askLedger.answer(.declined, for: id, at: Date())
            await answer(id, AskFirst.notAsked(toolName))
        case .cloudRead(let id, let call, _, _, _):
            _ = askLedger.answer(.declined, for: id, at: Date())
            await answer(id, AskFirst.notAsked(call.name))
        case .noteReminder(let id, _, _, _, _): await answer(id, VoiceToolReply.declinedNoteReminder)
        case .createList(let id, _, _): await answer(id, VoiceToolReply.declinedList)
        case .changeEvent(let id, _), .changeReminder(let id, _, _): await answer(id, VoiceToolReply.changeDeclined)
        case .deleteEvent(let id, _), .deleteReminder(let id, _): await answer(id, VoiceToolReply.deleteDeclined)
        case .undo(let id, _): await answer(id, VoiceToolReply.undoDeclined)
        case .parking(let id, _): await answer(id, VoiceToolReply.parkingDeclined)
        case .leaveBy(let id, _): await answer(id, VoiceToolReply.leaveByDeclined)
        case .ingredients(let id, _, _, _, _, _):
            if !replaced {
                ingredientsUnticked = []
                ingredientsAtHome = []
            }
            await answer(id, VoiceToolReply.ingredientsDeclined)
        case .bulk(let id, _, _, _):
            if !replaced { bulkUnticked = [] }
            await answer(id, VoiceToolReply.bulkDeclined)
        case .plan(let id, let steps, _):
            askedPlans[id] = nil
            let planID = UUID()
            for step in steps {
                logPlanStep(step, reply: PlanReply.declined, plan: ActivityPlanRef(id: planID, step: step.number, count: steps.count))
            }
            await answer(id, PlanReply.declined)
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

    /// DOD-07, on top of `AskFirst.need(for:)`: once text from outside has reached this conversation, the few tools that
    /// could carry it out of the phone (a text, a file or a question to Claude with material, a look at the screen,
    /// items on a shared list) ask for a tap too, and `make_document` and the first look always do
    /// (`AskFirst.need(for:in:listIsShared:)`). True when it showed that card and the call stops here; false when the
    /// session rule adds nothing, or the user already tapped for exactly this call, and the baseline check follows.
    private func asksBecauseOfOutsideContent(_ call: ClientToolCallEvent, request: VoiceToolRequest) async -> Bool {
        let onSharedList = await targetsSharedList(request)
        let need = AskFirst.need(for: request, in: outsideContent, listIsShared: onSharedList, polish: Self.cardsInPolish)
        guard need != AskFirst.need(for: request, polish: Self.cardsInPolish), case .tapFirst(let card) = need else { return false }
        guard askLedger.mayRun(call.toolCallId, request: request, at: Date()) else {
            askLedger.asked(call.toolCallId, request: request, needsTap: true, at: Date())
            propose(.ask(toolCallID: call.toolCallId, card: card, needsTap: true, toolName: call.toolName, parameters: call.parametersData),
                    toolCallID: call.toolCallId)
            return true
        }
        return false
    }

    /// True when `request` adds to or ticks items on a list that other people are on. Their changes sync to everyone
    /// on the list, so the call asks first unless the user just said the items (`AskFirst.need(for:in:listIsShared:)`).
    /// A list that isn't found, or named by several, changes nothing, so it is not shared for this purpose.
    private func targetsSharedList(_ request: VoiceToolRequest) async -> Bool {
        let name: String
        switch request {
        case .addToList(let list), .checkOff(let list): name = list.list
        default: return false
        }
        await store.reload()
        guard case .one(let list) = ListMatch.list(named: name, in: store.lists) else { return false }
        return SharedListsController.shared.isShared(list.id) != nil
    }

    /// L1: the user asked, so the items go straight on, read back, with a receipt and Undo.
    private func addToList(_ request: ListVoiceRequest, toolCallID: String) async {
        guard await mayTryAgain(toolCallID, app: .memories) else { return }
        guard let list = await resolveList(request.list, toolCallID: toolCallID) else { return }
        // Ended (or ended and started again) while the lists loaded: nothing changes after End
        // (review H9, ADR-458).
        guard isLive, isCurrent(toolCallID) else { return dropStale(toolCallID) }
        markStarted(toolCallID)
        do {
            let result = try await store.addToList(request.items, listID: list.id, source: .voice)
            writeResults[toolCallID] = WriteResult(
                reply: "", receipt: ActivityReceipt(list: list.name, listID: list.id, lines: Self.receiptLines(result), readAt: Date()),
                attempted: true)
            var lines = result.added.map { ListReceipt.Line.added($0.text) }
            lines += result.alreadyThere.map { .note("\($0) · already on the list, not added again") }
            lines += result.tooLong.map { .note("too long to add: \($0.prefix(40))…") }
            lines += result.noRoom.map { .note("\($0) · the list is full") }
            // Shopping list+ (ADR-631): added anyway, but the At home list has them open.
            let home = homeList
            let atHome = HomeStock.onHomeList(result.added.map(\.text), home: home, addingTo: list.id)
            lines += atHome.map { .note("\($0) · on your At home list") }
            // The write ran; its receipt only shows on its own conversation's screen (ADR-458).
            if isCurrent(toolCallID) {
                listReceipt = ListReceipt(
                    listID: list.id, title: result.added.isEmpty ? "Nothing new for \(list.name)" : "Added to \(list.name)",
                    lines: lines, undo: result.added.isEmpty ? nil : store.listUndo)
            }
            // What Doddy did can undo it for a day (ADR-276); kept only when something was added.
            let undo: ActivityUndo? = result.added.isEmpty ? nil : .listAdded(listID: list.id, list: list.name, items: result.added)
            await reply(toolCallID, VoiceToolReply.listAdded(result, list: list.name)
                + VoiceToolReply.onHomeList(atHome, home: home?.name ?? ""), undo: undo)
        } catch {
            writeResults[toolCallID] = WriteResult(reply: "", attempted: true)
            await reply(toolCallID, VoiceToolReply.listFailed(UserFacingError.listMessage(for: error)), isError: true)
        }
    }

    /// What the list's own result says, for the receipt in What Doddy did (ADR-321).
    private static func receiptLines(_ result: ListAddResult) -> [String] {
        result.added.map { "Added: \($0.text)" } + result.alreadyThere.map { "Already on the list: \($0)" }
            + result.tooLong.map { "Too long: \($0.prefix(40))" } + result.noRoom.map { "No room: \($0)" }
    }

    private func readList(_ name: String, toolCallID: String) async {
        guard let list = await resolveList(name, toolCallID: toolCallID) else { return }
        guard isCurrent(toolCallID) else { return dropStale(toolCallID) }
        listReceipt = ListReceipt(listID: list.id, title: "\(list.name) · \(list.summary)", lines: list.open.map { .open($0.text) })
        await reply(toolCallID, VoiceToolReply.listRead(list))
    }

    /// Ticks or removes only clear matches; items that match several are offered to tap.
    private func changeList(_ request: ListVoiceRequest, tick: Bool, toolCallID: String) async {
        guard await mayTryAgain(toolCallID, app: .memories) else { return }
        guard let list = await resolveList(request.list, toolCallID: toolCallID) else { return }
        // Ended (or ended and started again) while the lists loaded: nothing changes after End
        // (review H9, ADR-458).
        guard isLive, isCurrent(toolCallID) else { return dropStale(toolCallID) }
        let pool = tick ? list.open : list.items
        var matched: [ListItem] = [], notFound: [String] = [], ambiguous: [(said: String, options: [ListItem])] = []
        for phrase in request.items {
            // Removing takes exact matches only (review C9): "remove milk" offers "oat milk" to
            // tap instead of deleting it. Ticking keeps partial matches.
            switch ListMatch.item(phrase, in: pool, partial: tick) {
            case .one(let item): if !matched.contains(item) { matched.append(item) }
            case .none: notFound.append(phrase)
            case .several(let options): ambiguous.append((said: phrase, options: options))
            }
        }
        do {
            var changed: [ListItem] = []
            if !matched.isEmpty {
                markStarted(toolCallID)
                if tick {
                    changed = try await store.setDone(matched, done: true, listID: list.id)
                } else {
                    changed = try await store.removeFromList(matched, listID: list.id)
                }
            }
            let verb = tick ? "ticked" : "removed"
            if isCurrent(toolCallID) {
                listReceipt = ListReceipt(
                    listID: list.id, title: "\(tick ? "Ticked on" : "Removed from") \(list.name)",
                    lines: changed.map { tick ? .ticked($0.text) : .removed($0.text) } + notFound.map { .note("not on the list: \($0)") },
                    undo: changed.isEmpty ? nil : store.listUndo,
                    choices: ambiguous.first.map { ListReceipt.Choices(said: $0.said, options: $0.options, tick: tick) })
            }
            let undo: ActivityUndo? = changed.isEmpty ? nil
                : tick ? .listTicked(listID: list.id, list: list.name, items: changed)
                : .listRemoved(listID: list.id, list: list.name, items: changed)
            writeResults[toolCallID] = WriteResult(
                reply: "",
                receipt: ActivityReceipt(
                    list: list.name, listID: list.id, lines: changed.map { "\(tick ? "Ticked" : "Removed"): \($0.text)" }, readAt: Date()),
                attempted: !matched.isEmpty)
            await reply(toolCallID, VoiceToolReply.listChanged(verb: verb, changed: changed, list: list.name, notFound: notFound, ambiguous: ambiguous), undo: undo)
        } catch {
            writeResults[toolCallID] = WriteResult(reply: "", attempted: true)
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
        } catch let error as ListUndoError {
            // The undo ran but didn't take everything back (review C10): say exactly what it
            // did, and don't offer it again, since running it twice could repeat what came back.
            receipt.undo = nil
            receipt.problem = error.message
            listReceipt = receipt
        } catch {
            receipt.problem = "Couldn't undo. " + UserFacingError.listMessage(for: error)
            listReceipt = receipt
        }
    }

    func dismissListReceipt() {
        listReceipt = nil
    }

    func dismissBlikCard() {
        blikCard = nil
    }

    func dismissLostWalletCard() {
        lostWalletCard = nil
    }

    /// The person's own tick (ADR-692): it records only that they said they did the step.
    func toggleLostWalletStep(_ id: LostWalletStepID) {
        guard var card = lostWalletCard, card.steps.contains(where: { $0.id == id }) else { return }
        if card.done.contains(id) { card.done.remove(id) } else { card.done.insert(id) }
        lostWalletCard = card
    }

    /// The step's official page or number, on the person's tap. Only what DoddyCore allows opens.
    func openLostWalletStep(_ step: LostWalletStep) {
        guard let action = step.action, LostWalletPlan.isAllowed(action), let url = action.url else { return }
        Task { _ = await open(url) }
    }

    /// The user tapped Confirm next to a value only the model suggested (ADR-677): the NIP or a
    /// line's VAT rate, exactly as the card showed it.
    func confirmInvoiceSuggestion(_ field: InvoiceField) {
        guard invoiceSession.confirmSuggested(field) else { return }
        Self.invoiceDraftFile?.save(invoiceSession)
    }

    /// The user closed the invoice card: the draft is gone from the screen and from this iPhone;
    /// nothing was sent anywhere.
    func dismissInvoiceDraft() {
        invoiceSession.close()
        Self.invoiceDraftFile?.remove()
    }

    /// The draft kept from an earlier conversation (ADR-678), with a default issue date moved to today.
    private func restoreInvoiceDraft() {
        invoiceSession = InvoiceVoiceSession()
        guard let file = Self.invoiceDraftFile else { return }
        switch file.load() {
        case .none: break
        case .setAside: invoiceDraftWasSetAside = true
        case .draft(var kept):
            if let today = CalendarDate.day(of: Date(), in: .current), kept.refreshDefaults(today: today) { file.save(kept) }
            invoiceSession = kept
        }
    }

    /// The VAT register from this iPhone, then CEIDG through Doddy's server when the register has no
    /// such taxpayer or couldn't be asked (ADR-685, `CompanyLookup.combined`).
    private static func lookUpCompany(_ nip: Nip, on day: CalendarDate) async -> CompanyLookup {
        let vat = await VatRegisterClient.shared.lookup(nip, on: day)
        guard vat.asksCeidgToo, let server = ServerConfig.client() else { return vat }
        return CompanyLookup.combined(vat: vat, ceidg: await server.lookupCeidg(nip, on: day))
    }

    /// Application Support/Invoices/invoice-draft.json; a new file for each UI-test launch.
    static let invoiceDraftFile: InvoiceDraftFile? = ProcessInfo.processInfo.arguments.contains("-inMemoryStore")
        ? InvoiceDraftFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("invoice-draft-\(UUID().uuidString).json"))
        : InvoiceDraftFile.inApplicationSupport()

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

    /// A translator start from a shared-context conversation needs a fresh private session (review H3).
    var translatorStartsNewConversation: Bool {
        sharedOwnerContext && startedMode != nil
    }

    private func startTranslator(_ setup: TranslatorSetup, toolCallID: String) async {
        // Already translating (a start from Home, then the agent asking again): nothing changes.
        if let current = translator {
            await reply(toolCallID, VoiceToolReply.translatorAlreadyOn(current.setup))
            return
        }
        // Do not carry this conversation's notes, profile or lists into translation (review H3).
        if translatorStartsNewConversation, let mode = startedMode {
            isPrivate = true
            await reply(toolCallID, "stopped: translator mode starts in a new conversation that has none of the user's notes, profile or lists. This conversation ends now; say nothing more.")
            await stop()
            await start(mode, profile: .empty, translator: setup)
            return
        }
        beginTranslator(setup)
        await reply(toolCallID, VoiceToolReply.translatorStarted(setup))
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
        // This iPhone only (no Universal Clipboard), and gone from the clipboard when the five
        // minutes end, like the text itself (review H10).
        UIPasteboard.general.setItems(
            [["public.utf8-plain-text": summary.transcript]],
            options: [.localOnly: true, .expirationDate: summary.expiresAt])
        return true
    }

    /// Copy from the BLIK card (ADR-510): a phone number or the title, to paste in the bank app.
    /// This iPhone only (no Universal Clipboard), and gone from the clipboard after ten minutes.
    func copyForBlik(_ text: String) {
        UIPasteboard.general.setItems(
            [["public.utf8-plain-text": text]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(600)])
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
    /// (LiveKit's local volume for the agent's track); the provider
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
        // A step the user had to change is a correction (ADR-440).
        store.learning?.recordChangedStep(tool: step.toolName, requestID: "\(id)-\(step.number)", sessionID: conversationID)
        pendingAction = .plan(toolCallID: id, steps: steps, blocked: blocked)
    }

    func dismissPlanStatus() {
        guard planStatus?.isRunning == false else { return }
        planStatus = nil
    }

    func dismissContactCard() {
        contactCard = nil
    }

    func dismissParkingCard() {
        parkingCard = nil
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
        // ADR-617: the island speaks the language of Doddy's screens (Polish by default), which the
        // widget extension can't read for itself.
        state.language = Bundle.main.preferredLocalizations.first
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
        // ADR-616: every other card has its kind on the island (it was the bare "Confirm in Doddy").
        case .some(let action): return .actionWaiting(Self.islandAction(action))
        case nil: break
        }
        // ADR-616: an iPhone permission, a function that is off, or an account to connect.
        if permissionRequest != nil || accessRequest != nil { return .actionWaiting(.access) }
        if accountNeeded != nil { return .actionWaiting(.signIn) }
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

    /// The island's word for a card (ADR-616): its kind only, never what it says.
    private static func islandAction(_ action: PendingAction) -> IslandAction {
        switch action {
        case .message(_, let draft, _): return draft.channel == .email ? .email : .text
        case .blik: return .transfer
        case .event, .changeEvent, .deleteEvent: return .calendar
        case .reminder, .noteReminder, .changeReminder, .deleteReminder: return .reminder
        case .timer, .alarm, .cancelAlarm: return .alarm
        case .map, .leaveBy: return .map
        case .shortcut: return .shortcut
        case .camera: return .camera
        case .presentation: return .presentation
        case .createList, .ingredients: return .list
        case .cloud(_, let call, _, _, _):
            let name = call.name.lowercased()
            return name.contains("gmail") || name.contains("outlook") || name.contains("mail") ? .email : .onlineApp
        // A spoken yes answers a read only (ADR-483); an ask that needs a tap (ADR-716) says nothing of "yes".
        case .ask(_, _, let needsTap, _, _): return needsTap ? .other : .askFirst
        case .cloudRead: return .askFirst
        // A call booked for later (ADR-754): the island says only that something waits for a tap.
        case .memory, .plan, .bulk, .undo, .parking, .home, .callLater, .callNow, .callTask: return .other
        }
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

    /// Opens the island up for a moment when Doddy starts speaking, when `IslandExpansion` says
    /// it's due (ADR-577): his first words, then the start of each answer, while Doddy isn't the
    /// app on screen. Not while translating: he speaks after every phrase there.
    private func expandIslandIfDue() {
        guard ownsIsland, translator == nil else { return }
        let onScreen = UIApplication.shared.applicationState == .active
        if islandExpansion.doddyStartedSpeaking(at: Date(), appOnScreen: onScreen) { island.expand() }
    }

    /// ADR-616: a card arrived; `IslandExpansion` says whether the island opens up for it.
    private func expandIslandForCard() {
        guard ownsIsland, translator == nil else { return }
        let onScreen = UIApplication.shared.applicationState == .active
        if islandExpansion.cardArrived(at: Date(), appOnScreen: onScreen) { island.expand() }
    }

    /// Listens to how loud Doddy's voice is while he talks, for Home's island extension (ADR-655):
    /// attached the first time he speaks (that is when his audio track exists), let go when the
    /// conversation is over. A provider without such a track attaches nothing.
    private func updateVoiceMeter() {
        if phase == .speaking, meteredConversation == nil, let conversation {
            if conversation.attachAgentLevelMeter(AgentVoiceMeter.shared) { meteredConversation = conversation }
            AgentVoiceMeter.shared.markAttached(meteredConversation != nil)
        } else if !isLive, let metered = meteredConversation {
            // Let go of the conversation it was attached to: stop() and a drop clear `conversation`
            // before the phase changes, so detaching from `conversation` did nothing (ADR-672).
            metered.detachAgentLevelMeter(AgentVoiceMeter.shared)
            meteredConversation = nil
            AgentVoiceMeter.shared.reset()
        }
    }

    private func syncIsland() {
        if let state = islandState {
            ownsIsland = true
            island.show(state, startedAt: startedAt ?? .now)
            return
        }
        // Only a conversation that showed itself on the island ends it.
        guard ownsIsland else { return }
        ownsIsland = false
        switch phase {
        case .ended:
            island.finish(savedCount: savedThisConversation)
        case .failed:
            // It couldn't start or the connection dropped: the Lock Screen says so for a moment,
            // with Open Doddy, instead of the island just vanishing (ADR-579).
            island.finishFailed(savedCount: savedThisConversation)
        default:
            island.end()
        }
    }

    // MARK: Events

    /// The person spoke over Doddy: nothing is waited on, and a held "Working on it…" goes back to
    /// what the provider said (it may have said listening before this ran).
    private func turnInterrupted() {
        turnFeedback.reset()
        if isLive, phase == .thinking, providerState == .listening { phase = .listening }
    }

    private func apply(_ state: ElevenLabs.AgentState) {
        guard isLive else { return }
        providerState = state
        switch state {
        case .listening:
            // The SDK says listening as soon as a tool answers, while the model is still writing the
            // answer to it: keep "Working on it…" for a few seconds unless Doddy speaks first
            // (decision 2026-11-12-voice-turn-feedback).
            let held = turnFeedback.holdsThinking { [weak self] in
                guard let self, self.isLive, self.phase == .thinking, self.providerState == .listening else { return }
                self.phase = .listening
            }
            phase = held ? .thinking : .listening
        case .speaking:
            turnFeedback.agentStartedSpeaking()
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
            }
            return
        }
        lines.append(Line(fromUser: fromUser, text: text))
        // The user's own words (not Doddy's, not a tool's): what a tool that works on their list may be matched to.
        if fromUser { outsideContent.userSaid(text) }
        // The island opens up again when Doddy starts answering this (ADR-577).
        if fromUser { islandExpansion.userSpoke() }
        if !fromUser, checkInNeedsBriefing {
            checkInNeedsBriefing = false
            Task { await sendToAgent("Morning check-in: give the briefing now, as the morning check-in section says.") }
        }
        // Only if the user hasn't already spoken: then their own request comes first, no tour.
        if !fromUser, firstConversationNeedsTour {
            firstConversationNeedsTour = false
            Task { await sendToAgent(FirstConversationPrompt.appMessage) }
        }
        if fromUser { firstConversationNeedsTour = false }
        if fromUser { Task { await spokenAnswer(text) } }
        if !fromUser, let question = noteQuestion {
            noteQuestion = nil
            Task { await sendToAgent(question) }
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
        let wasLive = isLive
        if sessionEnd == nil { sessionEnd = .dropped(isOffline ? .offline : .error(message)) }
        stopWatchingAudioInterruptions()
        keepRecoveryDraft()
        phase = .failed(message)
        pendingAction = nil
        dropLongTurn()
        // The lines and unanswered cards are kept now, not only at the next Close (ADR-360).
        keepLog()
        // After an error the SDK may keep the microphone (review H2), so the conversation is
        // ended here as stop() does, instead of waiting for a disconnect that may not come.
        let hold = takeAudioHold()
        if let active = conversation {
            conversation = nil
            endTranslator()
            Task {
                await active.endConversation()
                ConversationAudioSession.release(hold)
            }
        } else {
            ConversationAudioSession.release(hold)
        }
        // As after a drop by disconnect: "Worth keeping?" once Doddy had been listening.
        if wasLive { offerSaveSuggestions() }
    }

    private func disconnected(_ kind: VoiceSessionEnd.Disconnect) {
        if sessionEnd == nil { sessionEnd = VoiceSessionEnd.afterDisconnect(kind, userAsked: userAskedToEnd) }
        let wasLive = isLive
        dropLongTurn()
        endTranslator()
        stopWatchingAudioInterruptions()
        conversation = nil
        ConversationAudioSession.release(takeAudioHold())
        if wasLive { keepRecoveryDraft() }
        pendingAction = nil
        keepLog()
        if case .failed = phase { return }
        // A drop is never shown as a normal end (ADR-360).
        if let end = sessionEnd, end.isDrop, wasLive {
            phase = .failed(SessionRecovery.status(end, connected: connectedOnce, language: .current).detail ?? "")
            offerSaveSuggestions()
            return
        }
        phase = .ended
        offerSaveSuggestions()
        offerLearning()
        activity.sessionID = nil
    }

    // MARK: End-of-conversation learning card (ADR-440)

    /// At most one "I noticed…" card, from sentences the "Worth keeping?" card did not already
    /// offer and from tools repeated on three separate days. Only when learning is on, never for
    /// a private conversation, never while connections are paused (the service checks all three).
    private func offerLearning() {
        guard let learning = store.learning, phase == .ended else { return }
        let alreadyOnNoteCard = Set(saveSuggestions?.items.map(\.suggestion.text) ?? [])
        let pool = SaveSuggestions.suggest(
            userLines: lines.filter(\.fromUser).map(\.text), alreadyProposed: proposedNoteTexts,
            existingNotes: store.memories, max: 8)
        let leftover = pool.filter { !alreadyOnNoteCard.contains($0.text) }
        let wasPrivate = isPrivate
        Task { await learning.proposeAfterConversation(leftover: leftover, isPrivate: wasPrivate) }
    }

    // MARK: Session recovery (OP-023, ADR-360)

    /// How this conversation ended; nil while it runs.
    private(set) var sessionEnd: VoiceSessionEnd?
    /// After a drop: what Doddy last heard and hadn't answered, and the note it was asking about.
    /// On this screen only, never written anywhere; it becomes a note only on Save.
    private(set) var recovery: RecoveryDraft?
    /// The note saved from the draft, as read back.
    private(set) var recoverySaved: String?
    /// Set by End, Close or the island; a disconnect after it is the user's end, not a drop.
    private var userAskedToEnd = false
    /// True once Doddy was ready to listen, so a later stop is a drop, not "Couldn't connect".
    private var connectedOnce = false

    /// What Home says when this conversation connected and then dropped (ADR-687); nil while it
    /// runs, after any other end, and when it never connected.
    var homeDropNotice: HomeDropNotice? {
        guard case .failed = phase, let end = sessionEnd else { return nil }
        return SessionRecovery.homeNotice(end, connected: connectedOnce, language: .current)
    }

    /// The title for how it ended: "The conversation dropped", "Couldn't connect"…
    var endTitle: String? {
        sessionEnd.map { SessionRecovery.status($0, connected: connectedOnce, language: .current).title }
    }

    private func keepRecoveryDraft() {
        guard let end = sessionEnd, connectedOnce, recovery == nil else { return }
        let pendingNote: String? = if case .memory(_, let text) = pendingAction { text } else { nil }
        recovery = SessionRecovery.draft(
            lines: lines.map { ConversationLog.Line(fromUser: $0.fromUser, text: $0.text) },
            pendingNote: pendingNote, end: end, endedAt: Date())
    }

    func editRecovery(_ text: String) {
        recovery?.text = text
    }

    /// Saves the draft as a note, only now that the user tapped Save; read back by the store.
    /// Returns what went wrong, or nil.
    func saveRecovery() async -> String? {
        guard let text = recovery?.text else { return nil }
        do {
            try MemoryTextValidator.validate(text)
            let record = try await store.save(text: text, category: .other, source: .explicitVoice)
            guard store.record(id: record.id) != nil else { return NSLocalizedString("The note couldn't be confirmed. Check your notes.", comment: "") }
            recoverySaved = record.currentText
            recovery = nil
            return nil
        } catch {
            return UserFacingError.message(for: error)
        }
    }

    func discardRecovery() {
        recovery = nil
    }

    // MARK: End-of-conversation save suggestions (ADR-247)

    /// Picks what the user said that may be worth keeping, on the phone, from their own lines only.
    /// Not for a private conversation, not when switched off, not when notes can't be saved.
    private func offerSaveSuggestions() {
        // After an end, and after a drop once Doddy had been listening (ADR-360).
        let dropped = sessionEnd?.isDrop == true && connectedOnce
        guard !suggestionsOffered, phase == .ended || dropped else { return }
        suggestionsOffered = true
        guard !isPrivate, store.isStorageAvailable,
              UserDefaults.standard.object(forKey: PreferenceKey.suggestSavesAfterConversation) as? Bool ?? true
        else { return }
        let found = SaveSuggestions.suggest(
            userLines: lines.filter(\.fromUser).map(\.text),
            // What the recovery draft already offers isn't offered twice.
            alreadyProposed: proposedNoteTexts + (recovery.map { $0.unanswered + [$0.pendingNote].compactMap { $0 } } ?? []),
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

    /// `attempt` is the start the call arrived in. From here on every card, screen change and
    /// result checks it (ADR-458): `propose` and `reply` for all of them, and the places below that
    /// change the screen or a list after an `await`.
    private func handle(_ call: ClientToolCallEvent, attempt: Int) async {
        // A call still queued when the user tapped End runs nothing (review H9).
        guard isLive, attempt == startAttempt else { return }
        callOwners.record(call.toolCallId, attempt: attempt)
        callsAsReceived[call.toolCallId] = (call.toolName, call.parametersData)
        turnFeedback.toolStarted(id: call.toolCallId, name: call.toolName)
        let request = VoiceToolRequest.parse(name: call.toolName, parametersJSON: call.parametersData)
        // The release scope (decision 2026-11-07-release-scope), translator (ADR-215), plan, Pause all, then the tool's switch,
        // in that order (ToolGate).
        let gate = ToolGate.decide(
            toolName: call.toolName, request: request, translatorOn: translator != nil,
            pauseAll: UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey), isOn: { isOn($0) },
            scope: ReleaseScopeStore.current)
        switch gate {
        case .hidden:
            // A feature this build hides: nothing runs, nothing is logged; the agent says it isn't in the app.
            await reply(call.toolCallId, VoiceToolReply.hidden(call.toolName))
            return
        case .translatorRefused:
            // Checked before anything is looked up or logged.
            await reply(call.toolCallId, VoiceToolReply.translatorRefused(call.toolName))
            return
        case .plan:
            await handlePlan(call)
            return
        case .paused, .notConnected, .run:
            break
        }
        asked[call.toolCallId] = ActivityRequest.describe(request, calendar: .current)?.naming(call.toolName)
        switch gate {
        case .paused:
            // Settings → Pause all: no other app or account is used; notes still work.
            await reply(call.toolCallId, ConnectionPause.reply)
            return
        case .notConnected(let connection):
            await notConnected(call.toolCallId, connection)
            return
        case .hidden, .translatorRefused, .plan, .run:
            break
        }
        // Decision 2026-11-09-doddy-looks-at-the-screen: without a fresh picture of the shared screen there is
        // nothing to ask about. If sharing is off, iOS's own "Start Broadcast" sheet is opened (it reads nothing;
        // iOS asks the person itself), and the agent tells them to tap it and ask again.
        if case .lookAtScreen = request {
            let readiness = ScreenShareFiles.current().readiness
            if var notReady = ScreenLookSpeech.notReady(readiness) {
                if readiness == .notSharing, ScreenSharePicker.present() { notReady += " " + ScreenLookSpeech.sheetOpened }
                await reply(call.toolCallId, notReady)
                return
            }
        }
        // ASK-01 (ADR-483) as it stands since 11 Nov 2026: a change with no card of its own waits here for the
        // user's tap for exactly this call. Tools with a payload card of their own (and the server's writes)
        // ask through that card. What the user asked to see or start of their own runs at once (`.runsNow`).
        if await asksBecauseOfOutsideContent(call, request: request) { return }
        switch AskFirst.need(for: request, polish: Self.cardsInPolish) {
        case .yesFirst(let card), .tapFirst(let card):
            guard askLedger.mayRun(call.toolCallId, request: request, at: Date()) else {
                let needsTap = AskFirst.needsTap(AskFirst.need(for: request))
                askLedger.asked(call.toolCallId, request: request, needsTap: needsTap, at: Date())
                propose(.ask(toolCallID: call.toolCallId, card: card, needsTap: needsTap, toolName: call.toolName, parameters: call.parametersData),
                        toolCallID: call.toolCallId)
                return
            }
        case .nothingRuns, .ownPayloadCard, .serverCard, .runsNow:
            // .runsNow: a public lookup (ADR-575), a look at the user's own things or one of Doddy's own small
            // actions (decision 2026-11-11-asked-for-runs-at-once) runs at once.
            break
        }
        // From here the tool runs. One that brings in text from outside marks the conversation before its result can
        // reach the agent; a look at the screen that runs here was tapped for, or follows one that was.
        if AskFirst.need(for: request) != .nothingRuns { outsideContent.noteRun(of: call.toolName) }
        switch request {
        case .searchMemories(let query):
            // "#car": exactly the notes with that tag (ADR-333). Private notes stay out.
            if let tag = NoteTags.tagQuery(query) {
                // Startup no longer loads the whole screen store. A tagged read is on demand.
                await store.reload()
                guard isCurrent(call.toolCallId) else { return }
                guard store.loadError == nil else {
                    await reply(call.toolCallId, VoiceToolReply.failed(store.loadError ?? "Saved notes could not be read."), isError: true)
                    return
                }
                let notes = NoteTags.filter(PrivateNotesStore.current().shareable(store.memories), tag: tag)
                await reply(call.toolCallId, VoiceToolReply.taggedNotes(tag, notes: notes))
                return
            }
            do {
                let recall = ShareableRecallService(base: store.environment.recallService) { PrivateNotesStore.current().ids }
                let outcome = try await recall.recall(query, limit: 20)
                // No word matched: the newest notes too, e.g. one saved during this call.
                let newest = outcome == .noMatch ? await store.newestNotesForVoice(excluding: PrivateNotesStore.current().ids) : .none
                let currentPrivacy = PrivateNotesStore.current()
                let shareableNewest = NewestNotes.pick(newest.notes, excluding: currentPrivacy.ids, withPhoto: newest.withPhoto)
                await reply(call.toolCallId, VoiceToolReply.search(currentPrivacy.shareable(outcome), question: query, newest: shareableNewest))
            } catch {
                await reply(call.toolCallId, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
            }
        case .saveMemory(let text):
            // Nothing is stored until the user taps Save on the card.
            guard await mayTryAgain(call.toolCallId, app: .memories) else { return }
            proposedNoteTexts.append(text)
            pendingMemoryCategory = .other
            propose(.memory(toolCallID: call.toolCallId, text: text), toolCallID: call.toolCallId)
        case .readCalendar(let range):
            guard devices.access(for: .calendar) == .granted else {
                await notConnected(call.toolCallId, .calendar)
                return
            }
            let events = await devices.readEvents(in: range)
            await reply(call.toolCallId, VoiceToolReply.calendarEvents(events, range: range, calendar: .current))
        case .findFreeTime(let request):
            // Read-only (ADR-332): gaps worked out here from the iPhone's calendars.
            guard devices.access(for: .calendar) == .granted else {
                await notConnected(call.toolCallId, .calendar)
                return
            }
            let events = await devices.readEvents(in: request.range(calendar: .current))
            let days = FreeTime.days(request, events: events, now: Date(), calendar: .current)
            await reply(call.toolCallId, VoiceToolReply.freeTime(days, request: request, calendar: .current))
        case .createCalendarEvent(let draft):
            guard await mayTryAgain(call.toolCallId, app: .calendar) else { return }
            propose(.event(toolCallID: call.toolCallId, draft: draft), toolCallID: call.toolCallId)
        case .createReminder(let draft):
            // Blocked by iOS: say so now instead of showing a card that can only fail.
            guard devices.access(for: .reminders) == .granted else {
                await notConnected(call.toolCallId, .reminders)
                return
            }
            guard await mayTryAgain(call.toolCallId, app: .reminders) else { return }
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
                let matches = try await devices.readContacts(named: name)
                contactCard = ContactCard(query: name, matches: matches)
                await reply(call.toolCallId, VoiceToolReply.contactMatches(matches.map(\.name), query: name))
            } catch {
                await reply(call.toolCallId, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
            }
        case .undoLast:
            // Only a change from this conversation, Doddy's own and checked; nothing runs before the tap.
            guard let start = startedAt, let entry = ActivityUndo.latest(in: activity.entries, since: start, now: Date()) else {
                await reply(call.toolCallId, VoiceToolReply.nothingToUndo)
                return
            }
            propose(.undo(toolCallID: call.toolCallId, entry: entry), toolCallID: call.toolCallId)
        case .calculate(let expression):
            // Worked out on the iPhone (ADR-270); no app, account or network.
            await reply(call.toolCallId, VoiceToolReply.calculation(expression))
        case .convertUnits(let request):
            await reply(call.toolCallId, VoiceToolReply.conversion(request))
        case .parkingSpot(let action):
            await handleParking(action, toolCallID: call.toolCallId)
        case .leaveBy(let request):
            await handleLeaveBy(request, toolCallID: call.toolCallId)
        case .addIngredients(let proposal):
            guard let list = await resolveList(proposal.list, toolCallID: call.toolCallId) else { return }
            guard isCurrent(call.toolCallId) else { return dropStale(call.toolCallId) }
            let open = IngredientsProposal.alreadyOpen(proposal.items, on: list)
            // Shopping list+ (ADR-631): what the At home list has starts unticked too, and says so.
            let atHome = HomeStock.positionsOnHomeList(proposal.items, home: homeList, addingTo: list.id).subtracting(open)
            ingredientsAtHome = atHome
            ingredientsUnticked = open.union(atHome)
            propose(.ingredients(toolCallID: call.toolCallId, listID: list.id, listName: list.name, dish: proposal.dish,
                                 items: proposal.items, alreadyOpen: open), toolCallID: call.toolCallId)
        case .convertCurrency(let request):
            // The ECB's public rates file, fetched by the app (ADR-300); the last rates kept are
            // used, with their date, when newer ones can't be fetched.
            let found = await ExchangeRateClient.shared.rates()
            await reply(call.toolCallId, VoiceToolReply.currency(request, rates: found.rates, isLastKnown: found.isLastKnown))
        case .upcomingBirthdays(let days):
            // Read only (ADR-269): the agent hears names with the day and month, nothing else.
            guard devices.access(for: .contacts) == .granted else {
                await notConnected(call.toolCallId, .contacts)
                return
            }
            do {
                let everyone = try await devices.readContactBirthdays()
                let found = UpcomingBirthdays.upcoming(everyone, now: Date(), days: days, calendar: .current)
                await reply(call.toolCallId, VoiceToolReply.birthdays(found, days: days, calendar: .current))
            } catch {
                await reply(call.toolCallId, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
            }
        case .setTimer(let draft):
            // AlarmKit on iOS 26 needs no notification permission (ADR-650).
            guard await devices.timerAccess() == .granted else {
                await notConnected(call.toolCallId, .timers)
                return
            }
            guard await mayTryAgain(call.toolCallId, app: .timers) else { return }
            propose(.timer(toolCallID: call.toolCallId, draft: draft), toolCallID: call.toolCallId)
        case .followNews(let ask):
            // At once since 11 Nov 2026 (decision 2026-11-11-asked-for-runs-at-once). Said from the list as it is
            // kept on this iPhone after the write, never assumed (ADR-657).
            let outcome = FollowingModel.shared.follow(ask.base)
            var alertResult: NewsFollowAlertResult?
            if let alertAsk = ask.alertAsk {
                // The alert applies to a follow that was just added or that the person already had; the radar's own
                // sync says whether Doddy's server kept it.
                switch outcome {
                case .added(let follow), .alreadyFollowing(let follow):
                    let kept = await FollowingModel.shared.apply(alertAsk.alert(followID: follow.id), to: follow)
                    alertResult = kept
                        ? .kept(FollowingModel.shared.alert(for: follow))
                        : .hereOnly(reason: FollowingModel.shared.radarProblem ?? "")
                case .full, .notKept: break
                }
            }
            await reply(call.toolCallId, VoiceToolReply.newsFollow(outcome, alert: alertResult))
        case .startStopwatch(let label):
            // At once since 11 Nov 2026 (decision 2026-11-11-asked-for-runs-at-once). One stopwatch at a time: a
            // second start reports the one running and changes nothing (ADR-652).
            switch StopwatchController.shared.start(label: label) {
            case .started(let watch):
                await reply(call.toolCallId, VoiceToolReply.stopwatchStarted(label: watch.label))
            case .alreadyThere(let watch):
                await reply(call.toolCallId, VoiceToolReply.stopwatchAlreadyThere(elapsed: watch.elapsed(at: Date()), paused: watch.isPaused))
            }
        case .stopStopwatch:
            // Said from the stored stopwatch, never from a guess: none, or one already stopped,
            // is a failure the voice reads out as it is.
            let before = StopwatchController.shared.watch
            if let elapsed = StopwatchController.shared.stop() {
                await reply(call.toolCallId, VoiceToolReply.stopwatchStopped(elapsed: elapsed))
            } else {
                let stoppedAt = before.flatMap { $0.isOver ? $0.elapsed(at: $0.stoppedAt ?? Date()) : nil }
                await reply(call.toolCallId, VoiceToolReply.noStopwatchToStop(stoppedAt: stoppedAt))
            }
        case .checkStopwatch:
            StopwatchController.shared.refresh()
            await reply(call.toolCallId, VoiceToolReply.stopwatchReading(StopwatchController.shared.watch, now: Date()))
        // The focus timer and the wind-down (decision 2026-11-10-timers-by-voice), at once since 11 Nov 2026
        // (decision 2026-11-11-asked-for-runs-at-once). One of each at a time: a running one is never replaced. Every reply is read back from the
        // controller after the change, so Doddy never says one runs or stopped when it didn't.
        case .startFocus(let minutes, let label):
            let focus = FocusController.shared
            focus.refresh()
            if let running = focus.session, !running.isOver {
                await reply(call.toolCallId, VoiceToolReply.countdownAlreadyThere(.focus, running, now: Date()))
                return
            }
            await focus.start(minutes: minutes, label: label)
            await reply(call.toolCallId, VoiceToolReply.countdownStarted(
                .focus, focus.session, alertConfirmed: focus.notificationConfirmed, calendar: .current))
        case .stopFocus:
            let focus = FocusController.shared
            focus.refresh()
            let before = focus.session
            if before.map({ !$0.isOver }) == true { focus.stop() }
            await reply(call.toolCallId, VoiceToolReply.countdownStopped(.focus, before: before, after: focus.session, now: Date()))
        case .checkFocus:
            FocusController.shared.refresh()
            await reply(call.toolCallId, VoiceToolReply.focusReading(FocusController.shared.session, now: Date(), calendar: .current))
        case .startWindDown(let minutes):
            let countdowns = CountdownController.shared
            countdowns.refresh()
            if let running = countdowns.session(.windDown), !running.isOver {
                await reply(call.toolCallId, VoiceToolReply.countdownAlreadyThere(.windDown, running, now: Date()))
                return
            }
            let outcome = await countdowns.start(seconds: minutes * 60, purpose: .windDown, label: nil)
            await reply(call.toolCallId, VoiceToolReply.countdownStarted(
                .windDown, countdowns.session(.windDown), alertConfirmed: outcome == .verified, calendar: .current))
        case .stopWindDown:
            let countdowns = CountdownController.shared
            countdowns.refresh()
            let before = countdowns.session(.windDown)
            if before.map({ !$0.isOver }) == true { countdowns.stop(.windDown) }
            await reply(call.toolCallId, VoiceToolReply.countdownStopped(.windDown, before: before, after: countdowns.session(.windDown), now: Date()))
        case .listAlarms:
            // Read on the phone (ADR-283): times and labels Doddy set, nothing else. An unreadable
            // list is said as such, never as "none" (voice-agent review 2).
            guard let alarms = AlarmScheduler.currentIfReadable() else {
                await reply(call.toolCallId, VoiceToolReply.alarmsUnreadable)
                return
            }
            await reply(call.toolCallId, VoiceToolReply.alarms(alarms))
        case .cancelAlarm(let clock, let label):
            // Unreadable is not "not found": the alarm may still ring.
            guard let alarms = AlarmScheduler.currentIfReadable() else {
                await reply(call.toolCallId, VoiceToolReply.alarmsUnreadable)
                return
            }
            // ADR-718: before the tap the agent hears nothing about the user's alarms, whether none
            // matched or several did; the one that matched is on the card.
            switch AlarmMatch.prepare(clock: clock, label: label, in: alarms) {
            case .refuse(let text): await reply(call.toolCallId, text)
            case .card(let alarm): propose(.cancelAlarm(toolCallID: call.toolCallId, alarm: alarm), toolCallID: call.toolCallId)
            }
        case .setAlarm(let draft):
            // Said now, before a card that could only fail: an older iOS, or alarms refused.
            switch AlarmScheduler.support() {
            case .needsNewerIOS: await reply(call.toolCallId, VoiceToolReply.alarmNeedsNewerIOS)
            case .notAllowed: await reply(call.toolCallId, VoiceToolReply.alarmNotAllowed)
            case .available:
                guard await mayTryAgain(call.toolCallId, app: .timers) else { return }
                propose(.alarm(toolCallID: call.toolCallId, draft: draft), toolCallID: call.toolCallId)
            }
        case .openMap(let place, let from, let mode):
            propose(.map(toolCallID: call.toolCallId, trip: MapTrip(place: place, from: from, mode: mode)), toolCallID: call.toolCallId)
        case .runShortcut(let name):
            propose(.shortcut(toolCallID: call.toolCallId, name: name), toolCallID: call.toolCallId)
        case .draftMessage(let draft):
            // ADR-717: Doddy's own Contacts switch as well as iOS's permission, as for lookup_contact, and at
            // most three searches before a card. A draft needs an address from Contacts, so with the switch off
            // the access card asks for it.
            switch ContactRead.decide(
                switchOn: isOn(.contacts), iosAllows: devices.access(for: .contacts) == .granted, budget: &contactSearches) {
            case .switchOff, .notAllowedByIOS:
                await notConnected(call.toolCallId, .contacts)
                return
            case .budgetSpent:
                await reply(call.toolCallId, VoiceToolReply.contactSearchesSpent, isError: true)
                return
            case .search:
                break
            }
            do {
                let found = try devices.findContacts(named: draft.recipientName)
                // Several matches are never guessed between: unless one is exactly the name asked for, the
                // agent hears how many and asks the user for the full name.
                switch MessageRecipient.resolve(
                    found.map { (name: $0.name, phoneNumbers: $0.phoneNumbers, emailAddresses: $0.emailAddresses) },
                    query: draft.recipientName) {
                case .nobody:
                    await reply(call.toolCallId, VoiceToolReply.contactMatches([], query: draft.recipientName))
                case .several(let names):
                    await reply(call.toolCallId, VoiceToolReply.messageSeveralContacts(names, query: draft.recipientName))
                case .contact(let name, let phoneNumbers, let emailAddresses):
                    guard let address = draft.channel == .text ? phoneNumbers.first : emailAddresses.first else {
                        await reply(call.toolCallId, VoiceToolReply.noAddress(name, channel: draft.channel), isError: true)
                        return
                    }
                    propose(.message(toolCallID: call.toolCallId, draft: draft, address: address), toolCallID: call.toolCallId)
                }
            } catch {
                await reply(call.toolCallId, VoiceToolReply.failed(UserFacingError.message(for: error)), isError: true)
            }
        case .draftBlikTransfer(let draft):
            // ADR-510: a card with the details, for the user to send in their bank app. Doddy never
            // sends money. Contacts only adds the number, when Doddy's Contacts switch is on, iOS allows
            // it and this conversation still has a search left (ADR-717); otherwise the card shows the name
            // as said. When several contacts have the name, the agent asks which one instead of the card
            // guessing.
            var recipient = BlikRecipient.nameOnly
            if ContactRead.decide(
                switchOn: isOn(.contacts), iosAllows: devices.access(for: .contacts) == .granted, budget: &contactSearches) == .search,
               let matches = try? devices.findContacts(named: draft.recipientName) {
                recipient = BlikRecipient.resolve(matches.map { (name: $0.name, phoneNumbers: $0.phoneNumbers) }, query: draft.recipientName)
            }
            switch recipient {
            case .several(let names):
                await reply(call.toolCallId, VoiceToolReply.blikSeveralContacts(names, query: draft.recipientName))
            case .nameOnly:
                propose(.blik(toolCallID: call.toolCallId, draft: draft, contactName: nil, numbers: []), toolCallID: call.toolCallId)
            case .contact(let name, let numbers):
                propose(.blik(toolCallID: call.toolCallId, draft: draft, contactName: name, numbers: numbers), toolCallID: call.toolCallId)
            }
        case .draftInvoice(let update):
            // ADR-677: the draft on the card changes with each detail the user dictates. Only the
            // user's own transcribed words count as having said a NIP or a VAT rate; nothing leaves
            // this iPhone, and issuing is the card's own tap (not offered while
            // InFaktAPI.createVerified is false).
            guard let today = CalendarDate.day(of: Date(), in: .current) else {
                await reply(call.toolCallId, VoiceToolReply.invoiceRefused("the iPhone's date couldn't be read."), isError: true)
                return
            }
            let userWords = lines.filter(\.fromUser).map(\.text)
            var session = invoiceSession
            switch session.apply(update, userWords: userWords, today: today) {
            case .drafted(var operation, var notes):
                guard onScreen(attempt) else {
                    await reply(call.toolCallId, VoiceToolReply.invoiceRefused("the conversation ended before the draft could be shown."))
                    return
                }
                invoiceSession = session
                // ADR-685: a NIP the person said is looked up in the public registers, the VAT register
                // from this iPhone and CEIDG through Doddy's server; only the NIP leaves the phone.
                // The answer is applied to the draft as it is now, and only if the NIP is still the same.
                if let nip = invoiceSession.registerLookupNip {
                    if UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) {
                        notes.append(.registerPaused)
                    } else {
                        let lookup = await Self.lookUpCompany(nip, on: today)
                        guard onScreen(attempt) else {
                            await reply(call.toolCallId, VoiceToolReply.invoiceRefused("the conversation ended before the draft could be shown."))
                            return
                        }
                        notes += invoiceSession.applyRegister(lookup, for: nip)
                        operation = invoiceSession.operation ?? operation
                    }
                }
                // Kept only when the file reads back as this draft (ADR-678); the agent hears which.
                let kept = Self.invoiceDraftFile?.save(invoiceSession) ?? false
                var text = VoiceToolReply.invoiceDraft(operation, notes: notes, kept: kept)
                if invoiceDraftWasSetAside {
                    invoiceDraftWasSetAside = false
                    text += "\nAn earlier invoice draft on this iPhone couldn't be read, so it was set aside, not deleted. Tell the user in one sentence."
                }
                await reply(call.toolCallId, text)
            case .refused(let reason):
                await reply(call.toolCallId, VoiceToolReply.invoiceRefused(reason))
            }
        case .makePresentation(let draft):
            // ADR-567: every slide on a card; the file is made only on the tap.
            propose(.presentation(toolCallID: call.toolCallId, draft: draft), toolCallID: call.toolCallId)
        case .readSteps(let day):
            // ADR-568: one day's totals from Motion & Fitness, read only.
            guard devices.stepCountingAvailable else {
                await reply(call.toolCallId, VoiceToolReply.stepsUnavailable)
                return
            }
            guard devices.access(for: .steps) == .granted else {
                await notConnected(call.toolCallId, .steps)
                return
            }
            do {
                let now = Date()
                let totals = try await devices.steps(on: day, now: now)
                await reply(call.toolCallId, VoiceToolReply.steps(totals, day: day, until: day.daysAgo == 0 ? now : nil, calendar: .current))
            } catch {
                await reply(call.toolCallId, VoiceToolReply.stepsFailed(UserFacingError.message(for: error)), isError: true)
            }
        case .openTrainingPlan(let ask):
            // ADR-626, at once since 11 Nov 2026 (decision 2026-11-11-asked-for-runs-at-once). The screen asks the safety questions and makes the
            // plan; the agent hears only that it is open, never the answers or the plan.
            if isCurrent(call.toolCallId) { planRequest = PlanAskRequest(ask: ask) }
            await reply(call.toolCallId, VoiceToolReply.trainingPlanOpened(ask))
        case .readHealthWeek:
            // ADR-623: the week from Apple Health as a summary worked out on the iPhone. Only with
            // Apple Health on and the voice's own consent; the ask before it is ASK-01's.
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: HealthConnectionView.preferenceKey),
                  HealthVoiceConsent.isGranted(storedVersion: defaults.integer(forKey: HealthConnectionView.voiceConsentVersionKey)) else {
                await reply(call.toolCallId, VoiceToolReply.healthWeekNotAllowed)
                return
            }
            do {
                let glance = try await HealthReader.shared.glance(now: Date())
                await reply(call.toolCallId, glance.isEmpty ? VoiceToolReply.healthWeekEmpty : VoiceToolReply.healthWeek(glance, calendar: .current))
            } catch {
                await reply(call.toolCallId, VoiceToolReply.healthWeekFailed(UserFacingError.message(for: error)), isError: true)
            }
        case .findPhotos(let request):
            // ADR-569: counts and times to the agent; the pictures stay on this screen.
            guard devices.access(for: .photos) == .granted else {
                await notConnected(call.toolCallId, .photos)
                return
            }
            let found = devices.findPhotos(request, now: Date())
            if isCurrent(call.toolCallId) {
                photoResults = PhotoResults(request: request, summary: found.summary, identifiers: found.identifiers)
                // ADR-616: the pictures are on the conversation's screen; the island says so.
                if !found.identifiers.isEmpty { flashIsland(.resultReady(.photos)) }
            }
            await reply(call.toolCallId, VoiceToolReply.photosFound(found.summary, request: request, calendar: .current))
        case .openCamera:
            guard devices.cameraAvailable else {
                await reply(call.toolCallId, VoiceToolReply.cameraUnavailable)
                return
            }
            guard devices.access(for: .camera) == .granted else {
                await notConnected(call.toolCallId, .camera)
                return
            }
            propose(.camera(toolCallID: call.toolCallId), toolCallID: call.toolCallId)
        case .openFoodApp(let handoff):
            // Decision 2026-11-12-food-by-voice: the card's tap (AskFirst.tapFirst, checked above) was the yes.
            // The app's front page opens (its app when installed, else the website); nothing is ordered or sent.
            let opened = await open(handoff.openURL)
            await reply(call.toolCallId, opened ? handoff.openedReply : handoff.notOpenedReply, isError: !opened)
        case .lookAtScreen(let question):
            // Sharing is on (checked above) and that is the person's yes since 11 Nov 2026 (decision
            // 2026-11-11-asked-for-runs-at-once): the picture as it is now, fresh or nothing.
            // It goes to Doddy's server for this one answer and is never kept (decision 2026-11-09-doddy-looks-at-the-screen).
            let current = ScreenShareFiles.current()
            guard case .ready(let age) = current.readiness, let jpeg = current.jpeg else {
                await reply(call.toolCallId, ScreenLookSpeech.notReady(current.readiness) ?? ScreenLookSpeech.result(.invalidRequest).text)
                return
            }
            guard let server = Self.messagingClient() else {
                let result = ScreenLookSpeech.result(.notConfigured)
                await reply(call.toolCallId, result.text, isError: result.isError)
                return
            }
            let locale = ConversationLanguage.stored().overrideCode ?? Locale.preferredLanguages.first ?? "en"
            let outcome = await server.lookAtScreen(ScreenLookRequest(locale: locale, question: question, frameAge: age, jpeg: jpeg))
            let result = ScreenLookSpeech.result(outcome)
            await reply(call.toolCallId, result.text, isError: result.isError)
        case .controlHome(let proposal):
            guard devices.homeAvailable else {
                await reply(call.toolCallId, VoiceToolReply.homeUnavailable)
                return
            }
            guard devices.access(for: .home) == .granted else {
                await notConnected(call.toolCallId, .home)
                return
            }
            guard let snapshot = await homeKit.snapshot() else {
                await reply(call.toolCallId, VoiceToolReply.failed("Home didn't load, so nothing was changed. Tell the user in one short sentence."), isError: true)
                return
            }
            // The words are matched to one exact accessory or scene by code; the card shows HomeKit's own name for it.
            switch HomeCommandRules.resolve(proposal, in: snapshot) {
            case .ready(let command): propose(.home(toolCallID: call.toolCallId, command: command), toolCallID: call.toolCallId)
            case .ambiguous(let names): await reply(call.toolCallId, VoiceToolReply.homeAmbiguous(names))
            case .notFound: await reply(call.toolCallId, VoiceToolReply.homeNotFound)
            case .refused(let reason): await reply(call.toolCallId, VoiceToolReply.homeRefused(reason))
            case .unreachable(let name): await reply(call.toolCallId, VoiceToolReply.homeUnreachable(name))
            }
        case .cloudTool(let cloud):
            await handleCloud(cloud, toolCallID: call.toolCallId)
        case .textMe(let body):
            await proposeText(body, toolCallID: call.toolCallId)
        case .callMeLater(let draft):
            await proposeCallLater(draft, toolCallID: call.toolCallId)
        case .callMeNow:
            await proposeCallNow(toolCallID: call.toolCallId)
        case .callPlaces(let draft):
            await proposeCallTask(draft, toolCallID: call.toolCallId)
        case .startTranslator(let proposal):
            guard let setup = proposal.setup(ownerDefault: Self.ownerLanguage) else {
                await reply(call.toolCallId, VoiceToolReply.failed("Both languages are the same. Ask the user which language the other person speaks."), isError: true)
                return
            }
            await startTranslator(setup, toolCallID: call.toolCallId)
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
            guard await mayTryAgain(call.toolCallId, app: .memories) else { return }
            // From a template (ADR-334): its items first, then any the user said.
            var items = request.items
            if let wanted = request.template {
                let templates = ListTemplateStore.current()
                guard let template = templates.named(wanted) else {
                    await reply(call.toolCallId, VoiceToolReply.templateNotFound(wanted, templates: templates))
                    return
                }
                items = ListTemplates.items(from: template, plus: request.items)
            }
            propose(.createList(toolCallID: call.toolCallId, name: request.list, items: items), toolCallID: call.toolCallId)
        case .stopTranslator:
            guard translator != nil else {
                await reply(call.toolCallId, VoiceToolReply.translatorNotOn)
                return
            }
            endTranslator()
            await reply(call.toolCallId, VoiceToolReply.translatorStopped)
        case .handOverErrand(let draft):
            // ADR-570: after the user's tap on the ask card above (a spoken yes can't start it, ADR-716),
            // the app creates the task on Doddy's server and approves it with the digest of exactly
            // the words and note on that card. That one tap covers every look-up of this task; it is
            // never approved twice.
            if let issue = draft.validationIssues().first {
                await reply(call.toolCallId, VoiceToolReply.failed(issue.reason), isError: true)
                return
            }
            await reply(call.toolCallId, await ErrandsModel.shared.handOver(draft))
        case .checkErrands(let about):
            await reply(call.toolCallId, await ErrandsModel.shared.agentReply(about: about))
        case .makeSomething(let job):
            // ADR-740: after the user's tap on the ask card above (a spoken yes can't start it, ADR-742),
            // the app creates the job on Doddy's server and approves it with the digest of that job. That
            // one tap covers its web look-ups and making its files, within the server's dollar limits;
            // it is never approved twice.
            if let issue = job.validationIssues().first {
                await reply(call.toolCallId, VoiceToolReply.failed(issue.reason), isError: true)
                return
            }
            await reply(call.toolCallId, await StudioModel.shared.make(job))
        case .findDeals(let request):
            // SHOPPING.md 2: at once since 11 Nov 2026, one request to Doddy's server, which reads the
            // chains' leaflets for it and keeps nothing. The answer also stays on the leaflets screen.
            await reply(call.toolCallId, await DealsModel.shared.searchForAgent(request))
        case .lostWallet(let situation):
            // ADR-692: the checklist is its own card and changes nothing. Its steps and links come
            // from DoddyCore's table; a page opens or a number is dialled only on the person's tap.
            if isCurrent(call.toolCallId) {
                lostWalletCard = LostWalletCard(situation: situation, steps: LostWalletPlan.steps(for: situation, polish: Self.cardsInPolish))
            }
            await reply(call.toolCallId, VoiceToolReply.lostWalletShown(situation))
        case .noteCapabilityGap(let category):
            // Nothing changes and no app is used: one row on this iPhone, as a category (ADR-440).
            // "Written down" only after the write (ADR-672); no store or a failed write says so.
            let noted = await store.learning?.recordGap(category, requestID: call.toolCallId, sessionID: conversationID) ?? false
            await reply(call.toolCallId, noted ? LearningPrompt.gapNoted : LearningPrompt.gapNotNoted)
        case .unsupported(let name):
            await reply(call.toolCallId, VoiceToolReply.unsupported(name), isError: true)
        case .invalid(_, let reason):
            await reply(call.toolCallId, VoiceToolReply.failed("The request was incomplete (\(reason))."), isError: true)
        }
    }

    /// The ask cards whose words DoddyCore chooses (ADR-666: leaflets) follow the language the app is shown in.
    private static var cardsInPolish: Bool { NotificationLanguage.preferred(Bundle.main.preferredLocalizations) == .polish }

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
        var blocked: [Int: PlanBlock] = [:]
        // This plan's own approvals (review H7): kept apart until its card is shown, so an
        // overlapping propose_plan can't mix its approvals into this card or this one's into it.
        var approvals: [Int: PlanCloudApproval] = [:]
        for step in steps {
            if let block = await planBlock(for: step) {
                blocked[step.number] = block
                if connectionNeeded == nil, isCurrent(call.toolCallId), case .notConnected(let connection) = block { connectionNeeded = connection }
            } else if let request = step.activity(calendar: .current),
                      case .stop(let count) = ActionRetry.decide(for: request, in: activity.entries, now: Date()) {
                // Tried too often without a confirmed result (ADR-319): shown on the card, not run.
                blocked[step.number] = .tooManyTries(app: request.app, count: count)
            } else if let call = step.cloudCall {
                // As a single card: the server checks the switch, the connection and the arguments,
                // and returns the preview the card shows with an approval for exactly these.
                switch await prepareCloud(call) {
                case .ready(let approval): approvals[step.number] = approval
                case .blocked(let block): blocked[step.number] = block
                }
            }
        }
        // Ended, or ended and started again, while the steps were checked: no card, no reply and
        // no plan state in the next conversation (review H9, ADR-458).
        guard isLive, isCurrent(call.toolCallId) else {
            dropStale(call.toolCallId, steps: steps)
            return
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
        // A card shown while the steps were checked is replaced by this one in propose(_:toolCallID:).
        planTicked = Set(steps.map(\.number)).subtracting(blocked.keys)
        planChanged = []
        planCloud = approvals
        askedPlans[call.toolCallId] = steps
        propose(.plan(toolCallID: call.toolCallId, steps: steps, blocked: blocked), toolCallID: call.toolCallId)
    }

    /// Ticked steps run one after another, each through the same path as its single card, and each
    /// gets its own result. A step that fails doesn't stop the others; none is retried.
    private func runPlan(_ toolCallID: String, steps: [PlanStep], blocked: [Int: PlanBlock]) async {
        // The steps the user approved run to the end and are logged even if the conversation ends;
        // only its own screen shows their progress (ADR-458).
        let attempt = startAttempt
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
            var write: WriteResult?
            let text: String
            if let block = blocked[step.number] {
                text = block.reply
            } else if !ticked.contains(step.number) {
                text = PlanReply.unticked
            } else {
                // Earlier tries are read before this one is written down (ADR-319).
                let request = step.activity(calendar: .current)
                let retry = ActionRetry.decide(for: request, in: activity.entries, now: Date())
                if case .stop(let count) = retry, let request {
                    text = VoiceToolReply.retryStopped(count: count, app: request.app)
                } else {
                    // On disk before it runs, like a single card (ActivityLog.recoverInterrupted).
                    if let request {
                        let entry = ActivityEntry.started(request, at: Date(), plan: ref)
                        activity.append(entry)
                        startedEntry = entry
                    }
                    write = await runPlanStep(step, approval: approvals[step.number], retry: retry, attempt: attempt)
                    text = write?.reply ?? ""
                }
            }
            let logged = logPlanStep(step, reply: text, plan: ref, replacing: startedEntry, write: write)
            if attempt == startAttempt { planStatus?.results[step.number] = logged }
            results.append((step, text))
        }
        if attempt == startAttempt { planStatus?.isRunning = false }
        // A saved procedure with exactly these steps counts as used (ADR-440).
        if !ticked.subtracting(blocked.keys).isEmpty {
            await store.learning?.planRan(tools: steps.map(\.toolName))
        }
        await reply(toolCallID, PlanReply.summary(results, changed: changed))
    }

    /// Checked again at the tap: the user may have paused or switched off the app while the card waited.
    /// A step's reply, what its entry keeps (receipt, whether it wrote) and what Undo needs when it
    /// added an event or reminder and read it back (ADR-271, ADR-319): the same as from its single card.
    private func runPlanStep(_ step: PlanStep, approval: PlanCloudApproval?, retry: ActionRetryDecision, attempt: Int) async -> WriteResult {
        if let block = await planBlock(for: step) { return WriteResult(reply: block.reply) }
        switch step.request {
        case .createCalendarEvent(let draft):
            return eventResult(addEvent(draft), draft: draft, retry: retry)
        case .createReminder(let draft):
            return reminderResult(await addReminder(draft, attempt: attempt), draft: draft, retry: retry)
        case .setTimer(let draft):
            return await timerResult(draft, retry: retry)
        case .cloudTool(let call):
            return await runPlanCloud(call, approval: approval, app: step.activity(calendar: .current)?.app ?? .gmail)
        case .saveMemory(let text):
            if let since = retry.uncheckedSince, let existing = NoteIdempotency.savedSince(since, text: text, in: store.memories) {
                return WriteResult(
                    reply: VoiceToolReply.noteAlreadySaved(existing), receipt: ActivityReceipt(note: existing, readAt: Date()), attempted: false)
            }
            do {
                let record = try await store.save(text: text, category: .other, source: .explicitVoice)
                if onScreen(attempt) { savedThisConversation += 1 }
                return WriteResult(
                    reply: VoiceToolReply.saved(record), receipt: ActivityReceipt(note: record, readAt: Date()), attempted: true,
                    undo: .savedNote(id: record.id, text: record.currentText))
            } catch {
                return WriteResult(reply: VoiceToolReply.failed(UserFacingError.message(for: error)), attempted: true)
            }
        case .addToList(let request):
            // Matched now, exactly as a single add_to_list would be; nothing changes on no match.
            await store.reload()
            switch ListMatch.list(named: request.list, in: store.lists) {
            case .none: return WriteResult(reply: VoiceToolReply.listNotFound(request.list, lists: store.lists), attempted: false)
            case .several(let lists): return WriteResult(reply: VoiceToolReply.listAmbiguous(request.list, lists: lists), attempted: false)
            case .one(let list):
                do {
                    let result = try await store.addToList(request.items, listID: list.id, source: .voice)
                    return WriteResult(
                        reply: VoiceToolReply.listAdded(result, list: list.name),
                        receipt: ActivityReceipt(list: list.name, listID: list.id, lines: Self.receiptLines(result), readAt: Date()),
                        attempted: true)
                } catch {
                    return WriteResult(reply: VoiceToolReply.listFailed(UserFacingError.listMessage(for: error)), attempted: true)
                }
            }
        default:
            // PlanProposal only makes the kinds above.
            return WriteResult(reply: VoiceToolReply.notAdded("This step can't run in a plan."))
        }
    }

    private enum CloudPrepared {
        case ready(PlanCloudApproval)
        /// Why the server didn't prepare the step, for the card and the agent.
        case blocked(PlanBlock)
    }

    private func prepareCloud(_ call: CloudToolCall) async -> CloudPrepared {
        guard let client = await OnlineAccountsClientFactory.ready() else {
            return .blocked(.onlineAccount(
                screen: OnlineAccountsError.notConfigured.userMessage,
                reply: VoiceToolReply.cloudFailed(.notConfigured, tool: call.name)))
        }
        do {
            let prepared = try await client.prepare(call)
            // An earlier unsure try is already there (ADR-322): shown on the card, not run again.
            if prepared.earlier?.status == .found {
                return .blocked(.onlineAccount(
                    screen: "Already in \(CloudToolName.account(call.name)) from an earlier try", reply: VoiceToolReply.cloudAlreadyThere(call.name)))
            }
            return .ready(PlanCloudApproval(preview: prepared.preview, approvalID: prepared.approvalId, mode: prepared.mode, preparedAt: Date()))
        } catch {
            return .blocked(.onlineAccount(screen: error.userMessage, reply: VoiceToolReply.cloudFailed(error, tool: call.name)))
        }
    }

    /// The server's approval works once and lasts two minutes. If the card waited longer, a fresh
    /// one is asked for the same arguments the user saw; the server checks them again.
    private func runPlanCloud(_ call: CloudToolCall, approval: PlanCloudApproval?, app: ActivityApp) async -> WriteResult {
        func written(_ record: CloudWriteRecord) -> WriteResult {
            WriteResult(reply: record.reply, receipt: record.receipt, attempted: record.attempted)
        }
        guard let client = await OnlineAccountsClientFactory.ready() else {
            return written(CloudWriteRecord(.failure(.notConfigured), tool: call.name, app: app, readAt: Date()))
        }
        var approvalID = approval?.approvalID
        if approval == nil || Date().timeIntervalSince(approval?.preparedAt ?? .distantPast) > 90 {
            do {
                let prepared = try await client.prepare(call)
                if prepared.earlier?.status == .found {
                    return WriteResult(reply: VoiceToolReply.cloudAlreadyThere(call.name), attempted: false)
                }
                approvalID = prepared.approvalId
            } catch {
                return written(CloudWriteRecord(.failure(error), tool: call.name, app: app, readAt: Date()))
            }
        }
        guard let approvalID else {
            // A read in a plan runs without a confirmation.
            do {
                return WriteResult(reply: VoiceToolReply.cloudResult(try await client.run(call, timeZone: TimeZone.current.identifier, approvalId: nil)))
            } catch {
                return WriteResult(reply: VoiceToolReply.cloudFailed(error, tool: call.name))
            }
        }
        let outcome = await CloudRun.confirmed(call, approvalId: approvalID, timeZone: TimeZone.current.identifier, client: client)
        return written(CloudWriteRecord(outcome, tool: call.name, app: app, readAt: Date()))
    }

    private func planBlock(for step: PlanStep) async -> PlanBlock? {
        if UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey), ConnectionPause.applies(to: step.request) {
            return .paused
        }
        guard let connection = step.connection else { return nil }
        guard isOn(connection) else { return .notConnected(connection) }
        let access: DeviceConnections.Access
        if connection == .timers {
            // Plan steps on Timers are timers (alarms aren't in plans): AlarmKit or notifications.
            access = await devices.timerAccess()
        } else {
            access = devices.access(for: connection)
        }
        return access == .granted ? nil : .notConnected(connection)
    }

    @discardableResult
    private func logPlanStep(
        _ step: PlanStep, reply text: String, plan: ActivityPlanRef, replacing started: ActivityEntry? = nil, write: WriteResult? = nil
    ) -> ActivityEntry? {
        guard let request = step.activity(calendar: .current) else { return nil }
        if let started {
            let entry = ActivityEntry.finished(
                started, request: request, reply: text, at: Date(),
                undo: write?.undo, receipt: write?.receipt, attempted: write?.attempted)
            activity.replace(entry)
            return entry
        }
        let entry = ActivityEntry(
            request: request, reply: text, at: Date(), plan: plan,
            undo: write?.undo, receipt: write?.receipt, attempted: write?.attempted)
        activity.append(entry)
        return entry
    }

    /// The voice agent proposed paying for a page (ADR-736). The agent only names the page. The card shows the
    /// server's exact terms; the person confirms (typing the amount for larger payments), then Face ID; only then
    /// does Doddy's server pay. The agent hears the outcome after the person has decided, and never pays itself.
    private func handlePayForPage(_ call: CloudToolCall, toolCallID: String) async {
        guard let url = PaymentToolName.address(from: call) else {
            await reply(toolCallID, VoiceToolReply.paymentBadArguments, isError: true)
            return
        }
        if let open = paymentApproval, open.phase != .idle {
            await reply(toolCallID, VoiceToolReply.paymentCardOpen, isError: true)
            return
        }
        guard let client = PaymentsClientFactory.make() else {
            await reply(toolCallID, VoiceToolReply.paymentNotSetUp, isError: true)
            return
        }
        let model = PaymentApprovalModel(client: client, authenticator: FaceIDPaymentAuthenticator())
        paymentApproval = model
        await model.start(url: url)
        let outcome = await model.outcome()
        var failed = false
        if case .failed = outcome { failed = true }
        await reply(toolCallID, VoiceToolReply.paymentOutcome(outcome), isError: failed)
    }

    /// Gmail, Drive, Notion, Todoist and web search go through Doddy's server, which checks the tool's
    /// switch (and, for accounts, the connection and the grant). Reads answer at once; writes show a card first.
    /// `pay_for_page` is answered by its own payment card first (ADR-736).
    private func handleCloud(_ cloud: CloudToolCall, toolCallID: String) async {
        if cloud.name == PaymentToolName.payForPage {
            await handlePayForPage(cloud, toolCallID: toolCallID)
            return
        }
        guard let client = await OnlineAccountsClientFactory.ready() else {
            await reply(toolCallID, VoiceToolReply.cloudFailed(.notConfigured, tool: cloud.name), isError: true)
            return
        }
        do {
            if cloud.isWrite {
                // Tried too often without a confirmed result: stop before the card (ADR-322).
                guard await mayTryAgain(toolCallID, app: asked[toolCallID]?.app ?? .gmail) else { return }
                let prepared = try await client.prepare(cloud)
                // An earlier unsure try is already there (the server looked): nothing more to do.
                if prepared.earlier?.status == .found {
                    writeResults[toolCallID] = WriteResult(reply: "", attempted: false)
                    await reply(toolCallID, VoiceToolReply.cloudAlreadyThere(cloud.name))
                    return
                }
                propose(
                    .cloud(toolCallID: toolCallID, call: cloud, preview: prepared.preview, approvalID: prepared.approvalId, mode: prepared.mode),
                    toolCallID: toolCallID)
            } else if AskFirst.need(for: .cloudTool(cloud)) == .runsNow {
                // ADR-575, and since 11 Nov 2026 every read through Doddy's server (decision
                // 2026-11-11-asked-for-runs-at-once): the user asked, so it runs at once. The server's
                // single-use approval is still made for exactly these words and used straight away.
                let prepared = try await client.prepare(cloud)
                let result = try await client.run(cloud, timeZone: TimeZone.current.identifier, approvalId: prepared.approvalId)
                await keepMadeDocument(result, from: cloud)
                keepFlightLinks(result)
                await reply(toolCallID, madeFileReply(result))
            } else {
                // ASK-01: the server makes the card from the arguments alone (nothing is read) and a
                // single-use approval; the read runs only after the user's yes (runAskedCloudRead).
                let prepared = try await client.prepare(cloud)
                askLedger.asked(toolCallID, request: .cloudTool(cloud), needsTap: false, at: Date())
                propose(
                    .cloudRead(toolCallID: toolCallID, call: cloud, preview: prepared.preview, approvalID: prepared.approvalId, mode: prepared.mode),
                    toolCallID: toolCallID)
            }
        } catch {
            await reply(toolCallID, await cloudFailureReply(error, tool: cloud.name), isError: true)
        }
    }

    /// ASK-01: the user said yes to this read. The server checks the approval again and uses it up.
    private func runAskedCloudRead(_ cloud: CloudToolCall, approvalID: UUID, toolCallID: String) async {
        guard askLedger.mayRun(toolCallID, request: .cloudTool(cloud), at: Date()) else {
            await reply(toolCallID, AskFirst.notAsked(cloud.name))
            return
        }
        guard let client = await OnlineAccountsClientFactory.ready() else {
            await reply(toolCallID, VoiceToolReply.cloudFailed(.notConfigured, tool: cloud.name), isError: true)
            return
        }
        do {
            let result = try await client.run(cloud, timeZone: TimeZone.current.identifier, approvalId: approvalID)
            await keepMadeDocument(result, from: cloud)
            await reply(toolCallID, madeFileReply(result))
        } catch {
            await reply(toolCallID, await cloudFailureReply(error, tool: cloud.name), isError: true)
        }
    }

    /// find_flights: the flights' Kiwi.com pages become buttons; a new search replaces the old ones.
    private func keepFlightLinks(_ result: RunResult) {
        guard result.tool == CloudToolName.findFlights else { return }
        flightLinks = (result.links ?? []).filter(\.isKiwi)
    }

    /// ADR-564: a file Claude is making gets a button on screen; the agent never gets its link. Its card and its
    /// message in Messages say what it is about: what the agent asked the server for (owner review, 13 Nov 2026).
    private func keepMadeDocument(_ result: RunResult, from call: CloudToolCall) async {
        guard let document = result.document else { return }
        let about = ThreadDelivery.madeFileBrief(of: call)
        if let about { documentBriefs[document.url] = about }
        documents.insert(document, at: 0)
        // ADR-616: "ready" only when the server says the file is ready.
        switch document.status {
        case .ready: flashIsland(.resultReady(.document))
        case .working:
            flashIsland(.resultReady(.documentStarted))
            // In the app: the island's small note, not the pop-up card (MadeFileStart.popsUpCard).
            showMadeFileNote(document)
            // One notification when it is done, if the messaging server is set up for it.
            FileReadyPush.watch(document)
        case .failed: break
        }
        // Also Doddy's own message in Messages, with the file to open and share from (owner, 10 Nov 2026).
        // A private conversation keeps nothing on this iPhone, so it adds nothing there either.
        if !isPrivate { await ThreadInbox.deliver(document: document, about: about, polish: Self.cardsInPolish) }
    }

    /// Home's island note for a file being made: up for a few seconds, then gone by itself.
    private func showMadeFileNote(_ document: RunDocument) {
        guard MadeFileStart.showsNote(document) else { return }
        madeFileNote = MadeFileNote(document: document, keptInMessages: !isPrivate)
        madeFileNoteClear?.cancel()
        madeFileNoteClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(MadeFileStart.noteSeconds))
            guard !Task.isCancelled else { return }
            self?.madeFileNote = nil
        }
    }

    /// What the agent hears for a server tool's result. A file still being made gets the phone's own words, with no
    /// card or tap in them, and no promise of Messages in a private conversation (`MadeFileStart.voiceReply`).
    private func madeFileReply(_ result: RunResult) -> String {
        MadeFileStart.voiceReply(result, keptInMessages: !isPrivate) ?? VoiceToolReply.cloudResult(result)
    }

    /// A tap on the island note puts it away sooner. Nothing else happens.
    func dismissMadeFileNote() {
        madeFileNoteClear?.cancel()
        madeFileNote = nil
    }

    /// ADR-563: what the agent hears when a server tool fails. An account that isn't connected gets
    /// a Connect button on screen; a refused session is renewed so the next try works.
    private func cloudFailureReply(_ error: OnlineAccountsError, tool: String) async -> String {
        if case .unauthenticated = error { _ = await OnlineAccountsClientFactory.renewed() }
        if ["not_connected", "connection_expired", "permission_insufficient"].contains(error.code ?? ""),
           CloudToolName.needsAccount(tool), let toolkit = error.receipt?.toolkit {
            accountNeeded = AccountNeeded(toolkit: toolkit, title: CloudToolName.account(tool))
            accountMessage = nil
        }
        return VoiceToolReply.cloudFailed(error, tool: tool)
    }

    /// "Connect Gmail" on the card: the provider's own sign-in sheet over the conversation, then the
    /// agent hears it worked and does what the user asked (still asking first, as always).
    func connectAccount() async {
        guard let needed = accountNeeded, !isConnectingAccount else { return }
        isConnectingAccount = true
        defer { isConnectingAccount = false }
        guard let client = await OnlineAccountsClientFactory.ready() else {
            accountMessage = OnlineAccountsError.notConfigured.userMessage
            return
        }
        let model = OnlineAccountsModel(client: client, authenticator: SystemWebAuthenticator())
        await model.connect(needed.toolkit)
        if model.lastReceipt?.toolkit == needed.toolkit, model.lastReceipt?.operation == .connect, model.lastReceipt?.status == .succeeded {
            accountNeeded = nil
            accountMessage = nil
            await sendToAgent("\(needed.title) is connected now. Do what the user asked before, the same way, and ask first as usual.")
        } else {
            accountMessage = model.message ?? "\(needed.title) wasn't connected. Nothing changed."
        }
    }

    func dismissAccountNeeded() {
        accountNeeded = nil
        accountMessage = nil
    }

    /// ASK-01: runs the call the user said yes to. For `.ask`, the call is handled again from the
    /// start (Pause all and the switches are checked again); the ledger lets it through once.
    private func runAsked(_ action: PendingAction, attempt: Int) async {
        switch action {
        case .ask(let id, _, _, let toolName, let parameters):
            await handle(ClientToolCallEvent(toolName: toolName, toolCallId: id, parametersData: parameters, eventId: 0, expectsResponse: true),
                         attempt: attempt)
        case .cloudRead(let id, let call, _, let approvalID, _):
            await runAskedCloudRead(call, approvalID: approvalID, toolCallID: id)
        default:
            break
        }
    }

    /// ASK-01: the user's own words while a read's card is up. Only a short, clear yes counts
    /// (`SpokenYes`); a change never runs on words, only on a tap.
    private func spokenAnswer(_ text: String) async {
        guard let action = pendingAction else { return }
        let id: String
        switch action {
        case .ask(let callID, _, false, _, _), .cloudRead(let callID, _, _, _, _): id = callID
        default: return
        }
        guard askLedger.answer(.userSaid(text), for: id, at: Date()) == .granted, pendingAction == action else { return }
        pendingAction = nil
        await runAsked(action, attempt: startAttempt)
    }

    /// The user tapped the card. The approval is for exactly the arguments the card showed. A lost
    /// answer is asked for once more with the same approval, which can't run it twice (ADR-322).
    private func runConfirmedCloud(_ cloud: CloudToolCall, approvalID: UUID, app: ActivityApp) async -> CloudWriteRecord {
        guard let client = await OnlineAccountsClientFactory.ready() else {
            return CloudWriteRecord(.failure(.notConfigured), tool: cloud.name, app: app, readAt: Date())
        }
        let outcome = await CloudRun.confirmed(cloud, approvalId: approvalID, timeZone: TimeZone.current.identifier, client: client)
        return CloudWriteRecord(outcome, tool: cloud.name, app: app, readAt: Date())
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
            noteReminderRings = draft.rings || store.noteReminders?.wantsToRing(memoryID: record.id) == true
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
            // Maps answered after End (and maybe a new Start): the place choice belongs to the
            // conversation on screen now, so it is not touched (ADR-458).
            guard isCurrent(toolCallID) else {
                dropStale(toolCallID)
                return
            }
            // This card replaces any card still waiting (propose), so the choice starts at the first place.
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

    /// The reminder the note on the card has now, which Set reminder replaces (review C3).
    var noteReminderReplaces: MemoryReminder? {
        guard case .noteReminder(_, let memoryID, _, _, _) = pendingAction else { return nil }
        return store.noteReminders?.reminder(forMemory: memoryID)
    }

    /// Shows one card at a time. A second proposal while one is waiting is refused, so no tool
    /// call is left without an answer.
    /// Parking (ADR-301). Location is read once, only for "save" and, if location is already
    /// allowed, for the distance on "find"; the agent hears no coordinates.
    /// "Remind me when to leave" (ADR-335): one position, an Apple Maps search near it and the
    /// travel time; the card shows what Maps found. Nothing is set until Set reminder.
    private func handleLeaveBy(_ request: LeaveByRequest, toolCallID: String) async {
        // No 3-try stop here (ADR-319's asks the user to look in the app, and a waiting leave
        // reminder shows nowhere): setting always looks for the same one first, so asking again
        // can't set a second.
        let location = PlaceLocation.shared
        var readiness = await location.readiness()
        if readiness == .notDetermined { readiness = await location.requestWhenInUse() }
        guard readiness == .ready || readiness == .approximateOnly else {
            await reply(toolCallID, VoiceToolReply.leaveByNoLocation(readiness))
            return
        }
        guard let here = await location.currentFix(within: 3_000)?.coordinate else {
            await reply(toolCallID, VoiceToolReply.leaveByNoLocation(nil))
            return
        }
        guard let place = (try? await location.search(request.place, near: here))?.first else {
            await reply(toolCallID, VoiceToolReply.leaveByNoPlace(request.place))
            return
        }
        guard let seconds = try? await location.travelTime(from: here, to: place.coordinate, mode: request.mode, arriveBy: request.arriveBy) else {
            await reply(toolCallID, VoiceToolReply.leaveByNoRoute(request.mode))
            return
        }
        switch LeaveBy.plan(request, placeName: place.name, placeAddress: place.address, travelSeconds: seconds, now: Date()) {
        case .success(let plan): propose(.leaveBy(toolCallID: toolCallID, plan: plan), toolCallID: toolCallID)
        case .failure(.tooLate(let leaveAt)): await reply(toolCallID, VoiceToolReply.leaveByTooLate(leaveAt, calendar: .current))
        case .failure(.tooFar): await reply(toolCallID, VoiceToolReply.leaveByTooFar)
        }
    }

    private func handleParking(_ action: ParkingAction, toolCallID: String) async {
        switch action {
        case .save(let note):
            var readiness = await PlaceLocation.shared.readiness()
            if readiness == .notDetermined { readiness = await PlaceLocation.shared.requestWhenInUse() }
            guard readiness == .ready else {
                await reply(toolCallID, VoiceToolReply.parkingNoLocation(readiness))
                return
            }
            guard let fix = await PlaceLocation.shared.currentFix(within: Parking.worstAccuracyMeters) else {
                await reply(toolCallID, VoiceToolReply.parkingNoLocation(nil))
                return
            }
            let spot = ParkingSpot(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude,
                                   accuracyMeters: fix.accuracy, savedAt: Date(), note: note)
            propose(.parking(toolCallID: toolCallID, spot: spot), toolCallID: toolCallID)
        case .find:
            guard let spot = ParkingStore.current() else {
                await reply(toolCallID, VoiceToolReply.parkingNone)
                return
            }
            var distance: Double?
            if await PlaceLocation.shared.readiness() == .ready, let here = await PlaceLocation.shared.currentCoordinate() {
                distance = Parking.distance(from: (here.latitude, here.longitude), to: (spot.latitude, spot.longitude))
            }
            // Location was read after an await: no parking card in a later conversation (ADR-458).
            guard isCurrent(toolCallID) else { return dropStale(toolCallID) }
            parkingCard = spot
            await reply(toolCallID, VoiceToolReply.parkingFound(spot, now: Date(), calendar: .current, distanceMeters: distance))
        case .clear:
            guard ParkingStore.current() != nil else {
                await reply(toolCallID, VoiceToolReply.parkingNothingToClear)
                return
            }
            if ParkingStore.clear() { parkingCard = nil }
            WidgetSync.shared.refresh()
            await reply(toolCallID, ParkingStore.current() == nil ? VoiceToolReply.parkingCleared : VoiceToolReply.failed("The parking spot couldn't be removed."))
        }
    }

    // MARK: Texts from Doddy's number (ADR-750 U2)

    /// One messaging client for approved texts while Doddy runs, shared by every conversation, so
    /// a try-again after an unknown outcome reuses its idempotency key and the server sends that
    /// text at most once (`DoddyServerClient.sendApprovedText`). The key lives in memory only:
    /// after Doddy is closed, a new try is a new request.
    private static var textClient: (url: URL, client: DoddyServerClient)?
    /// Approval hashes of texts whose outcome was unknown, so the card can say so.
    private(set) static var unconfirmedTexts: Set<String> = []
    /// When each approved text was queued, by approval hash, so a card for the same text again
    /// says it was already sent (the agent may ask again after its own wait ran out).
    private(set) static var queuedTexts: [String: Date] = [:]

    private static func messagingClient() -> DoddyServerClient? {
        guard let url = ServerConfig.baseURL() else { return nil }
        if let held = textClient, held.url == url { return held.client }
        guard let client = ServerConfig.client() else { return nil }
        textClient = (url, client)
        return client
    }

    /// Asks Doddy's server which number is the user's and whether texts are on, then sends the text at
    /// once: to the user's own verified number only, with no card (owner, 9 Nov 2026, decision
    /// 2026-11-09-restaurant-calls-one-tap). Exactly the same text sent a few minutes ago isn't sent again.
    private func proposeText(_ body: String, toolCallID: String) async {
        guard let client = Self.messagingClient() else {
            await reply(toolCallID, VoiceToolReply.textNoServer, isError: true)
            return
        }
        // No account yet means no verified number; asking the server would create an account.
        guard await client.hasAccount() else {
            await reply(toolCallID, VoiceToolReply.textNotReady(.noPhone))
            return
        }
        let readiness: TextReadiness
        do {
            readiness = TextReadiness(try await client.phoneStatus())
        } catch {
            await reply(toolCallID, VoiceToolReply.textCheckFailed(error as? ServerError), isError: true)
            return
        }
        guard case .ready(let to) = readiness else {
            await reply(toolCallID, VoiceToolReply.textNotReady(readiness))
            return
        }
        let draft = ApprovedTextDraft(body: body, to: to)
        guard !TextRepeat.sentMomentsAgo(draft.approvalHash, queued: Self.queuedTexts, now: Date()) else {
            await reply(toolCallID, VoiceToolReply.textSentMomentsAgo)
            return
        }
        // On disk before the text leaves, as for a confirmed card: a crash mid-send shows "Not sure" (ADR-321).
        markStarted(toolCallID)
        textSending = true
        let result = await sendApprovedText(draft)
        textSending = false
        writeResults[toolCallID] = WriteResult(reply: result.reply, attempted: result.attempted)
        await reply(toolCallID, result.reply)
    }

    /// The text and the approval hash of exactly that text and number go to the server, which checks
    /// the hash against the number it holds before queueing. Then a few
    /// seconds of status, so the reply says what is known and no more (DOD-08).
    private func sendApprovedText(_ draft: ApprovedTextDraft) async -> (reply: String, attempted: Bool) {
        guard let client = Self.messagingClient() else { return (VoiceToolReply.textNoServer, false) }
        let outcome: ApprovedTextOutcome
        do {
            outcome = try await client.sendApprovedText(draft.body, approvalHash: draft.approvalHash)
        } catch {
            // Certainly not queued: offline before it left, or an answer that means it never ran.
            return (VoiceToolReply.textNotSent(error as? ServerError), false)
        }
        switch outcome {
        case .unknown:
            Self.unconfirmedTexts.insert(draft.approvalHash)
            return (VoiceToolReply.textUnknown, true)
        case .refused(let code):
            return (VoiceToolReply.textRefused(code), false)
        case .queued(let queued):
            Self.unconfirmedTexts.remove(draft.approvalHash)
            Self.queuedTexts[draft.approvalHash] = Date()
            // A few seconds at most, so the reply comes well inside the agent's wait; after that
            // the reply says the server has it, and What Doddy did keeps the rest.
            let deadline = Date().addingTimeInterval(6)
            var status: UpdateStatus?
            while Date() < deadline {
                try? await Task.sleep(for: .seconds(1))
                guard let latest = try? await client.updateStatus(queued.id, timeout: 3) else { break }
                status = latest
                if !latest.isPending { break }
            }
            return (VoiceToolReply.textResult(status), true)
        }
    }

    // MARK: Calls to places (decision 2026-11-09-restaurant-calls-one-tap)

    /// Checks that calls can be made, sends the places to Doddy's server and shows the one card it
    /// returns, built from the exact payloads it will send. Nothing is dialled here; the card waits
    /// for the tap.
    private func proposeCallTask(_ draft: CallTaskDraft, toolCallID: String) async {
        guard let client = Self.messagingClient() else {
            await reply(toolCallID, VoiceToolReply.callTaskNoServer, isError: true)
            return
        }
        // No account yet means no verified number; asking the server would create an account.
        guard await client.hasAccount() else {
            await reply(toolCallID, VoiceToolReply.callTaskNoPhone)
            return
        }
        let availability: CallCaseAvailability
        do {
            availability = try await client.callCaseAvailability()
        } catch {
            await reply(toolCallID, VoiceToolReply.callTaskRefused(error), isError: true)
            return
        }
        guard availability.available, availability.phoneVerified else {
            await reply(toolCallID, VoiceToolReply.callTaskNotReady(availability))
            return
        }
        // Booking needs the booking agent on the server (decision 2026-11-12-book-agent); asking works without it.
        if draft.booking != nil, availability.booking != true {
            await reply(toolCallID, VoiceToolReply.callTaskBookingOff)
            return
        }
        // Ordering food needs the order agent on the server (decision 2026-11-12-food-by-phone).
        if draft.order != nil, availability.order != true {
            await reply(toolCallID, VoiceToolReply.callTaskOrderOff)
            return
        }
        guard !callerFirstName.isEmpty else {
            await reply(toolCallID, VoiceToolReply.callTaskNoName)
            return
        }
        let preview: CallTaskPreview
        do {
            preview = try await client.createCallTask(draft.body(principalName: callerFirstName))
        } catch {
            await reply(toolCallID, VoiceToolReply.callTaskRefused(error))
            return
        }
        propose(.callTask(toolCallID: toolCallID, preview: preview), toolCallID: toolCallID)
    }

    /// After the tap: the task with exactly this digest starts and its first place is dialled. An
    /// answer that never came back is `unknown`, and nothing is redialled (ADR-672).
    private func approveCallTask(_ preview: CallTaskPreview) async -> (reply: String, attempted: Bool) {
        guard let client = Self.messagingClient() else { return (VoiceToolReply.callTaskNoServer, false) }
        let approval: CallApproval
        do {
            approval = try await client.approveCallTask(preview.taskId, digest: preview.digest)
        } catch {
            return (VoiceToolReply.callTaskRefused(error), false)
        }
        guard approval.state != "unknown" else { return (VoiceToolReply.callTaskUnknown, true) }
        let first = preview.places.first?.callee.name ?? ""
        return (VoiceToolReply.callTaskStarted(first: first, count: preview.places.count, textResult: preview.textResult,
                                               booking: preview.isBooking, order: preview.isOrder), true)
    }

    // MARK: Calls from Doddy's number later (ADR-754)

    /// Approval hashes of calls whose booking was unknown, so the card can say so.
    private(set) static var unconfirmedCalls: Set<String> = []

    /// Asks Doddy's server which number is the user's, whether calls from Doddy are on and what
    /// quiet hours are before the card is shown. Nothing is booked here.
    private func proposeCallLater(_ draft: CallLaterDraft, toolCallID: String) async {
        guard let client = Self.messagingClient() else {
            await reply(toolCallID, VoiceToolReply.callNoServer, isError: true)
            return
        }
        // No account yet means no verified number; asking the server would create an account.
        guard await client.hasAccount() else {
            await reply(toolCallID, VoiceToolReply.callNotReady(.noPhone))
            return
        }
        let readiness: CallReadiness
        do {
            async let settings = client.callSettings()
            async let phone = client.phoneStatus()
            readiness = CallReadiness(settings: try await settings, phone: try await phone)
        } catch {
            await reply(toolCallID, VoiceToolReply.callCheckFailed(error as? ServerError), isError: true)
            return
        }
        guard case .ready(let to, let quietHours) = readiness else {
            await reply(toolCallID, VoiceToolReply.callNotReady(readiness))
            return
        }
        callLaterAllowQuiet = false
        propose(.callLater(toolCallID: toolCallID, draft: draft, to: to, quietHours: quietHours), toolCallID: toolCallID)
    }

    /// After the tap: the time, reason and quiet-hours choice go to the server with the approval
    /// hash of exactly what the card showed. The server books it; the call is placed later.
    private func bookCall(
        _ draft: CallLaterDraft, to: String, quietHours: CallQuietHours, allowQuietHours: Bool
    ) async -> (reply: String, attempted: Bool) {
        // An earlier try of this call (either switch) had an unclear outcome: a refusal now
        // doesn't mean nothing is booked.
        let identity = draft.identity(to: to)
        let mayBeBooked = Self.unconfirmedCalls.contains(identity)
        // The card may have waited: a time inside quiet hours needs the switch, and a time that
        // is now under a minute away can't be booked.
        if draft.inQuietHours(quietHours) && !allowQuietHours {
            return (VoiceToolReply.callRefused("quiet_hours", quietHours: quietHours, mayBeBooked: mayBeBooked), false)
        }
        if draft.at.timeIntervalSinceNow < 60 { return (VoiceToolReply.callRefused("too_soon", mayBeBooked: mayBeBooked), false) }
        guard let client = Self.messagingClient() else { return (VoiceToolReply.callNoServer, false) }
        do {
            switch try await client.scheduleCall(draft, to: to, allowQuietHours: allowQuietHours, language: .current) {
            case .booked:
                Self.unconfirmedCalls.remove(identity)
                Self.rememberBooked(draft)
                return (VoiceToolReply.callBooked(draft, calendar: .current), true)
            case .refused(let code):
                return (VoiceToolReply.callRefused(code, quietHours: quietHours, mayBeBooked: mayBeBooked), false)
            case .unknown:
                Self.unconfirmedCalls.insert(identity)
                Self.rememberBooked(draft)
                return (VoiceToolReply.callUnknown, true)
            }
        } catch {
            // Certainly not booked now: offline before it left, or an answer that means it never ran.
            let reply = VoiceToolReply.callNotBooked(error as? ServerError)
            return (mayBeBooked ? reply + " An earlier try of this call may already be booked: tell the user to check Settings, Phone calls." : reply, false)
        }
    }

    /// "Call me now" (decision 2026-11-10-call-me-now-by-voice): the same checks as a call booked for later,
    /// then a card with the number's last digits. Nothing is placed here.
    private func proposeCallNow(toolCallID: String) async {
        guard let client = Self.messagingClient() else {
            await reply(toolCallID, VoiceToolReply.callNowNoServer, isError: true)
            return
        }
        // No account yet means no verified number; asking the server would create an account.
        guard await client.hasAccount() else {
            await reply(toolCallID, VoiceToolReply.callNowNotReady(.noPhone))
            return
        }
        let readiness: CallReadiness
        do {
            async let settings = client.callSettings()
            async let phone = client.phoneStatus()
            readiness = CallReadiness(settings: try await settings, phone: try await phone)
        } catch {
            await reply(toolCallID, VoiceToolReply.callNowCheckFailed(error as? ServerError), isError: true)
            return
        }
        guard case .ready(let to, _) = readiness else {
            await reply(toolCallID, VoiceToolReply.callNowNotReady(readiness))
            return
        }
        propose(.callNow(toolCallID: toolCallID, to: to), toolCallID: toolCallID)
    }

    /// After the tap: the same request as Settings, Phone calls, Call me now. A request that may have
    /// reached the server is `unknown`, never retried (DOD-08, ADR-672).
    private func placeCallNow() async -> CallNowOutcome {
        guard let client = Self.messagingClient() else { return .refused(.notConfigured("no_server")) }
        do {
            return CallNowOutcome(try await client.callMeNow())
        } catch let error as ServerError {
            return .refused(error)
        } catch {
            return .refused(.unexpected(status: 0))
        }
    }

    /// So the app sends its time zone again when it comes to the front while this call may be
    /// waiting (CallZoneSync); the booking itself sent this zone.
    private static func rememberBooked(_ draft: CallLaterDraft) {
        let defaults = UserDefaults.standard
        let until = defaults.object(forKey: CallZoneSync.waitingUntilKey) as? Date
        defaults.set(max(until ?? draft.at, draft.at), forKey: CallZoneSync.waitingUntilKey)
        defaults.set(draft.timeZoneID, forKey: CallZoneSync.lastSentKey)
    }

    private func propose(_ action: PendingAction, toolCallID: String) {
        // A proposal that finished its lookups after End shows no card (review H9), and one that
        // finished after End and a new Start shows none in the new conversation (ADR-458).
        guard isLive, isCurrent(toolCallID) else { return dropStale(toolCallID) }
        // One card at a time: the newest ask wins. The card it replaces is closed unanswered and
        // nothing on it runs (owner, 10 Nov 2026).
        if let waiting = pendingAction {
            pendingAction = nil
            Task { await settleUnanswered(waiting, replaced: true) }
        }
        pendingAction = action
    }

    /// Looks in Calendar first, so asking again after an unconfirmed try never adds a second copy;
    /// the start is checked again too, since it may have passed while the card waited (ADR-128).
    private func addEvent(_ draft: CalendarEventDraft) -> EventAddOutcome? {
        guard devices.access(for: .calendar) == .granted else { return nil }
        return EventAddAction.add(draft, to: devices, now: Date(), calendar: .current)
    }

    // MARK: Action status (ADR-319)

    /// The reply for the agent, plus what the entry in "What Doddy did" keeps.
    private struct WriteResult {
        var reply: String
        var receipt: ActivityReceipt? = nil
        var attempted: Bool? = nil
        /// What Undo needs; kept only when the reply says it was added and checked (ADR-268).
        var undo: ActivityUndo? = nil
    }

    /// Stops before the card when this change was already tried too often without a confirmed
    /// result; otherwise remembers whether an earlier try is open, so the reply can say Doddy checked.
    private func mayTryAgain(_ toolCallID: String, app: ActivityApp) async -> Bool {
        if app == .memories { await settleLocalEntries() }
        let decision = ActionRetry.decide(for: asked[toolCallID], in: activity.entries, now: Date())
        if case .stop(let count) = decision {
            await reply(toolCallID, VoiceToolReply.retryStopped(count: count, app: app))
            return false
        }
        retryChecks[toolCallID] = decision
        return true
    }

    /// Unsure note and list entries are settled from Doddy's own database before any retry is
    /// decided (ADR-321), and only once it has loaded.
    private func settleLocalEntries() async {
        await store.reload()
        guard store.hasLoaded, store.loadError == nil else { return }
        activity.settleLocal(notes: store.memories, lists: store.lists)
    }

    private func eventResult(_ outcome: EventAddOutcome?, draft: CalendarEventDraft, retry: ActionRetryDecision?) -> WriteResult {
        guard let outcome else { return WriteResult(reply: VoiceToolReply.notAdded("Calendar isn't connected."), attempted: false) }
        var result = WriteResult(reply: VoiceToolReply.event(outcome, draft: draft, calendar: .current), attempted: outcome.attemptedWrite)
        switch outcome {
        case .added(let event, let eventID):
            result.receipt = ActivityReceipt(event: event, calendar: .current, readAt: Date())
            // Undo only with Calendar's own identifier for the event Doddy wrote. Undo removes a
            // single event only, so a repeating one isn't offered for undo.
            result.undo = draft.repeats == nil ? eventID.map { .addedEvent(eventID: $0, event: event) } : nil
            if case .checkFirst = retry { result.reply = VoiceToolReply.checkedFirst(result.reply, app: .calendar) }
        case .alreadyThere(let event):
            result.receipt = ActivityReceipt(event: event, calendar: .current, readAt: Date())
            if case .checkFirst = retry { result.reply = VoiceToolReply.checkedFirst(result.reply, app: .calendar) }
        default:
            break
        }
        return result
    }

    private func reminderResult(_ outcome: ReminderOutcome, draft: ReminderDraft, retry: ActionRetryDecision?) -> WriteResult {
        var result = WriteResult(
            reply: VoiceToolReply.reminder(outcome), attempted: outcome.attemptedWrite,
            undo: ActivityUndo.addedReminder(outcome, draft: draft))
        switch outcome {
        case .added(let receipt), .alreadyThere(let receipt):
            result.receipt = ActivityReceipt(reminder: receipt, readAt: Date())
            if case .checkFirst = retry { result.reply = VoiceToolReply.checkedFirst(result.reply, app: .reminders) }
        default:
            break
        }
        return result
    }

    /// The user tapped the undo card (ADR-271). The same checks and write as Undo in What Doddy
    /// did: the row as it is now, Pause all, the switch, then DeviceConnections' guarded undo.
    private func undoFromVoice(_ entry: ActivityEntry, attempt: Int) async -> String {
        // It may have been undone in Settings, or the day may have passed, while the card waited.
        guard let current = activity.entries.first(where: { $0.id == entry.id }), let undo = current.undo,
              current.canUndo(now: Date()) else {
            return VoiceToolReply.nothingToUndo
        }
        let result: UndoResult
        if let reason = undo.blocked(
            pauseAll: UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey),
            connectionOn: undo.connection.map(isOn) ?? true) {
            if let connection = undo.connection, !isOn(connection) { connectionNeeded = connection }
            result = .notDone(reason)
        } else if undo.connection == nil {
            result = await store.undoFromActivity(undo)
        } else {
            result = await devices.undo(undo)
        }
        activity.replace(ActivityLog.undid(current, result: result, at: Date()))
        // The on-screen Undo for the same change is no longer offered (ADR-268 merge); a later
        // conversation's receipt is a different change and is left alone (ADR-458).
        if result == .undone, onScreen(attempt), let receipt = changeReceipt {
            switch receipt.kind {
            case .event(let plan) where undo.isSameChange(event: plan, reminderID: nil): changeReceipt = nil
            case .reminder(let before, _) where undo.isSameChange(event: nil, reminderID: before.id): changeReceipt = nil
            default: break
            }
        }
        return VoiceToolReply.undo(result, undo)
    }

    // MARK: Changing events and reminders (ADR-229)

    /// Exactly one event with the title and start the agent read; otherwise the agent asks.
    private func proposeEventChange(_ draft: EventChangeDraft, toolCallID: String) async {
        guard devices.access(for: .calendar) == .granted else {
            await notConnected(toolCallID, .calendar)
            return
        }
        let events = await devices.readEvents(in: EventChange.searchRange(draft, calendar: .current))
        switch EventChange.match(draft, in: events, calendar: .current) {
        case .none, .several:
            await reply(toolCallID, VoiceToolReply.eventNotPrepared)
        case .one(let event):
            let place = draft.newLocation == nil ? nil : devices.eventLocation(event)
            let notes = draft.replaceNotes == nil ? nil : devices.eventNotes(event)
            guard let plan = EventChange.plan(draft, for: event, locationBefore: place, notesBefore: notes, calendar: .current) else {
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
        var draft = draft
        // The list the user named (ADR-302): exactly one of their Reminders lists, or nothing.
        if let name = draft.listName {
            let lists = devices.reminderLists()
            // ADR-718: none of the user's lists is named to the agent before the tap, and it isn't said
            // whether the name matched none or several.
            switch ReminderDetails.prepareList(name, in: lists) {
            case .refuse(let text):
                await reply(toolCallID, text)
                return
            case .list(let list):
                draft.toList = list
            }
        }
        do {
            let open = try await devices.incompleteReminders()
            switch EventChange.matchReminder(draft.title, in: open) {
            case .none, .several:
                await reply(toolCallID, VoiceToolReply.reminderNotPrepared)
            case .one(let reminder):
                // A repeat needs a due (Reminders' rule, ADR-314).
                if case .set? = draft.repeatChange, reminder.due == nil, draft.newDue == nil {
                    await reply(toolCallID, VoiceToolReply.reminderRepeatNeedsDue)
                    return
                }
                let nothingNew = draft.changesDetails
                    ? ReminderDetails.changesNothing(reminder, change: draft.details, newDue: draft.newDue)
                    : !draft.markDone && EventChange.sameDue(reminder.due, draft.newDue)
                if nothingNew {
                    await reply(toolCallID, VoiceToolReply.changeNothingNew)
                    return
                }
                propose(.changeReminder(toolCallID: toolCallID, reminder: reminder, draft: draft), toolCallID: toolCallID)
            }
        } catch {
            await reply(toolCallID, VoiceToolReply.failed(UserFacingError.message(for: error), nothing: .changed), isError: true)
        }
    }

    /// Checked again at the tap: permission, the time, and that the event still looks as shown.
    private func changeEvent(_ plan: EventChangePlan) -> String {
        guard isOn(.calendar), devices.access(for: .calendar) == .granted else {
            connectionNeeded = .calendar
            return VoiceToolReply.failed("Calendar isn't connected.", nothing: .changed)
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
            return VoiceToolReply.failed(UserFacingError.message(for: error), nothing: .changed)
        }
    }

    private func changeReminderDetails(_ reminder: ReminderSnapshot, _ draft: ReminderChangeDraft) -> String {
        guard isOn(.reminders), devices.access(for: .reminders) == .granted else {
            connectionNeeded = .reminders
            return VoiceToolReply.failed("Reminders isn't connected. Nothing changed.")
        }
        if EventChange.duePassed(draft.newDue, now: Date(), local: .current) { return VoiceToolReply.eventChangeTimePassed }
        do {
            switch try devices.changeReminder(reminder, .details(newDue: draft.newDue, draft.details)) {
            case .verified: return VoiceToolReply.reminderDetailsChanged(reminder.title, change: draft.details, due: draft.newDue)
            case .changedElsewhere: return VoiceToolReply.reminderChangedElsewhere
            case .unconfirmed: return VoiceToolReply.reminderChangeUnconfirmed
            }
        } catch {
            return VoiceToolReply.failed(UserFacingError.message(for: error))
        }
    }

    private func changeReminder(_ reminder: ReminderSnapshot, _ draft: ReminderChangeDraft) -> String {
        guard isOn(.reminders), devices.access(for: .reminders) == .granted else {
            connectionNeeded = .reminders
            return VoiceToolReply.failed("Reminders isn't connected.", nothing: .changed)
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
            return VoiceToolReply.failed(UserFacingError.message(for: error), nothing: .changed)
        }
    }

    // MARK: Several changes on one card (ADR-280)

    /// Items the user unticked on the several-changes card. Everything starts ticked.
    private(set) var bulkUnticked: Set<String> = []

    /// Ingredients the user unticked on the card (ADR-305), by position.
    private(set) var ingredientsUnticked: Set<Int> = []
    /// Shopping list+ (ADR-631): ingredients open on the At home list; the card says so and starts them unticked.
    private(set) var ingredientsAtHome: Set<Int> = []

    /// The At home list chosen on this iPhone (ADR-631), or nil.
    private var homeList: DoddyList? {
        HomeStock.list(storedID: UserDefaults.standard.string(forKey: HomeStock.preferenceKey), in: store.lists)
    }

    func toggleIngredient(_ index: Int) {
        if ingredientsUnticked.contains(index) { ingredientsUnticked.remove(index) } else { ingredientsUnticked.insert(index) }
    }

    func toggleBulkItem(_ id: String) {
        if bulkUnticked.contains(id) { bulkUnticked.remove(id) } else { bulkUnticked.insert(id) }
    }

    private func proposeBulkEventDelete(_ range: VoiceTimeRange, toolCallID: String) async {
        guard devices.access(for: .calendar) == .granted else {
            await notConnected(toolCallID, .calendar)
            return
        }
        let inRange = await devices.readEvents(in: range)
        let events = BulkChange.eventsToDelete(inRange, in: range)
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
            await reply(toolCallID, VoiceToolReply.failed(UserFacingError.message(for: error), nothing: .changed), isError: true)
        }
    }

    private func proposeBulk(_ items: [BulkItem], verb: String, skipped: [String], toolCallID: String) async {
        // The reminders were read after an await: the ticks belong to the conversation on screen.
        guard isCurrent(toolCallID) else { return dropStale(toolCallID) }
        guard !items.isEmpty else { return await reply(toolCallID, VoiceToolReply.bulkNothing) }
        guard items.count <= BulkChange.maxItems else { return await reply(toolCallID, VoiceToolReply.bulkTooMany(items.count)) }
        bulkUnticked = []
        propose(.bulk(toolCallID: toolCallID, items: items, verb: verb, skipped: skipped), toolCallID: toolCallID)
    }

    /// Each ticked item on its own: checked unchanged, changed, read back (ADR-280).
    private func runBulk(_ items: [BulkItem], verb: String, skipped: [String]) -> String {
        guard isOn(.calendar) || isOn(.reminders) else {
            return VoiceToolReply.failed("Calendar and Reminders aren't connected.", nothing: .changed)
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
        let events = await devices.readEvents(in: EventChange.searchRange(draft, calendar: .current))
        switch EventChange.match(draft, in: events, calendar: .current) {
        case .none, .several: await reply(toolCallID, VoiceToolReply.eventNotPrepared)
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
            case .none, .several: await reply(toolCallID, VoiceToolReply.reminderNotPrepared)
            case .one(let reminder): propose(.deleteReminder(toolCallID: toolCallID, reminder: reminder), toolCallID: toolCallID)
            }
        } catch {
            await reply(toolCallID, VoiceToolReply.failed(UserFacingError.message(for: error), nothing: .deleted), isError: true)
        }
    }

    /// Checked again at the tap: permission, and that the event still looks as shown. "Deleted"
    /// only when Calendar no longer has it.
    private func deleteEvent(_ event: CalendarEventSummary) -> String {
        guard isOn(.calendar), devices.access(for: .calendar) == .granted else {
            connectionNeeded = .calendar
            return VoiceToolReply.failed("Calendar isn't connected.", nothing: .deleted)
        }
        do {
            switch try devices.deleteEvent(event) {
            case .verified: return VoiceToolReply.eventDeleted(event, calendar: .current)
            case .changedElsewhere: return VoiceToolReply.eventChangedElsewhere
            case .unconfirmed: return VoiceToolReply.deleteUnconfirmed
            }
        } catch {
            return VoiceToolReply.failed(UserFacingError.message(for: error), nothing: .deleted)
        }
    }

    private func deleteReminder(_ reminder: ReminderSnapshot) -> String {
        guard isOn(.reminders), devices.access(for: .reminders) == .granted else {
            connectionNeeded = .reminders
            return VoiceToolReply.failed("Reminders isn't connected.", nothing: .deleted)
        }
        do {
            switch try devices.deleteReminder(reminder) {
            case .verified: return VoiceToolReply.reminderDeleted(reminder.title)
            case .changedElsewhere: return VoiceToolReply.reminderChangedElsewhere
            case .unconfirmed: return VoiceToolReply.deleteUnconfirmed
            }
        } catch {
            return VoiceToolReply.failed(UserFacingError.message(for: error), nothing: .deleted)
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
            // The same change's row in What Doddy did no longer offers Undo (ADR-268 merge).
            let target: (plan: EventChangePlan?, reminderID: String?) = switch receipt.kind {
            case .event(let changed): (changed, nil)
            case .reminder(let before, _): (nil, before.id)
            }
            if let row = ActivityLog.undoneOnScreen(activity.entries, event: target.plan, reminderID: target.reminderID, now: Date()) {
                activity.replace(row)
            }
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
    private func addReminder(_ draft: ReminderDraft, attempt: Int) async -> ReminderOutcome {
        guard isOn(.reminders), devices.access(for: .reminders) == .granted else {
            if onScreen(attempt) { connectionNeeded = .reminders }
            return .notAdded(.notAllowed)
        }
        let outcome = await ReminderAction.add(draft, to: devices, now: Date())
        if outcome == .notAdded(.notAllowed), onScreen(attempt) { connectionNeeded = .reminders }
        return outcome
    }

    /// Looks for a running copy only after an unconfirmed try of the same timer (ADR-320); "started"
    /// only when the iPhone lists it, with the ring time it lists.
    private func timerResult(_ draft: TimerDraft, retry: ActionRetryDecision?) async -> WriteResult {
        guard await devices.timerAccess() == .granted else {
            return WriteResult(reply: VoiceToolReply.notAdded("Notifications are off for Doddy."), attempted: false)
        }
        let outcome = await TimerStartAction.start(draft, with: devices, uncheckedSince: retry?.uncheckedSince)
        var result = WriteResult(reply: VoiceToolReply.timer(outcome, draft: draft, calendar: .current), attempted: outcome.attemptedWrite)
        switch outcome {
        case .started(let timer):
            result.receipt = ActivityReceipt(timer: timer, draft: draft, calendar: .current, readAt: Date())
            if case .checkFirst = retry { result.reply = VoiceToolReply.checkedFirst(result.reply, app: .timers) }
        case .alreadyRunning(let timer):
            result.receipt = ActivityReceipt(timer: timer, draft: draft, calendar: .current, readAt: Date())
        default:
            break
        }
        return result
    }

    /// Checked again at the tap: the switch, and that the time hasn't passed while the card waited.
    /// Looks at Doddy's alarms first, so asking again never sets a second one (ADR-320).
    private func alarmResult(_ draft: AlarmDraft, retry: ActionRetryDecision?) async -> WriteResult {
        guard isOn(.timers) else {
            connectionNeeded = .timers
            return WriteResult(reply: VoiceToolReply.failed("Timers and alarms are switched off. Nothing was set."), attempted: false)
        }
        let outcome = await AlarmSetAction.set(draft, with: alarmWriter, now: Date())
        var result = WriteResult(reply: VoiceToolReply.alarm(outcome), attempted: outcome.attemptedWrite)
        switch outcome {
        case .set(let alarm), .alreadySet(let alarm):
            result.receipt = ActivityReceipt(alarm: alarm, readAt: Date())
            if case .checkFirst = retry { result.reply = VoiceToolReply.checkedFirst(result.reply, app: .timers) }
        default:
            break
        }
        return result
    }

    /// Nothing ran yet. The access card goes up and the agent says one line ("Allow it on screen and
    /// I'll carry on"); after the tap it is told, and tries once more (ADR-578).
    private func notConnected(_ toolCallID: String, _ connection: VoiceConnection) async {
        // Some callers waited first (notification access): no prompt in a later conversation.
        guard isCurrent(toolCallID) else { return dropStale(toolCallID) }
        if connection == .steps, !devices.stepCountingAvailable {
            await reply(toolCallID, VoiceToolReply.stepsUnavailable)
            return
        }
        if connection == .home, !devices.homeAvailable {
            await reply(toolCallID, VoiceToolReply.homeUnavailable)
            return
        }
        if connection == .camera, !devices.cameraAvailable {
            await reply(toolCallID, VoiceToolReply.cameraUnavailable)
            return
        }
        // ADR-566: hold the call and slide the permission sheet up, instead of answering "not
        // connected" and leaving the user to find Settings. One sheet at a time; a connection the
        // user said Not now to isn't asked for again in this conversation.
        if isLive, let call = callsAsReceived[toolCallID],
           PermissionAsk.mayAsk(connection, declined: declinedPermissions, sheetShowing: permissionRequest != nil) {
            let refused: Bool
            if connection == .timers {
                refused = await devices.notificationAccess() == .denied
            } else {
                refused = devices.access(for: connection) == .denied
            }
            if isCurrent(toolCallID), permissionRequest == nil {
                let request = VoiceToolRequest.parse(name: call.toolName, parametersJSON: call.parameters)
                var askCard: AskCard?
                if case .yesFirst(let card) = AskFirst.need(for: request, polish: Self.cardsInPolish) { askCard = card }
                permissionRequest = PermissionRequest(
                    toolCallID: toolCallID, connection: connection, kind: PermissionAsk.kind(iosRefused: refused),
                    reason: PermissionAsk.reason(request), askCard: askCard, toolName: call.toolName, parameters: call.parameters)
                return
            }
            guard isCurrent(toolCallID) else { return dropStale(toolCallID) }
        }
        // Not asked on the sheet (another sheet is up, it was declined earlier, or the call came from a
        // card): the access card stays in the conversation with one-tap Allow (ADR-578).
        let permission = await systemPermission(connection)
        guard isCurrent(toolCallID) else { return dropStale(toolCallID) }
        if accessRequest?.connection != connection {
            accessRequest = ConnectionApprovalCard(connection: connection, permission: permission)
        }
        await reply(toolCallID, declinedPermissions.contains(connection)
            ? PermissionAsk.declinedEarlier(connection)
            : VoiceToolReply.notConnected(connection, card: accessRequest?.card ?? .allow))
    }

    /// Allow on the permission sheet (ADR-566). The switch goes on, iOS shows its own prompt if it
    /// has never been asked, and the call is handled again from the start: Pause all, its own card
    /// and every check run as if the switch had been on. For a read, the sheet showed exactly what
    /// will be read, so this tap is also its ASK-01 yes; a change still shows its own card.
    func allowPermission() async {
        guard let ask = permissionRequest else { return }
        permissionRequest = nil
        let attempt = startAttempt
        switch ask.kind {
        case .openSettings:
            // Only iPhone Settings can undo iOS's no. Doddy can't see what the user does there.
            connectionNeeded = ask.connection
            if let url = URL(string: UIApplication.openSettingsURLString) { _ = await open(url) }
            await reply(ask.toolCallID, PermissionAsk.blocked(ask.connection))
        case .turnOn:
            let access = await devices.request(ask.connection)
            if access == .granted { UserDefaults.standard.set(true, forKey: ask.connection.preferenceKey) }
            // The conversation ended while iOS was asking: the switch stays as the user chose, and
            // the call goes with its conversation.
            guard isLive, onScreen(attempt) else { return }
            guard access == .granted else {
                declinedPermissions.insert(ask.connection)
                connectionNeeded = ask.connection
                await reply(ask.toolCallID, PermissionAsk.declined(ask.connection))
                return
            }
            connectionNeeded = nil
            if ask.askCard != nil {
                let request = VoiceToolRequest.parse(name: ask.toolName, parametersJSON: ask.parameters)
                askLedger.asked(ask.toolCallID, request: request, needsTap: false, at: Date())
                _ = askLedger.answer(.tapped, for: ask.toolCallID, at: Date())
            }
            await handle(ClientToolCallEvent(toolName: ask.toolName, toolCallId: ask.toolCallID, parametersData: ask.parameters,
                                             eventId: 0, expectsResponse: true),
                         attempt: attempt)
        }
    }

    /// Not now, or the sheet swiped away (ADR-566): nothing was read or changed, and this
    /// connection isn't asked for again in this conversation.
    func declinePermission() async {
        guard let ask = permissionRequest else { return }
        permissionRequest = nil
        declinedPermissions.insert(ask.connection)
        connectionNeeded = ask.connection
        await reply(ask.toolCallID, ask.kind == .openSettings ? PermissionAsk.blocked(ask.connection) : PermissionAsk.declined(ask.connection))
    }

    func dismissPresentationReady() {
        presentationReady = nil
    }

    func dismissPhotoResults() {
        photoResults = nil
    }

    /// The camera screen went away, with or without a photo.
    func cameraClosed() {
        cameraRequest = nil
    }

    /// The training plan screen went away, with or without a kept plan.
    func planClosed() {
        planRequest = nil
    }

    // MARK: Access card (ADR-578)

    /// "Allow": the switch turns on, after iOS's own prompt when iOS has never asked (a refusal
    /// from before is returned as it is, with no prompt). On a yes the card goes and the agent
    /// tries once more, still asking for the action's own yes (ASK-01); on a no in iOS's prompt
    /// nothing changes; when iOS had already said no, the card offers iPhone Settings instead.
    func allowConnection() async {
        guard var request = accessRequest else { return }
        guard request.beginAllow() else { return }
        accessRequest = request
        let connection = request.connection
        let attempt = startAttempt
        let before = await systemPermission(connection)
        // The switch is stored on only when iOS allows it, as in Settings › Connections.
        if await devices.request(connection) == .granted {
            UserDefaults.standard.set(true, forKey: connection.preferenceKey)
        }
        // Only the card on screen is answered (ADR-458): End, or a newer card, drops this one.
        guard onScreen(attempt), accessRequest?.connection == connection else { return }
        let outcome = ConnectionApproval.outcome(before: before, switchIsOn: isOn(connection))
        if request.finish(outcome) {
            accessRequest = request
        } else {
            accessRequest = nil
            await tellAgent(outcome, connection)
        }
    }

    /// "Open iPhone Settings": Doddy's own page there, the only place iOS lets a refused
    /// permission change. Looked at again when Doddy is in front (`recheckConnectionAccess`).
    func openSettingsForConnection() async {
        guard var request = accessRequest else { return }
        guard request.sendToSettings() else { return }
        accessRequest = request
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        _ = await open(url)
    }

    /// Doddy is in front again. After the card sent the user to iPhone Settings, the switch turns
    /// on only if iOS now allows it: that tap and their own change there are the yes.
    func recheckConnectionAccess() async {
        guard let request = accessRequest, request.sentToSettings else { return }
        let attempt = startAttempt
        let now = await systemPermission(request.connection)
        guard request.allowsOnReturn(now), onScreen(attempt), accessRequest == request else { return }
        UserDefaults.standard.set(true, forKey: request.connection.preferenceKey)
        accessRequest = nil
        await tellAgent(.allowed, request.connection)
    }

    /// "Not now": nothing changes, and the agent is told quietly not to ask again.
    func declineConnection() async {
        guard let request = accessRequest, request.canDecline else { return }
        accessRequest = nil
        await tellAgent(.declined, request.connection)
    }

    /// Called after the Connections sheet (the card's Details) closes: if the user turned it on
    /// there, the card goes and the agent is told, as after Allow.
    func refreshConnectionNeeded() async {
        guard let request = accessRequest, !request.isWorking, isOn(request.connection) else { return }
        let attempt = startAttempt
        guard await systemPermission(request.connection) == .granted, onScreen(attempt), accessRequest == request else { return }
        accessRequest = nil
        await tellAgent(.allowed, request.connection)
    }

    /// An "(app)" message: after a yes Doddy carries on now; after a no it is background only.
    private func tellAgent(_ outcome: ConnectionApproval.Outcome, _ connection: VoiceConnection) async {
        guard isLive else { return }
        switch outcome {
        case .allowed:
            await sendToAgent(ConnectionApproval.allowedMessage(connection))
        case .declined:
            try? await conversation?.updateContext("\(TranslatorSession.appMessagePrefix) \(ConnectionApproval.declinedContext(connection))")
        case .blockedBySystem:
            break
        }
    }

    /// iOS's answer for the permission `connection` needs. Timers use notification permission,
    /// which iOS reports only asynchronously.
    private func systemPermission(_ connection: VoiceConnection) async -> ConnectionApproval.SystemPermission {
        if connection == .timers { return Self.permission(await devices.notificationAccess()) }
        return Self.permission(devices.access(for: connection))
    }

    /// The same without waiting, for the paths that can't: timers read as not asked here, and
    /// the Allow tap reads them properly.
    private func systemPermissionNow(_ connection: VoiceConnection) -> ConnectionApproval.SystemPermission {
        Self.permission(devices.access(for: connection))
    }

    private static func permission(_ access: DeviceConnections.Access) -> ConnectionApproval.SystemPermission {
        switch access {
        case .granted: .granted
        case .notDetermined: .notAsked
        case .denied: .denied
        }
    }

    private func open(_ url: URL) async -> Bool {
        await UIApplication.shared.open(url)
    }

    private func isOn(_ connection: VoiceConnection) -> Bool {
        UserDefaults.standard.bool(forKey: connection.preferenceKey)
    }

    /// `undo` is what "What Doddy did" needs to put the change back; the entry keeps it only when
    /// `text` says the change was made and checked (ADR-268). A reminder or event add passes its
    /// receipt, attempt and undo through `writeResults` instead (ADR-319).
    private func reply(_ toolCallID: String, _ text: String, isError: Bool = false, undo: ActivityUndo? = nil) async {
        callsAsReceived[toolCallID] = nil
        turnFeedback.toolAnswered(id: toolCallID)
        let write = writeResults.removeValue(forKey: toolCallID)
        retryChecks[toolCallID] = nil
        let undo = undo ?? write?.undo
        if let request = asked.removeValue(forKey: toolCallID) {
            if let entry = started.removeValue(forKey: toolCallID) {
                activity.replace(ActivityEntry.finished(
                    entry, request: request, reply: text, at: Date(), undo: undo, receipt: write?.receipt, attempted: write?.attempted))
            } else {
                activity.append(ActivityEntry(
                    request: request, reply: text, at: Date(), undo: undo, receipt: write?.receipt, attempted: write?.attempted))
            }
        }
        // Logged above whatever happens (a confirmed change that ran is still recorded), but sent
        // only to the conversation that asked (ADR-458): a result from an ended conversation never
        // reaches the next one.
        guard callOwners.finish(toolCallID, attempt: startAttempt) else {
            Self.toolLog.notice("result of a tool call from an ended conversation was not sent")
            return
        }
        try? await conversation?.sendToolResult(for: toolCallID, result: text, isError: isError)
    }

    /// True while the conversation `toolCallID` arrived in is still the one on screen (ADR-458).
    private func isCurrent(_ toolCallID: String) -> Bool {
        callOwners.isCurrent(toolCallID, attempt: startAttempt)
    }

    /// True while the conversation of start `attempt` is still the one on screen (ADR-458). For a
    /// change the user confirmed: it runs to the end, but only its own screen shows how it went.
    private func onScreen(_ attempt: Int) -> Bool {
        attempt == startAttempt
    }

    /// On disk before a change runs: if the conversation ends, or Doddy is closed, mid-write, the
    /// row says "in progress" (then "Not sure") until the result replaces it, never "not done"
    /// (`logUnanswered` skips started rows), and is settled at the next look (ADR-321). Confirmed
    /// cards and the list tools (ADR-458).
    private func markStarted(_ toolCallID: String) {
        guard started[toolCallID] == nil, let request = asked[toolCallID] else { return }
        let entry = ActivityEntry.started(request, at: Date())
        activity.append(entry)
        started[toolCallID] = entry
    }

    /// A call whose conversation ended before its card or result was ready (ADR-458): nothing is
    /// shown or sent. What it asked is logged as not done, once; `stop()` has usually done that.
    private func dropStale(_ toolCallID: String, steps: [PlanStep] = []) {
        callOwners.forget(toolCallID)
        retryChecks[toolCallID] = nil
        writeResults[toolCallID] = nil
        Self.toolLog.notice("dropped a tool call from an ended conversation")
        if started[toolCallID] == nil, let request = asked.removeValue(forKey: toolCallID) {
            activity.append(Self.unanswered(request))
        }
        guard !steps.isEmpty else { return }
        let planID = UUID()
        for step in steps {
            guard let request = step.activity(calendar: .current) else { continue }
            activity.append(Self.unanswered(request, plan: ActivityPlanRef(id: planID, step: step.number, count: steps.count)))
        }
    }

    /// A request that got no answer: nothing happened.
    private static func unanswered(_ request: ActivityRequest, plan: ActivityPlanRef? = nil) -> ActivityEntry {
        var entry = ActivityEntry(request: request, reply: "", at: Date(), plan: plan)
        entry.outcome = .notDone
        entry.note = ActivityLog.unansweredNote
        return entry
    }

    /// Requests still waiting on a card when the conversation ends: nothing happened.
    private func logUnanswered() {
        // Confirmed changes still running keep their entry; their result replaces it when it arrives.
        for (toolCallID, request) in asked where started[toolCallID] == nil {
            activity.append(Self.unanswered(request))
            asked[toolCallID] = nil
        }
        for (_, steps) in askedPlans {
            let planID = UUID()
            for step in steps {
                guard let request = step.activity(calendar: .current) else { continue }
                activity.append(Self.unanswered(request, plan: ActivityPlanRef(id: planID, step: step.number, count: steps.count)))
            }
        }
        askedPlans = [:]
        retryChecks = [:]
        writeResults = [:]
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
             .deleteEvent, .deleteReminder, .bulk, .parking, .ingredients, .leaveBy, .presentation, .home, .callLater, .callNow, .callTask: true
        // Each step of a plan is logged on its own (runPlan), not the plan as a whole. An undo
        // is recorded on the row it undoes (ADR-271).
        // ASK-01 asks: the change itself (a list item) is logged by the flow it runs. A BLIK card only
        // shows what the user sends in their bank app (ADR-510).
        case .map, .shortcut, .message, .blik, .plan, .undo, .ask, .cloudRead, .camera: false
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
