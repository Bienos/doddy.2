import DoddyCore
import SwiftUI

enum PreferenceKey {
    static let appearance = "appearance"
    static let hideCharacterArt = "hideCharacterArt"
    static let hasSeenFirstHello = "hasSeenFirstHello"
    static let voiceAgentID = "voiceAgentID"
}

enum AppTab: Hashable {
    case home, memories, settings
}

struct RootView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.hasSeenFirstHello) private var hasSeenFirstHello = false
    @State private var selectedTab: AppTab = .home
    @State private var showVoice = false
    private var launchRouter = VoiceLaunchRouter.shared

    private var colorScheme: ColorScheme? {
        switch AppearancePreference(rawValue: appearanceRaw) ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab, showVoice: $showVoice)
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
        .preferredColorScheme(colorScheme)
        .task { await store.reload() }
        // "Talk to Doddy" shortcut / Back Tap. Waits until the first hello has been seen, and
        // never opens voice when voice is not available.
        .onChange(of: launchRouter.isRequested, initial: true) { _, _ in openVoiceIfRequested() }
        .onChange(of: hasSeenFirstHello) { _, _ in openVoiceIfRequested() }
        .fullScreenCover(isPresented: .constant(!hasSeenFirstHello)) {
            FirstHelloView { hasSeenFirstHello = true }
                .preferredColorScheme(colorScheme)
        }
    }

    private func openVoiceIfRequested() {
        guard launchRouter.isRequested, hasSeenFirstHello else { return }
        launchRouter.clear()
        guard store.environment.capabilities.isAvailable(.voiceInput) else { return }
        selectedTab = .home
        showVoice = true
    }
}
