import DoddyCore
import SwiftUI

/// Home's reminder that a payment was sent and never confirmed (ADR-452). Doddy can't tell whether it went through:
/// only the person's wallet history can, so this stays until they say they checked. Shown only after payments were
/// switched on once; otherwise Home never contacts the server about payments.
struct UnconfirmedPaymentsBanner: View {
    @State private var model = PaymentsBannerModel(client: PaymentsClientFactory.make(), storage: UserDefaultsPaymentsBannerStorage())

    var body: some View {
        Group {
            if model.isVisible {
                VStack(alignment: .leading, spacing: 10) {
                    Label("A payment wasn't confirmed", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.error)
                    Text("Doddy can't tell whether it went through. Check your wallet's history before paying that page again.")
                        .font(.subheadline)
                    HStack(spacing: 16) {
                        NavigationLink {
                            PaymentsScreen()
                        } label: {
                            Text("Open Payments")
                        }
                        .accessibilityIdentifier("home.payments.open")
                        Button("I've checked") { model.acknowledge() }
                            .accessibilityIdentifier("home.payments.checked")
                    }
                    .font(.subheadline.weight(.medium))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.payments.banner")
            }
        }
        .task { await model.refresh() }
    }
}
