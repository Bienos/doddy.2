import DoddyCore
import SwiftUI

/// Builds the model from the development server settings. Without a server URL and a session
/// token the screen says Connected Apps isn't set up; it never shows invented connections.
struct ConnectedAppsScreen: View {
    @AppStorage(PreferenceKey.connectedAppsServerURL) private var serverURL = ""

    var body: some View {
        ConnectedAppsView(model: Self.makeModel(serverURL: serverURL))
            .id(serverURL)
    }

    @MainActor
    static func makeModel(serverURL: String) -> ConnectedAppsModel {
        let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces))
        let client = url.flatMap {
            BackendConnectedAppsClient(baseURL: $0, boundToken: { KeychainSessionStore.read() }, transport: URLSessionTransport.shared)
        }
        // The token is used only with the server that issued it (`BoundSessionToken`).
        let configured = client != nil && url.flatMap { KeychainSessionStore.read()?.token(for: $0) } != nil
        return ConnectedAppsModel(client: configured ? client : nil, authenticator: SystemWebAuthenticator())
    }
}

struct ConnectedAppsView: View {
    @State private var model: ConnectedAppsModel
    @Environment(MemoryStore.self) private var store
    @State private var confirmConnect = false
    @State private var confirmDisconnect = false
    @State private var savedEvents: Set<Int> = []
    /// Events being saved right now, so a double tap can't save one twice (DOD-06).
    @State private var savingEvents: Set<Int> = []
    @State private var saveError: String?

    init(model: ConnectedAppsModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            if model.isDemo {
                Section {
                    Label("Demo data — Google Calendar is not connected", systemImage: "theatermasks")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("connectedApps.demoBanner")
                }
            }

            googleCalendar

            if let events = model.events {
                eventsSection(events)
            }

            if let receipt = model.lastReceipt {
                Section("Last action") {
                    NavigationLink {
                        ReceiptsView(receipts: model.receipts)
                    } label: {
                        ReceiptRow(receipt: receipt)
                    }
                    .accessibilityIdentifier("connectedApps.receipt")
                }
            }

            Section {
                ForEach(PlannedApp.allCases, id: \.self) { app in
                    StatusRow(title: app.name, value: "Planned")
                        .foregroundStyle(Theme.secondaryText)
                }
            } header: {
                Text("Planned")
            } footer: {
                Text("Not built yet. Nothing here asks for permission or connects anything.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Connected Apps")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onAppear { model.discardExpiredEvents() }
        .onChange(of: model.events?.receipt.operationId) { savedEvents = [] }
        .confirmationDialog("Connect Google Calendar?", isPresented: $confirmConnect, titleVisibility: .visible) {
            Button("Continue") { Task { await model.connect() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(connectExplanation)
        }
        .confirmationDialog("Disconnect Google Calendar?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await model.disconnect() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Doddy stops reading your calendar right away and asks Google to remove its access. Memories you saved yourself stay.")
        }
        .foregroundStyle(Theme.ink)
    }

    private var connectExplanation: String {
        model.connection?.mode == .mock
            ? "This server is in demo mode. No Google account is used; you'll see made-up events."
            : "You'll sign in with Google in a secure browser page. Doddy asks only to read your calendar events, to show plans like tomorrow's. It can't create, change or delete events."
    }

    // MARK: Google Calendar card

    @ViewBuilder
    private var googleCalendar: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Google Calendar", systemImage: "calendar")
                        .font(.headline)
                    Spacer()
                    Text(statusText)
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("connectedApps.status")
                }
                if let label = model.connection?.accountLabel, model.cardState == .connected {
                    Text("Calendar: \(label) (name reported by Google)")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(model.connection?.access.summary ?? "Reads your calendar events when you ask. Can't create, change or delete events.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)

            stateControls

            if let message = model.message {
                Label(message, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("connectedApps.message")
            }
        } footer: {
            if let checked = model.connection?.lastCheckedAt.flatMap(ConnectedAppsDates.instant) {
                Text("Last checked \(checked.formatted(date: .omitted, time: .shortened))")
            }
        }
    }

    @ViewBuilder
    private var stateControls: some View {
        switch model.cardState {
        case .notConfigured:
            Text("Connected Apps needs a Doddy server. Set its address and a session token in Settings › Connected Apps server.")
                .font(.footnote)
        case .loading, .connecting, .disconnecting:
            ProgressView(progressText)
                .accessibilityIdentifier("connectedApps.progress")
        case .awaitingDemoApproval:
            Text("Demo connection: no Google account is involved and the events are made up.")
                .font(.footnote)
            Button("Connect demo calendar") { Task { await model.completeDemo(approve: true) } }
                .accessibilityIdentifier("connectedApps.demoApprove")
            Button("Cancel", role: .cancel) { Task { await model.cancelDemo() } }
        case .disconnected:
            Button("Connect Google Calendar") { confirmConnect = true }
                .disabled(model.isWorking)
                .accessibilityIdentifier("connectedApps.connect")
        case .connected:
            Button {
                Task { await model.loadTomorrow() }
            } label: {
                if model.isReadingEvents {
                    ProgressView("Checking tomorrow…")
                } else {
                    Label("Tomorrow's events", systemImage: "calendar.day.timeline.left")
                }
            }
            .disabled(model.isWorking)
            .accessibilityIdentifier("connectedApps.tomorrow")
            disconnectButton
        case .permissionInsufficient(let reason):
            Text(Self.permissionText(reason))
                .font(.footnote)
            reconnectButton
            disconnectButton
        case .expired:
            Text("Access expired or was removed at Google. Reconnect to keep using it.")
                .font(.footnote)
            reconnectButton
            disconnectButton
        case .error(let message):
            Text(message).font(.footnote)
            Button("Try again") { Task { await model.load() } }
                .disabled(model.isWorking)
        }
    }

    private var reconnectButton: some View {
        Button("Reconnect") { confirmConnect = true }
            .disabled(model.isWorking)
            .accessibilityIdentifier("connectedApps.reconnect")
    }

    private var disconnectButton: some View {
        Button("Disconnect", role: .destructive) { confirmDisconnect = true }
            .disabled(model.isWorking)
            .accessibilityIdentifier("connectedApps.disconnect")
    }

    private var statusText: String {
        let demo = model.isDemo ? " (demo)" : ""
        switch model.cardState {
        case .notConfigured: return NSLocalizedString("Not set up", comment: "")
        case .loading: return NSLocalizedString("Checking…", comment: "")
        case .disconnected: return NSLocalizedString("Not connected", comment: "")
        case .connecting, .awaitingDemoApproval: return NSLocalizedString("Connecting…", comment: "")
        case .connected: return "Connected\(demo)"
        case .permissionInsufficient: return NSLocalizedString("Needs attention", comment: "")
        case .expired: return NSLocalizedString("Expired", comment: "")
        case .error: return NSLocalizedString("Couldn't check", comment: "")
        case .disconnecting: return NSLocalizedString("Disconnecting…", comment: "")
        }
    }

    private var progressText: String {
        switch model.cardState {
        case .connecting: NSLocalizedString("Connecting…", comment: "")
        case .disconnecting: NSLocalizedString("Disconnecting…", comment: "")
        default: "Checking…"
        }
    }

    static func permissionText(_ reason: ConnectionReason?) -> String {
        switch reason {
        case .grantNotReadOnly:
            "The access Google granted could change events, so Doddy won't use it. Disconnect, then reconnect allowing read-only access."
        case .missingReadScope:
            "Reading calendar events wasn't allowed. Reconnect and allow it."
        default:
            "Doddy couldn't confirm the access is read-only, so it won't use it."
        }
    }

    // MARK: Events (transient)

    private func eventsSection(_ result: EventsResult) -> some View {
        let zone = TimeZone(identifier: result.window.timeZone) ?? .current
        return Section {
            if result.events.isEmpty {
                Text("Nothing on your calendar for tomorrow.")
                    .accessibilityIdentifier("connectedApps.emptyDay")
            }
            ForEach(Array(result.events.enumerated()), id: \.offset) { index, event in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                        Text(Self.timeText(event, zone: zone) + (event.isRecurring ? " · repeats" : ""))
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    if savedEvents.contains(index) {
                        Label("Saved", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(Theme.confirmed)
                            .accessibilityLabel("Saved to memories")
                    } else {
                        Button("Save") { Task { await save(event, index: index, window: result.window) } }
                            .buttonStyle(.borderless)
                            .disabled(!store.isStorageAvailable || savingEvents.contains(index))
                            .accessibilityLabel("Save \(event.title) to memories")
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if result.truncated {
                Text("Showing the first \(result.events.count) events.").font(.footnote)
            }
            if result.cancelledHidden > 0 {
                Text("\(result.cancelledHidden) cancelled event\(result.cancelledHidden == 1 ? "" : "s") hidden.").font(.footnote)
            }
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
            }
        } header: {
            Text("Tomorrow · \(result.window.date)")
        } footer: {
            Text(sourceText(result))
        }
    }

    private func sourceText(_ result: EventsResult) -> String {
        let checked = ConnectedAppsDates.instant(result.retrievedAt)?.formatted(date: .omitted, time: .shortened) ?? "just now"
        let mode = result.mode == .mock ? "Demo data, not your calendar. " : ""
        return "\(mode)From Google Calendar (primary), checked \(checked), \(result.window.timeZone). Shown only; nothing is kept unless you tap Save."
    }

    static func timeText(_ event: CalendarEventItem, zone: TimeZone) -> String {
        guard !event.allDay, let start = ConnectedAppsDates.instant(event.start), let end = ConnectedAppsDates.instant(event.end) else {
            return NSLocalizedString("All day", comment: "")
        }
        let style = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)
        return "\(start.formatted(style))–\(end.formatted(style))"
    }

    /// Explicit save only: one tap, one event, stored as a note that names its source.
    private func save(_ event: CalendarEventItem, index: Int, window: EventsWindow) async {
        guard !savingEvents.contains(index), !savedEvents.contains(index) else { return }
        savingEvents.insert(index)
        defer { savingEvents.remove(index) }
        do {
            _ = try await store.save(
                text: ConnectedAppsDates.memoryText(for: event, window: window), category: .commitment, source: .sharedContent)
            savedEvents.insert(index)
            saveError = nil
        } catch {
            saveError = UserFacingError.message(for: error)
        }
    }
}

private enum PlannedApp: CaseIterable {
    case appleCalendar, appleReminders

    var name: String {
        switch self {
        case .appleCalendar: NSLocalizedString("Apple Calendar", comment: "")
        case .appleReminders: NSLocalizedString("Apple Reminders", comment: "")
        }
    }
}

private struct ReceiptRow: View {
    let receipt: ConnectedAppReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(receipt.summary)
            Text("\(Self.statusText(receipt.status)) · \(receipt.mode == .mock ? "demo" : "live") · \(ConnectedAppsDates.instant(receipt.timestamp)?.formatted(date: .abbreviated, time: .shortened) ?? receipt.timestamp)")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    static func statusText(_ status: ReceiptStatus) -> String {
        switch status {
        case .succeeded: NSLocalizedString("Done", comment: "")
        case .failed: NSLocalizedString("Failed", comment: "")
        case .canceled: NSLocalizedString("Canceled", comment: "")
        case .blocked: NSLocalizedString("Blocked", comment: "")
        case .outcomeUnknown: NSLocalizedString("Not confirmed", comment: "")
        }
    }
}

private struct ReceiptsView: View {
    let receipts: [ConnectedAppReceipt]

    var body: some View {
        List(receipts) { receipt in
            VStack(alignment: .leading, spacing: 6) {
                ReceiptRow(receipt: receipt)
                Group {
                    Text("Operation: \(receipt.operation.rawValue) · \(receipt.capability)")
                    Text("Account: \(receipt.accountLabel ?? "not shown")")
                    if let code = receipt.errorCode { Text("Code: \(code)") }
                    Text("Provider reference: \(receipt.providerReference ?? "none returned")")
                    Text("Receipt ID: \(receipt.operationId.uuidString)")
                }
                .font(.caption.monospaced())
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Receipts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
