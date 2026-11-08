import DoddyCore
import SwiftUI

/// Builds the model for Doddy's server: the address `DeviceSession.serverURL()` gives (the one built in; a
/// Debug build may use the development address, ADR-720). The phone signs itself in first (ADR-563).
/// Without a server or a session the screen says online accounts aren't ready; it never shows invented connections.
struct OnlineAccountsScreen: View {
    @State private var signedIn = false

    var body: some View {
        let server = DeviceSession.serverURL()
        OnlineAccountsView(
            model: OnlineAccountsModel(client: OnlineAccountsClientFactory.make(), authenticator: SystemWebAuthenticator()))
            .id("\(server?.absoluteString ?? "")|\(signedIn)")
            .task(id: server) {
                if let server { signedIn = await DeviceSession.ensure(server: server) }
            }
    }
}

/// Settings → Online accounts. One section per account, one switch per tool. Web search starts on and
/// an account's tools start off after connecting until the user chooses (ADR-816, which replaces ADR-563 for accounts); a switch moves only after Doddy's server accepts it.
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
                    notConfiguredText
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
                    Text("Web search is on. When you connect an account its tools start off, and you choose what Doddy may do with it. Doddy still asks before every look, and anything that sends, adds or changes something shows you a card first and waits for your tap. You can switch any tool off here.")
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
        .sheet(item: Binding<ToolkitView?>(
            get: { model.choosingAccess.flatMap { model.toolkit($0) } },
            set: { if $0 == nil { model.dismissAccessChoice() } })
        ) { toolkit in
            AccessChoiceSheet(toolkit: toolkit, model: model)
        }
        .foregroundStyle(Theme.ink)
    }

    /// Why there is nothing to show yet. A shipped build has no server field in Settings (ADR-720), so it never
    /// tells the person to type an address; the Debug build keeps the sentence that names the field.
    @ViewBuilder
    private var notConfiguredText: some View {
        #if DEBUG
        Text("Online accounts need a Doddy server. Set its address and a session token in Settings › Connected Apps server.")
        #else
        Text("Signing in to Doddy's server isn't ready yet. Try again in a moment.")
        #endif
    }

    private func connectExplanation(_ toolkit: ToolkitView) -> String {
        model.isDemo
            ? "This server is in demo mode. No \(toolkit.title) account is used; you'll see made-up data."
            : "You'll sign in to \(toolkit.title) on its own secure page, not inside Doddy. \(toolkit.access) Afterwards you choose what Doddy may do with it."
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

            if toolkit.status == .connected, toolkit.hasAccount {
                Picker("What Doddy may do", selection: Binding(
                    get: { model.accessMode(toolkit.id) },
                    set: { mode in Task { await model.setAccess(toolkit.id, mode: mode) } })
                ) {
                    ForEach(AppAccess.allCases, id: \.self) { mode in
                        Text(Self.accessTitle(mode)).tag(mode)
                    }
                }
                .disabled(model.settingAccess.contains(toolkit.id) || model.busyToolkit != nil)
                .accessibilityIdentifier("onlineAccounts.access.\(toolkit.id)")
            }

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

    static func accessTitle(_ mode: AppAccess) -> String {
        switch mode {
        case .off: NSLocalizedString("Off", comment: "")
        case .read: NSLocalizedString("Look only", comment: "")
        case .act: NSLocalizedString("Look and act", comment: "")
        }
    }

    static func accessDetail(_ mode: AppAccess) -> String {
        switch mode {
        case .off: NSLocalizedString("Doddy won't use this account.", comment: "")
        case .read: NSLocalizedString("Doddy can look things up in this account when you ask. He asks first every time.", comment: "")
        case .act: NSLocalizedString("Doddy can also send, add or change things, but only after you tap a card that shows exactly what will happen.", comment: "")
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

/// Shown right after an account is connected (ADR-816): its tools are all off until the person says what
/// Doddy may do. Three plain options, none pre-selected. "Not now" leaves the account connected and off.
private struct AccessChoiceSheet: View {
    let toolkit: ToolkitView
    let model: OnlineAccountsModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(toolkit.title).font(.headline)
                    Text("Choose what Doddy may do with this account. You can change it any time in Settings.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }

                if let message = model.message {
                    Section {
                        Label(message, systemImage: "info.circle")
                            .font(.footnote)
                            .accessibilityIdentifier("onlineAccounts.access.message")
                    }
                }

                Section {
                    ForEach([AppAccess.read, .act, .off], id: \.self) { mode in
                        Button {
                            Task { await model.setAccess(toolkit.id, mode: mode) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(OnlineAccountsView.accessTitle(mode)).font(.headline)
                                Text(OnlineAccountsView.accessDetail(mode))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(model.settingAccess.contains(toolkit.id))
                        .accessibilityIdentifier("onlineAccounts.access.choose.\(mode.rawValue)")
                    }
                }

                Section {
                    Button("Not now") { model.dismissAccessChoice() }
                        .accessibilityIdentifier("onlineAccounts.access.notNow")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("What may Doddy do?")
            .navigationBarTitleDisplayMode(.inline)
        }
        .foregroundStyle(Theme.ink)
        .presentationDetents([.medium, .large])
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
