import DoddyCore
import SwiftUI

/// Settings (ADR-580, shortened by ADR-633 and again on 5 Nov 2026): four short groups and nine rows. Each row opens a page;
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
                // Decision 2026-11-08-required-account: only in a build with Doddy accounts set up.
                DoddyAccountSettingsSection()
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

    /// Help, the legal pages, Doddy's social accounts, the version and Advanced: one row (owner, 5 Nov 2026),
    /// because none of them is something a person changes about Doddy.
    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutSettingsView()
            } label: {
                StatusRow(title: NSLocalizedString("About", comment: "Settings row: help, terms, version"), value: Self.versionText)
            }
            .accessibilityIdentifier("settings.about")
        } footer: {
            Text("Doddy is an AI, not a person.")
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

    static var helpURL: URL {
        URL(string: (languageCode ?? "").hasPrefix("pl")
            ? "https://www.doddy.lol/pl/what-can-doddy-do/"
            : "https://www.doddy.lol/what-can-doddy-do/")!
    }

    // Doddy's own social accounts (ADR-130). Opening one hands off to the system; the app sends nothing.
    static let tiktokURL = URL(string: "https://www.tiktok.com/@doddy_mate")!
    static let instagramURL = URL(string: "https://www.instagram.com/doddy_mate/")!

    /// "0.1.0 (12, 8f3c2a1)": the version, the build number and, for a build Xcode Cloud made, the
    /// commit it was made from (`BuildCommit`, 7 Nov 2026 audit).
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        return BuildCommit.versionText(
            version: info?["CFBundleShortVersionString"] as? String,
            build: info?["CFBundleVersion"] as? String,
            commit: info?["DoddyGitCommit"] as? String)
    }
}

/// Settings › About (owner, 5 Nov 2026): what used to be the bottom group of Settings. Nothing here
/// changes how Doddy behaves, so it is out of the first page. Same rows, same identifiers.
struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                Link(destination: SettingsView.helpURL) {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("settings.help")
                Link(destination: LegalDocuments.url(.terms, languageCode: SettingsView.languageCode)) {
                    Label("Terms & Conditions", systemImage: "doc.text")
                }
                .accessibilityIdentifier("settings.terms")
                Link(destination: LegalDocuments.url(.privacy, languageCode: SettingsView.languageCode)) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                .accessibilityIdentifier("settings.privacyPolicy")
            }
            Section {
                // Doddy's own social accounts (ADR-130). Opening one hands off to the system; the app sends nothing.
                Link(destination: SettingsView.tiktokURL) {
                    Label("TikTok", systemImage: "play.rectangle")
                }
                .accessibilityIdentifier("settings.tiktok")
                Link(destination: SettingsView.instagramURL) {
                    Label("Instagram", systemImage: "camera")
                }
                .accessibilityIdentifier("settings.instagram")
            }
            Section {
                StatusRow(title: NSLocalizedString("Version", comment: ""), value: SettingsView.versionText)
                NavigationLink {
                    AdvancedSettingsView()
                } label: {
                    Text("Advanced")
                }
                .accessibilityIdentifier("settings.advanced")
            } footer: {
                Text("Links open outside Doddy; nothing from the app is shared.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(Theme.ink)
    }
}
