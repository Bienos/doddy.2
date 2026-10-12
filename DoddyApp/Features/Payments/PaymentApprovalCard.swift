import DoddyCore
import SwiftUI

/// The card that asks "pay this?" (ADR-451). It shows exactly what Doddy's server returned for the
/// page (never an amount or a recipient the app made up), asks Face ID right before paying, and says
/// plainly what happened. Never compiled with Xcode when written: see docs/implementation/PAYMENTS_STATUS.md.
///
/// What it will not do, by the shape of `PaymentApprovalModel`: pay without a fresh Face ID, pay twice,
/// be cancelled or swiped away while the payment is being sent, or offer "pay again" when it isn't sure.
struct PaymentApprovalCard: View {
    var model: PaymentApprovalModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.canvas)
            .navigationTitle("Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { model.dismiss() }
                        .disabled(!model.canDismiss)
                        .accessibilityIdentifier("payment.close")
                }
            }
        }
        // Swiping the sheet away while the payment is in flight would hide the answer, not stop the payment.
        .interactiveDismissDisabled(!model.canDismiss)
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .preparing:
            HStack(spacing: 12) {
                ProgressView()
                Text("Checking the price…")
            }
            .accessibilityElement(children: .combine)
        case .awaitingApproval(let prepared):
            terms(prepared, working: false)
        case .authenticating(let prepared):
            terms(prepared, working: true)
        case .paying(let prepared):
            terms(prepared, working: true)
        case .paid(let result):
            paid(result)
        case .failed(let message, _):
            outcome(symbol: "xmark.octagon", tint: Theme.error, title: "Nothing was paid", message: message) {
                Button("Done") { model.finish() }
                    .buttonStyle(.borderedProminent).tint(Theme.ink)
                    .accessibilityIdentifier("payment.done")
            }
        case .unconfirmed(let message, _):
            outcome(symbol: "questionmark.circle", tint: Theme.error, title: "Not confirmed", message: message) {
                Button("Check again") { Task { await model.checkAgain() } }
                    .buttonStyle(.borderedProminent).tint(Theme.ink)
                    .accessibilityIdentifier("payment.checkAgain")
                Button("Done") { model.finish() }
                    .accessibilityIdentifier("payment.done")
            }
        }
    }

    // MARK: Terms (before and during the payment)

    @ViewBuilder
    private func terms(_ prepared: PaymentPrepared, working: Bool) -> some View {
        if prepared.mode == .mock {
            Label("Demo: no real money moves", systemImage: "theatermasks")
                .font(.headline)
                .accessibilityIdentifier("payment.demoBanner")
        }
        Text(prepared.preview.title)
            .font(.title2.weight(.semibold))
            .accessibilityIdentifier("payment.title")

        // The server's own lines, in its order: amount first, then who, from where, which network, today's total.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(prepared.preview.lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(index == 0 ? .title3.weight(.medium) : .body)
                    .foregroundStyle(index == 0 ? Theme.ink : Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("payment.terms")

        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let seconds = model.secondsLeft() {
                if seconds > 0 {
                    Text(String(format: NSLocalizedString("This confirmation runs out in %lld s.", comment: ""), seconds))
                } else {
                    Text("This confirmation has run out.")
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondaryText)

        if let notice = model.notice {
            Label(notice, systemImage: "info.circle")
                .font(.footnote)
                .accessibilityIdentifier("payment.notice")
        }

        if working {
            HStack(spacing: 12) {
                ProgressView()
                if case .paying = model.phase {
                    Text("Paying… keep Doddy open.")
                } else {
                    Text("Confirm with Face ID…")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("payment.working")
        } else {
            Button {
                Task { await model.approve() }
            } label: {
                // The server's own words ("Pay 0.05 USDC"), so the button says what the card says.
                Label(prepared.preview.confirmLabel, systemImage: "faceid")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
            .accessibilityIdentifier("payment.approve")

            Button("Cancel", role: .cancel) { model.cancel() }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("payment.cancel")

            Text("Doddy asks for Face ID or your passcode every time before paying.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: Outcomes

    private func paid(_ result: PaymentResult) -> some View {
        outcome(symbol: "checkmark.circle.fill", tint: Theme.confirmed, title: "Paid", message: result.receipt.summary) {
            if let transaction = result.receipt.transaction {
                Text(shortened(transaction))
                    .font(.footnote.monospaced())
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityLabel(String(format: NSLocalizedString("Transaction %@", comment: ""), shortened(transaction)))
            }
            if result.mode == .mock {
                Text("Demo: no real money moved.").font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Button("Done") { model.finish() }
                .buttonStyle(.borderedProminent).tint(Theme.ink)
                .accessibilityIdentifier("payment.done")
        }
    }

    private func outcome<Actions: View>(
        symbol: String, tint: Color, title: LocalizedStringKey, message: String, @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text(title).font(.title2.weight(.semibold))
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            // The server's words, as written: what happened and what is safe to do next.
            Text(message)
                .accessibilityIdentifier("payment.outcome")
            if let notice = model.notice {
                Label(notice, systemImage: "info.circle")
                    .font(.footnote)
                    .accessibilityIdentifier("payment.notice")
            }
            actions()
        }
    }

    /// "0xabab…abab": enough to find it on a block explorer, short enough to read.
    private func shortened(_ hash: String) -> String {
        hash.count > 14 ? "\(hash.prefix(8))…\(hash.suffix(6))" : hash
    }
}
