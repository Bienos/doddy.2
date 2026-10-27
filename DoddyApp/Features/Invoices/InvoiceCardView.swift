import DoddyCore
import SwiftUI

/// The invoice card (ADR-640): the exact invoice laid out for the person's yes. Every word and sum
/// comes from `InvoiceCard` (DoddyCore, tested); this view only lays it out. It offers no Confirm
/// button while `InvoiceCard.canConfirm` is false, which is always the case until a sandbox call has
/// settled how inFakt takes an invoice (`InFaktAPI.createVerified`). Not seen on a device in this build.
struct InvoiceCardView: View {
    let card: InvoiceCard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: card.stateLine).font(.headline)

            if !card.problems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(card.problems, id: \.self) { problem in
                        Label { Text(verbatim: problem) } icon: { Image(systemName: "exclamationmark.triangle") }
                            .foregroundStyle(Theme.error)
                            .font(.subheadline)
                    }
                }
            }

            block(NSLocalizedString("Buyer", comment: ""), rows: card.buyer)

            VStack(alignment: .leading, spacing: 8) {
                Text("Lines").font(.subheadline.weight(.semibold))
                ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: line.name).font(.body)
                            if line.proposed { suggestedMark }
                            Spacer(minLength: 8)
                            Text(verbatim: line.net).font(.body.monospacedDigit())
                        }
                        Text(verbatim: line.detail).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
            }

            block(NSLocalizedString("Details", comment: ""), rows: card.facts)
            block(NSLocalizedString("Totals", comment: ""), rows: card.totals)

            if let note = card.sendingNote {
                Label { Text(verbatim: note) } icon: { Image(systemName: "info.circle") }
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("invoice.card")
    }

    @ViewBuilder
    private func block(_ title: String, rows: [InvoiceCard.Row]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title).font(.subheadline.weight(.semibold))
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: row.label).foregroundStyle(Theme.secondaryText)
                        Spacer(minLength: 12)
                        Text(verbatim: row.value).multilineTextAlignment(.trailing)
                        if row.proposed { suggestedMark }
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// A value only the model suggested: shown so it can be confirmed, never taken for something said.
    private var suggestedMark: some View {
        Image(systemName: "questionmark.circle")
            .foregroundStyle(Theme.error)
            .accessibilityLabel("Suggested by the model, not confirmed")
    }
}

/// An example with gaps on purpose, so the card can be seen before any invoice exists. The VAT rate is
/// shown as the model's suggestion and the due date is missing; nothing here is anyone's invoice.
enum InvoiceCardExample {
    static var operation: InvoiceOperation {
        func said<T: Equatable & Sendable & Codable>(_ value: T) -> Sourced<T> { Sourced(value, source: .saidByUser) }
        let draft = InvoiceDraft(
            contractor: InvoiceContractor(
                kind: said(.company), name: said("Przykładowa Firma Sp. z o.o."), nip: said("1234563218"),
                address: said(InvoiceAddress(street: "Lipowa", buildingNumber: "3", flatNumber: "4", city: "Kraków", postCode: "31-004"))),
            lines: [InvoiceLine(
                name: said("Konsultacje"), quantityMilli: 2_000, unit: "godz.", netUnitPriceMinor: 50_000,
                vat: Sourced(.percent(23), source: .proposedByModel))],
            currency: said(.pln), issueDate: CalendarDate(iso: "2026-10-24"), saleDate: CalendarDate(iso: "2026-10-24"),
            paymentMethod: said(.transfer))
        return InvoiceOperation(draft: draft)
    }
}

struct InvoiceExampleView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("An example, not your invoice. The VAT rate is marked as the model's suggestion, so you would have to confirm it, and the payment due date is missing, so the card could not be confirmed yet.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                InvoiceCardView(card: InvoiceCard(
                    InvoiceCardExample.operation,
                    polish: NotificationLanguage.preferred(Bundle.main.preferredLocalizations) == .polish))
            }
            .padding(16)
        }
        .background(Theme.canvas)
        .navigationTitle("Invoice card example")
        .navigationBarTitleDisplayMode(.inline)
    }
}
