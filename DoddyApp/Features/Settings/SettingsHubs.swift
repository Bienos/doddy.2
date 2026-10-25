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
                    StatusRow(title: NSLocalizedString("Notes", comment: ""), value: "\(store.memories.count)")
                }
                .accessibilityIdentifier("settings.memory.notes")
                Button { openMemories(.lists) } label: {
                    StatusRow(title: NSLocalizedString("Lists", comment: ""), value: "\(store.lists.count)")
                }
                .accessibilityIdentifier("settings.memory.lists")
                Button { openMemories(.find) } label: {
                    Label("Find something", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("settings.memory.find")
            } footer: {
                Text("Only what you chose to save. Kept on this iPhone.")
            }
            .foregroundStyle(Theme.ink)
            Section {
                NavigationLink {
                    AboutYouSettingsView()
                } label: {
                    StatusRow(title: NSLocalizedString("My profile", comment: ""),
                              value: profiles.profile.isEmpty ? NSLocalizedString("Not set", comment: "")
                                  : (profiles.profile.value(.name) ?? NSLocalizedString("Saved", comment: "")))
                }
                .accessibilityIdentifier("settings.profile")
                NavigationLink {
                    KnowledgeSettingsView()
                } label: {
                    Text("What Doddy knows")
                }
                .accessibilityIdentifier("settings.knowledge")
                NavigationLink {
                    MemoriesSettingsView()
                } label: {
                    Text("Export, backup and delete")
                }
                .accessibilityIdentifier("settings.memories")
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
    @AppStorage(PreferenceKey.assistantConsent) private var assistantConsent = false
    @State private var connections = ConnectionController()

    private var activityLog: ActivityLogStore { .shared }

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
                NavigationLink {
                    OnlineAccountsScreen()
                } label: {
                    Text("Online accounts")
                }
                .accessibilityIdentifier("settings.onlineAccounts")
                // ADR-641: parcels checked with InPost by the number you add; off until you turn it on.
                NavigationLink {
                    ParcelsView()
                } label: {
                    Text("Parcels (InPost)")
                }
                .accessibilityIdentifier("settings.parcels")
                // ADR-640: your inFakt key, kept in this iPhone's Keychain.
                NavigationLink {
                    InFaktSettingsView()
                } label: {
                    Text("Invoices (inFakt)")
                }
                .accessibilityIdentifier("settings.invoices")
                // ADR-600: sign in to Doddy on the web with a code from this iPhone.
                NavigationLink {
                    WebSignInScreen()
                } label: {
                    Text("Doddy on the web")
                }
                .accessibilityIdentifier("settings.web")
                NavigationLink {
                    AskDoddySettingsView()
                } label: {
                    StatusRow(title: NSLocalizedString("Ask Doddy (typed questions)", comment: ""),
                              value: assistantConsent ? NSLocalizedString("On", comment: "") : NSLocalizedString("Off", comment: ""))
                }
                .accessibilityIdentifier("settings.askDoddy")
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

    private var activitySummary: String {
        let today = activityLog.entries.filter { Calendar.current.isDateInToday($0.at) }.count
        return activityLog.entries.isEmpty ? NSLocalizedString("Nothing yet", comment: "") : "\(today) today"
    }
}

/// Settings › Notifications (ADR-633): everything that can reach the user without opening Doddy.
struct NotificationsSettingsView: View {
    var body: some View {
        Form {
            Section {
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
            }
            Section {
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
        .settingsPage()
        .navigationTitle("Notifications")
    }
}
