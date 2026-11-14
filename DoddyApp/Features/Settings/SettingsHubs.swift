import DoddyCore
import SwiftUI

// The pages behind Settings' short rows (ADR-633). Each gathers rows that used to sit on the top level,
// unchanged: same pages, same preference keys, same accessibility identifiers.

/// Which memory screen a row opens. Notes, lists and search are their own screen (the Memories tab,
/// with no tab of its own any more); the other memory pages open inside Settings.
enum MemoryOpening: Equatable {
    case notes, lists, find
}

/// Settings › Doddy's memory (ADR-633): the one place for what Doddy remembers. It replaces Memories in
/// the tab bar and at the bottom of Home, the "Memories" sheet, and three separate Settings rows.
struct DoddyMemorySettingsView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(ProfileStore.self) private var profiles
    let openMemories: (MemoryOpening) -> Void

    var body: some View {
        Form {
            Section {
                Button { openMemories(.notes) } label: {
                    SettingsRow(icon: "note.text", title: NSLocalizedString("Notes", comment: ""), value: "\(store.memories.count)")
                }
                .accessibilityIdentifier("settings.memory.notes")
                Button { openMemories(.lists) } label: {
                    SettingsRow(icon: "list.bullet", title: NSLocalizedString("Lists", comment: ""), value: "\(store.lists.count)")
                }
                .accessibilityIdentifier("settings.memory.lists")
                // "Find something" was a third row; Find is on the notes screen itself (7 Nov 2026).
            } footer: {
                Text("Only what you chose to save. Kept on this iPhone.")
            }
            .foregroundStyle(Theme.ink)
            Section {
                NavigationLink {
                    AboutYouSettingsView()
                } label: {
                    SettingsRow(icon: "person.crop.circle", title: NSLocalizedString("My profile", comment: ""),
                                value: profiles.profile.isEmpty ? NSLocalizedString("Not set", comment: "")
                                    : (profiles.profile.value(.name) ?? NSLocalizedString("Saved", comment: "")))
                }
                .accessibilityIdentifier("settings.profile")
                // The learning loop waits for the beta's result (decision 2026-11-07-release-scope, M6): hidden with its row.
                if ReleaseScopeStore.current.shows(.learning) {
                    NavigationLink {
                        KnowledgeSettingsView()
                    } label: {
                        SettingsRow(icon: "lightbulb", title: NSLocalizedString("What Doddy knows", comment: ""))
                    }
                    .accessibilityIdentifier("settings.knowledge")
                }
                NavigationLink {
                    MemoriesSettingsView()
                } label: {
                    SettingsRow(icon: "square.and.arrow.up", title: NSLocalizedString("Export, backup and delete", comment: ""))
                }
                .accessibilityIdentifier("settings.memories")
            } footer: {
                // Was Settings' first-page header until 12 Nov 2026; it is about memory, so it is said here.
                Text("You choose each saved memory. See the original, edit it or remove it.")
            }
        }
        .settingsPage()
        .navigationTitle("Doddy's memory")
    }
}

/// Settings › Connections (ADR-633): everything Doddy connects to, the switch that pauses it all, and
/// what he did with it. Calendar, reminders and contacts; online accounts; the web; typed questions.
struct ConnectionsSettingsView: View {
    @AppStorage(ConnectionPause.preferenceKey) private var pauseAllConnections = false
    @AppStorage(HealthConnectionView.preferenceKey) private var appleHealthOn = false
    @AppStorage(PreferenceKey.assistantConsent) private var assistantConsent = PreferenceKey.assistantConsentDefault
    @State private var connections = ConnectionController()

    private var activityLog: ActivityLogStore { .shared }
    /// Each row below is a feature's way in; a hidden one has no row (decision 2026-11-07-release-scope).
    private var scope: ReleaseScope { ReleaseScopeStore.current }

    var body: some View {
        Form {
            Section {
                Toggle("Pause all connections", isOn: $pauseAllConnections)
                    .accessibilityIdentifier("settings.pauseAll")
            } footer: {
                HStack(alignment: .top, spacing: 12) {
                    // Paused: Doddy lies low, crouching (ADR-323).
                    if pauseAllConnections { WholeDoddyView(pose: .sneakyCrouch, height: 56) }
                    Text(pauseAllConnections
                        ? "Paused: Doddy doesn't use Calendar, Reminders, Contacts, Timers, Maps, Shortcuts, Messages or your online accounts. Your notes still work. Turning this off brings back the ones you had on; iPhone permissions don't change."
                        : "Each one starts off. Turning one on asks iPhone for permission first.")
                }
            }
            Section {
                NavigationLink {
                    ConnectionsView()
                } label: {
                    StatusRow(title: NSLocalizedString("Calendar, reminders, contacts", comment: ""), value: connectionSummary)
                }
                .accessibilityIdentifier("settings.connections")
                // Connections uses its own controller; re-read when coming back from it.
                .onAppear { Task { await connections.refresh() } }
                if scope.shows(.onlineAccounts) {
                    NavigationLink {
                        OnlineAccountsScreen()
                    } label: {
                        Text("Online accounts")
                    }
                    .accessibilityIdentifier("settings.onlineAccounts")
                }
                // ADR-641: parcels checked with InPost by the number you add; off until you turn it on.
                if scope.shows(.parcels) {
                    NavigationLink {
                        ParcelsView()
                    } label: {
                        Text("Parcels (InPost)")
                    }
                    .accessibilityIdentifier("settings.parcels")
                }
                // ADR-640: your inFakt key, kept in this iPhone's Keychain.
                if scope.shows(.invoices) {
                    NavigationLink {
                        InFaktSettingsView()
                    } label: {
                        Text("Invoices (inFakt)")
                    }
                    .accessibilityIdentifier("settings.invoices")
                }
                // ADR-735: USDC for pages that ask for payment. Off until the server has a wallet and the person turns it on.
                // Shown since 10 Nov 2026 (decision 2026-11-10-no-beta-scope); payments are off on the server by flag and say so. Home's "a payment wasn't confirmed" banner stays in every build.
                if scope.shows(.payments) {
                    NavigationLink {
                        PaymentsScreen()
                    } label: {
                        Text("Payments")
                    }
                    .accessibilityIdentifier("settings.payments")
                }
                // ADR-600: sign in to Doddy on the web with a code from this iPhone.
                if scope.shows(.doddyWeb) {
                    NavigationLink {
                        WebSignInScreen()
                    } label: {
                        Text("Doddy on the web")
                    }
                    .accessibilityIdentifier("settings.web")
                }
                // `Feature.` spelled out: `.messages` is also a `VoiceConnection`, so `shows(.messages)` is ambiguous.
                if scope.shows(Feature.messages) {
                    NavigationLink {
                        AskDoddySettingsView()
                    } label: {
                        StatusRow(title: NSLocalizedString("Ask Doddy (typed questions)", comment: ""),
                                  value: assistantConsent ? NSLocalizedString("On", comment: "") : NSLocalizedString("Off", comment: ""))
                    }
                    .accessibilityIdentifier("settings.askDoddy")
                }
            }
            // Sport mode (ADR-621 to 625): Apple Health, read only, and the training plan, each on its own page.
            if scope.shows(.health) || scope.shows(.trainingPlan) {
                Section {
                    if scope.shows(.health) {
                        NavigationLink {
                            HealthConnectionView()
                        } label: {
                            StatusRow(title: "Apple Health",
                                      value: appleHealthOn ? NSLocalizedString("On", comment: "") : NSLocalizedString("Off", comment: ""))
                        }
                        .accessibilityIdentifier("connections.appleHealth")
                    }
                    if scope.shows(.trainingPlan) {
                        NavigationLink {
                            TrainingPlanView()
                        } label: {
                            StatusRow(title: NSLocalizedString("Training plan", comment: ""), value: trainingPlanSummary)
                        }
                        .accessibilityIdentifier("connections.trainingPlan")
                        // ADR-642: sets, weight and how it felt, kept on this iPhone only if you say yes.
                        NavigationLink {
                            TrainingLogView()
                        } label: {
                            Text("Training log")
                        }
                        .accessibilityIdentifier("connections.trainingLog")
                    }
                } header: {
                    Text("Sport and health")
                }
            }
            Section {
                NavigationLink {
                    ActivityView()
                } label: {
                    StatusRow(title: NSLocalizedString("What Doddy did", comment: ""), value: activitySummary)
                }
                .accessibilityIdentifier("settings.activity")
            }
        }
        .settingsPage()
        .navigationTitle("Connections")
    }

    private var connectionSummary: String {
        if pauseAllConnections { return NSLocalizedString("Paused", comment: "") }
        let on = VoiceConnection.allCases.filter { connections.state(of: $0) == .on }.count
        return on == 0 ? "All off" : "\(on) of \(VoiceConnection.allCases.count) on"
    }

    /// "Week 3 of 8", the days until it starts, or None.
    private var trainingPlanSummary: String {
        guard let saved = TrainingPlanStore.shared.saved else { return NSLocalizedString("None", comment: "") }
        return PlanText.position(PlanCalendar.position(of: saved.plan, start: saved.start, now: .now, calendar: .current), plan: saved.plan)
    }

    private var activitySummary: String {
        let today = activityLog.entries.filter { Calendar.current.isDateInToday($0.at) }.count
        return activityLog.entries.isEmpty ? NSLocalizedString("Nothing yet", comment: "") : "\(today) today"
    }
}

/// Settings › Notifications (ADR-633): everything that can reach the user without opening Doddy.
/// A row whose feature the build hides is left out (decision 2026-11-07-release-scope). Phone calls moved to Settings'
/// first page on 12 Nov 2026 (decision `2026-11-12-settings-one-voice-page`); the rows have the first page's tiles.
struct NotificationsSettingsView: View {
    private var scope: ReleaseScope { ReleaseScopeStore.current }

    var body: some View {
        Form {
            Section {
                if scope.shows(.updates) {
                    NavigationLink {
                        UpdatesSettingsView()
                    } label: {
                        SettingsRow(icon: "bell.badge", title: NSLocalizedString("Notifications and texts", comment: ""))
                    }
                    .accessibilityIdentifier("settings.updates")
                }
                NavigationLink {
                    RoutinesSettingsView()
                } label: {
                    SettingsRow(icon: "checklist", title: NSLocalizedString("Check-ins and reminders", comment: ""))
                }
                .accessibilityIdentifier("settings.routines")
            }
            Section {
                NavigationLink {
                    AlarmsView()
                } label: {
                    SettingsRow(icon: "alarm", title: NSLocalizedString("Alarms", comment: ""))
                }
                .accessibilityIdentifier("settings.alarms")
                if scope.shows(.birthdays) {
                    NavigationLink {
                        BirthdaysView()
                    } label: {
                        SettingsRow(icon: "gift", title: NSLocalizedString("Birthdays", comment: ""))
                    }
                    .accessibilityIdentifier("settings.birthdays")
                }
                if scope.shows(.dailyNews) {
                    NavigationLink {
                        NewsSettingsView()
                    } label: {
                        SettingsRow(icon: "newspaper", title: NSLocalizedString("Daily news", comment: ""))
                    }
                    .accessibilityIdentifier("settings.news")
                }
            }
        }
        .settingsPage()
        .navigationTitle("Notifications")
    }
}
