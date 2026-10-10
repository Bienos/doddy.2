import DoddyCore
import Foundation
import Observation

/// Single owner of "what the app shows because a shortcut ran". The Talk to Doddy intent and
/// the UI both go through it, so a second invocation focuses the open conversation instead of
/// starting a second one, and a tap test can claim the invocation as its receipt.
@MainActor
@Observable
final class ShortcutRouter {
    static let shared = ShortcutRouter()

    /// Bound to the full-screen voice conversation in `RootView`.
    var isVoicePresented = false
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

    init(setup: BackTapSetupModel = BackTapSetupModel()) {
        self.setup = setup
    }

    /// Called from `TalkToDoddyIntent.perform()`. If a tap test is active the invocation is its
    /// receipt and the setup sheet takes over; otherwise the voice conversation opens.
    func talkToDoddyInvoked(at now: Date = .now) {
        // A shared draft's capture sheet is up on the same view as the conversation cover: a
        // second presentation would be dropped and leave drafts queued behind it for good.
        if drafts.shown != nil { return }
        if setup.deliver(ShortcutReceipt(receivedAt: now)) {
            isVoicePresented = false
            isSetupPresented = true
        } else {
            isSetupPresented = false
            isVoicePresented = true
        }
    }

    /// Called by the opening when Settings → "Start listening when I open Doddy" is on (ADR-210).
    /// Opens the conversation unless one is already open or something else is on screen; it
    /// never starts a second conversation and never pushes a sheet aside.
    func startListeningOnOpen() {
        guard !isVoicePresented, !isSetupPresented, !isOnboardingShown, drafts.shown == nil else { return }
        isVoicePresented = true
    }

    /// Called from `SaveToDoddyIntent.perform()`. Shows the text on the capture screen, or keeps
    /// it until the conversation or another capture screen closes. Never saves anything.
    func saveToDoddyInvoked(text: String) {
        drafts.receive(SharedDraft(text: text), blocked: closeSetupSheet() || isCaptureBlocked)
    }

    /// Called from `NewNoteIntent.perform()` (control, Siri, Action Button). If a capture screen
    /// is already open the user is already where they asked to be, so nothing else opens; and an
    /// empty screen never takes the place of shared text that is waiting to be shown.
    func newNoteInvoked() {
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
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults
        coordinator = BackTapSetupCoordinator(summary: Self.load(from: defaults), now: now)
    }

    var phase: BackTapSetupPhase { coordinator.phase }

    @discardableResult
    func send(_ event: BackTapSetupEvent) -> BackTapSetupOutcome {
        let outcome = coordinator.handle(event)
        persist()
        return outcome
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
