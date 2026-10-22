import DoddyCore
import SwiftUI

/// Settings (ADR-580): six short groups of controls, each a row or a switch. Explanations live on
/// the screen a row opens, in Help, in "What leaves this iPhone" and in the Privacy Policy, not
/// here; a short line stays where a choice sends something off the iPhone. The inventory of
/// where each old setting went is `docs/implementation/SETTINGS_SIMPLIFIED.md`.
struct SettingsView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(ProfileStore.self) private var profiles
    @AppStorage(TalkLaunchMode.preferenceKey) private var talkLaunchRaw = TalkLaunchMode.default.rawValue
    @AppStorage(LaunchPreferencesMigration.islandExpandsKey) private var islandExpands = true
    @AppStorage(VoiceProvider.preferenceKey) private var voiceProvider = ""
    @AppStorage(PreferenceKey.assistantConsent) private var assistantConsent = false
    @AppStorage(ConnectionPause.preferenceKey) private var pauseAllConnections = false
    @AppStorage(LegalAcceptance.preferenceKey) private var legalRecordData: Data?
    @State private var connections = ConnectionController()

    private var activityLog: ActivityLogStore { .shared }

    var body: some View {
        NavigationStack {
            Form {
                header
                profileSection
                voiceSection
                memorySection
                connectedAppsSection
                notificationsSection
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

    private var profileSection: some View {
        Section("Profile") {
            NavigationLink {
                AboutYouSettingsView()
            } label: {
                StatusRow(title: "My profile", value: profiles.profile.isEmpty ? NSLocalizedString("Not set", comment: "") : (profiles.profile.value(.name) ?? NSLocalizedString("Saved", comment: "")))
            }
            .accessibilityIdentifier("settings.profile")
            PersonalityLinkRow()
            NavigationLink {
                Form { AppLanguageSettingsSection() }
                    .navigationTitle("Language")
            } label: {
                StatusRow(title: "Language", value: AppLanguageStore.chosen().nativeName ?? NSLocalizedString("Same as this iPhone", comment: ""))
            }
            .accessibilityIdentifier("settings.language")
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                Text("Appearance")
            }
            .accessibilityIdentifier("settings.appearance")
        }
    }

    private var voiceSection: some View {
        Section {
            NavigationLink {
                VoiceSettingsView()
            } label: {
                StatusRow(title: "Voice", value: VoiceProvider.effective(stored: voiceProvider, tokenServerSet: true).shortName)
            }
            .accessibilityIdentifier("settings.voice")
            // What Doddy's "Talk to Doddy" control does (ADR-579). Which control the button runs is
            // set in iPhone Settings; the footer says where.
            Picker("Action Button", selection: $talkLaunchRaw) {
                Text("Dynamic Island").tag(TalkLaunchMode.dynamicIsland.rawValue)
                Text("Open App").tag(TalkLaunchMode.openApp.rawValue)
                Text("Automatic").tag(TalkLaunchMode.automatic.rawValue)
            }
            .accessibilityIdentifier("settings.actionButton")
            // The island and its styles: iPhone only (ADR-432, ADR-453).
            if DeviceSupport.hasDynamicIsland {
                IslandStyleLinkRow()
                Toggle("Expand when Doddy speaks", isOn: $islandExpands)
                    .accessibilityIdentifier("settings.islandExpands")
            }
            NavigationLink {
                WaysSettingsView()
            } label: {
                if DeviceSupport.hasBackTap { Text("Siri and Back Tap") } else { Text("Siri") }
            }
            .accessibilityIdentifier("settings.ways")
        } header: {
            Text("Voice and interaction")
        } footer: {
            Text(actionButtonFooter)
                .accessibilityIdentifier("settings.actionButton.note")
        }
    }

    private var actionButtonFooter: String {
        let what: String
        switch TalkLaunchMode.stored(talkLaunchRaw) {
        case .dynamicIsland: what = NSLocalizedString("Talk without opening Doddy. Press again to end.", comment: "")
        case .openApp: what = NSLocalizedString("Opens Doddy and starts talking.", comment: "")
        case .automatic: what = NSLocalizedString("Uses the Dynamic Island, or opens Doddy when something needs setting up first.", comment: "")
        }
        return what + " " + NSLocalizedString("To add Doddy: iPhone Settings › Action Button › Controls › Talk to Doddy.", comment: "")
    }

    private var memorySection: some View {
        Section("Memory and privacy") {
            NavigationLink {
                MemoriesSettingsView()
            } label: {
                StatusRow(title: "Memories", value: "\(store.memories.count)")
            }
            .accessibilityIdentifier("settings.memories")
            NavigationLink {
                KnowledgeSettingsView()
            } label: {
                Text("What Doddy knows")
            }
            .accessibilityIdentifier("settings.knowledge")
            NavigationLink {
                PrivacySettingsView()
            } label: {
                Text("Privacy")
            }
            .accessibilityIdentifier("settings.privacyScreen")
        }
    }

    private var connectedAppsSection: some View {
        Section {
            Toggle("Pause all connections", isOn: $pauseAllConnections)
                .accessibilityIdentifier("settings.pauseAll")
            NavigationLink {
                ConnectionsView()
            } label: {
                StatusRow(title: "Calendar, reminders, contacts", value: connectionSummary)
            }
            .accessibilityIdentifier("settings.connections")
            // Connections uses its own controller; re-read when coming back from it.
            .onAppear { Task { await connections.refresh() } }
            NavigationLink {
                ConnectedAppsScreen()
            } label: {
                Text("Connected Apps")
            }
            .accessibilityIdentifier("settings.connectedApps")
            NavigationLink {
                OnlineAccountsScreen()
            } label: {
                Text("Online accounts")
            }
            .accessibilityIdentifier("settings.onlineAccounts")
            // ADR-585: sign in to Doddy on the web with a code from this iPhone.
            NavigationLink {
                WebSignInScreen()
            } label: {
                Text("Doddy on the web")
            }
            .accessibilityIdentifier("settings.web")
            NavigationLink {
                AskDoddySettingsView()
            } label: {
                StatusRow(title: "Ask Doddy (typed questions)", value: assistantConsent ? NSLocalizedString("On", comment: "") : NSLocalizedString("Off", comment: ""))
            }
            .accessibilityIdentifier("settings.askDoddy")
            NavigationLink {
                ActivityView()
            } label: {
                StatusRow(title: "What Doddy did", value: activitySummary)
            }
            .accessibilityIdentifier("settings.activity")
        } header: {
            Text("Connected apps")
        } footer: {
            HStack(alignment: .top, spacing: 12) {
                // Paused: Doddy lies low, crouching (ADR-323).
                if pauseAllConnections { WholeDoddyView(pose: .sneakyCrouch, height: 56) }
                Text(pauseAllConnections
                    ? "Paused: Doddy doesn't use Calendar, Reminders, Contacts, Timers, Maps, Shortcuts, Messages or your online accounts. Your notes still work. Turning this off brings back the ones you had on; iPhone permissions don't change."
                    : "Each one starts off. Turning one on asks iPhone for permission first.")
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            NavigationLink {
                UpdatesSettingsView()
            } label: {
                Text("Notifications and texts")
            }
            .accessibilityIdentifier("settings.updates")
            NavigationLink {
                RoutinesSettingsView()
            } label: {
                Text("Check-ins and reminders")
            }
            .accessibilityIdentifier("settings.routines")
            NavigationLink {
                AlarmsView()
            } label: {
                Text("Alarms")
            }
            .accessibilityIdentifier("settings.alarms")
            NavigationLink {
                BirthdaysView()
            } label: {
                Text("Birthdays")
            }
            .accessibilityIdentifier("settings.birthdays")
            NavigationLink {
                NewsSettingsView()
            } label: {
                Text("Daily news")
            }
            .accessibilityIdentifier("settings.news")
            NavigationLink {
                CallsSettingsView()
            } label: {
                Text("Phone calls")
            }
            .accessibilityIdentifier("settings.calls")
        }
    }

    private var aboutSection: some View {
        Section {
            Link(destination: Self.helpURL) {
                Label("Help", systemImage: "questionmark.circle")
            }
            .accessibilityIdentifier("settings.help")
            NavigationLink {
                PlanPracticeView()
            } label: {
                Text("Try a plan card")
            }
            .accessibilityIdentifier("settings.planPractice")
            Link(destination: LegalDocuments.url(.terms, languageCode: Self.languageCode)) {
                Label("Terms & Conditions", systemImage: "doc.text")
            }
            .accessibilityIdentifier("settings.terms")
            Link(destination: LegalDocuments.url(.privacy, languageCode: Self.languageCode)) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            .accessibilityIdentifier("settings.privacyPolicy")
            if let accepted = LegalAcceptance.decode(legalRecordData) {
                StatusRow(title: "Terms accepted", value: DateText.full(accepted.acceptedAt))
                    .accessibilityIdentifier("settings.termsAccepted")
            }
            Link(destination: Self.tiktokURL) {
                Label("TikTok · doddy_mate", systemImage: "play.rectangle")
            }
            .accessibilityIdentifier("settings.tiktok")
            Link(destination: Self.instagramURL) {
                Label("Instagram · doddy_mate", systemImage: "camera")
            }
            .accessibilityIdentifier("settings.instagram")
            StatusRow(title: "Version", value: Self.versionText)
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

    private var activitySummary: String {
        let today = activityLog.entries.filter { Calendar.current.isDateInToday($0.at) }.count
        return activityLog.entries.isEmpty ? NSLocalizedString("Nothing yet", comment: "") : "\(today) today"
    }

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
