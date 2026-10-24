import DoddyCore
import SwiftUI

/// Settings (ADR-580, shortened by ADR-633): four short groups and fourteen rows. Each row opens a page;
/// the controls that were rows here (the island, Siri, the connections, the notifications, the memory
/// pages) are on those pages with the same preference keys and accessibility identifiers, so nothing a
/// user set changes. Explanations live on the screen a row opens, in Help, in "What leaves this
/// iPhone" and in the Privacy Policy. Where each old row went: `docs/implementation/SETTINGS_SIMPLIFIED.md`.
struct SettingsView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(VoiceProvider.preferenceKey) private var voiceProvider = ""
    @AppStorage(ConnectionPause.preferenceKey) private var pauseAllConnections = false
    @State private var connections = ConnectionController()
    /// Opens notes, lists or search (ADR-633). They are their own screen, reached from Doddy's memory.
    var openMemories: (MemoryOpening) -> Void = { _ in }
    /// A new value empties the page stack. Set when notes, lists or search open from Doddy's memory, so
    /// Settings is on its first page when it is next shown (ADR-633): one move for Doddy, the one any
    /// return to Settings makes, not a move to the tab bar and another as the page closes. That second
    /// move changed his size while he was still visible (the motion checks, MotionEvidenceTests).
    @State private var stackID = UUID()

    var body: some View {
        NavigationStack {
            Form {
                header
                doddySection
                connectionsSection
                iPhoneSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            // Motion v2 (MV3): Settings pushes its pages without a path, so the form's own
            // appearing says whether a page covers it (he stays where he stood, covered).
            .onAppear { DoddyDirector.shared.pageChanged(on: .settings, open: false, detail: false) }
            .onDisappear { DoddyDirector.shared.pageChanged(on: .settings, open: true, detail: false) }
            .navigationTitle("Settings")
            .toolbar(.hidden, for: .tabBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .id(stackID)
        .foregroundStyle(Theme.ink)
    }

    // MARK: Groups

    private var header: some View {
        Section {
            JourneyHeading(eyebrow: "Less magic. More control.", title: "Yours to keep.\nYours to change.")
            HStack(spacing: 18) {
                if DoddyDirector.shared.isActive {
                    // Motion v2 (Q4): Doddy's spot on Settings is where this picture
                    // stands, on its own floor (3 pt above the box: the picture's ground
                    // is at 97 %). No new line: the one Doddy stands here instead of a
                    // picture of him, in the picture's place (same size, no gap).
                    Color.clear.frame(width: 73, height: 110)
                        .overlay(alignment: .bottom) {
                            Color.clear.frame(width: 60, height: 1)
                                .padding(.bottom, 3)
                                .motionSurface(.ledge("settings"))
                        }
                } else {
                    UploadedCharacterView(assetName: "UploadedDoddy_Privacy", height: 110)
                }
                Text("You choose each saved memory. See the original, edit it or remove it.")
                    .font(.subheadline)
            }
        }
        .listRowBackground(Theme.canvas)
    }

    /// His voice and his memory: the two things that make him Doddy.
    private var doddySection: some View {
        Section("Doddy") {
            NavigationLink {
                VoiceSettingsView()
            } label: {
                StatusRow(title: NSLocalizedString("Voice", comment: ""),
                          value: VoiceProvider.effective(stored: voiceProvider, tokenServerSet: true).shortName)
            }
            .accessibilityIdentifier("settings.voice")
            NavigationLink {
                DoddyMemorySettingsView(openMemories: { opening in
                    openMemories(opening)
                    stackID = UUID()
                })
            } label: {
                StatusRow(title: NSLocalizedString("Doddy's memory", comment: "Settings row: notes, lists and what Doddy knows"),
                          value: String(format: NSLocalizedString("%lld notes", comment: "Settings › Doddy's memory: how many notes"), store.memories.count))
            }
            .accessibilityIdentifier("settings.memory")
        }
    }

    /// Everything Doddy connects to, and everything that reaches the user unasked: one row each.
    private var connectionsSection: some View {
        Section {
            NavigationLink {
                ConnectionsSettingsView()
            } label: {
                StatusRow(title: NSLocalizedString("Connections", comment: ""), value: connectionSummary)
            }
            .accessibilityIdentifier("settings.connectionsHub")
            // Its page uses its own controller; re-read when coming back from it.
            .onAppear { Task { await connections.refresh() } }
            NavigationLink {
                NotificationsSettingsView()
            } label: {
                Text("Notifications")
            }
            .accessibilityIdentifier("settings.notifications")
        }
    }

    private var iPhoneSection: some View {
        Section("This iPhone") {
            NavigationLink {
                Form { AppLanguageSettingsSection() }
                    .navigationTitle("Language")
            } label: {
                StatusRow(title: NSLocalizedString("Language", comment: ""),
                          value: AppLanguageStore.chosen().nativeName ?? NSLocalizedString("Same as this iPhone", comment: ""))
            }
            .accessibilityIdentifier("settings.language")
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                Text("Appearance")
            }
            .accessibilityIdentifier("settings.appearance")
            NavigationLink {
                PrivacySettingsView()
            } label: {
                Text("Privacy")
            }
            .accessibilityIdentifier("settings.privacyScreen")
        }
    }

    private var aboutSection: some View {
        Section {
            Link(destination: Self.helpURL) {
                Label("Help", systemImage: "questionmark.circle")
            }
            .accessibilityIdentifier("settings.help")
            Link(destination: LegalDocuments.url(.terms, languageCode: Self.languageCode)) {
                Label("Terms & Conditions", systemImage: "doc.text")
            }
            .accessibilityIdentifier("settings.terms")
            Link(destination: LegalDocuments.url(.privacy, languageCode: Self.languageCode)) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            .accessibilityIdentifier("settings.privacyPolicy")
            // Doddy's own social accounts (ADR-130); they stay on this page (owner, 24 Oct 2026).
            Link(destination: Self.tiktokURL) {
                Label("TikTok · doddy_mate", systemImage: "play.rectangle")
            }
            .accessibilityIdentifier("settings.tiktok")
            Link(destination: Self.instagramURL) {
                Label("Instagram · doddy_mate", systemImage: "camera")
            }
            .accessibilityIdentifier("settings.instagram")
            StatusRow(title: NSLocalizedString("Version", comment: ""), value: Self.versionText)
            NavigationLink {
                AdvancedSettingsView()
            } label: {
                Text("Advanced")
            }
            .accessibilityIdentifier("settings.advanced")
        } header: {
            Text("About")
        } footer: {
            Text("Doddy is an AI, not a person. Links open outside Doddy; nothing from the app is shared.")
        }
    }

    // MARK: Values

    private var connectionSummary: String {
        if pauseAllConnections { return NSLocalizedString("Paused", comment: "") }
        let on = VoiceConnection.allCases.filter { connections.state(of: $0) == .on }.count
        return on == 0 ? "All off" : "\(on) of \(VoiceConnection.allCases.count) on"
    }

    /// The language the screens are showing, for the Polish or English legal pages.
    static var languageCode: String? { Bundle.main.preferredLocalizations.first }

    private static var helpURL: URL {
        URL(string: (languageCode ?? "").hasPrefix("pl")
            ? "https://www.doddy.lol/pl/what-can-doddy-do/"
            : "https://www.doddy.lol/what-can-doddy-do/")!
    }

    // Doddy's own social accounts (ADR-130). Opening one hands off to the system; the app sends nothing.
    private static let tiktokURL = URL(string: "https://www.tiktok.com/@doddy_mate")!
    private static let instagramURL = URL(string: "https://www.instagram.com/doddy_mate/")!

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
