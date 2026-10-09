import DoddyCore
import SwiftUI
import UIKit

/// Settings → Connections. Lists what Doddy may use on this iPhone and what is still planned.
struct ConnectionsView: View {
    @Environment(ConnectionsStore.self) private var connections

    var body: some View {
        List {
            Section {
                Text("Doddy only uses what you connect here. Once connected, Doddy reads it when you open the app or ask. Anything Doddy adds is shown to you first and only added when you tap Add.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }

            Section("On this iPhone") {
                ForEach(ConnectionKind.allCases, id: \.self) { kind in
                    NavigationLink {
                        ConnectionDetailView(kind: kind)
                    } label: {
                        Label {
                            StatusRow(title: kind.title, value: ConnectionsCopy.status(connections.state(kind)))
                        } icon: {
                            Image(systemName: kind.systemImage).foregroundStyle(Theme.ink)
                        }
                    }
                    .accessibilityIdentifier("connections.\(kind.rawValue)")
                }
                NavigationLink {
                    NudgesView()
                } label: {
                    Label {
                        StatusRow(title: "Nudges", value: ConnectionsCopy.nudgeStatus(connections.nudgeAuthorization, pending: connections.pendingNudges.count))
                    } icon: {
                        Image(systemName: "bell").foregroundStyle(Theme.ink)
                    }
                }
                .accessibilityIdentifier("connections.nudges")
            }

            Section {
                StatusRow(title: "Google Calendar", value: "Through iPhone Calendar")
            } header: {
                Text("Accounts")
            } footer: {
                Text("Doddy has no Google sign-in of its own. Add your Google account to the iPhone's Calendar app in iOS Settings (Calendar → Calendar Accounts), then connect Calendar here.")
            }

            Section {
                StatusRow(title: "Message-style nudges from Doddy", value: "Planned V4b")
                StatusRow(title: "WhatsApp", value: "Planned V4b")
                StatusRow(title: "Watch notes (news)", value: "Planned V4c")
                StatusRow(title: "MCP servers", value: "Not planned yet")
            } header: {
                Text("Not built yet")
            } footer: {
                Text("These need a Doddy server and aren't part of this build. Doddy can't send iMessages: iOS doesn't let apps send texts on their own.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(Theme.ink)
        .task { await connections.refresh() }
        .refreshable { await connections.refresh() }
    }
}

/// One connection: verified status, what Doddy can do, what leaves the iPhone, connect/disconnect.
struct ConnectionDetailView: View {
    let kind: ConnectionKind

    @Environment(ConnectionsStore.self) private var connections
    @State private var isWorking = false
    @State private var confirmDisconnect = false

    private var state: ConnectionState { connections.state(kind) }

    var body: some View {
        List {
            Section {
                StatusRow(title: "Status", value: ConnectionsCopy.status(state))
                    .accessibilityIdentifier("connection.status")
                if case .connected(let proof) = state.status {
                    StatusRow(title: "Checked", value: "\(proof.evidence) · \(proof.verifiedAt.formatted(date: .omitted, time: .shortened))")
                }
                statusExplanation
            }

            Section("What Doddy can do") {
                ForEach(Self.abilities(kind), id: \.self) { Text($0) }
            }

            Section("What leaves this iPhone") {
                Text(Self.egress(kind))
            }

            if kind == .calendar, state.canRead, !connections.calendars.isEmpty {
                Section("Calendars Doddy can see") {
                    ForEach(connections.calendars) { calendar in
                        StatusRow(title: calendar.title, value: calendar.allowsWrites ? "Read and add" : "Read only")
                    }
                }
            }

            Section { actions }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(Theme.ink)
        .confirmationDialog("Stop using \(kind.title)?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { run { await connections.disconnect(kind) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Doddy stops reading \(kind.title). Anything already added stays in \(kind.title). To remove the iOS permission too, turn it off in iOS Settings → Doddy.")
        }
    }

    @ViewBuilder
    private var statusExplanation: some View {
        switch state.status {
        case .off:
            Text("Off. Doddy doesn't read \(kind.title).")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        case .notConnected:
            Text("iOS will ask you once. You can change it any time in iOS Settings.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        case .denied:
            Text("\(kind.title) access is off for Doddy in iOS Settings, so Doddy can't read or add anything. Only you can turn it on there.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        case .authorizedUnverified:
            Text(state.authorization == .writeOnly
                 ? "iOS lets Doddy add events but not see them, so Doddy can't show your day or confirm what it added. Choose Full Access to fix that."
                 : "Permission is on but Doddy hasn't read anything yet. Pull down to check.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        case .connected:
            EmptyView()
        case .error(let message):
            ProblemView(message: message)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if !connections.isAvailable(kind) {
            Text("Not available in this build.").foregroundStyle(Theme.secondaryText)
        } else {
            switch state.status {
            case .off, .notConnected:
                Button { run { await connections.connect(kind) } } label: {
                    HStack { Text(isWorking ? "Connecting…" : "Connect \(kind.title)"); Spacer(); Image(systemName: "link") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isWorking)
                .accessibilityIdentifier("connection.connect")
            case .denied:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    HStack { Text("Open iOS Settings"); Spacer(); Image(systemName: "gear") }
                }
                .buttonStyle(PrimaryButtonStyle())
                disconnectButton
            case .authorizedUnverified:
                Button { run { await connections.connect(kind) } } label: {
                    HStack { Text(state.authorization == .writeOnly ? "Ask for full access" : "Check again"); Spacer(); Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isWorking)
                disconnectButton
            case .error:
                Button { run { await connections.refresh() } } label: {
                    HStack { Text("Try again"); Spacer(); Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isWorking)
                disconnectButton
            case .connected:
                disconnectButton
            }
        }
    }

    private var disconnectButton: some View {
        Button(role: .destructive) { confirmDisconnect = true } label: {
            HStack { Text("Disconnect"); Spacer(); Image(systemName: "xmark.circle") }
        }
        .buttonStyle(SecondaryButtonStyle(tint: Theme.error))
        .accessibilityIdentifier("connection.disconnect")
    }

    private func run(_ work: @escaping @MainActor () async -> Void) {
        isWorking = true
        Task {
            await work()
            isWorking = false
        }
    }

    static func abilities(_ kind: ConnectionKind) -> [String] {
        switch kind {
        case .calendar:
            [
                "Show today's events on Home.",
                "Tell you what's on when you ask while talking to Doddy.",
                "Add an event after you tap Add on the card Doddy shows. Never silently.",
                "Nudge you before an event, scheduled on this iPhone.",
            ]
        case .reminders:
            [
                "Show reminders due today on Home.",
                "Add a reminder after you tap Add on the card Doddy shows. Never silently.",
            ]
        case .contacts:
            [
                "Find a person by name when you ask while talking to Doddy, and show their number and e-mail on your screen.",
                "Doddy can't call, text or e-mail anyone for you.",
            ]
        }
    }

    static func egress(_ kind: ConnectionKind) -> String {
        switch kind {
        case .calendar:
            "Nothing, unless you ask about your calendar while talking to Doddy. Then the events Doddy looked up (titles, times, places) are sent to ElevenLabs, which runs the voice conversation."
        case .reminders:
            "Nothing, unless you ask Doddy to add a reminder while talking. Then the reminder you dictated is part of the conversation sent to ElevenLabs."
        case .contacts:
            "Only names. When you ask for someone while talking, Doddy tells the voice agent the matching names; phone numbers and e-mail addresses stay on your screen and are never sent."
        }
    }
}

/// Nudges scheduled on this iPhone, read back from iOS.
struct NudgesView: View {
    @Environment(ConnectionsStore.self) private var connections
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                StatusRow(title: "Notifications", value: notificationText)
                if connections.nudgeAuthorization == .denied {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            } footer: {
                Text("Nudges are scheduled by iOS on this iPhone. They need no internet and no Doddy server. If an event moves, its nudge keeps its old time until you set it again.")
            }

            Section("Scheduled") {
                if connections.pendingNudges.isEmpty {
                    Text("No nudges set. On Home, tap the bell next to one of today's events.")
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(connections.pendingNudges) { nudge in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(nudge.body)
                        Text(nudge.fireAt.map { "At \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Time unknown")
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                        if let event = connections.event(for: nudge), nudge.matches(event) == false {
                            Label("The event moved. This nudge is at the old time.", systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(Theme.error)
                        }
                    }
                    .swipeActions {
                        Button("Cancel", role: .destructive) { Task { await cancel(nudge) } }
                    }
                    .accessibilityAction(named: "Cancel nudge") { Task { await cancel(nudge) } }
                }
            }

            if let problem = errorMessage ?? connections.nudgeProblem {
                Section { ProblemView(message: problem) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Nudges")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(Theme.ink)
        .task { await connections.refresh() }
        .refreshable { await connections.refresh() }
    }

    private var notificationText: String {
        switch connections.nudgeAuthorization {
        case .notDetermined: "Asked when you set the first nudge"
        case .denied: "Off in iOS Settings"
        case .authorized: "On"
        }
    }

    private func cancel(_ nudge: ScheduledNudge) async {
        do {
            try await connections.cancelNudge(id: nudge.id)
            errorMessage = nil
        } catch {
            errorMessage = ConnectionsCopy.message(for: error)
        }
    }
}
