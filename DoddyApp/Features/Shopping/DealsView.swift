import DoddyCore
import SwiftUI

// "Cheapest this week" (docs/implementation/SHOPPING.md 2, design/shopping-mode-v0.1): the user's
// items, then for each one the best value offer in the leaflets (the lowest price per kg, l or piece
// where the sizes are known, `BasketSolver.bestValue`) with what it takes to get that price
// (the shop's app, a card, a minimum quantity, the last day), the other chains in a line below, and
// the chains that weren't read with a link to their leaflet, and the ones read only in part. An offer
// Doddy's code couldn't confirm says so. Every price is the leaflet's, read on this request; nothing here is kept after it closes.

struct DealsView: View {
    @Environment(\.dismiss) private var dismiss
    private let model = DealsModel.shared
    @State private var itemsText = ""
    @State private var chains: Set<DealsChain> = Set(DealsChain.read)
    @State private var showBasket = false
    private let language = NotificationLanguage.current

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Butter, nappies size 4, ground coffee", text: $itemsText, axis: .vertical)
                        .lineLimit(1...4)
                        .accessibilityIdentifier("deals.items")
                    ForEach(DealsChain.read + DealsChain.linkOnly, id: \.rawValue) { chain in
                        Toggle(isOn: binding(for: chain)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chain.name)
                                if !chain.isRead {
                                    Text("Link to the leaflet only").font(.footnote).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                    }
                    Button {
                        Task { await search() }
                    } label: {
                        Label("Check this week's leaflets", systemImage: "magnifyingglass")
                    }
                    .disabled(items.isEmpty || chains.isEmpty || model.phase == .checking)
                    .accessibilityIdentifier("deals.search")
                } footer: {
                    Text("Separate items with commas. Doddy's server reads the shops' own leaflets for this request and keeps nothing. Nothing that identifies you goes to the shops; Rossmann gets the item names as a search.")
                }

                switch model.phase {
                case .checking:
                    Section { ProgressView("Reading the leaflets…") }
                case .failed(let message):
                    Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error) }
                case .idle:
                    EmptyView()
                }

                if let result = model.lastResult {
                    results(result)
                }
            }
            .navigationTitle("Cheapest this week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(isPresented: $showBasket) {
                if let result = model.lastResult { BasketView(result: result) }
            }
            .onAppear {
                if itemsText.isEmpty, let last = model.lastRequest {
                    itemsText = last.items.joined(separator: ", ")
                    chains = Set(last.chainsAsked)
                }
            }
        }
    }

    private var items: [String] {
        itemsText.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func binding(for chain: DealsChain) -> Binding<Bool> {
        Binding(get: { chains.contains(chain) }, set: { on in if on { chains.insert(chain) } else { chains.remove(chain) } })
    }

    private func search() async {
        let order = DealsChain.all.filter { chains.contains($0) }
        await model.search(DealsRequest(items: items, chains: order, language: language == .polish ? "pl" : "en"))
    }

    @ViewBuilder
    private func results(_ result: DealsResult) -> some View {
        Section {
            if let checked = result.checkedDate {
                Text(String(format: NSLocalizedString("Read %@. Prices are the leaflets'; in the shop they can differ.", comment: ""), DateText.full(checked)))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Button {
                showBasket = true
            } label: {
                Label("Work out the basket: one shop or two", systemImage: "cart")
            }
            .disabled(!result.items.contains { !$0.offers.isEmpty })
            .accessibilityIdentifier("deals.basket")
        }
        let chainOrder = BasketSolver.chainOrder(result)
        ForEach(Array(result.items.enumerated()), id: \.offset) { _, item in
            Section(item.query) {
                if let best = BasketSolver.bestValue(item.offers, chainOrder: chainOrder) ?? item.offers.first {
                    DealRow(offer: best, language: language)
                    let others = item.offers.filter { $0 != best }.prefix(3)
                    if !others.isEmpty {
                        Text(others.map { "\($0.chain.name) \($0.price.text(language))" }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                } else {
                    Text("Not in the leaflets that were read.").foregroundStyle(Theme.secondaryText)
                }
            }
        }
        let inPart = result.chains.filter { $0.status == .checked && $0.pages != nil }
        if !inPart.isEmpty {
            Section("Read in part") {
                ForEach(Array(inPart.enumerated()), id: \.offset) { _, report in
                    if let pages = report.pages {
                        Text(String(format: NSLocalizedString("%@: Doddy read %lld of %lld pages. A cheaper offer may be on the others.", comment: "a leaflet read in part"),
                                    report.chain.name, pages.read, pages.of))
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
        let notRead = result.chains.filter { !$0.status.wasRead }
        if !notRead.isEmpty {
            Section("Not checked") {
                ForEach(Array(notRead.enumerated()), id: \.offset) { _, report in
                    ChainNotReadRow(report: report)
                }
            }
        }
    }
}

private struct DealRow: View {
    let offer: DealOffer
    let language: NotificationLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(offer.product).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(offer.price.text(language)).font(.title2.weight(.heavy)).foregroundStyle(Theme.ink)
                Text(offer.chain.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                if let unit = offer.unitPriceMoney, let per = offer.unitPrice?.per {
                    Text(verbatim: "\(unit.text(language))/\(per.rawValue)").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            if !offer.conditions.isEmpty {
                Text(offer.conditions.joined(separator: " · ")).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accentText)
            }
            if let to = offer.validTo {
                Text(String(format: NSLocalizedString("Until %@", comment: "leaflet offer end date"), to.rawValue))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if let regular = offer.regularPrice {
                Text(String(format: NSLocalizedString("Regular price %@", comment: ""), regular.text(language)))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if let lowest = offer.lowest30d {
                Text(String(format: NSLocalizedString("Lowest in the last 30 days: %@", comment: ""), lowest.text(language)))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if offer.check {
                Label("Doddy couldn't confirm this one. Check the leaflet.", systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(Theme.error)
            }
            if let url = ShopPage.url(offer.source.url) {
                Link(destination: url) {
                    Text(offer.source.page.map { String(format: NSLocalizedString("Leaflet, page %lld", comment: ""), $0) }
                         ?? NSLocalizedString("Leaflet", comment: ""))
                }
                .font(.footnote)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ChainNotReadRow: View {
    let report: DealsChainReport

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(report.chain.name).foregroundStyle(Theme.ink)
            Text(reason).font(.footnote).foregroundStyle(Theme.secondaryText)
            if let url = (report.leafletUrl ?? report.leaflet?.url).flatMap(ShopPage.url) {
                Link("Open the leaflet", destination: url).font(.footnote)
            }
        }
    }

    private var reason: String {
        switch report.status {
        case .linkOnly: NSLocalizedString("Doddy doesn't read this chain's leaflet yet.", comment: "")
        case .blocked: NSLocalizedString("Its site doesn't let automated readers in, and Doddy doesn't get around that.", comment: "")
        case .noLeaflet: NSLocalizedString("No leaflet for this week was found.", comment: "")
        case .failed:
            if let pages = report.pages, pages.read > 0 {
                String(format: NSLocalizedString("Doddy read %lld of %lld pages and found nothing in them.", comment: "a leaflet read in part"), pages.read, pages.of)
            } else {
                NSLocalizedString("The leaflet couldn't be read this time.", comment: "")
            }
        default: NSLocalizedString("Not checked.", comment: "")
        }
    }
}
