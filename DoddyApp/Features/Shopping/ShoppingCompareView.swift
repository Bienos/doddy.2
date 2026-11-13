import DoddyCore
import SwiftUI

// "Compare" on a shopping task's result (owner, 13 Nov 2026: "zawsze wyskakuje kilka opcji, porównywanie dogłębsze,
// ustawienia cen"). The picks side by side: the price, how far above the lowest pick it is, the shop, where the price
// came from and when, the delivery the source gave, Doddy's notes, the reason for the pick and its trade-off. Which
// price is the lowest is worked out by the code from the registered prices (`ShoppingComparison`, DoddyCore), never by
// a model, and only when the prices are in one currency. A delivery the result doesn't carry says so; returns are not
// in the result, so nothing is said about them. "Watch the price" is the existing watch, one tap away on each pick
// whose price was read on the shop's page. "Buy at" opens the shop's own page in Safari, as on the result card.

struct ShoppingCompareView: View {
    /// The task's title (the person's words), shown under the heading.
    let title: String
    let shopping: ShoppingResult
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize

    private var comparison: ShoppingComparison { ShoppingComparison(shopping) }

    var body: some View {
        NavigationStack {
            DoddyPage {
                DoddyPageHeader(eyebrow: "Shopping", title: "Compare the picks",
                                subtitle: "Side by side, as Doddy's server registered them. The lowest price is marked only when the prices can be compared.")
                Text(verbatim: String(format: NSLocalizedString("“%@”", comment: ""), title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !comparison.pricesComparable && comparison.columns.count > 1 {
                    DoddyNotice(text: Text("These prices are in different currencies, so Doddy doesn't mark the lowest."))
                }
                columns
                DoddyFinePrint(text: Text("Prices can change after the time they were checked. A price from the Google Shopping list wasn't checked on the shop's page, so it can't be watched. Doddy never buys: “Buy at” opens the shop's page in Safari."))
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    /// Next to each other, scrolling sideways; one under another at the largest text sizes.
    @ViewBuilder
    private var columns: some View {
        let list = comparison.columns
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, column in
                    CompareColumn(column: column)
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(list.enumerated()), id: \.offset) { _, column in
                        CompareColumn(column: column)
                            .frame(width: 252)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }
}

/// One pick in "Compare".
private struct CompareColumn: View {
    let column: ShoppingComparison.Column
    @Environment(\.openURL) private var openURL
    private let language = NotificationLanguage.current

    private var offer: ShoppingOffer { column.offer }
    private var pick: ShoppingPick { column.pick }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            top
            facts
            reasons
            actions
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .doddyCard(padding: 16, accent: pick.role == .best)
    }

    // MARK: The price

    private var top: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: pick.role.label(language).uppercased())
                .font(.caption.weight(.bold)).tracking(0.8)
                .foregroundStyle(Theme.accentText)
            if column.isLowestPrice {
                Label("Lowest price of these picks", systemImage: "arrow.down.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.inkOnOrange)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.orangeCue, in: Capsule())
                    .accessibilityIdentifier("shopping.compare.lowest")
            }
            Text(verbatim: offer.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: offer.price.text(language))
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .foregroundStyle(Theme.ink)
            if let above = column.aboveLowest {
                Text(verbatim: String(format: NSLocalizedString("%@ more than the lowest", comment: "a pick's price against the cheapest pick"), above.text(language)))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            if let over = pick.overBudget {
                Text(verbatim: String(format: NSLocalizedString("%@ over your budget", comment: ""), over.text(language)))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.error)
            }
        }
    }

    // MARK: Shop, source, delivery

    private var facts: some View {
        VStack(alignment: .leading, spacing: 8) {
            FactRow(label: Text("Shop"), value: offer.shop)
            FactRow(label: Text("Price from"),
                    value: "\(offer.evidence.label(language)) \(offer.seenAt.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: column.priceCheckedOnPage ? "checkmark.seal.fill" : "list.bullet",
                    tint: column.priceCheckedOnPage ? Theme.confirmed : Theme.secondaryText)
            FactRow(label: Text("Delivery"),
                    value: offer.delivery ?? NSLocalizedString("Not in the result", comment: "a pick with no delivery text"))
            if let notes = offer.notes {
                FactRow(label: Text("In short"), value: notes)
            }
        }
    }

    // MARK: Why

    private var reasons: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Why this one").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            Text(verbatim: pick.why).font(.subheadline).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let tradeoff = pick.tradeoff {
                Text(verbatim: tradeoff).font(.footnote).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Buy, watch

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if offer.canWatchPrice {
                WatchPriceButton(offer: offer, prominent: true)
            } else {
                Text("This price came from a list, not the shop's page, so Doddy can't watch it.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = ShopPage.url(offer.buyUrl ?? offer.url) {
                Button {
                    let page = ShopPage(url: url, offer: offer)
                    openURL(url) { opened in if opened { ShopPage.record(page) } }
                } label: {
                    Label(String(format: NSLocalizedString("Buy at %@", comment: "opens the shop's page"), offer.shop), systemImage: "bag")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1) }
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shopping.compare.buy")
                if offer.isAffiliate {
                    Text("Partner link: the page goes through an affiliate network on its way to the shop, and Doddy may earn a commission if you buy. Prices and the order of the picks don't change.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A label over a value (data) in a compare column.
private struct FactRow: View {
    let label: Text
    let value: String
    var systemImage: String?
    var tint: Color = Theme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            label.font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption).foregroundStyle(tint).accessibilityHidden(true)
                }
                Text(verbatim: value).font(.footnote).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
