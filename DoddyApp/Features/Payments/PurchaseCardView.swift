import DoddyCore
import SwiftUI

/// The Buy card (ADR-490): what the agent prepared, exactly as Doddy's server will charge it, and
/// the only buttons that pay. After the agent has its answer the same card is the receipt.
struct PurchaseCardView: View {
    @Bindable var flow: PurchaseFlow
    let onClose: () -> Void
    @FocusState private var blikFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            details
            actions
            if let problem = flow.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(Theme.error)
                    .accessibilityIdentifier("purchase.problem")
            }
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .fullScreenCover(isPresented: Binding(get: { flow.checkoutURL != nil }, set: { if !$0 { flow.checkoutClosed() } })) {
            if let url = flow.checkoutURL {
                CheckoutBrowser(url: url) { flow.checkoutClosed() }
                    .ignoresSafeArea()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("purchase.card")
    }

    // MARK: Parts

    @ViewBuilder private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            title
                .font(.headline)
            Spacer()
            if flow.purchase.testMode {
                Text("Test · no real money")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.orangeCue.opacity(0.18), in: Capsule())
                    .accessibilityIdentifier("purchase.testBadge")
            }
        }
    }

    @ViewBuilder private var details: some View {
        let purchase = flow.purchase
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: purchase.merchantName)
                .font(.title3.weight(.semibold))
            Text(verbatim: purchase.description)
                .foregroundStyle(Theme.secondaryText)
            Text(verbatim: PurchaseMoney.format(minor: purchase.amountMinor, currency: purchase.currency))
                .font(.title2.weight(.bold))
                .padding(.top, 2)
                .accessibilityLabel(flow.isCheckout
                    ? Text("Expected price \(PurchaseMoney.format(minor: purchase.amountMinor, currency: purchase.currency))")
                    : Text("Price \(PurchaseMoney.format(minor: purchase.amountMinor, currency: purchase.currency))"))
            if flow.isCheckout {
                Text("Expected price. The shop's page shows the real one, and you pay the shop there.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                if let host = purchase.checkoutHost {
                    Label { Text(verbatim: host) } icon: { Image(systemName: "lock") }
                        .font(.footnote.weight(.semibold))
                }
            } else {
                Text("Paid to \(flow.prepared.payee). Nothing is paid until you confirm with Face ID or a BLIK code.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        switch flow.phase {
        case .ready:
            if flow.isCheckout {
                checkoutButtons
            } else {
                paymentButtons
            }
        case .paying(let method):
            progress(method == .blik ? Text("Sending the BLIK code…") : Text("Paying…"))
        case .waitingForBank(let purchase):
            if purchase.method == .blik {
                progress(Text("Approve \(PurchaseMoney.format(minor: purchase.amountMinor, currency: purchase.currency)) in your bank app"))
                Button("Cancel") { Task { await flow.cancel() } }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(flow.isChecking)
            } else {
                progress(Text("Checking with the bank…"))
            }
        case .openingCheckout:
            progress(Text("Opening the shop's page…"))
        case .settled(let purchase):
            receipt(purchase)
        case .lost:
            Text("Doddy lost the answer while paying. It may have gone through: check your bank app before trying again.")
                .font(.body)
            receiptButtons(canCheck: true, isHandoff: false)
        }
    }

    @ViewBuilder private var paymentButtons: some View {
        if flow.applePayAvailable {
            ApplePayButton { Task { await flow.payWithApplePay() } }
        }
        if flow.blikAvailable {
            if flow.isEnteringBlik {
                VStack(alignment: .leading, spacing: 8) {
                    Text("BLIK code from your bank app")
                        .font(.footnote.weight(.semibold))
                    TextField("6 digits", text: $flow.blikCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.title3.monospacedDigit())
                        .padding(10)
                        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
                        .focused($blikFocused)
                        .accessibilityIdentifier("purchase.blikCode")
                    Button {
                        Task { await flow.payWithBlik() }
                    } label: {
                        HStack { Text("Pay with BLIK"); Spacer(); Image(systemName: "checkmark") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(BlikCode.normalize(flow.blikCode) == nil)
                    .accessibilityIdentifier("purchase.payBlik")
                }
            } else if flow.applePayAvailable {
                Button {
                    flow.isEnteringBlik = true
                    blikFocused = true
                } label: {
                    HStack { Text("Use BLIK instead"); Spacer(); Image(systemName: "number") }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("purchase.blik")
            } else {
                Button {
                    flow.isEnteringBlik = true
                    blikFocused = true
                } label: {
                    HStack { Text("Pay with BLIK"); Spacer(); Image(systemName: "number") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("purchase.blik")
            }
        }
        if !flow.applePayAvailable && !flow.blikAvailable {
            Text("No payment method is set up in this build.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        Button("Don't pay") { Task { await flow.cancel() } }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("purchase.decline")
    }

    @ViewBuilder private var checkoutButtons: some View {
        Button {
            Task { await flow.openCheckout() }
        } label: {
            HStack { Text("Open the shop's checkout"); Spacer(); Image(systemName: "safari") }
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityIdentifier("purchase.openCheckout")
        Button("Not now") { Task { await flow.cancel() } }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("purchase.decline")
    }

    @ViewBuilder private func receipt(_ purchase: PurchaseView) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(for: purchase.status))
                .foregroundStyle(purchase.status == .paid ? Theme.confirmed : (purchase.status == .failed ? Theme.error : Theme.secondaryText))
                .accessibilityHidden(true)
            Text(verbatim: purchase.summary)
                .font(.body)
                .accessibilityIdentifier("purchase.summary")
        }
        if purchase.status == .handedOff {
            Text("Did you pay at \(purchase.checkoutHost ?? purchase.merchantName)?")
                .font(.footnote.weight(.semibold))
            HStack {
                Button("I paid") { Task { await flow.reportCheckout(paid: true) } }
                    .buttonStyle(SecondaryButtonStyle())
                Button("I didn't") { Task { await flow.reportCheckout(paid: false) } }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .disabled(flow.isChecking)
        }
        receiptButtons(canCheck: purchase.status.needsStatusCheck, isHandoff: purchase.status == .handedOff)
    }

    @ViewBuilder private func receiptButtons(canCheck: Bool, isHandoff: Bool) -> some View {
        if canCheck {
            Button {
                Task { await flow.checkAgain() }
            } label: {
                HStack { Text("Check again"); Spacer(); if flow.isChecking { ProgressView() } }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(flow.isChecking)
        }
        if isHandoff, flow.handoffURL != nil {
            Button("Open the shop's page again") { flow.reopenCheckout() }
                .buttonStyle(SecondaryButtonStyle())
        }
        Button("Close", action: onClose)
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("purchase.close")
    }

    private func progress(_ label: Text) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            label
        }
        .padding(.vertical, 6)
    }

    private var title: Text {
        switch flow.phase {
        case .settled, .lost: Text("Payment")
        default: flow.isCheckout ? Text("Open this checkout?") : Text("Pay for this?")
        }
    }

    private func symbol(for status: PurchaseStatus) -> String {
        switch status {
        case .paid: "checkmark.circle.fill"
        case .failed, .expired: "xmark.circle"
        case .cancelled: "hand.raised"
        case .handedOff, .userReportedPaid: "safari"
        case .awaitingTap, .paying, .waitingForBank, .outcomeUnknown: "questionmark.circle"
        }
    }
}
