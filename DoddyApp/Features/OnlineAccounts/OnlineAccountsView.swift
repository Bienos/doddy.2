import DoddyCore
import SwiftUI

/// Builds the model for Doddy's server (built in, or Settings' development address). The phone signs
/// itself in first (ADR-563). Without a server or a session the screen says online accounts aren't
/// set up; it never shows invented connections.
struct OnlineAccountsScreen: View {
    @AppStorage(PreferenceKey.connectedAppsServerURL) private var serverURL = ""
    @State private var signedIn = false

    var body: some View {
        OnlineAccountsView(
            model: OnlineAccountsModel(client: OnlineAccountsClientFactory.make(), authenticator: SystemWebAuthenticator()))
            .id("\(serverURL)|\(signedIn)")
            .task(id: serverURL) {
                if let url = DeviceSession.serverURL() { signedIn = await DeviceSession.ensure(server: url) }
            }
    }
}

/// Settings → Online accounts. One section per account, one switch per tool. Web search starts on and
/// an account's tools come on with it (ADR-563); a switch moves only after Doddy's server accepts it.
struct OnlineAccountsView: View {
    @State private var model: OnlineAccountsModel
    @State private var confirmConnect: ToolkitView?
    @State private var confirmDisconnect: ToolkitView?

    init(model: OnlineAccountsModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            if model.isDemo {
                Section {
                    Label("Demo data — no real account is connected", systemImage: "theatermasks")
                        .font(.headline)
                        .accessibilityIdentifier("onlineAccounts.demoBanner")
                }
            }

            switch model.load {
            case .notConfigured:
                Section {
                    Text("Online accounts need a Doddy server. Set its address and a session token in Settings › Connected Apps server.")
                        .accessibilityIdentifier("onlineAccounts.notConfigured")
                }
            case .loading:
                Section { ProgressView("Checking…") }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                    Button("Try again") { Task { await model.refresh() } }
                }
            case .ready:
                EmptyView()
            }

            if let message = model.message {
                Section {
                    Label(message, systemImage: "info.circle")
                        .font(.footnote)
                        .accessibilityIdentifier("onlineAccounts.message")
                }
            }

            if let catalog = model.catalog {
                Section {
                    Text("Web search is on, and an account's tools come on when you connect it. Doddy still asks before every look, and anything that sends, adds or changes something shows you a card first and waits for your tap. Switch any tool off here.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(catalog.toolkits) { toolkit in
                    toolkitSection(toolkit)
                }
            }

            if let receipt = model.lastReceipt {
                Section("Last action") {
                    NavigationLink {
                        OnlineReceiptsView(receipts: model.receipts)
                    } label: {
                        OnlineReceiptRow(receipt: receipt)
                    }
                    .accessibilityIdentifier("onlineAccounts.receipt")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Online accounts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refresh() }
        .confirmationDialog(
            "Connect \(confirmConnect?.title ?? "")?",
            isPresented: Binding(get: { confirmConnect != nil }, set: { if !$0 { confirmConnect = nil } }),
            titleVisibility: .visible,
            presenting: confirmConnect
        ) { toolkit in
            Button("Continue") { Task { await model.connect(toolkit.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { toolkit in
            Text(connectExplanation(toolkit))
        }
        .confirmationDialog(
            "Disconnect \(confirmDisconnect?.title ?? "")?",
            isPresented: Binding(get: { confirmDisconnect != nil }, set: { if !$0 { confirmDisconnect = nil } }),
            titleVisibility: .visible,
            presenting: confirmDisconnect
        ) { toolkit in
            Button("Disconnect", role: .destructive) { Task { await model.disconnect(toolkit.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { toolkit in
            Text("Doddy switches off every \(toolkit.title) tool right away and asks \(toolkit.title) to remove its access. Nothing you saved in Doddy is deleted.")
        }
        .foregroundStyle(Theme.ink)
    }

    private func connectExplanation(_ toolkit: ToolkitView) -> String {
        model.isDemo
            ? "This server is in demo mode. No \(toolkit.title) account is used; you'll see made-up data."
            : "You'll sign in to \(toolkit.title) on its own secure page, not inside Doddy. \(toolkit.access) The tools stay off until you switch them on."
    }

    // MARK: Account section

    @ViewBuilder
    private func toolkitSection(_ toolkit: ToolkitView) -> some View {
        Section {
            HStack {
                Text(toolkit.title).font(.headline)
                Spacer()
                Text(statusText(toolkit))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("onlineAccounts.status.\(toolkit.id)")
            }
            .accessibilityElement(children: .combine)

            controls(toolkit)

            if toolkit.status == .connected {
                ForEach(toolkit.tools) { tool in
                    Toggle(isOn: Binding(
                        get: { model.isEnabled(tool.name) },
                        set: { on in Task { await model.setSwitch(tool.name, enabled: on) } })
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.title)
                            Text(tool.blurb)
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                            if tool.risk == .write {
                                Text("Shows a card and waits for your tap every time")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                    .disabled(model.switching.contains(tool.name))
                    .accessibilityIdentifier("onlineAccounts.switch.\(tool.name)")
                }
            }
        } footer: {
            Text(toolkit.access)
        }
    }

    @ViewBuilder
    private func controls(_ toolkit: ToolkitView) -> some View {
        if model.busyToolkit == toolkit.id {
            ProgressView("Working…")
        } else if let demo = model.demoAttempt, demo.toolkit == toolkit.id {
            Text("Demo connection: no \(toolkit.title) account is involved and the data is made up.")
                .font(.footnote)
            Button("Connect demo \(toolkit.title)") { Task { await model.completeDemo(approve: true) } }
                .accessibilityIdentifier("onlineAccounts.demoApprove")
            Button("Cancel", role: .cancel) { Task { await model.cancelDemo() } }
        } else if !toolkit.hasAccount {
            // Web search: nothing to sign in to, only the switch below.
            if toolkit.status == .unavailable {
                Text("\(toolkit.title) isn't set up on this server.")
                    .font(.footnote)
            }
        } else {
            switch toolkit.status {
            case .unavailable:
                Text("\(toolkit.title) isn't set up on this server.")
                    .font(.footnote)
            case .disconnected, .connecting, .error:
                Button("Connect \(toolkit.title)") { confirmConnect = toolkit }
                    .disabled(model.busyToolkit != nil)
                    .accessibilityIdentifier("onlineAccounts.connect.\(toolkit.id)")
            case .connected:
                Button("Disconnect", role: .destructive) { confirmDisconnect = toolkit }
                    .disabled(model.busyToolkit != nil)
                    .accessibilityIdentifier("onlineAccounts.disconnect.\(toolkit.id)")
            case .permissionInsufficient:
                Text(Self.permissionText(toolkit))
                    .font(.footnote)
                Button("Reconnect") { confirmConnect = toolkit }
                    .disabled(model.busyToolkit != nil)
                Button("Disconnect", role: .destructive) { confirmDisconnect = toolkit }
                    .disabled(model.busyToolkit != nil)
            case .expired:
                Text("Access expired or was removed at \(toolkit.title). Its tools are off. Reconnect to keep using it.")
                    .font(.footnote)
                Button("Reconnect") { confirmConnect = toolkit }
                    .disabled(model.busyToolkit != nil)
                Button("Disconnect", role: .destructive) { confirmDisconnect = toolkit }
                    .disabled(model.busyToolkit != nil)
            }
            if toolkit.remoteCleanup == .failed {
                Label("Disconnected in Doddy, but removing access at \(toolkit.title) couldn't be confirmed. Remove Doddy in your \(toolkit.title) account settings.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.error)
            }
        }
    }

    private func statusText(_ toolkit: ToolkitView) -> String {
        switch toolkit.status {
        case .unavailable: NSLocalizedString("Not set up", comment: "")
        case .disconnected: NSLocalizedString("Not connected", comment: "")
        case .connecting: NSLocalizedString("Connecting…", comment: "")
        case .connected where !toolkit.hasAccount: model.isDemo ? "Ready (demo)" : "Ready, no sign-in"
        case .connected: model.isDemo ? "Connected (demo)" : "Connected"
        case .permissionInsufficient: NSLocalizedString("Needs attention", comment: "")
        case .expired: NSLocalizedString("Expired", comment: "")
        case .error: NSLocalizedString("Couldn't check", comment: "")
        }
    }

    static func permissionText(_ toolkit: ToolkitView) -> String {
        switch toolkit.reason {
        case .grantTooBroad:
            "The access \(toolkit.title) granted is broader than Doddy needs, so Doddy won't use it. Disconnect, then reconnect."
        case .grantUnverifiable:
            "Doddy couldn't confirm what access \(toolkit.title) granted, so it won't use it."
        default:
            "The access \(toolkit.title) granted isn't what Doddy expects, so it won't use it. Reconnect and allow what's asked."
        }
    }
}

private struct OnlineReceiptRow: View {
    let receipt: OnlineToolReceipt

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

private struct OnlineReceiptsView: View {
    let receipts: [OnlineToolReceipt]

    var body: some View {
        List(receipts) { receipt in
            VStack(alignment: .leading, spacing: 6) {
                OnlineReceiptRow(receipt: receipt)
                Group {
                    Text("Operation: \(receipt.operation.rawValue) · \(receipt.toolkit)\(receipt.tool.map { " · \($0)" } ?? "")")
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
