import DoddyCore
import Foundation
import Observation

/// How the rest of the app asks whether the Face ID lock is up (ADR-723). `DoddyApp.init` sets it to
/// `AppLock`'s answer. It lives here, not in `AppLock`, because the router and Siri's note lookup import
/// no UI framework and still compile in `scripts/typecheck_app_logic.sh`. Until it is set, and with the
/// lock off, nothing is locked.
@MainActor
enum AppLockGate {
    static var isLocked: @MainActor () -> Bool = { false }

    /// True when `entry` may go ahead now. Siri and Shortcuts can't wait for a face, so an intent that
    /// reads or changes what Doddy keeps asks this first and answers `AppLockPolicy.lockedAnswer` when it
    /// is false (ADR-723). With the lock off it is always true.
    static func allows(_ entry: AppLockEntry) -> Bool {
        AppLockPolicy.allows(entry, isLocked: isLocked())
    }
}

/// Single owner of "what the app shows because a shortcut ran". The Talk to Doddy intent and
/// the UI both go through it, so a second invocation focuses the open conversation instead of
/// starting a second one, and a tap test can claim the invocation as its receipt.
///
/// Every way in that shows notes or opens a screen asks the Face ID lock first (ADR-723, the rules
/// are `AppLockPolicy` in DoddyCore): while Doddy is locked the request is kept for a couple of
/// minutes and goes ahead after the unlock (`runHeldAfterUnlock`). With the lock off, nothing is kept.
@MainActor
@Observable
final class ShortcutRouter {
    static let shared = ShortcutRouter()

    /// Bound to the full-screen voice conversation in `RootView`.
    var isVoicePresented = false
    /// Home › Translate (ADR-215): the conversation that opens next starts in translator mode.
    private var translatorPreset: TranslatorSetup?
    /// Set when "Talk to Doddy" opens the conversation; taken once by its start (`takeTalkToDoddyOpening`).
    private var talkToDoddyOpened = false
    /// The morning check-in screen (ADR-220), opened from its notification or Settings.
    var isCheckInPresented = false
    /// The weekly tidy-up screen (ADR-228), from its notification or Settings.
    var isTidyUpPresented = false
    /// The evening wrap-up screen (ADR-261), from its notification or Settings.
    var isWrapUpPresented = false
    /// The weekly look-back (ADR-306).
    var isLookBackPresented = false
    /// The weekly plan (ADR-651), from its notification or Settings.
    var isWeeklyPlanPresented = false
    /// "Talk it through": the conversation that opens next starts with this briefing.
    private var checkInBriefing: MorningBriefing?
    /// "Ask me about it" on a recently saved note (ADR-403), for the conversation that is starting.
    private var noteToAsk: UUID?
    /// Bound to the guided Back Tap setup sheet in `RootView`.
    var isSetupPresented = false
    let setup: BackTapSetupModel
    /// "Save to Doddy" drafts (ADR-179). `RootView` shows `drafts.shown` in a capture sheet.
    private(set) var drafts = SharedDraftQueue()
    /// Capture screens open anywhere in the app (Home, Memories or a shared draft).
    private var openCaptureScreens = 0
    /// First-use onboarding covers the tabs, so a draft sheet can't appear until it is done.
    /// Set by `RootView`.
    var isOnboardingShown = false {
        didSet { if oldValue && !isOnboardingShown { showWaitingDraft() } }
    }
    /// "Find in Doddy" (ADR-181). `RootView` switches to Memories → Find when it changes;
    /// Find takes the query once with `takeFindQuery()`.
    private(set) var findRequest: FindRequest?
    private var unclaimedFindQuery: String?

    /// Requests that came in while the Face ID lock was up, to go ahead after the unlock (ADR-723).
    @ObservationIgnored private var held = AppLockHold<@MainActor () -> Void>()

    init(setup: BackTapSetupModel = BackTapSetupModel()) {
        self.setup = setup
    }

    // MARK: The Face ID lock (ADR-723)

    /// True when `entry` may go ahead now. While the lock is up it is false, and `again` (if given and the
    /// policy says to wait) is kept to run after the unlock. With the lock off it is always true and
    /// nothing is kept, so Doddy behaves exactly as it did before the lock was looked at here.
    private func mayGoAhead(_ entry: AppLockEntry, again: (@MainActor () -> Void)? = nil) -> Bool {
        guard !AppLockPolicy.allows(entry, isLocked: AppLockGate.isLocked()) else { return true }
        if AppLockPolicy.whenLocked(entry) == .afterUnlock, let again { held.hold(again, for: entry, at: .now) }
        return false
    }

    /// Runs `action` now, or after the unlock if the lock is up. For a way in whose screen isn't the
    /// router's (the saved parking spot opens in Maps).
    func runWhenUnlocked(_ entry: AppLockEntry, _ action: @escaping @MainActor () -> Void) {
        if mayGoAhead(entry, again: action) { action() }
    }

    /// The Face ID cover is gone: what was asked for while it was up goes ahead now, oldest first. Each
    /// request goes through its own checks again, as it would have at the time it came in.
    func runHeldAfterUnlock() {
        for action in held.release(at: .now) { action() }
        showWaitingDraft()
    }

    /// The Face ID lock came back (the app was away long enough): every screen the router presents is
    /// closed, and what was prepared for a conversation is dropped, so nothing stays above the cover and
    /// nothing opens by itself later. A capture screen's words are already kept as an unfinished note (ADR-362).
    func dismissForLock() {
        isVoicePresented = false
        isSetupPresented = false
        isCheckInPresented = false
        isTidyUpPresented = false
        isWrapUpPresented = false
        isLookBackPresented = false
        isWeeklyPlanPresented = false
        isRecordingsPresented = false
        isCallRecapsPresented = false
        isMessagesRequested = false
        priceCheckLink = nil
        translatorPreset = nil
        talkToDoddyOpened = false
        checkInBriefing = nil
        noteToAsk = nil
        recordingToOpen = nil
        if drafts.shown != nil { drafts.shownClosed() }
    }

    /// Called from `TalkToDoddyIntent.perform()`. If a tap test is active the invocation is its
    /// receipt and the setup sheet takes over; otherwise the voice conversation opens.
    /// With `startOnHome` the voice screen is not opened: the answer is true when the caller should
    /// start the conversation on Home, where its strip over the island is the screen (owner, 9 Nov
    /// 2026: "only the small island"). The router has no UI types, so the caller starts it.
    @discardableResult
    func talkToDoddyInvoked(at now: Date = .now, startOnHome: Bool = false) -> Bool {
        guard mayGoAhead(.startConversation, again: { [self] in _ = talkToDoddyInvoked(at: now, startOnHome: startOnHome) }) else { return false }
        // A shared draft's capture sheet is up on the same view as the conversation cover: a
        // second presentation would be dropped and leave drafts queued behind it for good.
        if drafts.shown != nil { return false }
        // Whatever started it, the shortcut ran: the card and the weekly reminder have done their job.
        setup.noteShortcutRan()
        Task { await OpenWaysReminderScheduler.refresh(setup) }
        if setup.deliver(ShortcutReceipt(receivedAt: now)) {
            isVoicePresented = false
            isSetupPresented = true
            return false
        } else if !BackTapAction.stored(UserDefaults.standard.string(forKey: PreferenceKey.backTapAction)).startsConversation {
            // Settings → Back Tap and Siri → "Only open Doddy": the app comes forward (the intent
            // opens it) and no conversation, microphone or island starts.
            return false
        } else {
            isSetupPresented = false
            if startOnHome, !isVoicePresented { return true }
            if !isVoicePresented { talkToDoddyOpened = true }
            isVoicePresented = true
            return false
        }
    }

    /// The "Talk to Doddy" control brought Doddy forward (after iOS's "Open Doddy?" when the island
    /// start needed the app, or pressed with Doddy on screen; ADR-579, ADR-632). Opens the conversation
    /// with the shortcut greeting. Unlike `talkToDoddyInvoked` it isn't a Back Tap test receipt
    /// and ignores Back Tap's "Only open Doddy": the user chose to talk. Never over a shared
    /// draft's sheet; the "Before we start" step (ADR-581) covers the app until it is done.
    func talkButtonOpenedApp() {
        guard mayGoAhead(.startConversation, again: { [self] in talkButtonOpenedApp() }) else { return }
        if drafts.shown != nil { return }
        isSetupPresented = false
        if !isVoicePresented { talkToDoddyOpened = true }
        isVoicePresented = true
    }

    /// Called by the opening when Settings → "Start listening when I open Doddy" is on (ADR-225).
    /// Opens the conversation unless one is already open or something else is on screen; it
    /// never starts a second conversation and never pushes a sheet aside.
    func startListeningOnOpen() {
        guard mayGoAhead(.startConversation, again: { [self] in startListeningOnOpen() }) else { return }
        guard !isVoicePresented, !isSetupPresented, !isCheckInPresented, !isTidyUpPresented, !isWrapUpPresented, !isLookBackPresented, !isWeeklyPlanPresented, !isOnboardingShown, drafts.shown == nil else { return }
        isVoicePresented = true
    }

    /// Call only while a conversation is running (`VoiceSessionController.runningConversation`).
    /// Doddy came to the front, or Talk in the Island was pressed with him on screen, and no screen
    /// shows that conversation: it was started without opening the app (ADR-577), and the user
    /// just tapped its island. Shows it; the voice screen takes the running conversation instead
    /// of starting another. Never over another sheet or the introduction.
    func showConversationStartedElsewhere() {
        // Not over the Face ID cover; the app brings it forward itself after the unlock (ADR-577, ADR-723).
        guard mayGoAhead(.showRunningConversation) else { return }
        guard !isVoicePresented, !isCheckInPresented, !isTidyUpPresented, !isWrapUpPresented,
              !isLookBackPresented, !isWeeklyPlanPresented, !isOnboardingShown, drafts.shown == nil else { return }
        isSetupPresented = false
        isVoicePresented = true
    }

    /// Opens the conversation in translator mode, unless one is already open.
    func openTranslator(_ setup: TranslatorSetup) {
        guard mayGoAhead(.startConversation) else { return }
        guard !isVoicePresented, drafts.shown == nil else { return }
        isSetupPresented = false
        translatorPreset = setup
        isVoicePresented = true
    }

    /// The check-in notification was tapped: show the check-in screen, unless a conversation or
    /// a shared draft is already up (the user is busy; the notification stays in history).
    func morningCheckInOpened() {
        guard mayGoAhead(.openNoteSheet, again: { [self] in morningCheckInOpened() }) else { return }
        guard !isVoicePresented, !isWrapUpPresented, !isWeeklyPlanPresented, drafts.shown == nil else { return }
        isSetupPresented = false
        isCheckInPresented = true
    }

    /// The weekly "Open Doddy faster" reminder was tapped: show the ways, unless something else is up.
    func openWaysOpened() {
        guard mayGoAhead(.openWays, again: { [self] in openWaysOpened() }) else { return }
        guard !isVoicePresented, !isCheckInPresented, !isTidyUpPresented, !isWrapUpPresented, !isLookBackPresented, !isWeeklyPlanPresented,
              !isOnboardingShown, drafts.shown == nil else { return }
        isSetupPresented = true
    }

    /// The tidy-up notification was tapped, or Settings asked for it.
    func tidyUpOpened() {
        guard mayGoAhead(.openNoteSheet, again: { [self] in tidyUpOpened() }) else { return }
        guard !isVoicePresented, !isCheckInPresented, !isWrapUpPresented, !isWeeklyPlanPresented, drafts.shown == nil else { return }
        isSetupPresented = false
        isTidyUpPresented = true
    }

    /// The wrap-up notification was tapped, or Settings asked for it.
    func eveningWrapUpOpened() {
        guard mayGoAhead(.openNoteSheet, again: { [self] in eveningWrapUpOpened() }) else { return }
        guard !isVoicePresented, !isCheckInPresented, !isTidyUpPresented, !isWeeklyPlanPresented, drafts.shown == nil else { return }
        isSetupPresented = false
        isWrapUpPresented = true
    }

    /// The weekly plan's notification was tapped, or Settings asked for it (ADR-651).
    func weeklyPlanOpened() {
        guard mayGoAhead(.openNoteSheet, again: { [self] in weeklyPlanOpened() }) else { return }
        guard !isVoicePresented, !isCheckInPresented, !isTidyUpPresented, !isWrapUpPresented, !isLookBackPresented,
              drafts.shown == nil else { return }
        isSetupPresented = false
        isWeeklyPlanPresented = true
    }

    /// The look-back notification was tapped, or Settings asked for it (ADR-306).
    func weeklyLookBackOpened() {
        guard mayGoAhead(.openNoteSheet, again: { [self] in weeklyLookBackOpened() }) else { return }
        guard !isVoicePresented, !isCheckInPresented, !isTidyUpPresented, !isWrapUpPresented, !isWeeklyPlanPresented,
              drafts.shown == nil else { return }
        isSetupPresented = false
        isLookBackPresented = true
    }

    /// "Talk it through" on the check-in screen. The sheet closes first; the conversation opens
    /// from `checkInSheetDismissed()`, once it has gone (one presentation at a time).
    func openCheckInConversation(_ briefing: MorningBriefing) {
        guard mayGoAhead(.startConversation) else { return }
        guard !isVoicePresented, drafts.shown == nil else { return }
        checkInBriefing = briefing
        isCheckInPresented = false
    }

    func checkInSheetDismissed() {
        if checkInBriefing != nil, !isVoicePresented, !AppLockGate.isLocked() { isVoicePresented = true } else { showWaitingDraft() }
    }

    /// A finished call's push was tapped (ADR-730): Files opens on Home, where Calls lists the recaps.
    /// Navigation only: it starts nothing and sends nothing.
    var isCallRecapsPresented = false

    func callRecapsOpened() {
        guard mayGoAhead(.openNoteSheet, again: { [self] in callRecapsOpened() }) else { return }
        guard !isVoicePresented, drafts.shown == nil else { return }
        isSetupPresented = false
        isCallRecapsPresented = true
    }

    /// A finished task's or file's push was tapped (owner, 10 Nov 2026): Home opens Messages, where Doddy's
    /// message about it is. Navigation only: it starts nothing and sends nothing. Home takes it once.
    var isMessagesRequested = false

    func messagesOpened() {
        guard mayGoAhead(.openNoteSheet, again: { [self] in messagesOpened() }) else { return }
        guard !isVoicePresented, drafts.shown == nil else { return }
        isSetupPresented = false
        isMessagesRequested = true
    }

    /// DODDY Capture (ADR-588): Recordings is a sheet on Home. A link, the island's Open button and
    /// "Open Latest Recording" all come here. Navigation only: it never starts or stops anything.
    var isRecordingsPresented = false
    private var recordingToOpen: UUID?

    func openRecordings() {
        // Hidden in this build (decision 2026-11-07-release-scope): a link or an older control opens nothing.
        guard ReleaseScopeStore.current.shows(.recordings) else { return }
        guard mayGoAhead(.openRecordings, again: { [self] in openRecordings() }) else { return }
        guard !isVoicePresented, drafts.shown == nil else { return }
        isSetupPresented = false
        isRecordingsPresented = true
    }

    /// The newest recording's page, or the list if there is none.
    func openLatestRecording() async {
        // Nothing is looked up while the lock is up; the whole request is made again after the unlock (ADR-723).
        guard mayGoAhead(.openRecordings, again: { [self] in Task { await self.openLatestRecording() } }) else { return }
        if let repository = AppEnvironment.shared.recordingRepository,
           let latest = try? await repository.recordings(category: .all, limit: 1, offset: 0).first {
            recordingToOpen = latest.recording.id
        }
        openRecordings()
    }

    /// True from "Open Latest Recording" until the Recordings screen has taken it.
    var hasRecordingToOpen: Bool { recordingToOpen != nil }

    /// The recording to open once, when Recordings appears.
    func takeRecordingToOpen() -> UUID? {
        defer { recordingToOpen = nil }
        return recordingToOpen
    }

    /// "Ask me about it" on Home (ADR-403): a conversation about that note. Never over another sheet.
    func askAboutNote(_ id: UUID) {
        guard mayGoAhead(.startConversation) else { return }
        guard !isVoicePresented, !isSetupPresented, drafts.shown == nil else { return }
        noteToAsk = id
        isVoicePresented = true
    }

    /// The note to ask about in the conversation that is starting, once.
    func takeNoteToAsk() -> UUID? {
        defer { noteToAsk = nil }
        return noteToAsk
    }

    /// The check-in briefing for the conversation that is starting, once.
    func takeCheckInBriefing() -> MorningBriefing? {
        defer { checkInBriefing = nil }
        return checkInBriefing
    }

    /// The translator setup for the conversation that is starting, once.
    func takeTranslatorPreset() -> TranslatorSetup? {
        defer { translatorPreset = nil }
        return translatorPreset
    }

    /// True once when "Talk to Doddy" opened the conversation (Back Tap, Action Button, Siri,
    /// Control Center), so it can greet on the island. Not set when a conversation was already open.
    func takeTalkToDoddyOpening() -> Bool {
        defer { talkToDoddyOpened = false }
        return talkToDoddyOpened
    }

    /// A product link shared from Safari or a shop app with "Check the price" (docs/implementation/SHOPPING.md "Check
    /// this"). Home opens the Shopping screen, which takes it into its "Check this" card. Nothing is read from the
    /// shop and nothing is sent until the person taps there.
    var priceCheckLink: String?

    /// Called by the app when it picks the shared link up (after the Face ID lock, if there is one). Text with no
    /// web address in it is ignored.
    func priceCheckInvoked(text: String) {
        guard SharedShopPage.parse(text) != nil else { return }
        priceCheckLink = text
    }

    /// The waiting link, once.
    func takePriceCheckLink() -> String? {
        defer { priceCheckLink = nil }
        return priceCheckLink
    }

    /// Called from `SaveToDoddyIntent.perform()`. Shows the text on the capture screen, or keeps
    /// it until the conversation or another capture screen closes. Never saves anything.
    func saveToDoddyInvoked(text: String) {
        guard mayGoAhead(.openCapture, again: { [self] in saveToDoddyInvoked(text: text) }) else { return }
        drafts.receive(SharedDraft(text: text), blocked: closeSetupSheet() || isCaptureBlocked)
    }

    /// Called from `NewNoteIntent.perform()` (control, Siri, Action Button). If a capture screen
    /// is already open the user is already where they asked to be, so nothing else opens; and an
    /// empty screen never takes the place of shared text that is waiting to be shown.
    func newNoteInvoked() {
        guard mayGoAhead(.openCapture, again: { [self] in newNoteInvoked() }) else { return }
        let setupWasOpen = closeSetupSheet()
        guard openCaptureScreens == 0, drafts.shown == nil, drafts.waiting == nil else { return }
        drafts.receive(.newNote(), blocked: setupWasOpen || isCaptureBlocked)
    }

    /// Closes the Back Tap setup sheet. Returns true if it was open: a draft then waits for the
    /// sheet's `onDismiss` instead of being presented while the sheet is still going away.
    private func closeSetupSheet() -> Bool {
        let wasOpen = isSetupPresented
        isSetupPresented = false
        return wasOpen
    }

    /// Called from `FindInDoddyIntent.perform()`. Closes the setup sheet; an open conversation
    /// or capture screen stays open and Find is ready underneath when it closes.
    func findInDoddyInvoked(query: String) {
        guard mayGoAhead(.openFind, again: { [self] in findInDoddyInvoked(query: query) }) else { return }
        isSetupPresented = false
        let request = FindRequest(query: query)
        unclaimedFindQuery = request.query
        findRequest = request
    }

    /// The query for the Find screen that is opening, once; later Find screens start empty.
    func takeFindQuery() -> String {
        defer { unclaimedFindQuery = nil }
        return unclaimedFindQuery ?? ""
    }

    /// The shared-draft sheet's binding: setting nil (dismissal) closes the shown draft.
    var shownDraft: SharedDraft? {
        get { drafts.shown }
        set { if newValue == nil { drafts.shownClosed() } }
    }

    func captureScreenAppeared() { openCaptureScreens += 1 }

    func captureScreenDisappeared() {
        openCaptureScreens = max(0, openCaptureScreens - 1)
        showWaitingDraft()
    }

    /// Call when something that blocks the capture sheet has finished closing (the conversation
    /// cover's or setup sheet's `onDismiss`, the end of onboarding, a capture screen).
    func showWaitingDraft() {
        // Not over the Face ID cover (ADR-723): a draft that is waiting comes after the unlock.
        guard !AppLockGate.isLocked() else { return }
        drafts.unblocked(stillBlocked: isCaptureBlocked)
    }

    private var isCaptureBlocked: Bool {
        isVoicePresented || isSetupPresented || isOnboardingShown || openCaptureScreens > 0
    }
}

/// Main-actor state over the deterministic `BackTapSetupCoordinator`. Persists only the
/// outcome (not started / deferred / tested by the user) and an active test window, as JSON in
/// UserDefaults next to the other UI preferences. Never any transcript or reported page.
@MainActor
@Observable
final class BackTapSetupModel {
    private(set) var coordinator: BackTapSetupCoordinator
    /// What decides when the Home card comes back and when the weekly reminder stops (ADR-559).
    /// Counts and flags only.
    private(set) var offer: OpenWaysOfferState
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults
        coordinator = BackTapSetupCoordinator(summary: Self.load(from: defaults), now: now)
        offer = Self.loadOffer(from: defaults)
    }

    var phase: BackTapSetupPhase { coordinator.phase }

    /// The user is using a way (Doddy's shortcut ran) or said their Back Tap test worked.
    var isUsingAWay: Bool { OpenWaysOffer.isDone(phase: phase, state: offer) }

    func cardDue(connectedConversations: Int) -> Bool {
        OpenWaysOffer.cardDue(phase: phase, state: offer, connectedConversations: connectedConversations)
    }

    func reminderWanted(connectedConversations: Int) -> Bool {
        OpenWaysOffer.reminderWanted(phase: phase, state: offer, connectedConversations: connectedConversations)
    }

    @discardableResult
    func send(_ event: BackTapSetupEvent) -> BackTapSetupOutcome {
        let outcome = coordinator.handle(event)
        persist()
        if event == .deferSetup, outcome == .accepted {
            offer.deferred(atConversations: defaults.integer(forKey: PreferenceKey.connectedConversations))
            persistOffer()
        }
        return outcome
    }

    /// Doddy's "Talk to Doddy" shortcut ran, from Back Tap, the Action Button, a control, Siri or
    /// the Shortcuts app. Doddy can't tell which; it is enough to stop offering and reminding.
    func noteShortcutRan() {
        guard !offer.usedAWay else { return }
        offer.wayUsed()
        persistOffer()
    }

    /// Settings → "Remind me about ways to open Doddy".
    func setReminders(on: Bool) {
        offer.setReminders(on: on)
        persistOffer()
    }

    /// A round of weekly reminders was put in iOS just now.
    func reminderRoundArmed(at date: Date) {
        offer.remindersArmedAt = date
        persistOffer()
    }

    /// True when the receipt matched an active test (the coordinator decides; stale, early or
    /// duplicate receipts and receipts outside a test are refused).
    func deliver(_ receipt: ShortcutReceipt) -> Bool {
        send(.receipt(receipt)) == .accepted
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(coordinator.summary) {
            defaults.set(data, forKey: PreferenceKey.backTapSetup)
        }
    }

    private func persistOffer() {
        if let data = try? JSONEncoder().encode(offer) {
            defaults.set(data, forKey: PreferenceKey.openWaysOffer)
        }
    }

    private static func loadOffer(from defaults: UserDefaults) -> OpenWaysOfferState {
        guard let data = defaults.data(forKey: PreferenceKey.openWaysOffer),
              let state = try? JSONDecoder().decode(OpenWaysOfferState.self, from: data)
        else { return OpenWaysOfferState() }
        return state
    }

    private static func load(from defaults: UserDefaults) -> BackTapSetupSummary {
        // UI tests preset the outcome with e.g. "-backTapSetupStatus deferred".
        if let raw = defaults.string(forKey: PreferenceKey.backTapSetupStatus),
           let status = BackTapSetupSummary.Status(rawValue: raw) {
            return BackTapSetupSummary(status: status, testedAt: status == .userReportedTested ? .now : nil)
        }
        guard let data = defaults.data(forKey: PreferenceKey.backTapSetup),
              let summary = try? JSONDecoder().decode(BackTapSetupSummary.self, from: data)
        else { return BackTapSetupSummary() }
        return summary
    }
}
