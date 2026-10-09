import DoddyCore
import SwiftUI

enum PreferenceKey {
    static let appearance = "appearance"
    static let hideCharacterArt = "hideCharacterArt"
    static let hasSeenFirstHello = "hasSeenFirstHello"
    static let voiceAgentID = "voiceAgentID"
    /// HTTPS address of `server/voice-token`. Empty = development public agent.
    static let voiceTokenServer = "voiceTokenServer"
    /// Seconds since 1970; 0 = never. Set only after the tap test received a shortcut and the
    /// user confirmed it came from Double Back Tap.
    static let backTapTestedAt = "backTapTestedAt"
}

enum AppTab: Hashable {
    case home, memories, settings
}

struct RootView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.hasSeenFirstHello) private var hasSeenFirstHello = false
    @State private var selectedTab: AppTab = .home
    @State private var showVoice = false
    @State private var handledTalkRequest = 0
    /// A shortcut asked to talk before First Hello was finished; opens once it is.
    @State private var talkAfterHello = false

    private var colorScheme: ColorScheme? {
        switch AppearancePreference(rawValue: appearanceRaw) ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            MemoriesView()
                .tabItem { Label("Memories", systemImage: "note.text") }
                .tag(AppTab.memories)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(Theme.accentText)
        .fullScreenCover(isPresented: $showVoice) {
            VoiceView()
                .preferredColorScheme(colorScheme)
        }
        .preferredColorScheme(colorScheme)
        .task { await store.reload() }
        // Covers a shortcut that ran before this view existed (cold launch) and later ones.
        .onAppear(perform: handleTalkRequest)
        .onChange(of: router.talkRequest) { _, _ in handleTalkRequest() }
        .fullScreenCover(
            isPresented: .constant(!hasSeenFirstHello),
            onDismiss: {
                if talkAfterHello {
                    talkAfterHello = false
                    showVoice = true
                }
            }
        ) {
            FirstHelloView { hasSeenFirstHello = true }
                .preferredColorScheme(colorScheme)
        }
    }

    /// The AI disclosure in First Hello comes before any conversation, even one a shortcut asked for.
    private func handleTalkRequest() {
        guard router.talkRequest != handledTalkRequest else { return }
        handledTalkRequest = router.talkRequest
        guard store.environment.capabilities.isAvailable(.voiceInput) else { return }
        selectedTab = .home
        if hasSeenFirstHello {
            showVoice = true
        } else {
            talkAfterHello = true
        }
    }
}
