import DoddyCore
import SwiftUI

// Adding a price alert (decision 2026-11-14-price-alerts-screen): the words, an optional price and the shops (none picked:
// every shop with leaflets). Nothing leaves the iPhone until "Save the alert", and nothing is said to be saved until the
// server answered and the answer was read (`PriceAlertsModel.Phase.saved`); what already matches is shown at once, said to be
// known and never pushed. A try whose answer never came back says it may exist and is not made again by itself. The wording is
// `DealWatchWords`; the limits are `DealWatchRequest`'s (the server checks them again).

struct PriceAlertForm: View {
    @Environment(\.dismiss) private var dismiss
    private let model = PriceAlertsModel.shared
    private let language = NotificationLanguage.current
    @State private var item = ""
    @State private var priceText = ""
    /// The shops the person picked; empty means every shop with leaflets.
    @State private var picked: [DealsChain] = []
    @FocusState private var typing: Field?

    private enum Field { case item, price }

    private var saving: Bool { model.phase == .saving }
    private var canSave: Bool { !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if case .saved(let created) = model.phase {
                        savedCard(created)
                    } else {
                        fields
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .readableColumn()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .foregroundStyle(Theme.ink)
            .navigationTitle(DealWatchWords.add(language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isSaved ? DealWatchWords.done(language) : DealWatchWords.cancel(language)) { dismiss() }
                        .disabled(saving)
                }
            }
            .onAppear { model.beginForm() }
        }
        .interactiveDismissDisabled(saving)
        .accessibilityIdentifier("priceAlerts.form")
    }

    private var isSaved: Bool {
        if case .saved = model.phase { return true }
        return false
    }

    // MARK: Fields

    @ViewBuilder private var fields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: DealWatchWords.itemLabel(language)).font(.subheadline.weight(.semibold))
            TextField(DealWatchWords.itemPlaceholder(language), text: $item)
                .focused($typing, equals: .item)
                .submitLabel(.next)
                .onSubmit { typing = .price }
                .shoppingFieldChrome(focused: typing == .item)
                .accessibilityIdentifier("priceAlerts.item")
            Text(verbatim: DealWatchWords.itemHint(language)).font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: DealWatchWords.priceLabel(language)).font(.subheadline.weight(.semibold))
            TextField(DealWatchWords.pricePlaceholder(language), text: $priceText)
                .keyboardType(.decimalPad)
                .focused($typing, equals: .price)
                .padding(14)
                .frame(minHeight: 48)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("priceAlerts.price")
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: DealWatchWords.shopsLabel(language)).font(.subheadline.weight(.semibold))
            DoddyChip(title: DealWatchWords.allShops(language), systemImage: "storefront", isSelected: picked.isEmpty) {
                picked = []
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach(DealWatchRequest.catalogued, id: \.rawValue) { chain in
                    DoddyChip(title: chain.name, isSelected: picked.contains(chain)) { toggle(chain) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(DealWatchWords.pickShops(language))
            .choiceMotion(picked)
        }
        if let problem = model.problem {
            Label { Text(verbatim: problem) } icon: { Image(systemName: "exclamationmark.triangle") }
                .foregroundStyle(Theme.error)
                .doddyCard(padding: 14)
                .accessibilityIdentifier("priceAlerts.problem")
        }
        Button {
            typing = nil
            Task { await model.add(item: item, priceText: priceText, chains: picked) }
        } label: {
            Text(verbatim: saving ? DealWatchWords.saving(language) : DealWatchWords.save(language))
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canSave)
        .accessibilityIdentifier("priceAlerts.save")
    }

    private func toggle(_ chain: DealsChain) {
        if let index = picked.firstIndex(of: chain) { picked.remove(at: index) } else { picked.append(chain) }
    }

    // MARK: After the server confirmed it

    private func savedCard(_ created: DealWatchCreated) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                BellTile(rings: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: created.watch.item)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: "\(DealWatchWords.priceLine(created.watch, language)) · \(DealWatchWords.shopsLine(created.watch, language))")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    if let ends = DealWatchWords.endsLine(created.watch, now: Date(), language) {
                        Text(verbatim: ends).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            Text(verbatim: DealWatchWords.saved(offers: created.offers.count, language))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("priceAlerts.saved")
            ForEach(Array(created.offers.enumerated()), id: \.offset) { index, offer in
                PriceAlertOfferRow(offer: offer, language: language, cheapest: index == 0)
                    .arrivesInOrder(index)
            }
            if created.chains.contains(where: { !$0.complete }) {
                DoddyFootnote(text: DealWatchWords.readInPart(language), systemImage: "exclamationmark.circle")
            }
            Button { dismiss() } label: { Text(verbatim: DealWatchWords.done(language)) }
                .buttonStyle(PrimaryButtonStyle())
        }
        .doddyCard()
    }
}
