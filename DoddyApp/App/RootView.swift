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
    /// Settings › App language (ADR-459): a language code, or "system" for the iPhone's language. Absent means English.
    static let appLanguage = "appLanguage"
    /// Memories list order (`MemorySort` raw value); display only (ADR-186).
    static let memorySort = "memorySort"
    /// JSON array of pinned note ids (`PinnedNotes`); display only, never any note text (ADR-187).
    static let pinnedNotes = "pinnedNotes"
    /// Widgets show pinned notes, reminders and lists (ADR-219); on unless turned off.
    static let widgetsShowContent = "widgetsShowContent"
    /// The Apple Watch app shows pinned notes, reminders and lists (ADR-232); on unless turned off.
    static let watchShowContent = "watchShowContent"
    static let hideCharacterArt = "hideCharacterArt"
    /// "Note saved" in the Dynamic Island for a few seconds after a save (ADR-781). On unless turned off.
    static let savedIsland = "savedIsland"
    /// Settings → Voice: open the conversation by itself when the app is opened (ADR-225). Off unless turned on.
    static let listenOnOpen = "listenOnOpen"
    static let voiceAgentID = "voiceAgentID"
    /// Settings → Siri and Back Tap: "Talk to Doddy" starts a conversation (default) or only opens the app (`BackTapAction`).
    /// Its old "Small island" moved to `islandExpands` at launch (ADR-579).
    static let backTapAction = "backTapAction"
    /// Settings → Action Button: what the "Talk to Doddy" control does (`TalkLaunchMode`, ADR-579).
    static let talkLaunchMode = TalkLaunchMode.preferenceKey
    /// Settings → Expand when Doddy speaks (`IslandExpansion`, ADR-577, ADR-579). On unless turned off.
    static let islandExpands = LaunchPreferencesMigration.islandExpandsKey
    /// JSON `LegalAcceptanceRecord`: the Terms and Privacy Policy versions accepted, when, where (ADR-581).
    static let legalAcceptance = LegalAcceptance.preferenceKey
    /// JSON `BackTapSetupSummary` (outcome and any active test window), never transcripts.
    static let backTapSetup = "backTapSetup"
    /// JSON `OpenWaysOfferState`: counts and flags for the Home card's return and the weekly reminder (ADR-559).
    static let openWaysOffer = "openWaysOffer"
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
    /// Development setting: base URL of the Doddy Connected Apps server (not a secret). Only a Debug build
    /// reads it, and only through `DeviceSession.serverURL()` (ADR-720); a shipped build ignores it and
    /// removes a value an earlier build saved.
    static let connectedAppsServerURL = "connectedAppsServerURL"
    /// Payments were switched on at some point; until then Home never asks the server about payments (ADR-736).
    static let paymentsEverEnabled = "paymentsEverEnabled"
    /// How many unconfirmed payments the person said they checked, and the server's last count (ADR-736).
    static let paymentsAcknowledgedUnresolved = "paymentsAcknowledgedUnresolved"
    static let paymentsLastUnresolved = "paymentsLastUnresolved"
    /// Ask Doddy (Messages): questions go to Doddy's server and Anthropic (ADR-587). On unless the person turns it off in
    /// Settings › Ask Doddy (owner, 9 Nov 2026, `2026-11-09-messages-on-by-default`); a saved choice, on or off, always wins.
    static let assistantConsent = "assistantConsent"
    static let assistantConsentDefault = true
    static let assistantUseNotes = "assistantUseNotes"
    /// Development setting: https origin of the Doddy messaging server (`server/messaging`).
    static let messagingServerURL = "messagingServerURL"
    /// The user turned Doddy's notifications on (re-registers the APNs token at launch).
    static let pushUpdatesOn = "pushUpdatesOn"
    /// The user turned on the server copy of their notes for phone calls (S2).
    static let memoryCopyOn = "memoryCopyOn"
    /// Texts to Doddy (ADR-753), as the server last reported; for What leaves this iPhone.
    static let textsToDoddyOn = "textsToDoddyOn"
    // Notes and conversations kept on Doddy's server (ADR-603) are `WebMemoryModel.notesKey` and
    // `WebMemoryModel.conversationsKey` in DoddyCore, off by default.
    /// "Worth keeping?" after a voice conversation (ADR-247). On unless turned off; on-device rules.
    static let suggestSavesAfterConversation = "suggestSavesAfterConversation"
    /// Siri may read saved notes aloud (ADR-248). On unless turned off; the phone must be unlocked.
    static let siriReadsNotes = "siriReadsNotes"
    /// The Quick start screen (ADR-324) was shown once, at the end of first use; never again.
    static let quickStartOffered = "quickStartOffered"
    /// A voice conversation has really connected once on this iPhone (the provider said it is
    /// listening). Until then Home keeps to Talk to Doddy and holds back the setup cards (ADR-326)
    /// and the voice picker (ADR-443).
    static let hadFirstConversation = "hadFirstConversation"
    /// Voice conversations that really connected on this iPhone (the provider said Listening),
    /// counted once each; for when the "Open Doddy faster" card returns (ADR-559). It was the
    /// Hey Doddy card's (ADR-328); PR #108 removed it with that card, and this PR keeps it.
    static let connectedConversations = "connectedConversations"
    /// The first-launch welcome (ADR-598) has been finished or skipped on this installation.
    static let welcomeSeen = "welcomeSeen"
    /// Settings › "Show the welcome again": the welcome shows once more, then clears this.
    static let welcomeReplay = "welcomeReplay"
    /// The first-run "Allow access" step (ADR-814) has been answered or skipped on this installation.
    static let firstRunAccessSeen = "firstRunAccessSeen"
    /// Cheapest this week › My loyalty apps (ADR-661): the programs the user said they don't use
    /// (`DealsPrograms.stored`). Empty means every leaflet price counts. Stays on this iPhone.
    static let dealsProgramsNotUsed = "deals.programsNotUsed"
    /// Cheapest this week › My shops (ADR-663): the shops the user picked (`MyShops.stored`, JSON). Stays on this iPhone.
    static let dealsMyShops = "deals.myShops"
    /// Basket › a second shop only when it saves at least this much, in grosze (ADR-664). 0 means any saving.
    static let dealsMinimumSaving = "deals.minimumSaving"
}

enum AppTab: Hashable {
    case home, memories, settings

    /// The tab as a screen in Doddy's motion world.
    var motionScreen: MotionScreen {
        switch self {
        case .home: .home
        case .memories: .memories
        case .settings: .settings
        }
    }
}

struct RootView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.default.rawValue
    @Environment(ProfileStore.self) private var profiles
    @State private var selectedTab: AppTab = .home
    @State private var showFind = false
    @State private var homePath: [UUID] = []
    /// How tall the transcript sheet opens (ADR-595): full for Transcript, half for a card.
    @State private var voiceDetent: PresentationDetent = .large
    /// The conversation's sheet as the pop-up card (owner, 10 Nov 2026): only what waits for the user
    /// or what Doddy just made. The Transcript button and "Show the conversation" show all of it.
    @State private var voiceAsCard = false
    @Environment(NoteReminderStore.self) private var noteReminders
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @Bindable private var router = ShortcutRouter.shared
    @State private var opening = OpeningModel()
    @AppStorage(PreferenceKey.pinnedNotes) private var pinnedRaw = "[]"
    @AppStorage(PreferenceKey.widgetsShowContent) private var widgetsOn = true
    @AppStorage(PreferenceKey.showNoteTextInNotifications) private var showNoteText = false
    /// "Hide character artwork" is passed on to widgets and the watch (ADR-331).
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideArt = false
    /// The Face ID cover is up (ADR-310); it stays briefly after an unlock for the door (ADR-380).
    @State private var lockCovered = false
    /// Counts the times the Face ID lock came back; the screens under the cover are made new each time,
    /// so no sheet state of theirs can open a screen over it (ADR-723).
    @State private var lockEpoch = 0
    /// Settings › "Show the welcome again" (ADR-598).
    @AppStorage(PreferenceKey.welcomeReplay) private var welcomeReplay = false
    /// The welcome was finished in this run, so it doesn't show again until a replay is asked for.
    @State private var welcomeDone = false
    /// The Doddy account (decision 2026-11-08-required-account).
    @State private var doddyAccount = DoddyAccountModel.shared

    /// The first-launch welcome (ADR-598) is on screen. It covers Home, and the first-use
    /// introduction waits until it is over. Only read once the store has loaded (`isFirstInstallation`).
    private var welcomeVisible: Bool {
        accountRequired || (!welcomeDone && WelcomeRule.shouldShow(
            seen: WelcomePreferences.seen(), firstInstallation: profiles.isFirstInstallation,
            replayRequested: welcomeReplay, override: WelcomePreferences.override()))
    }

    /// Decision 2026-11-08-required-account: in a build with Doddy accounts set up, nobody uses Doddy
    /// signed out. The welcome, whose sheet signs in, stays until they are, including after a sign-out.
    /// A build without them (and UI tests, `-welcome NO`) is unchanged.
    private var accountRequired: Bool {
        doddyAccount.isConfigured && !doddyAccount.isSignedIn && WelcomePreferences.override() != false
    }

    private func finishWelcome() {
        WelcomePreferences.markSeen()
        welcomeReplay = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { welcomeDone = true }
    }

    /// The Terms acceptance (ADR-581); the "Before we start" step shows until it is stored.
    @AppStorage(PreferenceKey.legalAcceptance) private var legalRecordData: Data?
    /// The "Allow access" step (ADR-814) was answered or skipped; it sets this itself.
    @AppStorage(PreferenceKey.firstRunAccessSeen) private var accessSeen = false

    private var colorScheme: ColorScheme? {
        switch AppearancePreference(rawValue: appearanceRaw) ?? .default {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The launched app's hooks, part one: the tab content with the Face ID lock, the launch work, the
    /// scene phase and the weekly reminder. The chain that used to be all of `body` is three pieces
    /// (this, `rootWithMotion` and what `body` adds): one expression of 24 modifiers is over the compiler's
    /// limit (Xcode 26.6: "unable to type-check this expression in reasonable time", RootView.swift:288).
    private var rootHooks: some View {
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
        .overlay { if AppLock.shared.isLocked || lockCovered { AppLockView(skip: { lockCovered = false; lockLifted() }) } }
        .onAppear { lockCovered = AppLock.shared.isLocked }
        .onChange(of: AppLock.shared.isLocked) { _, locked in
            guard !locked else {
                lockCovered = true
                lockEngaged()
                return
            }
            // Unlocked with a conversation from Talk in the Island running (ADR-577): Home shows it
            // (it holds it, ADR-595); nothing is put over the app. A card that waits for the user
            // opens the transcript by itself, after the unlock.
            if HomeConversation.shared.needsYou { presentTranscriptIfNeeded() }
            guard lockCovered, !reduceMotion, !hideArt else { lockCovered = false; lockLifted(); return }
            Task {
                try? await Task.sleep(for: .seconds(AppLockView.doorTime))
                withAnimation(.easeOut(duration: 0.25)) { lockCovered = false }
                lockLifted()
            }
        }
        // Signed in: whose data this iPhone holds is recorded before anything is sent (decision
        // 2026-11-12-local-data-owner), then a server that didn't answer about the account last time is asked again.
        .task {
            await DoddyAccountServers.claimLocalData()
            await DoddyAccountServers.catchUp()
        }
        .task {
            let notesLoad = LaunchWork.signposter.beginInterval("Notes load")
            await store.reload()
            LaunchWork.signposter.endInterval("Notes load", notesLoad)
            // Memory on calls, at launch: once after the update, the server copy is replaced with
            // one that has no private notes (ADR-310), only if the notes were read successfully.
            MemoryCopySync.shared.retryIfNeeded(PrivateNotesStore.current().shareable(store.memories),
                                                notesLoaded: store.hasLoaded && store.loadError == nil)
            // Notes and conversations kept on Doddy's server (ADR-603), only if the person turned that on:
            // the list again if the last send failed, and conversations that couldn't be sent.
            WebMemory.shared.retryIfNeeded(store.memories, privateNotes: PrivateNotesStore.current(),
                                           notesLoaded: store.hasLoaded && store.loadError == nil)
            await WebMemory.shared.retryConversations(from: ConversationLogStore.shared.logs, language: WebMemory.language())
            // Logbook (ADR-602): once the notes are read, the days that are due.
            Logbook.sync(store: store)
            await noteReminders.refreshOnForeground()
            pickUpSharedItem()
            // The weekly "Open Doddy faster" reminder, if it is still wanted (ADR-559).
            await OpenWaysReminderScheduler.refresh(router.setup)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // MV5: today's welcome (once a day; a hop in place first after three days away).
            if phase == .active { DoddyDirector.shared.appBecameActive() }
            // A conversation started without opening Doddy (Talk in the Island, ADR-577): opening
            // Doddy during it shows it on Home (`TalkInIsland` hands it to `HomeConversation`) and
            // the app stays usable: Messages, notes, lists. The transcript sheet is no longer put
            // over the app each time it comes forward; the island's Show, the Transcript button and
            // a card that needs the user (`needsYou`) still open it.
            if phase == .active, !AppLock.shared.isLocked, HomeConversation.shared.needsYou {
                presentTranscriptIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await noteReminders.refreshOnForeground() }
                // Tasks Doddy works on in the background (ADR-570): a finished one is saved here and acknowledged. While one
                // still runs, the app asks again every 30 s as long as it stays open (12 Nov 2026), so its result reaches
                // Messages without waiting for a push.
                Task {
                    await ErrandsModel.shared.refresh()
                    ErrandsModel.shared.watchWhileRunning()
                }
                // Studio (ADR-740): asked again only while something is being made.
                if StudioModel.shared.hasOpenItems { Task { await StudioModel.shared.refresh() } }
                FocusController.shared.refresh()
                StopwatchController.shared.refresh()
                CountdownController.shared.refresh()
                // "A thought is ready for review" (ADR-785): the next one, from the notes as they are now.
                Task { _ = await ThoughtReviewScheduler.refresh(store: store) }
                // Shared lists (ADR-263): changes others made arrive when Doddy comes to the front.
                // A cold launch also syncs (LaunchWork), so one that just ran is not repeated (ADR-547).
                Task { await SharedListsController.shared.syncAllUnlessRecent() }
                // Memory on calls: a copy upload that failed or was cut off is sent again, and once
                // after the update, a copy that may hold private notes is replaced (ADR-310).
                MemoryCopySync.shared.retryIfNeeded(PrivateNotesStore.current().shareable(store.memories),
                                                    notesLoaded: store.hasLoaded && store.loadError == nil)
                // Notes kept on Doddy's server (ADR-603): the same, for a send that failed.
                WebMemory.shared.retryIfNeeded(store.memories, privateNotes: PrivateNotesStore.current(),
                                               notesLoaded: store.hasLoaded && store.loadError == nil)
                // Logbook (ADR-602): the counts that are due, on unless turned off (decision 2026-11-09-usage-counts-on-by-default).
                Logbook.sync(store: store)
                // Quiet hours for a booked call are checked in this iPhone's zone (ADR-754).
                CallZoneSender.sendIfNeeded()
                pickUpSharedItem()
                Task { await OpenWaysReminderScheduler.refresh(router.setup) }
                // Doddy's free server sleeps when idle (ADR-686): one health ping now starts its
                // wake-up before a request needs it. Only for an iPhone that has a session with it.
                if let server = DeviceSession.serverURL(), KeychainSessionStore.read()?.token(for: server) != nil {
                    Task { await ServerWarmUp.shared.wake(server: server, transport: URLSessionTransport.shared) }
                }
            }
            // The app switcher's picture of Doddy: with the Face ID lock on, an opaque cover while he isn't in front (ADR-723).
            if phase != .active { PrivacyCover.shared.update(sceneIsActive: false) }
            if phase == .background {
                // Nothing asks Doddy's server about tasks while the app is away; a push or the next return does.
                ErrandsModel.shared.stopWatching()
                // What is being typed on a capture screen is on disk before iOS may end Doddy (ADR-362).
                UnfinishedNoteStore.shared.flush()
                // Logbook (ADR-602): today so far, at most once an hour.
                Logbook.sync(store: store)
                WidgetSync.shared.refresh()
                AppLock.shared.wentToBackground()
                QuickActions.install()
            }
            if phase == .active {
                AppLock.shared.cameBack()
                // Away long enough for the lock to come back: whatever was open is closed before the cover goes (ADR-723).
                if AppLock.shared.isLocked, !lockCovered { lockEngaged() }
                PrivacyCover.shared.update(sceneIsActive: true)
            }
            // On later returns, only the separately opted-in listen-on-open preference applies.
            switch phase {
            case .background: opening.appWentToBackground()
            // While the first-launch welcome is up the opening waits for it (ADR-598).
            case .active: if !welcomeVisible { opening.appBecameActive(openingConditions) }
            default: break
            }
        }
        // A tested or used way ends the weekly reminder at once (ADR-559).
        .onChange(of: router.setup.isUsingAWay) { Task { await OpenWaysReminderScheduler.refresh(router.setup) } }
    }

    /// Part two: the widget refreshes and Motion v2's hooks, on top of `rootHooks`.
    private var rootWithMotion: some View {
        rootHooks
        // Widgets (ADR-219) follow every change to notes, lists, pins and reminders.
        .onChange(of: store.revision) { WidgetSync.shared.refresh() }
        // Siri learns the list names for "Add to my shopping list in Doddy" (ADR-226).
        .onChange(of: store.lists.map(\.name)) { DoddyShortcuts.updateAppShortcutParameters() }
        .onChange(of: noteReminders.reminders) { WidgetSync.shared.refresh() }
        .onChange(of: pinnedRaw) { WidgetSync.shared.refresh() }
        .onChange(of: widgetsOn) { WidgetSync.shared.refresh() }
        .onChange(of: showNoteText) { WidgetSync.shared.refresh() }
        .onChange(of: hideArt) { WidgetSync.shared.refresh() }
        // Motion v2: the one persistent Doddy lives on iPhone layouts with his pictures shown
        // (Q13: iPad's sidebar keeps today's pictures; "Hide Doddy's pictures" turns him off).
        .onChange(of: motionWorldOn, initial: true) { _, on in
            DoddyDirector.shared.isActive = on
            if on, scenePhase == .active { DoddyDirector.shared.appBecameActive() }
        }
        .onAppear {
            DoddyClock.install()
            // MV5: a tap or hold on him talks, as Home's Talk button does: on Home (ADR-595).
            let store = store
            let profiles = profiles
            DoddyDirector.shared.onTalk = {
                // As Home's own Talk button: not while voice input isn't available.
                if store.environment.capabilities.isAvailable(.voiceInput) {
                    HomeConversation.shared.talk(store: store, profile: profiles.profile)
                }
            }
        }
        // MV5's listening pose read the wake word's conversation, the only one that could be
        // live on Home. "Hey Doddy" is gone (ADR-549, PR #108) and the voice screen hides him
        // while it is up, so nothing calls DoddyDirector.voiceListening here any more.
        // Reduce Motion: his hops become fades (brief rule 12).
        .onChange(of: reduceMotion || DoddyMotionDebug.forcesReduceMotion, initial: true) { _, on in
            DoddyDirector.shared.setReduceMotion(on)
        }
        // Q12: at accessibility text sizes he stays 1.0× on Home.
        .onChange(of: textSize.isAccessibilitySize, initial: true) { _, large in
            DoddyDirector.shared.setHomeScale(large ? 1.0 : 1.4)
        }
        // The first-use introduction and the Face ID cover are over the app: he is hidden.
        .coversDoddy(profiles.isIntroductionPresented || AppLock.shared.isLocked || lockCovered || welcomeVisible)
        // Settings › "Show the welcome again": it shows even though it was seen (ADR-598).
        .onChange(of: welcomeReplay) { _, on in if on { welcomeDone = false } }
    }

    var body: some View {
        if profiles.hasLoaded {
            rootWithMotion
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
                // Notes kept on Doddy's server (ADR-603), if the person turned that on: the whole current
                // list, private notes left out by `WebMemoryModel`, after the same successful read.
                WebMemory.shared.scheduleNotes(store.memories, privateNotes: PrivateNotesStore.current())
            }
            // First use: "Before we start" (ADR-581), then the introduction, in one cover.
            .fullScreenCover(isPresented: introductionPresentation) {
                Group {
                    if legalGateUp {
                        LegalAcceptanceView(source: LegalAcceptance.source(
                            hasUsedDoddyBefore: !profiles.isFirstInstallation, previous: LegalAcceptanceStore.record))
                    } else if accessStepUp {
                        FirstRunAccessView()
                    } else {
                        OnboardingFlowView()
                    }
                }
                .preferredColorScheme(colorScheme)
            }
            // Drafts and listen-on-open wait while the terms step is up, as during first use.
            .onChange(of: legalGateUp || accessStepUp, initial: true) { _, up in
                router.isOnboardingShown = up || profiles.route != .home
            }
        } else {
            // A moment while the store opens, so Home doesn't flash before first-use onboarding.
            Theme.canvas.ignoresSafeArea()
                .task { await profiles.load() }
        }
    }

    /// Text or a link shared from another app with "Save to Doddy" (ADR-311): opens the capture
    /// screen with it, as the shortcut does. Nothing is saved until Save there.
    private func pickUpSharedItem() {
        // While the Face ID lock is up the shared text stays in the inbox; it is picked up after the unlock (ADR-723).
        guard !AppLock.shared.isLocked else { return }
        // A product link shared with "Check the price": the Shopping screen opens with it ready, and reads nothing yet.
        if let link = ShareInboxFile.take(slot: .priceCheck) { ShortcutRouter.shared.priceCheckInvoked(text: link.text) }
        guard let item = ShareInboxFile.take() else { return }
        ShortcutRouter.shared.saveToDoddyInvoked(text: item.text)
    }

    /// The shared-list invitation sheet's binding. Not over the Face ID cover (ADR-723): an invitation that comes
    /// in while Doddy is locked waits for the unlock, and the sheet closing because the lock came back is not
    /// the person declining it.
    private var inviteSheet: Binding<SharedListsController.Invite?> {
        Binding(
            get: { AppLock.shared.isLocked ? nil : SharedListsController.shared.invite },
            set: { if $0 == nil, !AppLock.shared.isLocked { SharedListsController.shared.declineInvite() } })
    }

    /// The Face ID lock came back (ADR-723). Its cover is part of this view, so a sheet or cover presented
    /// over the app would stay above it: they are all closed, the screens under it start over, and the router
    /// forgets what it was about to open.
    private func lockEngaged() {
        lockEpoch += 1
        router.dismissForLock()
        PresentedScreens.dismissAll()
    }

    /// The Face ID cover and its door are gone: what was asked for while it was up goes ahead now (ADR-723).
    private func lockLifted() {
        router.runHeldAfterUnlock()
        pickUpSharedItem()
        presentTranscriptIfNeeded()
    }

    /// A conversation with a card waiting for the user opens its transcript, half height (ADR-595). Not over
    /// the Face ID cover: `lockLifted` does it after the unlock.
    private func presentTranscriptIfNeeded() {
        guard HomeConversation.shared.needsYou else { return }
        presentCard()
    }

    /// The pop-up card from the bottom: a card to answer, or something Doddy just made. Open
    /// already (card or transcript), it stays as it is; never over the Face ID cover.
    private func presentCard() {
        guard !router.isVoicePresented, !AppLock.shared.isLocked else { return }
        voiceAsCard = true
        voiceDetent = .medium
        router.isVoicePresented = true
    }

    /// A sheet or cover from the router is up (motion v2: Doddy is hidden while it is).
    private var routerCovers: Bool {
        router.isVoicePresented || router.isSetupPresented || router.isTidyUpPresented
            || router.isWrapUpPresented || router.isLookBackPresented || router.isWeeklyPlanPresented || router.isCheckInPresented
            || router.shownDraft != nil || SharedListsController.shared.invite != nil
    }

    /// Whether the motion world is on (motion v2): an iPhone layout, Doddy's pictures shown.
    private var motionWorldOn: Bool {
        !hideArt && !(horizontalSizeClass == .regular && DeviceSupport.hasSidebar)
    }

    /// What "Start listening when I open Doddy" needs to know right now (ADR-225). Read at decision
    /// time, so a switch changed in Settings counts from the next opening.
    private var openingConditions: OpeningConditions {
        OpeningConditions(
            listenOnOpen: OpeningPreferences.listenOnOpen(),
            atHome: profiles.route == .home,
            voiceAvailable: store.environment.capabilities.isAvailable(.voiceInput),
            microphoneAllowed: MicrophoneAccess.isAllowed,
            somethingIsOpen: router.isVoicePresented || router.isSetupPresented
                || router.shownDraft != nil || router.findRequest != nil)
    }

    /// "Before we start" is due (ADR-581). Not over the Face ID lock: it comes after the unlock.
    private var legalGateUp: Bool {
        LegalAcceptanceStore.isNeeded(legalRecordData) && !AppLock.shared.isLocked
    }

    /// "Allow access" is due (ADR-814): after the Terms, before the introduction, on a new installation only.
    /// Not over the Face ID lock, and not while the Terms step is up.
    private var accessStepUp: Bool {
        !legalGateUp && !AppLock.shared.isLocked
            && FirstRunAccessRule.shouldShow(
                seen: accessSeen, firstInstallation: profiles.isFirstInstallation,
                override: firstRunAccessOverride)
    }

    /// The UI tests' `-firstRunAccess YES/NO`, or nil when it isn't passed. A launch argument arrives as the
    /// text "YES" or "NO", not a Bool, so `as? Bool` never matched: `NO` was ignored, and a fresh install
    /// showed the step over Home unless an earlier test had answered it (the release-scope PR's Mac run,
    /// 7 Nov, where `FirstRunAccessUITests` didn't run first). Read like the welcome's `-welcome`.
    private var firstRunAccessOverride: Bool? {
        UserDefaults.standard.object(forKey: "firstRunAccess") == nil ? nil : UserDefaults.standard.bool(forKey: "firstRunAccess")
    }

    private var introductionPresentation: Binding<Bool> {
        Binding(
            // The introduction, and the Terms and access steps inside it, wait until the first-launch welcome is over (ADR-598, ADR-581).
            get: { (legalGateUp || accessStepUp || profiles.isIntroductionPresented) && !welcomeVisible },
            set: { presented in
                // The terms and access steps can't be closed without their own buttons.
                guard !presented, !legalGateUp, !accessStepUp, profiles.isIntroductionPresented else { return }
                Task { await profiles.finishIntroduction(saved: false) }
            })
    }

    private var tabs: some View {
        ZStack {
            tabContent.id(lockEpoch)
            // Motion v2: the one Doddy in the air (flights and fades). Under every sheet and cover.
            DoddyOverlay()
            // The first-launch welcome (ADR-598) sits over everything here; the Face ID cover is
            // drawn above all of it by the view that owns this one.
            if welcomeVisible {
                WelcomeView(finish: finishWelcome)
                    .zIndex(2)
                    .transition(.opacity)
            }
        }
        .tint(Theme.accentText)
        .background(Theme.canvas)
        // Every sheet and cover the router presents hides him in the frame it starts.
        .coversDoddy(routerCovers)
        // A tab changed without the tab bar (a link, a shortcut, a reminder): he follows.
        .onChange(of: selectedTab) { _, tab in DoddyDirector.shared.screenChanged(tab.motionScreen) }
        // One presentation point for the conversation, so a shortcut invocation while it is
        // open focuses it instead of starting a second one.
        // Waiting drafts appear only once a cover or sheet has finished going away.
        // The conversation itself is on Home (ADR-595); this sheet is its transcript, and it comes
        // up from the bottom, half height, when a card needs the user.
        .sheet(isPresented: $router.isVoicePresented, onDismiss: {
            voiceDetent = .large
            voiceAsCard = false
            router.showWaitingDraft()
        }) {
            VoiceView(asCard: voiceAsCard, onShowConversation: {
                voiceAsCard = false
                voiceDetent = .large
            })
                .presentationDetents([.medium, .large], selection: $voiceDetent)
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(voiceAsCard ? .enabled(upThrough: .medium) : .disabled)
        }
        .onChange(of: HomeConversation.shared.needsYou) { _, needsYou in
            guard needsYou else { return }
            presentTranscriptIfNeeded()
        }
        // Something new Doddy made or found comes up as the card too, not only in the transcript.
        .onChange(of: HomeConversation.shared.resultsToShow) { old, new in
            // Only for something added, not when a card was closed.
            let added = Set(new.split(separator: "|")).subtracting(old.split(separator: "|"))
            guard !added.isEmpty else { return }
            presentCard()
        }
        .sheet(isPresented: $router.isSetupPresented, onDismiss: { router.showWaitingDraft() }) {
            OpenDoddyWaysView(model: router.setup)
        }
        // The weekly tidy-up (ADR-228), from its notification or Settings.
        .sheet(isPresented: $router.isTidyUpPresented, onDismiss: { router.showWaitingDraft() }) { TidyUpView() }
        // A shared list's link (ADR-263): nothing is joined until Join.
        .sheet(item: inviteSheet) { invite in
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
        // The weekly plan (ADR-651), from its notification or Settings.
        .sheet(isPresented: $router.isWeeklyPlanPresented, onDismiss: { router.showWaitingDraft() }) { WeeklyPlanView() }
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
            router.isOnboardingShown = !atHome || legalGateUp || accessStepUp
            // The first time Home is ready and on screen is the launch (OpeningModel decides whether to listen).
            // Not while the first-launch welcome is up: it gets its turn when the welcome ends (ADR-598).
            if !welcomeVisible { opening.homeReady(openingConditions, isActive: scenePhase == .active) }
        }
        .onChange(of: welcomeVisible) { was, now in
            // The welcome is over: listening on open and the introduction go on as they always did.
            if was, !now { opening.homeReady(openingConditions, isActive: scenePhase == .active) }
        }
        // Recordings (ADR-588) is a sheet on Home, so a link or intent from any tab comes back to it.
        .onChange(of: router.isRecordingsPresented) { _, presented in
            if presented { selectedTab = .home }
        }
        // On my radar is a sheet on Home too: a radar push tapped on another tab comes back to Home first.
        .onChange(of: router.isRadarRequested) { _, requested in
            if requested { selectedTab = .home }
        }
        // Shopping is a sheet on Home too: a price-alert push tapped on another tab comes back to Home first.
        .onChange(of: router.isPriceAlertsRequested) { _, requested in
            if requested { selectedTab = .home }
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
            // The parking widget (ADR-315): the saved spot in Maps. No spot, nothing opens. With the
            // Face ID lock up it opens after the unlock (ADR-723).
            case .parking:
                router.runWhenUnlocked(.openParking) { QuickActions.openParkingSpot() }
            // DODDY Capture (ADR-588): the island's Open button. Navigation only.
            case .recordings:
                router.openRecordings()
            // The voice island's Show (ADR-616): the conversation's sheet, on the card that waits or
            // what Doddy made. Navigation only: the card still needs its own tap. With no
            // conversation left (an island from before the app stopped) it is just Home, so
            // opening the sheet never starts a new one.
            case .conversation:
                selectedTab = .home
                if HomeConversation.shared.forTranscript != nil || VoiceSessionController.runningConversation != nil {
                    voiceDetent = .medium
                    voiceAsCard = HomeConversation.shared.needsYou
                    router.showConversationStartedElsewhere()
                }
            }
        }
    }

    @ViewBuilder private var tabContent: some View {
        if horizontalSizeClass == .regular && DeviceSupport.hasSidebar {
            // iPad on a wide screen (ADR-430): a sidebar instead of the tab bar.
            SidebarLayout(selectedTab: $selectedTab, homePath: $homePath) {
                VStack(spacing: 0) {
                    selectedScreen
                        // One readable column (ADR-337) inside the detail column.
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                    if let deleted = store.recentlyDeleted {
                        UndoDeleteBar(deleted: deleted)
                    }
                }
                .background(Theme.canvas)
            }
        } else {
            VStack(spacing: 0) {
                TabView(selection: $selectedTab) {
                    HomeView(selectedTab: $selectedTab, showFind: $showFind, path: $homePath)
                        .tabItem { Label("Home", systemImage: "house") }
                        .tag(AppTab.home)
                    MemoriesView(showFind: $showFind)
                        .tabItem { Label("Memories", systemImage: "note.text") }
                        .tag(AppTab.memories)
                    SettingsView(openMemories: { openMemories($0) })
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(AppTab.settings)
                }
                .toolbar(.hidden, for: .tabBar)
                // A large iPhone in landscape is also regular width: one readable column (ADR-337).
                .frame(maxWidth: horizontalSizeClass == .regular ? 760 : .infinity)
                .frame(maxWidth: .infinity)
                .background(Theme.canvas)
                if let deleted = store.recentlyDeleted {
                    UndoDeleteBar(deleted: deleted)
                }
                // A sibling reserves real viewport space. A TabView-level safeAreaInset
                // left nested NavigationStack's final action behind the bar on iOS 27.
                // Home has its own bar and ••• menu, which reach Settings (ADR-545); notes and lists
                // are reached from Settings › Doddy's memory (ADR-633).
                if selectedTab != .home {
                    DoddyTabBar(selectedTab: $selectedTab)
                }
            }
        }
    }

    /// Settings › Doddy's memory opens notes, lists or search (ADR-633): the Memories screen, which no
    /// longer has a tab of its own. Lists or notes is the screen's own switch (ADR-216).
    private func openMemories(_ opening: MemoryOpening) {
        switch opening {
        case .notes: UserDefaults.standard.set(false, forKey: PreferenceKey.memoriesShowsLists)
        case .lists: UserDefaults.standard.set(true, forKey: PreferenceKey.memoriesShowsLists)
        case .find: break
        }
        // Doddy follows through `onChange(of: selectedTab)`, as for a link.
        selectedTab = .memories
        if opening == .find { showFind = true }
    }

    /// The sidebar's detail column shows one screen at a time. Home's path lives here, so Home
    /// keeps its place across a switch; Memories and Settings start at their top, as after a
    /// relaunch.
    @ViewBuilder private var selectedScreen: some View {
        switch selectedTab {
        case .home: HomeView(selectedTab: $selectedTab, showFind: $showFind, path: $homePath)
        case .memories: MemoriesView(showFind: $showFind)
        case .settings: SettingsView(openMemories: { openMemories($0) })
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
                .motionMark("undo")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(Theme.quietSurface)
        // Motion v2 (Q3): the bar above the tab bar is "the strip if showing", a surface that
        // comes and goes under him.
        .motionSurface(.panel)
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .contain)
        .task(id: deleted.deletedAt) {
            try? await Task.sleep(for: .seconds(DeletedNote.undoWindow))
            store.forgetDeleted(deleted)
        }
    }
}
