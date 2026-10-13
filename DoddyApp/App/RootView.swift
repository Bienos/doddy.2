import CoreSpotlight
import DoddyCore
import SwiftUI

enum PreferenceKey {
    /// Off by default (owner decision D4): note reminders never carry the note text unless turned on.
    static let showNoteTextInNotifications = "showNoteTextInNotifications"
    /// Memories shows Lists instead of Notes (ADR-216).
    static let memoriesShowsLists = "memoriesShowsLists"
    static let notificationExplainerSeen = "notificationExplainerSeen"
    static let appearance = "appearance"
    /// Memories list order (`MemorySort` raw value); display only (ADR-186).
    static let memorySort = "memorySort"
    /// JSON array of pinned note ids (`PinnedNotes`); display only, never any note text (ADR-187).
    static let pinnedNotes = "pinnedNotes"
    /// Widgets show pinned notes, reminders and lists (ADR-219); on unless turned off.
    static let widgetsShowContent = "widgetsShowContent"
    /// The Apple Watch app shows pinned notes, reminders and lists (ADR-232); on unless turned off.
    static let watchShowContent = "watchShowContent"
    static let hideCharacterArt = "hideCharacterArt"
    /// Settings → Voice → Dynamic Island style (`IslandStyle` raw value); display only (ADR-239).
    static let islandStyle = "islandStyle"
    /// Settings → Appearance: the basketball opening each time the app is opened (ADR-225). On unless turned off.
    static let openingScene = "openingScene"
    /// Settings → Voice: open the conversation by itself when the app is opened (ADR-225). On unless turned off.
    static let listenOnOpen = "listenOnOpen"
    static let voiceAgentID = "voiceAgentID"
    /// JSON `BackTapSetupSummary` (outcome and any active test window), never transcripts.
    static let backTapSetup = "backTapSetup"
    /// UI-test override of the outcome: "-backTapSetupStatus deferred".
    static let backTapSetupStatus = "backTapSetupStatus"
    /// Settings toggle: send the last few conversations to Doddy at the start of the next one.
    static let rememberConversations = "rememberConversations"
    /// Random, stable per-install id passed to ElevenLabs as the conversation user id.
    static let voiceUserID = "voiceUserID"
    static let personalityHumour = "personality.humour"
    static let personalityLength = "personality.length"
    static let personalityFormality = "personality.formality"
    static let personalityMood = "personality.mood"
    static let voiceChoice = "voice.choice"
    static let voiceSpeed = "voice.speed"
    static let voiceExpressiveness = "voice.expressiveness"
    /// Settings → Voice and personality: auto or one of 25 European languages (`ConversationLanguage`, ADR-212).
    static let voiceLanguage = "voice.language"
    /// What Doddy calls the user; sent with each voice conversation only when set (ADR-132).
    static let nickname = "personality.nickname"
    /// Settings → About you: send the approved introduction answers to voice conversations.
    /// Off by default; nothing about the user leaves the phone until they switch it on.
    static let shareProfileWithVoice = "shareProfileWithVoice"
    /// Learning loop (ADR-440). Off until turned on: Doddy proposes facts and routines only then.
    static let learningOn = "learning.on"
    /// Hand confirmed facts and saved procedures to voice conversations. Off until turned on.
    static let shareLearnedWithVoice = "learning.shareWithVoice"
    /// HTTPS address of `server/voice-token`. Empty = development public agent.
    static let voiceTokenServer = "voiceTokenServer"
    /// Development setting: base URL of the Doddy Connected Apps server (not a secret).
    static let connectedAppsServerURL = "connectedAppsServerURL"
    /// Ask Doddy: the user agreed that questions go to the gateway and OpenAI. Off by default.
    static let assistantConsent = "assistantConsent"
    static let assistantUseNotes = "assistantUseNotes"
    static let gatewayAddress = "gatewayAddress"
    /// Development setting: https origin of the Doddy messaging server (`server/messaging`).
    static let messagingServerURL = "messagingServerURL"
    /// The user turned Doddy's notifications on (re-registers the APNs token at launch).
    static let pushUpdatesOn = "pushUpdatesOn"
    /// The user turned on the server copy of their notes for phone calls (S2).
    static let memoryCopyOn = "memoryCopyOn"
    /// "Worth keeping?" after a voice conversation (ADR-247). On unless turned off; on-device rules.
    static let suggestSavesAfterConversation = "suggestSavesAfterConversation"
    /// Siri may read saved notes aloud (ADR-248). On unless turned off; the phone must be unlocked.
    static let siriReadsNotes = "siriReadsNotes"
    /// "Hey Doddy" listening (ADR-254). Off unless turned on. The AccessKey is in the Keychain and
    /// the keyword file in Application Support, never here.
    static let heyDoddyOn = "heyDoddy.on"
    /// The Quick start screen (ADR-324) was shown once, at the end of first use; never again.
    static let quickStartOffered = "quickStartOffered"
    /// A voice conversation has really connected once on this iPhone (the provider said it is
    /// listening). Until then Home keeps to Talk to Doddy and holds back the setup cards (ADR-326)
    /// and the voice picker (ADR-443).
    static let hadFirstConversation = "hadFirstConversation"
    /// Voice conversations that really connected on this iPhone (the provider said Listening),
    /// counted once each; only for when the Hey Doddy card may show (ADR-328).
    static let connectedConversations = "connectedConversations"
    /// The Home card offering "Hey Doddy" was answered (Turn on or Not now); it never shows again.
    static let heyDoddyOfferDone = "heyDoddy.offerDone"
}

enum AppTab: Hashable {
    case home, memories, settings
}

struct RootView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @Environment(ProfileStore.self) private var profiles
    @State private var selectedTab: AppTab = .home
    @State private var showFind = false
    @State private var homePath: [UUID] = []
    @Environment(NoteReminderStore.self) private var noteReminders
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @Bindable private var router = ShortcutRouter.shared
    @State private var opening = OpeningModel()
    @AppStorage(PreferenceKey.pinnedNotes) private var pinnedRaw = "[]"
    @AppStorage(PreferenceKey.widgetsShowContent) private var widgetsOn = true
    @AppStorage(PreferenceKey.showNoteTextInNotifications) private var showNoteText = false
    /// "Hide character artwork" is passed on to widgets and the watch (ADR-331).
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideArt = false
    /// The Face ID cover is up (ADR-310); it stays briefly after an unlock for the door (ADR-380).
    @State private var lockCovered = false

    private var colorScheme: ColorScheme? {
        switch AppearancePreference(rawValue: appearanceRaw) ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        if profiles.hasLoaded {
            // The VStack exists so the onboarding cover and the voice/setup presentations hang off
            // different views.
            VStack(spacing: 0) {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-islandBaseline") {
                    NativeIslandBaselineView()
                } else {
                    tabs
                }
                #else
                tabs
                #endif
            }
            .preferredColorScheme(colorScheme)
            // The Face ID lock (ADR-310) covers everything until iOS says yes.
            // After a real unlock the cover stays up a moment while Doddy's door opens (ADR-380).
            .overlay { if AppLock.shared.isLocked || lockCovered { AppLockView(skip: { lockCovered = false }) } }
            .onAppear { lockCovered = AppLock.shared.isLocked }
            .onChange(of: AppLock.shared.isLocked) { _, locked in
                guard !locked else { lockCovered = true; return }
                guard lockCovered, !reduceMotion, !hideArt else { lockCovered = false; return }
                Task {
                    try? await Task.sleep(for: .seconds(AppLockView.doorTime))
                    withAnimation(.easeOut(duration: 0.25)) { lockCovered = false }
                }
            }
            .task {
                await store.reload()
                await noteReminders.refreshOnForeground()
                if scenePhase == .active { heyDoddyAppBecameActive() }
                pickUpSharedItem()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await noteReminders.refreshOnForeground() }
                    FocusController.shared.refresh()
                    BreathingController.shared.refresh()
                    // Shared lists (ADR-263): changes others made arrive when Doddy comes to the front.
                    Task { await SharedListsController.shared.syncAll() }
                    // Memory on calls: a copy upload that failed or was cut off is sent again.
                    // Private notes (ADR-310) are never in the server copy.
                    if store.hasLoaded && store.loadError == nil {
                        MemoryCopySync.shared.retryIfNeeded(PrivateNotesStore.current().shareable(store.memories))
                    }
                    pickUpSharedItem()
                }
                if phase == .background {
                    // What is being typed on a capture screen is on disk before iOS may end Doddy (ADR-362).
                    UnfinishedNoteStore.shared.flush()
                    WidgetSync.shared.refresh()
                    AppLock.shared.wentToBackground()
                    QuickActions.install()
                }
                if phase == .active { AppLock.shared.cameBack() }
                // "Hey Doddy" (ADR-254): the microphone can only start while Doddy is open.
                switch phase {
                case .active: heyDoddyAppBecameActive()
                case .background: WakeWordListener.shared.appWentToBackground()
                default: break
                }
                // The opening plays again only after a real time away (OpeningPolicy.replayAfter).
                switch phase {
                case .background: opening.appWentToBackground()
                case .active: opening.appBecameActive(openingConditions)
                default: break
                }
            }
            // Widgets (ADR-219) follow every change to notes, lists, pins and reminders.
            .onChange(of: store.revision) { WidgetSync.shared.refresh() }
            // Siri learns the list names for "Add to my shopping list in Doddy" (ADR-226).
            .onChange(of: store.lists.map(\.name)) { DoddyShortcuts.updateAppShortcutParameters() }
            .onChange(of: noteReminders.reminders) { WidgetSync.shared.refresh() }
            .onChange(of: pinnedRaw) { WidgetSync.shared.refresh() }
            .onChange(of: widgetsOn) { WidgetSync.shared.refresh() }
            .onChange(of: showNoteText) { WidgetSync.shared.refresh() }
            .onChange(of: hideArt) { WidgetSync.shared.refresh() }
            // A tapped note reminder opens its exact memory on Home.
            .task(id: noteReminders.pendingOpenMemoryID) {
                guard let memoryID = noteReminders.pendingOpenMemoryID else { return }
                selectedTab = .home
                homePath = [memoryID]
                noteReminders.pendingOpenMemoryID = nil
            }
            // Keeps the opt-in server copy (memory on calls) equal to what is on this iPhone. Only
            // after a read that worked: a failed one can leave the list empty or stale, and uploading
            // that would wipe or roll back the server copy (DOD-06). Private notes (ADR-310) are
            // never in the server copy for calls.
            .onChange(of: store.revision) {
                guard store.hasLoaded, store.loadError == nil else { return }
                MemoryCopySync.shared.schedule(PrivateNotesStore.current().shareable(store.memories))
            }
            .fullScreenCover(isPresented: .constant(profiles.route != .home)) {
                OnboardingFlowView()
                    .preferredColorScheme(colorScheme)
            }
        } else {
            // A moment while the store opens, so Home doesn't flash before first-use onboarding.
            Theme.canvas.ignoresSafeArea()
                .task { await profiles.load() }
        }
    }

    /// Starts "Hey Doddy" listening if it is on, and opens the conversation the wake word
    /// started while Doddy was in the background, if it is running or left notes to look at.
    /// Text or a link shared from another app with "Save to Doddy" (ADR-311): opens the capture
    /// screen with it, as the shortcut does. Nothing is saved until Save there.
    private func pickUpSharedItem() {
        guard let item = ShareInboxFile.take() else { return }
        ShortcutRouter.shared.saveToDoddyInvoked(text: item.text)
    }

    private func heyDoddyAppBecameActive() {
        let listener = WakeWordListener.shared
        if listener.hasConversationToShow {
            // Never over another sheet: then it opens the next time Doddy comes to the front.
            _ = router.showWakeConversation()
        } else {
            listener.forgetFinishedConversation()
        }
        listener.appBecameActive()
        // The listening indicator above every screen (ADR-361).
        ListeningIndicatorWindow.shared.install()
    }

    /// What the opening's rules need to know right now (ADR-225). Read at decision time, so a
    /// switch changed in Settings counts from the next opening.
    private var openingConditions: OpeningConditions {
        OpeningConditions(
            sceneOn: OpeningPreferences.sceneOn(),
            listenOnOpen: OpeningPreferences.listenOnOpen(),
            characterArtHidden: UserDefaults.standard.bool(forKey: PreferenceKey.hideCharacterArt),
            reduceMotion: reduceMotion,
            voiceOverRunning: voiceOverOn,
            atHome: profiles.route == .home,
            voiceAvailable: store.environment.capabilities.isAvailable(.voiceInput),
            microphoneAllowed: MicrophoneAccess.isAllowed,
            somethingIsOpen: router.isVoicePresented || router.isSetupPresented
                || router.shownDraft != nil || router.findRequest != nil)
    }

    private var tabs: some View {
        ZStack {
            tabContent
            // The opening (ADR-225) sits over the ready app and fades away to reveal it; a tap
            // ends it early. It is removed from the hierarchy entirely once it is done.
            if let play = opening.play {
                // No fade at the end: Doddy is already in Home's place, and everything else has faded.
                OpeningSceneView(
                    play: play, homeTarget: opening.homeArtBox,
                    onHandover: { opening.handoverStarted() },
                    onFinished: { opening.finish() })
                .zIndex(1)
            }
        }
        .environment(opening)
        .tint(Theme.accentText)
        .background(Theme.canvas)
        // One presentation point for the conversation, so a shortcut invocation while it is
        // open focuses it instead of starting a second one.
        // Waiting drafts appear only once a cover or sheet has finished going away.
        .fullScreenCover(isPresented: $router.isVoicePresented, onDismiss: { router.showWaitingDraft() }) { VoiceView() }
        .sheet(isPresented: $router.isSetupPresented, onDismiss: { router.showWaitingDraft() }) {
            BackTapSetupView(model: router.setup)
        }
        // The weekly tidy-up (ADR-228), from its notification or Settings.
        .sheet(isPresented: $router.isTidyUpPresented, onDismiss: { router.showWaitingDraft() }) { TidyUpView() }
        // A shared list's link (ADR-263): nothing is joined until Join.
        .sheet(item: Binding(get: { SharedListsController.shared.invite }, set: { if $0 == nil { SharedListsController.shared.declineInvite() } })) { invite in
            SharedListInviteView(invite: invite) { list in
                selectedTab = .home
                homePath = [list.id]
            }
        }
        // The evening wrap-up (ADR-261), from its notification or Settings.
        .sheet(isPresented: $router.isWrapUpPresented, onDismiss: { router.showWaitingDraft() }) {
            EveningWrapUpView(openSettings: { selectedTab = .settings })
        }
        // The weekly look-back (ADR-306), from its notification or Settings.
        .sheet(isPresented: $router.isLookBackPresented, onDismiss: { router.showWaitingDraft() }) { WeeklyLookBackView() }
        // The morning check-in (ADR-220), from its notification or Settings.
        .sheet(isPresented: $router.isCheckInPresented, onDismiss: { router.checkInSheetDismissed() }) {
            MorningCheckInView(openSettings: { selectedTab = .settings })
        }
        .sheet(item: $router.shownDraft, onDismiss: { router.showWaitingDraft() }) { draft in
            CaptureView(sharedText: draft.isSharedText ? draft.text : nil)
        }
        // `initial: true`: on a cold launch the shortcut runs before these views exist.
        .onChange(of: router.findRequest?.id, initial: true) { _, id in
            guard id != nil else { return }
            selectedTab = .memories
            showFind = true
        }
        .onChange(of: profiles.route == .home, initial: true) { _, atHome in
            router.isOnboardingShown = !atHome
            // The first time Home is ready and on screen is the launch (OpeningModel decides).
            opening.homeReady(openingConditions, isActive: scenePhase == .active)
        }
        // A conversation that comes up on its own (Back Tap, Siri, the island) ends the opening.
        .onChange(of: router.isVoicePresented) { _, presented in
            if presented { opening.conversationOpened() }
            // "Hey Doddy" pauses while the voice screen is open and listens again when it closes.
            WakeWordListener.shared.refresh()
        }
        // A Spotlight result (ADR-330) opens that note or list, as a widget's link does.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let memoryID = SpotlightSync.memoryID(from: activity) else { return }
            selectedTab = .home
            homePath = [memoryID]
        }
        .onOpenURL { url in
            // doddy://home | memories | settings — navigation only; unknown links are ignored.
            // doddy://open/<id> from a widget opens that note or list on Home (ADR-219).
            if let memoryID = WidgetLink.memoryID(from: url) {
                selectedTab = .home
                homePath = [memoryID]
                return
            }
            guard let link = DeepLink(url: url) else { return }
            switch link {
            case .home: selectedTab = .home
            case .memories: selectedTab = .memories
            case .settings: selectedTab = .settings
            // The parking widget (ADR-315): the saved spot in Maps. No spot, nothing opens.
            case .parking:
                if let spot = ParkingStore.current(), let maps = Parking.mapsURL(spot) { openURL(maps) }
            }
        }
    }

    private var tabContent: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                HomeView(selectedTab: $selectedTab, showFind: $showFind, path: $homePath)
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(AppTab.home)
                MemoriesView(showFind: $showFind)
                    .tabItem { Label("Memories", systemImage: "note.text") }
                    .tag(AppTab.memories)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(AppTab.settings)
            }
            .toolbar(.hidden, for: .tabBar)
            // iPad (ADR-337): one readable column in the middle of a wide screen.
            .frame(maxWidth: horizontalSizeClass == .regular ? 760 : .infinity)
            .frame(maxWidth: .infinity)
            .background(Theme.canvas)
            if let deleted = store.recentlyDeleted {
                UndoDeleteBar(deleted: deleted)
            }
            // A sibling reserves real viewport space. A TabView-level safeAreaInset
            // left nested NavigationStack's final action behind the bar on iOS 27.
            DoddyTabBar(selectedTab: $selectedTab)
        }
    }
}

/// "Note deleted · Undo" for `DeletedNote.undoWindow` seconds after a single delete (ADR-183).
/// Undo adds the note back exactly as it was; if that fails, the bar says so until it times out.
private struct UndoDeleteBar: View {
    @Environment(MemoryStore.self) private var store
    let deleted: DeletedNote
    @State private var isUndoing = false
    @State private var failed = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: failed ? "exclamationmark.triangle" : "trash")
                .foregroundStyle(failed ? Theme.error : Theme.secondaryText)
            Text(failed
                 ? "Couldn't bring the \(deleted.record.category == .list ? "list" : "note") back."
                 : deleted.record.category == .list ? "List deleted." : "Note deleted.")
                .font(.subheadline)
            Spacer(minLength: 8)
            if !failed {
                Button(isUndoing ? "Undoing…" : "Undo") {
                    isUndoing = true
                    Task {
                        do { try await store.undoDelete() } catch { failed = true }
                        isUndoing = false
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .disabled(isUndoing)
                .accessibilityIdentifier("undoDelete")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(Theme.quietSurface)
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .contain)
        .task(id: deleted.deletedAt) {
            try? await Task.sleep(for: .seconds(DeletedNote.undoWindow))
            store.forgetDeleted(deleted)
        }
    }
}
