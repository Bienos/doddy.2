import DoddyCore
import SwiftUI

// "Cheapest this week" (docs/implementation/SHOPPING.md 2, design/shopping-mode-v0.1): the user's
// items, then for each one the best value offer in the leaflets (the lowest price per kg, l or piece
// where the sizes are known, `BasketSolver.bestValue`) with what it takes to get that price
// (the shop's app, a card, a minimum quantity, the last day), the other chains in a line below, and
// the chains that weren't read with a link to their leaflet, and the ones read only in part. An offer
// Doddy's code couldn't confirm says so. Every price is the leaflet's, read on this request; nothing here is kept after it closes.
// Since ADR-661: the items can come from a shopping list ("From my list"), with the quantities in
// their words kept for the basket; the loyalty apps the user doesn't use are left out of the pick
// (stored on this iPhone only); each offer shows the price per piece under a multi-buy, the real cut
// against the 30-day low or that it isn't one, the deposit, "while stocks last", "in some shops", a
// price that isn't on yet and a last day on a closed day; promotions printed without a price are
// listed as such; and an item whose offers are of different kinds can be narrowed to one.
// Since ADR-662 and 663: products of another kind in the item's family are listed as "similar, not the same"
// (never picked, never in the basket); "My shops" sets the chains a check asks for and names the user's shop
// when an offer is only in some shops.

struct DealsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MemoryStore.self) private var store
    private let model = DealsModel.shared
    @State private var itemsText = ""
    @State private var chains: Set<DealsChain> = Set(DealsChain.read)
    @State private var showBasket = false
    /// The kind picked per item (by its place in the answer); absent: all kinds.
    @State private var kinds: [Int: String] = [:]
    @AppStorage(PreferenceKey.dealsProgramsNotUsed) private var programsStored = ""
    @AppStorage(PreferenceKey.dealsMyShops) private var myShopsStored = "[]"
    private let language = NotificationLanguage.current

    private var programs: DealsPrograms { DealsPrograms(stored: programsStored) }
    private var myShops: MyShops { MyShops(stored: myShopsStored) }
    private var today: DealDay? { ShoppingCalendar.today() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Butter, nappies size 4, ground coffee", text: $itemsText, axis: .vertical)
                        .lineLimit(1...6)
                        .accessibilityIdentifier("deals.items")
                    fromListButton
                    NavigationLink {
                        MyShopsView()
                    } label: {
                        LabeledContent("My shops", value: myShops.shops.isEmpty
                            ? NSLocalizedString("None yet", comment: "no shops picked")
                            : myShops.chains.map(\.name).joined(separator: ", "))
                    }
                    .accessibilityIdentifier("deals.myShops")
                    if !myShops.shops.isEmpty, Set(myShops.chains) != chains {
                        Button {
                            chains = Set(myShops.chains)
                        } label: {
                            Label("Only my shops' chains", systemImage: "storefront")
                        }
                    }
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
                    .disabled(entries.isEmpty || chains.isEmpty || model.phase == .checking)
                    .accessibilityIdentifier("deals.search")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Separate items with commas. Doddy's server reads the shops' own leaflets for this request and keeps nothing. Nothing that identifies you goes to the shops; Rossmann gets the item names as a search.")
                        Text("Narrow an item with “tylko” and a brand (masło tylko Łaciate) or with “bez” (mleko bez laktozy).")
                    }
                }

                Section {
                    DisclosureGroup("My loyalty apps") {
                        ForEach(DealsProgram.allCases, id: \.rawValue) { program in
                            Toggle(isOn: programBinding(program)) {
                                Text(String(format: NSLocalizedString("I use %@", comment: "a chain's loyalty app or card"), program.name))
                            }
                            .accessibilityIdentifier("deals.program.\(program.rawValue)")
                        }
                    }
                } footer: {
                    Text("A price that needs an app you don't use isn't picked or counted in the basket. This choice stays on this iPhone.")
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
                if let result = model.lastResult {
                    BasketView(result: result, quantities: model.lastQuantities, programs: programs)
                }
            }
            .onAppear {
                // Seen here, so Home's card for a voice search goes (ADR-666).
                model.homeCardSeen()
                if itemsText.isEmpty, let last = model.lastRequest {
                    itemsText = last.items.joined(separator: ", ")
                    chains = Set(last.chainsAsked)
                } else if model.lastRequest == nil, !myShops.shops.isEmpty {
                    chains = Set(myShops.chains)
                }
            }
        }
    }

    // MARK: Items

    /// What the user typed, split at commas and new lines.
    private var entries: [String] {
        itemsText.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The shopping lists with something left to get.
    private var listsWithItems: [DoddyList] { store.lists.filter { !$0.open.isEmpty } }

    @ViewBuilder
    private var fromListButton: some View {
        let lists = listsWithItems
        if lists.count == 1, let list = lists.first {
            Button {
                fill(from: list)
            } label: {
                Label(String(format: NSLocalizedString("From my list: %@", comment: "fills the items from a shopping list"), list.name), systemImage: "list.bullet")
            }
            .accessibilityIdentifier("deals.fromList")
        } else if lists.count > 1 {
            Menu {
                ForEach(lists) { list in
                    Button(list.name) { fill(from: list) }
                }
            } label: {
                Label("From my list", systemImage: "list.bullet")
            }
            .accessibilityIdentifier("deals.fromList")
        }
    }

    /// The list's open items, one per line (a comma inside an item would split it, so it becomes a space).
    private func fill(from list: DoddyList) {
        itemsText = list.open.map { $0.text.replacingOccurrences(of: ",", with: " ") }.joined(separator: "\n")
    }

    private func binding(for chain: DealsChain) -> Binding<Bool> {
        Binding(get: { chains.contains(chain) }, set: { on in if on { chains.insert(chain) } else { chains.remove(chain) } })
    }

    private func programBinding(_ program: DealsProgram) -> Binding<Bool> {
        Binding(get: { !programs.notUsed.contains(program) },
                set: { used in programsStored = programs.setting(program, used: used).stored })
    }

    private func search() async {
        let read = DealsListItems.read(entries)
        guard !read.items.isEmpty else { return }
        kinds = [:]
        let order = DealsChain.all.filter { chains.contains($0) }
        await model.search(DealsRequest(items: read.items, chains: order, language: language == .polish ? "pl" : "en"),
                           quantities: read.quantities, leftOut: read.leftOut)
    }

    // MARK: The answer

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
        ForEach(Array(result.items.enumerated()), id: \.offset) { index, item in
            Section {
                itemRows(item, index: index, chainOrder: chainOrder)
            } header: {
                Text(header(item, index: index))
            }
        }
        if !model.lastLeftOut.isEmpty {
            Section("Not looked up") {
                Text(String(format: NSLocalizedString("Up to %lld items of up to %lld characters are checked at once. Not checked: %@", comment: ""),
                            DealsRequest.maxItems, DealsRequest.maxItemLength, model.lastLeftOut.joined(separator: ", ")))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
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
        if let further = result.further?.openable {
            SearchFurtherSections(further: further)
        }
    }

    /// "masło" or "mleka · 2 l".
    private func header(_ item: DealsItemResult, index: Int) -> String {
        guard index < model.lastQuantities.count, let quantity = model.lastQuantities[index] else { return item.query }
        return "\(item.query) · \(quantity.display(polish: language == .polish))"
    }

    @ViewBuilder
    private func itemRows(_ item: DealsItemResult, index: Int, chainOrder: [DealsChain]) -> some View {
        let variants = DealsVariants.split(item)
        if let variants {
            Picker("Kind", selection: kindBinding(index)) {
                Text("All kinds").tag("")
                ForEach(variants, id: \.label) { variant in
                    Text(verbatim: "\(variant.label) (\(variant.offerIndices.count))").tag(variant.label)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("deals.kind.\(index)")
        }
        let shown = shownOffers(item, variants: variants, index: index)
        if let best = BasketSolver.bestValue(shown, chainOrder: chainOrder, programs: programs) {
            DealRow(offer: best, language: language, today: today, missingProgram: nil, myShops: myShops.shops(of: best.chain))
            if let why = DealsWhy.reason(shown, chainOrder: chainOrder, programs: programs) {
                Text(whyText(why)).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            let others = shown.filter { $0 != best }.prefix(3)
            if !others.isEmpty {
                Text(others.map { otherText($0) }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        } else if let first = shown.first {
            // Only prices the user can't get (or none Doddy could compare): shown, and said why.
            DealRow(offer: first, language: language, today: today, missingProgram: programs.missing(for: first), myShops: myShops.shops(of: first.chain))
        } else if item.promotions.isEmpty {
            Text("Not in the leaflets that were read.").foregroundStyle(Theme.secondaryText)
        }
        if !item.similar.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Similar, not the same").font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                ForEach(Array(item.similar.enumerated()), id: \.offset) { _, offer in
                    Text(verbatim: "\(offer.product) · \(offer.chain.name) \(offer.price.text(language))")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                Text("Another kind of product: not counted for this item.").font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
        }
        ForEach(Array(item.promotions.enumerated()), id: \.offset) { _, promotion in
            PromotionRow(promotion: promotion)
        }
    }

    private func shownOffers(_ item: DealsItemResult, variants: [DealsVariant]?, index: Int) -> [DealOffer] {
        guard let picked = kinds[index], !picked.isEmpty, let variant = variants?.first(where: { $0.label == picked }) else { return item.offers }
        return variant.offerIndices.map { item.offers[$0] }
    }

    private func kindBinding(_ index: Int) -> Binding<String> {
        Binding(get: { kinds[index] ?? "" }, set: { kinds[index] = $0 })
    }

    /// "Why this one", in a line: the code's reason, never a model's.
    private func whyText(_ why: DealsWhy) -> String {
        switch why {
        case .only:
            return NSLocalizedString("Why this one: the only offer found for this item.", comment: "")
        case .lowestPerUnit(let per, let value, let next):
            let unit = "\(value.text(language))/\(per.rawValue)"
            guard let next else { return String(format: NSLocalizedString("Why this one: the lowest price per %@ (%@).", comment: "a unit, a price per unit"), per.rawValue, unit) }
            return String(format: NSLocalizedString("Why this one: the lowest price per %@ (%@); next, %@ at %@.", comment: "unit, price per unit, chain, its price per unit"),
                          per.rawValue, unit, next.chain.name, "\(next.value.text(language))/\(per.rawValue)")
        case .cheapestPack(let next):
            guard let next else { return NSLocalizedString("Why this one: the cheapest pack (no sizes to compare).", comment: "") }
            return String(format: NSLocalizedString("Why this one: the cheapest pack (no sizes to compare); next, %@ at %@.", comment: "chain, price"),
                          next.chain.name, next.price.text(language))
        }
    }

    /// "Lidl 5,49 zł", "Dino 25,99 zł (3 for 17,33 zł each)", "Lidl 4,49 zł (app you don't use)".
    private func otherText(_ offer: DealOffer) -> String {
        var text = "\(offer.chain.name) \(offer.price.text(language))"
        if offer.isMultiBuy, let e = offer.effective {
            text += " (" + String(format: NSLocalizedString("%lld for %@ each", comment: "a multi-buy price per piece"), e.quantity, e.price.text(language)) + ")"
        }
        if programs.missing(for: offer) != nil { text += " (" + NSLocalizedString("an app you don't use", comment: "") + ")" }
        return text
    }
}

private struct DealRow: View {
    let offer: DealOffer
    let language: NotificationLanguage
    let today: DealDay?
    /// The program the price needs that the user said they don't use.
    let missingProgram: DealsProgram?
    /// The user's own shops of this chain (My shops), for "only in some shops".
    var myShops: [MyShop] = []
    @State private var askReminder = false
    @State private var reminderNote: String?

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
            if let e = offer.effective {
                if offer.isMultiBuy {
                    Text(String(format: NSLocalizedString("%lld for %@ each (one alone: %@)", comment: "a multi-buy price per piece"),
                                e.quantity, e.price.text(language), offer.price.text(language)))
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                } else {
                    Text(String(format: NSLocalizedString("This price only when buying at least %lld", comment: ""), e.quantity))
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                }
            }
            if !offer.conditions.isEmpty {
                Text(offer.conditions.joined(separator: " · ")).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accentText)
            }
            if let program = missingProgram {
                Text(String(format: NSLocalizedString("Needs %@, which you said you don't use.", comment: "a loyalty app"), program.name))
                    .font(.footnote).foregroundStyle(Theme.error)
            }
            if let cut = offer.cut {
                Text(String(format: NSLocalizedString("%lld%% below its lowest price in the last 30 days", comment: "a real price cut"), cut))
                    .font(.footnote).foregroundStyle(Theme.ink)
            } else if offer.flags.contains(.notACut) {
                Text("Not a real cut: it cost this little or less in the last 30 days.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            ForEach(Array(timing.enumerated()), id: \.offset) { _, line in
                Text(line).font(.footnote).foregroundStyle(Theme.secondaryText)
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
            if DealStartReminder.canRemind(offer, today: today), let from = offer.validFrom {
                Button {
                    askReminder = true
                } label: {
                    Label(String(format: NSLocalizedString("Remind me on %@", comment: "the day a leaflet price starts"), DealDayText.text(from)), systemImage: "bell")
                }
                .font(.footnote)
                .buttonStyle(.borderless)
                .confirmationDialog(DealStartReminder.title(language), isPresented: $askReminder, titleVisibility: .visible) {
                    Button("Set the reminder") { Task { await setReminder() } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(String(format: NSLocalizedString("On %@ at 8:00 this iPhone will show: %@", comment: "a day, the notification's words"),
                                DealDayText.text(from), DealStartReminder.body(offer, language)))
                }
            }
            if let reminderNote {
                Text(reminderNote).font(.footnote).foregroundStyle(Theme.secondaryText)
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

    private func setReminder() async {
        switch await DealReminders.schedule(offer) {
        case .scheduled(let day):
            reminderNote = String(format: NSLocalizedString("Reminder set for %@ at 8:00.", comment: "a day"), DealDayText.text(day))
        case .needsPermission:
            reminderNote = NSLocalizedString("Notifications are off for Doddy, so no reminder was set. You can turn them on in Settings.", comment: "")
        case .failed:
            reminderNote = NSLocalizedString("The reminder couldn't be set. Nothing was scheduled.", comment: "")
        }
    }

    /// The days and the shop notes: not on yet, the last day (or the last open day before it), the
    /// deposit, while stocks last, some shops only.
    private var timing: [String] {
        var lines: [String] = []
        for entry in DealsChecklist.entries(for: offer, today: today) {
            switch entry.kind {
            case .startsOn(let day):
                lines.append(String(format: NSLocalizedString("Not on yet: from %@", comment: "a leaflet price that starts later"), DealDayText.text(day)))
            case .lastDay:
                lines.append(NSLocalizedString("Today is the last day.", comment: "a leaflet price"))
            case .lastOpenDay(let day):
                lines.append(String(format: NSLocalizedString("Shops are closed on its last day: buy by %@.", comment: ""), DealDayText.text(day)))
            case .deposit:
                lines.append(NSLocalizedString("Plus a deposit for the bottle or can.", comment: ""))
            case .whileStocksLast:
                lines.append(NSLocalizedString("While stocks last.", comment: ""))
            case .selectedStores:
                if let shop = myShops.first {
                    lines.append(String(format: NSLocalizedString("Only in some shops: check yours (%@).", comment: "the user's shop's address"), shop.address))
                } else {
                    lines.append(NSLocalizedString("Only in some shops: check yours.", comment: ""))
                }
            default:
                break
            }
        }
        if let to = offer.validTo, !lines.contains(where: { $0.contains(DealDayText.text(to)) }) {
            lines.append(String(format: NSLocalizedString("Until %@", comment: "leaflet offer end date"), DealDayText.text(to)))
        }
        return lines
    }
}

/// A promotion the leaflet prints without a price: its range and mechanic, as the server's code worded them.
private struct PromotionRow: View {
    let promotion: DealPromotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: NSLocalizedString("%@: %@", comment: "a chain and a promotion's range"), promotion.chain.name, promotion.text))
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            Text(([promotion.mechanic] + promotion.conditions).joined(separator: " · "))
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accentText)
            if let to = promotion.validTo {
                Text(String(format: NSLocalizedString("Until %@", comment: "leaflet offer end date"), DealDayText.text(to)))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Text("The leaflet prints no price for this; the price is on the shelf.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            if let url = ShopPage.url(promotion.source.url) {
                Link(destination: url) {
                    Text(promotion.source.page.map { String(format: NSLocalizedString("Leaflet, page %lld", comment: ""), $0) }
                         ?? NSLocalizedString("Leaflet", comment: ""))
                }
                .font(.footnote)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A leaflet day as the iPhone writes dates ("Thu 23 Oct"), from the day itself: no time zone moves it.
enum DealDayText {
    static func text(_ day: DealDay) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw") ?? .current
        guard let date = calendar.date(from: day.dateComponents) else { return day.rawValue }
        var style = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}

/// "Search further" (ADR-666): the leaflets of the chains Doddy doesn't read that weren't asked for, then each
/// item's search page at the online shops Doddy's server names, in its order. Addresses only: Safari opens the
/// shop's page and Doddy reads none of them. A partner link is marked on its row and explained below, before
/// any tap (ADR-612); it opens the same search page through the network.
private struct SearchFurtherSections: View {
    let further: DealsFurther

    var body: some View {
        if !further.leaflets.isEmpty {
            Section("Leaflets Doddy doesn't read") {
                ForEach(Array(further.leaflets.enumerated()), id: \.offset) { _, leaflet in
                    if let url = URL(string: leaflet.url) {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(leaflet.chain.name).foregroundStyle(Theme.ink)
                                Text("Open the leaflet").font(.footnote)
                            }
                        }
                        .accessibilityIdentifier("deals.further.leaflet")
                    }
                }
            }
        }
        if !further.searches.isEmpty {
            Section {
                ForEach(Array(further.searches.enumerated()), id: \.offset) { _, search in
                    ForEach(Array(search.links.enumerated()), id: \.offset) { _, link in
                        if let url = URL(string: link.openURL) {
                            Link(destination: url) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(format: NSLocalizedString("Search for “%@” at %@", comment: "an item in the user's words, an online shop"),
                                                search.item, link.shop))
                                        .foregroundStyle(Theme.ink)
                                    if link.isPartner {
                                        Text("Partner link").font(.caption.weight(.semibold)).foregroundStyle(Theme.accentText)
                                    }
                                }
                            }
                            .accessibilityIdentifier("deals.further.search")
                        }
                    }
                }
            } header: {
                Text("Search further online")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("These open the shops' own pages in Safari. Doddy doesn't read them.")
                    if further.hasPartnerLink {
                        Text("Partner link: the page goes through an affiliate network on its way to the shop, and Doddy may earn a commission if you buy. Prices and the order of the picks don't change.")
                            .accessibilityIdentifier("deals.further.partnerNote")
                    }
                }
            }
        }
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
