import DoddyCore
import SwiftUI

/// Settings (ADR-580, shortened by ADR-633 and again on 5 Nov 2026; Phone calls came out of Notifications and the voice and
/// personality pages became one on 12 Nov 2026, decision `2026-11-12-settings-one-voice-page`): four short groups and nine
/// rows. Each row opens a page;
/// the controls that were rows here (the island, Siri, the connections, the notifications, the memory
/// pages) are on those pages with the same preference keys and accessibility identifiers, so nothing a
/// user set changes. Explanations live on the screen a row opens, in Help, in "What leaves this
/// iPhone" and in the Privacy Policy. Where each old row went: `docs/implementation/SETTINGS_SIMPLIFIED.md`.
struct SettingsView: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(ConnectionPause.preferenceKey) private var pauseAllConnections = false
    @AppStorage(PreferenceKey.personalityHumour) private var humourRaw = PersonalitySettings.doddyDefault.humour.rawValue
    @AppStorage(PreferenceKey.personalityLength) private var lengthRaw = PersonalitySettings.doddyDefault.length.rawValue
    @AppStorage(PreferenceKey.personalityFormality) private var formalityRaw = PersonalitySettings.doddyDefault.formality.rawValue
    @AppStorage(PreferenceKey.personalityMood) private var moodRaw = PersonalitySettings.doddyDefault.mood.rawValue
    @State private var connections = ConnectionController()
    /// A row whose feature the build hides is left out (decision 2026-11-07-release-scope).
    private var scope: ReleaseScope { ReleaseScopeStore.current }
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
                // What this page is for (12 Nov 2026). It said "You choose each saved memory…", which belongs on the memory page.
                Text("Set how Doddy sounds, what he remembers and what he can use.")
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
                SettingsRow(icon: "waveform", title: NSLocalizedString("Voice and personality", comment: ""), value: personalitySummary)
            }
            .accessibilityIdentifier("settings.voice")
            NavigationLink {
                DoddyMemorySettingsView(openMemories: { opening in
                    openMemories(opening)
                    stackID = UUID()
                })
            } label: {
                SettingsRow(icon: "books.vertical", title: NSLocalizedString("Doddy's memory", comment: "Settings row: notes, lists and what Doddy knows"),
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
                SettingsRow(icon: "link", title: NSLocalizedString("Connections", comment: ""), value: connectionSummary)
            }
            .accessibilityIdentifier("settings.connectionsHub")
            // Its page uses its own controller; re-read when coming back from it.
            .onAppear { Task { await connections.refresh() } }
            // Its own row since 12 Nov 2026: it was the last row of Notifications, and verifying the number was one more
            // page down from there.
            if scope.shows(.phoneCalls) {
                NavigationLink {
                    CallsSettingsView()
                } label: {
                    SettingsRow(icon: "phone", title: NSLocalizedString("Phone calls", comment: ""))
                }
                .accessibilityIdentifier("settings.calls")
            }
            NavigationLink {
                NotificationsSettingsView()
            } label: {
                SettingsRow(icon: "bell", title: NSLocalizedString("Notifications", comment: ""))
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
                SettingsRow(icon: "globe", title: NSLocalizedString("Language", comment: ""),
                            value: AppLanguageStore.chosen().nativeName ?? NSLocalizedString("Same as this iPhone", comment: ""))
            }
            .accessibilityIdentifier("settings.language")
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                SettingsRow(icon: "paintbrush", title: NSLocalizedString("Appearance", comment: ""))
            }
            .accessibilityIdentifier("settings.appearance")
            NavigationLink {
                PrivacySettingsView()
            } label: {
                SettingsRow(icon: "hand.raised", title: NSLocalizedString("Privacy", comment: ""))
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
                SettingsRow(icon: "info.circle", title: NSLocalizedString("About", comment: "Settings row: help, terms, version"), value: Self.versionText)
            }
            .accessibilityIdentifier("settings.about")
        }
    }

    // MARK: Values

    /// "Default", "Focused", "Playful" or "Custom": what the personality dials add up to.
    private var personalitySummary: String {
        PersonalitySections.summary(PersonalitySettings(humour: humourRaw, length: lengthRaw, formality: formalityRaw, mood: moodRaw))
    }

    private var connectionSummary: String {
        if pauseAllConnections { return NSLocalizedString("Paused", comment: "") }
        let on = VoiceConnection.allCases.filter { connections.state(of: $0) == .on }.count
        return on == 0
            ? NSLocalizedString("All off", comment: "Settings › Connections: none is on")
            : String(format: NSLocalizedString("%lld of %lld on", comment: "Settings › Connections: how many are on"), on, VoiceConnection.allCases.count)
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
            // Decision 2026-11-08-required-account: only in a build with Doddy accounts set up. One page down from
            // Settings since 11 Nov 2026, so the first page is about Doddy, not the sign-in.
            DoddyAccountSettingsSection()
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

/// A first-page Settings row (11 Nov 2026): a small tile with the row's symbol in Doddy's orange, the title and,
/// when there is one, a quiet value. The title is looked up in the string catalog like `StatusRow`'s.
struct SettingsRow: View {
    let icon: String
    let title: String
    var value: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkOnOrange)
                .frame(width: 30, height: 30)
                .background(Theme.orangeCue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Text(NSLocalizedString(title, comment: ""))
            Spacer(minLength: 12)
            if let value {
                Text(value)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
