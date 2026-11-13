import DoddyCore
import SwiftUI

// Shopping in one place (owner, 11 Nov 2026: "skończ co już mamy"; docs/strategy/SKLEP_PROPOZYCJA_2026-11.md).
// Redesigned 13 Nov 2026 (owner: "najtaniej w tym tygodniu … trzeba złączyć", "te jedzeniowe oddzielnie, ciuchowe i inne
// oddzielnie", "wyszukujesz, porównujesz, … ustawienia cen, szukania okazji"): two worlds under one orange hero.
//   - Groceries: "Cheapest this week" (the leaflets, the basket, my shops), which left Home's menu and lives here.
//   - Everything else: a category (electronics, home, fashion, other) that changes what "what matters most" offers,
//     "Find me this" (docs/implementation/SHOPPING.md 1), the searches already handed over, comparing offers in
//     Shopify shops, "Check this" for a product link, and price alerts (SHOPPING_WATCH.md).
// Every price shown is one the server confirmed on a shop's own page; this screen writes none itself.

struct ShoppingHubView: View {
    /// The two worlds the owner asked to keep apart.
    enum World: String { case groceries, products }
    /// What kind of thing is wanted; only the suggestions under "What matters most?" change with it.
    enum Category: String, CaseIterable { case electronics, home, fashion, other }

    @Environment(\.dismiss) private var dismiss
    private let model = ErrandsModel.shared
    private let watches = WatchModel.shared
    @AppStorage("shopping.world") private var worldRaw = World.products.rawValue
    @State private var category: Category = .electronics
    @State private var words = ""
    /// What matters most, in the order it was tapped.
    @State private var priorities: [String] = []
    /// A priority of the person's own, being typed.
    @State private var ownPriority = ""
    @State private var asking: TypedAsk?
    @State private var note: HandOverNote?
    @State private var opened: UUID?
    @State private var showDeals = false
    @State private var showShopify = false
    /// "Check this": the link being pasted, the person's own name for the product, and the page whose card is open.
    @State private var link = ""
    @State private var linkName = ""
    @State private var watchPage: SharedShopPage?
    @FocusState private var typing: Bool

    /// Set when a link arrives from the Share Sheet, so the screen scrolls to the "Check this" card.
    @State private var scrollToCheckThis = false

    private var router: ShortcutRouter { .shared }
    private var scope: ReleaseScope { ReleaseScopeStore.current }
    private var shoppingTasks: [StoredErrand] { model.errands.filter { $0.draft.kind == .shopping } }
    private var world: World { World(rawValue: worldRaw) ?? .products }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if !model.isServerConfigured {
                        Label("Doddy's server isn't set up in this build, so tasks can't run yet.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                            .doddyCard()
                    }
                    switch world {
                    case .groceries:
                        if scope.shows(.deals) { leafletsCard }
                        groceriesHints
                    case .products:
                        if scope.shows(.errands) {
                            findCard
                            if !shoppingTasks.isEmpty { searches }
                        }
                        if scope.shows(.shopifyShopping) { shopifyLink }
                        if scope.shows(.priceWatch) {
                            DoddySectionTitle(title: "Price alerts")
                            WatchesSection()
                            if watches.watches.isEmpty && watches.loadProblem == nil && watches.message == nil { watchHint }
                            checkThisCard.id(Self.checkThisCardID)
                        }
                        howItWorks
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .readableColumn()
            }
            .scrollDismissesKeyboard(.interactively)
            .doddyScreen()
            .navigationTitle("Shopping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(item: $opened) { id in ErrandDetailView(id: id) }
            .sheet(item: $asking) { ask in
                TypedHandOverSheet(draft: ask.draft) { outcome in finished(outcome) }
            }
            .sheet(isPresented: $showDeals) { DealsView() }
            .sheet(isPresented: $showShopify) { ShopifyLiveShoppingView() }
            .sheet(item: $watchPage) { WatchCard(page: $0) }
            .refreshable { await reload() }
            .task {
                await model.load()
                await reload()
            }
            // A product link shared from Safari or a shop app with "Check the price": it fills the "Check this" card and
            // the screen scrolls there. The card still asks for a tap before anything is read or sent.
            .onChange(of: router.priceCheckLink, initial: true) { _, shared in
                guard shared != nil, let taken = router.takePriceCheckLink() else { return }
                link = taken
                linkName = ""
                worldRaw = World.products.rawValue
                scrollToCheckThis = true
            }
            .onChange(of: scrollToCheckThis) { _, go in
                guard go else { return }
                scrollToCheckThis = false
                withAnimation { proxy.scrollTo(Self.checkThisCardID, anchor: .top) }
            }
            }
        }
        .accessibilityIdentifier("shopping.hub")
    }

    private static let checkThisCardID = "shopping.checkThisCard"

    private func reload() async {
        await model.refresh()
        if scope.shows(.priceWatch) { await watches.refresh() }
    }

    // MARK: What this screen is

    private var hero: some View {
        DoddyHero(title: world == .groceries ? NSLocalizedString("What's on the list?", comment: "") : NSLocalizedString("What are you looking for?", comment: ""),
                  subtitle: world == .groceries
                    ? NSLocalizedString("Food and everyday things: where each is cheapest in this week's leaflets.", comment: "")
                    : NSLocalizedString("I look through shops in Poland, compare and bring back up to three picks, each with a price I read on the shop's own page. You buy in the shop; I never buy anything.", comment: ""),
                  pose: world == .groceries ? .reachingHigh : .kneelingInspect) {
            HStack(spacing: 8) {
                DoddyChip(title: "Groceries", systemImage: "cart", isSelected: world == .groceries, onOrange: true) {
                    worldRaw = World.groceries.rawValue
                }
                .accessibilityIdentifier("shopping.tab.groceries")
                DoddyChip(title: "Everything else", systemImage: "bag", isSelected: world == .products, onOrange: true) {
                    worldRaw = World.products.rawValue
                }
                .accessibilityIdentifier("shopping.tab.products")
            }
        }
    }

    // MARK: Find me this

    private var findCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find me this").font(.system(.title3, design: .rounded, weight: .bold)).accessibilityAddTraits(.isHeader)
            DoddyChipRow {
                ForEach(Category.allCases, id: \.self) { kind in
                    DoddyChip(title: Self.title(of: kind), systemImage: Self.symbol(of: kind), isSelected: category == kind) {
                        category = kind
                        // A chosen suggestion of another category stays: it is the person's own order.
                    }
                    .accessibilityIdentifier("shopping.category.\(kind.rawValue)")
                }
            }
            TextField("Find me this", text: $words, prompt: Text(verbatim: Self.example(of: category)), axis: .vertical)
                .lineLimit(2...5)
                .focused($typing)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.canvas))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                .onChange(of: words) { _, new in if !new.isEmpty { note = nil } }
                .accessibilityIdentifier("shopping.words")
            if words.utf16.count > ErrandDraft.maxWords - 200 {
                Text(verbatim: "\(words.utf16.count) / \(ErrandDraft.maxWords)")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(words.utf16.count > ErrandDraft.maxWords ? Theme.error : Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            prioritiesPicker
            Button {
                typing = false
                ask()
            } label: {
                Label("Find it", systemImage: "magnifyingglass")
            }
            .buttonStyle(DoddyInkButtonStyle())
            .disabled(words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.isServerConfigured || model.isHandingOver)
            .accessibilityIdentifier("shopping.find")
            if let note {
                Label(note.text, systemImage: note.kind.symbol)
                    .font(.subheadline)
                    .foregroundStyle(note.kind.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("shopping.findNote")
            }
            Text("Nothing is sent until you say yes on the next card. Doddy works on it in the background; the result waits here.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .doddyCard()
    }

    /// "What matters most?": tap in the order that matters. The number on a chip is its place.
    private var prioritiesPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What matters most? Tap in your order.")
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            ChipFlow(spacing: 8) {
                ForEach(choices, id: \.self) { choice in
                    let place = ShoppingPriorities.place(of: choice, in: priorities)
                    Button {
                        priorities = ShoppingPriorities.toggled(choice, in: priorities)
                    } label: {
                        HStack(spacing: 6) {
                            if let place {
                                Text(verbatim: "\(place)").font(.caption.weight(.bold)).monospacedDigit()
                            }
                            Text(verbatim: choice).font(.subheadline)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(minHeight: 36)
                        .foregroundStyle(place == nil ? Theme.ink : Theme.inkOnOrange)
                        .background(Capsule().fill(place == nil ? Theme.canvas : Theme.orangeCue))
                        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: place == nil ? 1 : 0))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: choice))
                    .accessibilityValue(Text(verbatim: place.map { String(format: NSLocalizedString("Number %lld", comment: "a shopping priority's place in the order"), $0) } ?? ""))
                    .accessibilityAddTraits(place == nil ? [] : .isSelected)
                    .accessibilityIdentifier("shopping.priority")
                }
            }
            if priorities.count < ErrandDraft.maxPriorities {
                TextField("Something else", text: $ownPriority, prompt: Text("Something else, e.g. white, made in the EU"))
                    .font(.subheadline)
                    .submitLabel(.done)
                    .onSubmit { addOwnPriority() }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                    .accessibilityIdentifier("shopping.ownPriority")
            }
        }
    }

    /// The suggestions, then whatever the person added themselves (so it can be tapped back out).
    private var choices: [String] {
        let own = priorities.filter { chosen in !suggestions.contains { $0.lowercased() == chosen.lowercased() } }
        return suggestions + own
    }

    /// The suggestions for the chosen category; the person's own words are added after them.
    private var suggestions: [String] { Self.suggestions(for: category) }

    private static func suggestions(for kind: Category) -> [String] {
        let price = NSLocalizedString("Price", comment: "a shopping priority")
        let reviews = NSLocalizedString("Good reviews", comment: "a shopping priority")
        let delivery = NSLocalizedString("Fast delivery", comment: "a shopping priority")
        switch kind {
        case .electronics:
            return [price, NSLocalizedString("Quality", comment: "a shopping priority"), NSLocalizedString("Warranty", comment: "a shopping priority"),
                    reviews, delivery, NSLocalizedString("Brand", comment: "a shopping priority")]
        case .home:
            return [price, NSLocalizedString("Quality", comment: "a shopping priority"), NSLocalizedString("Size that fits", comment: "a shopping priority"),
                    NSLocalizedString("Quiet", comment: "a shopping priority"), reviews, delivery]
        case .fashion:
            return [price, NSLocalizedString("My size in stock", comment: "a shopping priority"), NSLocalizedString("Material", comment: "a shopping priority"),
                    NSLocalizedString("Free returns", comment: "a shopping priority"), NSLocalizedString("Brand", comment: "a shopping priority"), delivery]
        case .other:
            return [price, NSLocalizedString("Quality", comment: "a shopping priority"), delivery, reviews,
                    NSLocalizedString("Warranty", comment: "a shopping priority"), NSLocalizedString("Brand", comment: "a shopping priority")]
        }
    }

    private static func title(of kind: Category) -> String {
        switch kind {
        case .electronics: NSLocalizedString("Electronics", comment: "a shopping category")
        case .home: NSLocalizedString("Home and garden", comment: "a shopping category")
        case .fashion: NSLocalizedString("Fashion", comment: "a shopping category")
        case .other: NSLocalizedString("Other", comment: "a shopping category")
        }
    }

    private static func symbol(of kind: Category) -> String {
        switch kind {
        case .electronics: "headphones"
        case .home: "sofa"
        case .fashion: "tshirt"
        case .other: "shippingbox"
        }
    }

    private static func example(of kind: Category) -> String {
        switch kind {
        case .electronics: NSLocalizedString("For example: a quiet 45 cm dishwasher under 2000 zł", comment: "")
        case .home: NSLocalizedString("For example: an armchair for a small living room, grey, up to 1200 zł", comment: "")
        case .fashion: NSLocalizedString("For example: a waterproof winter jacket, men's L, up to 600 zł", comment: "")
        case .other: NSLocalizedString("For example: a gift for a 10-year-old who likes science, up to 200 zł", comment: "")
        }
    }

    private func addOwnPriority() {
        let word = ownPriority.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        // Already chosen: leave it in (a second tap on its chip takes it out), just clear the field.
        if ShoppingPriorities.place(of: word, in: priorities) == nil {
            priorities = ShoppingPriorities.toggled(word, in: priorities)
        }
        ownPriority = ""
    }

    /// Checks here first (the server checks again): no link, not too long, Connections not paused.
    /// Only then does the card ask; nothing has been sent at this point.
    private func ask() {
        let language = ErrandDraft.typedLanguage(Bundle.main.preferredLocalizations.first ?? "en")
        let draft = ErrandDraft.typedShopping(words, priorities: priorities, language: language)
        if let issue = draft.validationIssues().first {
            note = HandOverNote(text: ErrandText.issue(issue), kind: .problem)
            return
        }
        if UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) {
            note = HandOverNote(text: ErrandText.paused, kind: .problem)
            return
        }
        note = nil
        asking = TypedAsk(draft: draft)
    }

    /// The card closed with an answer. "Looking" only when the server said it has the task.
    private func finished(_ outcome: ErrandsModel.HandOverOutcome) {
        switch outcome {
        case .started:
            words = ""
            priorities = []
            ownPriority = ""
            note = HandOverNote(text: NSLocalizedString("Doddy is looking. The picks will wait here, in Tasks and in Messages.", comment: ""), kind: .confirmed)
        case .maybeStarted:
            note = HandOverNote(text: NSLocalizedString("Doddy couldn't confirm it started. It may be running: pull down to check before you hand it over again.", comment: ""), kind: .unsure)
        case .notStarted(let error):
            note = HandOverNote(text: ErrandText.notStarted(error), kind: .problem)
        case .invalid(let issue):
            note = HandOverNote(text: ErrandText.issue(issue), kind: .problem)
        case .paused:
            note = HandOverNote(text: ErrandText.paused, kind: .problem)
        case .alreadySending:
            note = nil
        }
    }

    // MARK: What was already looked for

    private var searches: some View {
        VStack(alignment: .leading, spacing: 10) {
            DoddySectionTitle(title: "Your searches")
            VStack(spacing: 0) {
                ForEach(Array(shoppingTasks.enumerated()), id: \.element.id) { index, errand in
                    if index > 0 { Divider().overlay(Theme.separator) }
                    Button { opened = errand.id } label: {
                        ErrandCardRow(errand: errand, isNew: model.unseenFinished.contains(errand.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shopping.search")
                }
            }
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.quietSurface))
        }
    }

    // MARK: Check this

    /// The page in the pasted text, with the person's own name for it. Nothing has been sent: reading the text is
    /// done here, and Doddy's server gets the page only when the card's own button says "Check the page".
    private var pastedPage: SharedShopPage? {
        SharedShopPage.parse(link)?.titled(linkName)
    }

    private var checkThisCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Check this").font(.system(.title3, design: .rounded, weight: .bold)).accessibilityAddTraits(.isHeader)
            Text("Paste the link to a product you're looking at in a shop. Doddy's server reads the page and shows its price; then you can ask Doddy to watch it.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Product link", text: $link, prompt: Text(verbatim: "https://…"), axis: .vertical)
                .lineLimit(1...3)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.canvas))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                .accessibilityIdentifier("shopping.link")
            if let page = pastedPage {
                Label(String(format: NSLocalizedString("Page at %@", comment: "the shop a pasted link points to"), page.shop),
                      systemImage: "link")
                    .font(.subheadline)
                TextField("What is it? (optional)", text: $linkName)
                    .font(.subheadline)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
                    .accessibilityIdentifier("shopping.linkName")
            } else if !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("That isn't a web address Doddy can read. It must start with https://.", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                watchPage = pastedPage
            } label: {
                Label("Check this page", systemImage: "magnifyingglass")
            }
            .buttonStyle(DoddyInkButtonStyle())
            .disabled(pastedPage == nil || !model.isServerConfigured)
            .accessibilityIdentifier("shopping.checkThis")
            Text("Nothing is sent until you tap “Check the page” on the next card. Some shops don't let Doddy's server read their pages; then Doddy tells you it couldn't read a price.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .doddyCard()
    }

    // MARK: Watching a price

    /// Shown while nothing is watched: where a watch starts. It says nothing about whether one is on.
    private var watchHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Watched prices", systemImage: "bell").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Open a result and tap “Watch the price” on a pick. You give your price, and Doddy tells you once when the shop's page shows that price or less.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .doddyCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("shopping.watchHint")
    }

    // MARK: Groceries

    /// "Cheapest this week" (SHOPPING.md 2), which until 13 Nov 2026 had its own row on Home's menu.
    private var leafletsCard: some View {
        Button { showDeals = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    DoddySymbolTile(systemImage: "cart.fill", size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cheapest this week").font(.system(.title3, design: .rounded, weight: .bold))
                        Text("This week's leaflets, read for you").font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("Where each thing is cheapest, with the shop and the price", systemImage: "tag")
                    Label("Your basket: the shop where all of it costs least", systemImage: "basket")
                    Label("Your shops on the map, and a reminder for a later price", systemImage: "mappin.and.ellipse")
                }
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
            .doddyCard(padding: 18, cornerRadius: 26)
        }
        .buttonStyle(DoddyTapStyle())
        .accessibilityIdentifier("shopping.leaflets")
    }

    private var groceriesHints: some View {
        VStack(alignment: .leading, spacing: 8) {
            DoddyFootnote(text: NSLocalizedString("By voice too: “where is butter cheapest this week?” or “compare my basket”.", comment: ""), systemImage: "waveform")
            DoddyFootnote(text: NSLocalizedString("Prices come from the chains' own leaflets for this week. Doddy buys nothing; you shop as usual.", comment: ""))
        }
    }

    // MARK: Shopify shops

    private var shopifyLink: some View {
        Button { showShopify = true } label: {
            HStack(spacing: 12) {
                DoddySymbolTile(systemImage: "chart.bar.xaxis", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compare offers in Shopify shops").font(.headline)
                    Text("Search, see every shop's price side by side with the cheapest marked, and prepare a cart at the shop. Doddy takes no payment.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .doddyCard()
        }
        .buttonStyle(DoddyTapStyle())
        .accessibilityIdentifier("shopping.shopify")
    }

    // MARK: How it works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it works").font(.system(.headline, design: .rounded)).accessibilityAddTraits(.isHeader)
            Label("You say what you need and what matters most. By voice works too: “find me a quiet dishwasher”.", systemImage: "1.circle")
            Label("Doddy looks for offers and reads each shop's own page. A price he couldn't confirm there isn't shown, and he says so.", systemImage: "2.circle")
            Label("You get up to three picks with the reason for each, and you can ask Doddy to watch a price.", systemImage: "3.circle")
            Label("The buy button opens the shop's own page in Safari. The shop takes the payment.", systemImage: "4.circle")
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .doddyCard()
    }
}
