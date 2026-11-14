import DoddyCore
import SwiftUI

// What one price alert matches in the leaflets now (decision 2026-11-14-price-alerts-screen): read from the server's
// catalog each time this screen opens (`GET /v1/deal-watches/{id}/offers`), cheapest first, only the item itself and never
// a similar product (DoddyCore drops any the server marks `similar`). A chain whose leaflets were read only in part is
// said, because a cheaper offer may be on a page nobody has read. The prices are the leaflets' as the server parsed them.

struct PriceAlertMatchesView: View {
    let watch: DealWatch
    private let model = PriceAlertsModel.shared
    private let language = NotificationLanguage.current
    @State private var outcome: PriceAlertsModel.MatchesOutcome?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: watch.item)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "\(DealWatchWords.priceLine(watch, language)) · \(DealWatchWords.shopsLine(watch, language))")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .readableColumn()
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .navigationTitle(DealWatchWords.matchesTitle(language))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .accessibilityIdentifier("priceAlerts.matches")
    }

    @ViewBuilder private var content: some View {
        switch outcome {
        case .none:
            HStack(spacing: 10) {
                ProgressView()
                Text(verbatim: DealWatchWords.loading(language)).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
        case .some(.problem(let text)):
            VStack(alignment: .leading, spacing: 10) {
                Label { Text(verbatim: text) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .foregroundStyle(Theme.error)
                Button { Task { await load() } } label: { Text(verbatim: DealWatchWords.tryAgain(language)) }
                    .buttonStyle(DoddyOutlineButtonStyle())
            }
            .doddyCard(padding: 14)
            .accessibilityIdentifier("priceAlerts.matches.problem")
        case .some(.loaded(let matches)):
            if matches.offers.isEmpty {
                Text(verbatim: DealWatchWords.noMatchesNow(language)).font(.subheadline).foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(Array(matches.offers.enumerated()), id: \.offset) { index, offer in
                    PriceAlertOfferRow(offer: offer, language: language, cheapest: index == 0)
                        .arrivesInOrder(index)
                }
            }
            if matches.readInPart {
                DoddyFootnote(text: DealWatchWords.readInPart(language), systemImage: "exclamationmark.circle")
            }
        }
    }

    private func load() async {
        outcome = nil
        outcome = await model.matches(for: watch)
    }
}

/// One offer the catalog holds for an alert: the leaflet's own product name, the price (marked when it is the cheapest),
/// the shop and the conditions the leaflet states. Nothing here prices anything.
struct PriceAlertOfferRow: View {
    let offer: DealOffer
    let language: NotificationLanguage
    let cheapest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: offer.product)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                PriceMark(text: offer.price.text(language), marked: cheapest)
            }
            HStack(spacing: 8) {
                ShopBadge(name: offer.chain.name)
                if !offer.conditions.isEmpty {
                    Text(verbatim: offer.conditions.joined(separator: " · "))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .doddyCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}
