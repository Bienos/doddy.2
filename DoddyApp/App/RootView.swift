import DoddyCore
import SwiftUI

enum PreferenceKey {
    /// Off by default (owner decision D4): note reminders never carry the note text unless turned on.
    static let showNoteTextInNotifications = "showNoteTextInNotifications"
    static let notificationExplainerSeen = "notificationExplainerSeen"
    static let appearance = "appearance"
    /// Memories list order (`MemorySort` raw value); display only (ADR-186).
    static let memorySort = "memorySort"
    /// JSON array of pinned note ids (`PinnedNotes`); display only, never any note text (ADR-187).
    static let pinnedNotes = "pinnedNotes"
    static let hideCharacterArt = "hideCharacterArt"
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
    /// Settings → Voice and personality: auto, english or polish (`ConversationLanguage`).
    static let voiceLanguage = "voice.language"
    /// What Doddy calls the user; sent with each voice conversation only when set (ADR-132).
    static let nickname = "personality.nickname"
    /// Settings → About you: send the approved introduction answers to voice conversations.
    /// Off by default; nothing about the user leaves the phone until they switch it on.
    static let shareProfileWithVoice = "shareProfileWithVoice"
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
    /// Find by meaning (ADR-210). On unless turned off; on-device only. Off deletes the vectors.
    static let findByMeaning = "findByMeaning"
    /// "Worth keeping?" after a voice conversation (ADR-211). On unless turned off; on-device rules.
    static let suggestSavesAfterConversation = "suggestSavesAfterConversation"
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
    @Bindable private var router = ShortcutRouter.shared

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
            .task {
                await store.reload()
                await noteReminders.refreshOnForeground()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await noteReminders.refreshOnForeground() } }
            }
            // A tapped note reminder opens its exact memory on Home.
            .task(id: noteReminders.pendingOpenMemoryID) {
                guard let memoryID = noteReminders.pendingOpenMemoryID else { return }
                selectedTab = .home
                homePath = [memoryID]
                noteReminders.pendingOpenMemoryID = nil
            }
            // Keeps the opt-in server copy (memory on calls) equal to what is on this iPhone.
            .onChange(of: store.revision) { MemoryCopySync.shared.schedule(store.memories) }
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

    private var tabs: some View {
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
            if let deleted = store.recentlyDeleted {
                UndoDeleteBar(deleted: deleted)
            }
            // A sibling reserves real viewport space. A TabView-level safeAreaInset
            // left nested NavigationStack's final action behind the bar on iOS 27.
            DoddyTabBar(selectedTab: $selectedTab)
        }
        .tint(Theme.accentText)
        .background(Theme.canvas)
        // One presentation point for the conversation, so a shortcut invocation while it is
        // open focuses it instead of starting a second one.
        // Waiting drafts appear only once a cover or sheet has finished going away.
        .fullScreenCover(isPresented: $router.isVoicePresented, onDismiss: { router.showWaitingDraft() }) { VoiceView() }
        .sheet(isPresented: $router.isSetupPresented, onDismiss: { router.showWaitingDraft() }) {
            BackTapSetupView(model: router.setup)
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
        }
        .onOpenURL { url in
            // doddy://home | memories | settings — navigation only; unknown links are ignored.
            guard let link = DeepLink(url: url) else { return }
            switch link {
            case .home: selectedTab = .home
            case .memories: selectedTab = .memories
            case .settings: selectedTab = .settings
            }
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
            Text(failed ? "Couldn't bring the note back." : "Note deleted.")
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
