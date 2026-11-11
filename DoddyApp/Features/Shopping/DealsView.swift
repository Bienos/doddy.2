import DoddyCore
import SwiftUI

// "Cheapest this week" (docs/implementation/SHOPPING.md 2, design/shopping-mode-v0.1). Since 10 Nov 2026 (owner:
// "I say I need milk and this, find how much it costs, and I get which shop has what price"; decision
// 2026-11-10-cheapest-this-week-simpler) the first screen asks one question with the items as chips and one
// button; the shops and loyalty apps are on "Change"; the answer is one card, item → price → shop, and each
// item opens its page with everything below. Before that, the user's
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
    /// The items, one chip each (owner, 10 Nov 2026: "I say milk and this, find how much it costs").
    @State private var items: [String] = []
    /// What is being typed; a comma or Return turns it into chips.
    @State private var draft = ""
    // E.Leclerc starts off: its leaflets cost a screening on every search (ADR-667).
    @State private var chains: Set<DealsChain> = Set(DealsChain.defaultRead)
    @State private var showBasket = false
    @State private var showShops = false
    /// The kind picked per item (by its place in the answer); absent: all kinds.
    @State private var kinds: [Int: String] = [:]
    @AppStorage(PreferenceKey.dealsProgramsNotUsed) private var programsStored = ""
    @AppStorage(PreferenceKey.dealsMyShops) private var myShopsStored = "[]"
    @FocusState private var typing: Bool
    private let language = NotificationLanguage.current

    private var programs: DealsPrograms { DealsPrograms(stored: programsStored) }
    private var myShops: MyShops { MyShops(stored: myShopsStored) }
    private var today: DealDay? { ShoppingCalendar.today() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    itemsCard
                    searchButton
                    switch model.phase {
                    case .checking:
                        checkingCard
                    case .failed(let message):
                        card {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Theme.error)
                        }
                    case .idle:
                        EmptyView()
                    }
                    if let result = model.lastResult, model.phase != .checking {
                        results(result)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .foregroundStyle(Theme.ink)
            .navigationTitle("Cheapest this week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(isPresented: $showBasket) {
                if let result = model.lastResult {
                    BasketView(result: result, quantities: model.lastQuantities, programs: programs)
                }
            }
            .navigationDestination(for: DealsItemPage.self) { page in
                if let result = model.lastResult, page.index < result.items.count {
                    itemPage(result.items[page.index], index: page.index, chainOrder: BasketSolver.chainOrder(result))
                }
            }
            .sheet(isPresented: $showShops) {
                DealsShopsSheet(chains: $chains, programsStored: $programsStored, myShops: myShops)
            }
            .onAppear {
                // Seen here, so Home's card for a voice search goes (ADR-666).
                model.homeCardSeen()
                if items.isEmpty, let last = model.lastRequest {
                    items = last.items
                    chains = Set(last.chainsAsked)
                } else if model.lastRequest == nil, !myShops.shops.isEmpty {
                    chains = Set(myShops.chains)
                }
            }
        }
    }

    // MARK: The question

    /// Doddy with the leaflets and what this screen does, in one line.
    private var hero: some View {
        HStack(alignment: .bottom, spacing: 12) {
            UploadedCharacterView(assetName: "WholeDoddy_kneeling_inspect", height: 104)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("What do you need?")
                    .font(.title2.weight(.bold))
                Text("I check this week's leaflets and show where each thing is cheapest.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    /// The items as chips, a field for the next one, examples while it's empty and the user's lists.
    private var itemsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                if !items.isEmpty {
                    ChipFlow(spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            itemChip(item, index: index)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.orangeCue)
                        .accessibilityHidden(true)
                    TextField("Items", text: $draft,
                              prompt: Text(items.isEmpty
                                  ? NSLocalizedString("Milk, butter, ground coffee", comment: "shopping question, before any item")
                                  : NSLocalizedString("Add another", comment: "shopping question, after an item")))
                        .focused($typing)
                        .submitLabel(.done)
                        .onSubmit(addDraft)
                        .onChange(of: draft) { _, new in
                            if new.contains(",") || new.contains("\n") { addDraft() }
                        }
                        .accessibilityIdentifier("deals.items")
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.canvas))
                if items.isEmpty && draft.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Try:").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                        ChipFlow(spacing: 8) {
                            ForEach(examples, id: \.self) { example in
                                Button { add([example]) } label: {
                                    Text(verbatim: example)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                fromListButton
                Text("You can also ask Doddy: “How much is milk this week?”")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func itemChip(_ item: String, index: Int) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: item).font(.subheadline.weight(.semibold))
            Button {
                items.remove(at: index)
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(format: NSLocalizedString("Remove %@", comment: "an item on the shopping question"), item)))
        }
        .foregroundStyle(Theme.inkOnOrange)
        .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 7)
        .background(Capsule().fill(Theme.orangeCue.opacity(0.9)))
    }

    /// The big button, then which shops it asks, with a way to change them.
    private var searchButton: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                addDraft()
                typing = false
                Task { await search() }
            } label: {
                Label("Check prices", systemImage: "tag")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(allEntries.isEmpty || chains.isEmpty || model.phase == .checking)
            .accessibilityIdentifier("deals.search")
            Button { showShops = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "storefront").accessibilityHidden(true)
                    Text(shopsSummary)
                    Spacer(minLength: 4)
                    Text("Change").fontWeight(.semibold).foregroundStyle(Theme.accentText)
                }
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("deals.shops")
        }
    }

    private var shopsSummary: String {
        let read = chains.filter(\.isRead).count
        if !myShops.shops.isEmpty, Set(myShops.chains) == chains {
            return NSLocalizedString("My shops", comment: "")
        }
        return String(format: NSLocalizedString("%lld shops' leaflets", comment: "how many chains a check reads"), read)
    }

    private var checkingCard: some View {
        card {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reading the leaflets…").font(.headline)
                    Text("This takes up to half a minute.").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    /// A few things people often buy, in the reader's language.
    private var examples: [String] {
        language == .polish
            ? ["mleko", "masło", "jajka", "kawa mielona", "pieluchy 4"]
            : ["milk", "butter", "eggs", "ground coffee", "nappies size 4"]
    }

    // MARK: Items

    /// The chips and whatever is still in the field.
    private var allEntries: [String] { items + split(draft) }

    private func split(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func addDraft() {
        let new = split(draft)
        draft = ""
        add(new)
    }

    private func add(_ new: [String]) {
        for item in new where !items.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) {
            items.append(item)
        }
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
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accentText)
            .accessibilityIdentifier("deals.fromList")
        } else if lists.count > 1 {
            Menu {
                ForEach(lists) { list in
                    Button(list.name) { fill(from: list) }
                }
            } label: {
                Label("From my list", systemImage: "list.bullet")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.accentText)
            .accessibilityIdentifier("deals.fromList")
        }
    }

    /// The list's open items (a comma inside an item would split it, so it becomes a space).
    private func fill(from list: DoddyList) {
        items = []
        add(list.open.map { $0.text.replacingOccurrences(of: ",", with: " ") })
    }

    private func search() async {
        let read = DealsListItems.read(allEntries)
        guard !read.items.isEmpty else { return }
        kinds = [:]
        let order = DealsChain.all.filter { chains.contains($0) }
        await model.search(DealsRequest(items: read.items, chains: order, language: language == .polish ? "pl" : "en"),
                           quantities: read.quantities, leftOut: read.leftOut)
    }

    // MARK: The answer

    @ViewBuilder
    private func results(_ result: DealsResult) -> some View {
        let chainOrder = BasketSolver.chainOrder(result)
        VStack(alignment: .leading, spacing: 10) {
            Text("Where it's cheapest").font(.title3.weight(.bold))
            // Said first, not inside "What wasn't checked" (11 Nov 2026): when most leaflets couldn't be read this time,
            // "Not in the leaflets that were read" under every item read as "nothing is on offer".
            let read = result.chains.filter { $0.status.wasRead }.count
            if result.chains.count > 1, read * 2 < result.chains.count {
                Label(String(format: NSLocalizedString("Only %lld of %lld shops' leaflets could be read this time. Try again in a few minutes; what was read is kept for a while, so the next check is quicker.", comment: "most leaflets failed"),
                             read, result.chains.count), systemImage: "exclamationmark.triangle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.error)
                    .accessibilityIdentifier("deals.mostNotRead")
            }
            if let checked = result.checkedDate {
                Text(String(format: NSLocalizedString("Read %@. Prices are the leaflets'; in the shop they can differ.", comment: ""), DateText.full(checked)))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            VStack(spacing: 0) {
                ForEach(Array(result.items.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Divider().overlay(Theme.separator) }
                    NavigationLink(value: DealsItemPage(index: index)) {
                        summaryRow(item, index: index, chainOrder: chainOrder)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("deals.item.\(index)")
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.quietSurface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
            Button {
                showBasket = true
            } label: {
                Label("Work out the basket: one shop or two", systemImage: "cart")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!result.items.contains { !$0.offers.isEmpty })
            .accessibilityIdentifier("deals.basket")
        }
        notes(result)
    }

    /// One item: its name, the best price and where, the price per unit, how many other shops have it.
    private func summaryRow(_ item: DealsItemResult, index: Int, chainOrder: [DealsChain]) -> some View {
        let shown = shownOffers(item, variants: DealsVariants.split(item), index: index)
        let best = BasketSolver.bestValue(shown, chainOrder: chainOrder, programs: programs)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: header(item, index: index)).font(.headline)
                if let best {
                    Text(verbatim: best.product).font(.footnote).foregroundStyle(Theme.secondaryText).lineLimit(2)
                    HStack(spacing: 6) {
                        Text(verbatim: best.chain.name)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.orangeCue.opacity(0.18)))
                        if best.check {
                            Text("Check the leaflet").font(.caption.weight(.semibold)).foregroundStyle(Theme.error)
                        } else if !best.conditions.isEmpty {
                            Text(verbatim: best.conditions.joined(separator: " · "))
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accentText).lineLimit(1)
                        }
                    }
                } else if !item.promotions.isEmpty {
                    Text("A promotion without a printed price").font(.footnote).foregroundStyle(Theme.secondaryText)
                } else {
                    Text("Not in the leaflets that were read.").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 8)
            if let best {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: best.price.text(language)).font(.title3.weight(.heavy))
                    if let unit = best.unitPriceMoney, let per = best.unitPrice?.per {
                        Text(verbatim: "\(unit.text(language))/\(per.rawValue)").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    let others = Set(shown.map(\.chain)).subtracting([best.chain]).count
                    if others > 0 {
                        Text(String(format: NSLocalizedString("+%lld other shops", comment: "other chains with this item"), others))
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// What wasn't looked up, what was read only in part, what wasn't checked and where to look further.
    @ViewBuilder
    private func notes(_ result: DealsResult) -> some View {
        let inPart = result.chains.filter { $0.status == .checked && $0.pages != nil }
        let notRead = result.chains.filter { !$0.status.wasRead }
        if !model.lastLeftOut.isEmpty || !inPart.isEmpty || !notRead.isEmpty {
            card {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        if !model.lastLeftOut.isEmpty {
                            Text(String(format: NSLocalizedString("Up to %lld items of up to %lld characters are checked at once. Not checked: %@", comment: ""),
                                        DealsRequest.maxItems, DealsRequest.maxItemLength, model.lastLeftOut.joined(separator: ", ")))
                                .font(.footnote).foregroundStyle(Theme.secondaryText)
                        }
                        ForEach(Array(inPart.enumerated()), id: \.offset) { _, report in
                            if let pages = report.pages {
                                Text(String(format: NSLocalizedString("%@: Doddy read %lld of %lld pages. A cheaper offer may be on the others.", comment: "a leaflet read in part"),
                                            report.chain.name, pages.read, pages.of))
                                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                            }
                        }
                        ForEach(Array(notRead.enumerated()), id: \.offset) { _, report in
                            ChainNotReadRow(report: report)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(String(format: NSLocalizedString("What wasn't checked (%lld)", comment: "shops or items a leaflet check didn't cover"),
                                notRead.count + inPart.count + (model.lastLeftOut.isEmpty ? 0 : 1)))
                        .font(.subheadline.weight(.semibold))
                }
                .tint(Theme.ink)
            }
        }
        if let further = result.further?.openable {
            SearchFurtherCards(further: further)
        }
    }

    /// "masło" or "mleka · 2 l".
    private func header(_ item: DealsItemResult, index: Int) -> String {
        guard index < model.lastQuantities.count, let quantity = model.lastQuantities[index] else { return item.query }
        return "\(item.query) · \(quantity.display(polish: language == .polish))"
    }

    // MARK: One item

    /// Everything about one item: the pick with what it takes, why it was picked, the other shops,
    /// similar products and promotions without a price. Nothing on the summary hides any of it.
    private func itemPage(_ item: DealsItemResult, index: Int, chainOrder: [DealsChain]) -> some View {
        Form {
            Section { itemRows(item, index: index, chainOrder: chainOrder) }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle(header(item, index: index))
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: Parts

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.quietSurface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
    }
}

/// An item's own page in the answer, by its place.
private struct DealsItemPage: Hashable {
    let index: Int
}

/// Which leaflets a check reads, My shops and the loyalty apps: what used to fill the first screen
/// (owner, 10 Nov 2026: "I don't get it"). Same preferences and identifiers.
private struct DealsShopsSheet: View {
    @Binding var chains: Set<DealsChain>
    @Binding var programsStored: String
    let myShops: MyShops
    @Environment(\.dismiss) private var dismiss

    private var programs: DealsPrograms { DealsPrograms(stored: programsStored) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                }
                Section {
                    ForEach(DealsChain.read + DealsChain.linkOnly, id: \.rawValue) { chain in
                        Toggle(isOn: binding(for: chain)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chain.name)
                                if !chain.isRead {
                                    Text("Link to the leaflet only").font(.footnote).foregroundStyle(Theme.secondaryText)
                                } else if DealsChain.specialty.contains(chain) {
                                    // ADR-667: the server asks it only when an item is its kind of thing.
                                    Text("Only for items it sells").font(.footnote).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                        .tint(Theme.orangeCue)
                    }
                } header: {
                    Text("Leaflets to check")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Doddy's server reads the shops' own leaflets for this request and keeps nothing. Nothing that identifies you goes to the shops; Rossmann gets the item names as a search.")
                        Text("Narrow an item with “tylko” and a brand (masło tylko Łaciate) or with “bez” (mleko bez laktozy).")
                    }
                }
                Section {
                    ForEach(DealsProgram.allCases, id: \.rawValue) { program in
                        Toggle(isOn: programBinding(program)) {
                            Text(String(format: NSLocalizedString("I use %@", comment: "a chain's loyalty app or card"), program.name))
                        }
                        .tint(Theme.orangeCue)
                        .accessibilityIdentifier("deals.program.\(program.rawValue)")
                    }
                } header: {
                    Text("My loyalty apps")
                } footer: {
                    Text("A price that needs an app you don't use isn't picked or counted in the basket. This choice stays on this iPhone.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Shops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func binding(for chain: DealsChain) -> Binding<Bool> {
        Binding(get: { chains.contains(chain) }, set: { on in if on { chains.insert(chain) } else { chains.remove(chain) } })
    }

    private func programBinding(_ program: DealsProgram) -> Binding<Bool> {
        Binding(get: { !programs.notUsed.contains(program) },
                set: { used in programsStored = programs.setting(program, used: used).stored })
    }
}

/// Chips that wrap onto the next line.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.init(width: width, height: nil))
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.init(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .init(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            row = max(row, size.height)
        }
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
            // ADR-668: the shop's page through a partner link, said before the tap; it never moves the offer.
            if offer.isPartner, let buy = offer.buyUrl.flatMap(ShopPage.url) {
                Link(destination: buy) { Text("Open in the shop") }
                    .font(.footnote)
                    .accessibilityIdentifier("deals.offer.partner")
                Text("Partner link: the page goes through an affiliate network on its way to the shop, and Doddy may earn a commission if you buy. Prices and the order of the picks don't change.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
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
private struct SearchFurtherCards: View {
    let further: DealsFurther

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !further.leaflets.isEmpty {
                Text("Leaflets Doddy doesn't read").font(.subheadline.weight(.semibold))
                ForEach(Array(further.leaflets.enumerated()), id: \.offset) { _, leaflet in
                    if let url = URL(string: leaflet.url) {
                        Link(destination: url) {
                            HStack {
                                Text(leaflet.chain.name).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("Open the leaflet").font(.footnote)
                            }
                        }
                        .accessibilityIdentifier("deals.further.leaflet")
                    }
                }
            }
            if !further.searches.isEmpty {
                Text("Search further online").font(.subheadline.weight(.semibold)).padding(.top, 4)
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
                Text("These open the shops' own pages in Safari. Doddy doesn't read them.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                if further.hasPartnerLink {
                    Text("Partner link: the page goes through an affiliate network on its way to the shop, and Doddy may earn a commission if you buy. Prices and the order of the picks don't change.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("deals.further.partnerNote")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.quietSurface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
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
