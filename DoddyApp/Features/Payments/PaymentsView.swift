import DoddyCore
import SwiftUI

/// Builds the models from the development server settings. Without a server address and a session
/// token the screen says payments aren't set up; it never shows an invented wallet or balance.
struct PaymentsScreen: View {
    @AppStorage(PreferenceKey.connectedAppsServerURL) private var serverURL = ""

    var body: some View {
        PaymentsView(
            settings: PaymentsSettingsModel(client: PaymentsClientFactory.make()),
            approval: PaymentApprovalModel(client: PaymentsClientFactory.make(), authenticator: FaceIDPaymentAuthenticator()))
            .id(serverURL)
    }
}

/// Settings → Payments (ADR-451). Everything starts off; the switch moves only after Doddy's server
/// accepts it; every payment goes through the approval card (exact price, then Face ID).
struct PaymentsView: View {
    @State private var settings: PaymentsSettingsModel
    @State private var approval: PaymentApprovalModel
    @State private var address = ""

    init(settings: PaymentsSettingsModel, approval: PaymentApprovalModel) {
        _settings = State(initialValue: settings)
        _approval = State(initialValue: approval)
    }

    var body: some View {
        List {
            if settings.isDemo {
                Section {
                    Label("Demo data: no real money moves", systemImage: "theatermasks")
                        .font(.headline)
                        .accessibilityIdentifier("payments.demoBanner")
                }
            }

            switch settings.load {
            case .notConfigured:
                Section {
                    Text("Payments need a Doddy server. Set its address and a session token in Settings › Connected Apps server.")
                        .accessibilityIdentifier("payments.notConfigured")
                }
            case .loading:
                Section { ProgressView("Checking…") }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                    Button("Try again") { Task { await settings.refresh() } }
                }
            case .ready:
                EmptyView()
            }

            if settings.unresolved > 0 {
                Section {
                    Label("Some payments weren't confirmed. Check your wallet's history before paying that page again.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.error)
                        .accessibilityIdentifier("payments.unresolved")
                }
            }

            if let message = settings.message {
                Section {
                    Label(message, systemImage: "info.circle")
                        .font(.footnote)
                        .accessibilityIdentifier("payments.message")
                }
            }

            if let status = settings.status {
                switchSection(status)
                walletSection(status.wallet)
                limitsSection(status.limits)
                paySection
            }

            if !settings.receipts.isEmpty {
                Section("Recent") {
                    ForEach(settings.receipts.prefix(10)) { receipt in
                        PaymentReceiptRow(receipt: receipt)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Payments")
        .navigationBarTitleDisplayMode(.inline)
        .task { await settings.refresh() }
        .sheet(isPresented: Binding(get: { approval.phase != .idle }, set: { shown in if !shown { approval.dismiss() } })) {
            PaymentApprovalCard(model: approval)
        }
        // After a card closes, today's total and any unconfirmed payment come from the server again.
        .onChange(of: approval.phase == .idle) { _, isIdle in
            if isIdle { Task { await settings.refresh() } }
        }
        .foregroundStyle(Theme.ink)
    }

    // MARK: Sections

    private func switchSection(_ status: PaymentStatus) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.isEnabled },
                set: { on in Task { await settings.setEnabled(on) } })
            ) {
                Text("Let Doddy pay for pages")
            }
            .disabled(!status.wallet.configured || settings.switching)
            .accessibilityIdentifier("payments.switch")
        } footer: {
            if status.wallet.configured {
                Text("Off until you turn it on. Even then, every payment shows you the exact price and asks for Face ID first.")
            } else {
                Text("No payment wallet is set up on your Doddy server, so this can't be turned on.")
            }
        }
    }

    @ViewBuilder
    private func walletSection(_ wallet: PaymentWalletInfo) -> some View {
        Section("Wallet") {
            LabeledContent("Paid from") {
                switch wallet.kind {
                case .none: Text("None set up")
                case .mock: Text("Demo wallet")
                case .coinbaseCdp: Text("Coinbase wallet")
                }
            }
            if let account = wallet.account {
                LabeledContent("Account") { Text(account).font(.body.monospaced()) }
            }
            LabeledContent("Network") {
                if wallet.testNetwork {
                    Text("Test network, no real money")
                } else {
                    Text("Real money")
                }
            }
        }
    }

    private func limitsSection(_ limits: PaymentLimits) -> some View {
        Section {
            LabeledContent("Each payment, at most") { Text(limits.perPayment + " " + limits.asset) }
            LabeledContent("Each day, at most") { Text(limits.perDay + " " + limits.asset) }
            LabeledContent("Paid today") { Text(limits.usedToday + " " + limits.asset) }
        } header: {
            Text("Limits")
        } footer: {
            Text("Set on your Doddy server. A page that asks for more is refused before anything is shown to confirm.")
        }
    }

    private var paySection: some View {
        Section {
            TextField("Web address of the page (https://…)", text: $address)
                .font(.body.monospaced())
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("payments.address")
            Button {
                Task { await approval.start(url: address) }
            } label: {
                Label("See the price", systemImage: "magnifyingglass")
            }
            .disabled(!settings.canPay || approval.isBusy || address.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("payments.start")
        } header: {
            Text("Pay for a page")
        } footer: {
            if settings.canPay {
                Text("Doddy asks the page for its price and shows it to you. Nothing is paid until you confirm with Face ID.")
            } else {
                Text("Turn on “Let Doddy pay for pages” first.")
            }
        }
    }
}

struct PaymentReceiptRow: View {
    let receipt: PaymentReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(receipt.summary, systemImage: symbol)
                .font(.subheadline)
            if let date = PaymentTime.parse(receipt.timestamp) {
                Text(date, style: .relative)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("payments.receipt")
    }

    private var symbol: String {
        switch receipt.status {
        case .succeeded: "checkmark.circle"
        case .outcomeUnknown: "questionmark.circle"
        case .failed, .blocked, .canceled: "xmark.circle"
        }
    }
}
