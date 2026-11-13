import DoddyCore
import SwiftUI

// Shopping in one place (owner, 11 Nov 2026: "skończ co już mamy"; docs/strategy/SKLEP_PROPOZYCJA_2026-11.md), redrawn
// in Doddy's colours on 13 Nov 2026 (owner: "trzeba trochę poprawić … jedzeniowe oddzielnie, ciuchowe oddzielnie,
// inne oddzielnie"). Nothing here is a new capability; it gathers what already existed:
//   - "Find me this" (docs/implementation/SHOPPING.md 1) as the hero: the words and what matters most, and the same yes
//     card as a typed task, which shows exactly what goes to Doddy's server (ShoppingFindCard);
//   - five kinds of shop (ShopCategory, DoddyCore): groceries first, whose page holds this week's deals (the leaflets
//     and "cheapest this week" as one screen), then fashion, electronics, home and other, each with its own page;
//   - the shopping tasks already handed over, with their state; a tap opens the result, its picks and "Compare";
//   - watched prices (SHOPPING_WATCH.md), the same section as on Tasks: "hunting for a deal";
//   - "Check this": a pasted or shared product link, whose price Doddy's server reads only after a tap.
// Every price shown is one the server confirmed on a shop's own page; this screen writes none itself.

struct ShoppingHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    private let model = ErrandsModel.shared
    private let watches = WatchModel.shared
    @State private var opened: UUID?
    /// "Check this": the link being pasted, the person's own name for the product, and the page whose card is open.
    @State private var link = ""
    @State private var linkName = ""
    @State private var watchPage: SharedShopPage?

    /// Set when a link arrives from the Share Sheet, so the screen scrolls to the "Check this" card.
    @State private var scrollToCheckThis = false

    private var router: ShortcutRouter { .shared }
    private var scope: ReleaseScope { ReleaseScopeStore.current }
    private var shoppingTasks: [StoredErrand] { model.errands.filter { $0.draft.kind == .shopping } }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                DoddyPage {
                    header
                    if !model.isServerConfigured {
                        DoddyNotice(text: Text("Doddy's server isn't set up in this build, so tasks can't run yet."), isProblem: true)
                    }
                    if scope.shows(.errands) {
                        ShoppingFindCard(category: nil)
                    }
                    kinds
                    if scope.shows(.errands) && !shoppingTasks.isEmpty {
                        searches
                    }
                    if scope.shows(.priceWatch) {
                        watched
                        checkThisCard.id(Self.checkThisCardID)
                    }
                    howItWorks
                    DoddyFinePrint(text: Text("Doddy never buys or pays. “Buy at” opens the shop's own page in Safari, and the shop takes the payment."))
                }
                .navigationTitle("Shopping")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .navigationDestination(item: $opened) { id in ErrandDetailView(id: id) }
                .navigationDestination(for: ShopCategory.self) { category in ShoppingCategoryView(category: category) }
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

    private var header: some View {
        DoddyPageHeader(eyebrow: "Shopping", title: "What are you looking for?",
                        subtitle: "I look through shops in Poland, put up to three picks side by side and watch prices for you. You buy in the shop; I never pay.",
                        pose: .kneelingInspect)
    }

    // MARK: Kinds of shop

    /// Groceries first and wide (its page holds this week's deals), then the other four two by two.
    private var kinds: some View {
        VStack(alignment: .leading, spacing: 12) {
            DoddySectionTitle(title: "Shop by kind")
            NavigationLink(value: ShopCategory.groceries) {
                KindTile(category: .groceries, highlight: true, names: names(of: .groceries))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("shopping.leaflets")
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(Self.otherKinds) { category in
                    NavigationLink(value: category) {
                        KindTile(category: category, highlight: false, names: names(of: category))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shopping.kind.\(category.rawValue)")
                }
            }
        }
    }

    private static let otherKinds: [ShopCategory] = [.fashion, .electronics, .home, .other]

    private var columns: [GridItem] {
        textSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    /// The shops by name on a tile (data: the shops' own names).
    private func names(of category: ShopCategory) -> String {
        ShopDirectory.shops(in: category, shopify: scope.shows(.shopifyShopping)).map(\.name).joined(separator: " · ")
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
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    // MARK: Watched prices

    @ViewBuilder
    private var watched: some View {
        VStack(alignment: .leading, spacing: 10) {
            DoddySectionTitle(title: "Watched prices")
            Text("Hunting for a deal: give the price you'd pay, and Doddy's server reads the shop's page a few times a day and tells you once when it's that or less. It never buys anything.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if watches.watches.isEmpty && watches.loadProblem == nil && watches.message == nil {
                watchHint
            } else {
                WatchesSection(showsHeading: false)
            }
        }
    }

    /// Shown while nothing is watched: where a watch starts. It says nothing about whether one is on.
    private var watchHint: some View {
        Label("Open a result and tap “Watch the price” on a pick, or paste a product link below.", systemImage: "bell")
            .font(.subheadline)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .doddyCard()
            .accessibilityIdentifier("shopping.watchHint")
    }

    // MARK: Check this

    /// The page in the pasted text, with the person's own name for it. Nothing has been sent: reading the text is
    /// done here, and Doddy's server gets the page only when the card's own button says "Check the page".
    private var pastedPage: SharedShopPage? {
        SharedShopPage.parse(link)?.titled(linkName)
    }

    private var checkThisCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                DoddyIconBadge(systemName: "link", size: 40, filled: false)
                Text("Check this")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Text("Paste the link to a product you're looking at in a shop. Doddy's server reads the page and shows its price; then you can ask Doddy to watch it.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Product link", text: $link, prompt: Text(verbatim: "https://…"), axis: .vertical)
                .lineLimit(1...3)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .doddyField()
                .accessibilityIdentifier("shopping.link")
            pastedPageLines
            Button {
                watchPage = pastedPage
            } label: {
                Label("Check this page", systemImage: "magnifyingglass")
            }
            .buttonStyle(DoddyAccentButtonStyle())
            .disabled(pastedPage == nil || !model.isServerConfigured)
            .accessibilityIdentifier("shopping.checkThis")
            DoddyFinePrint(text: Text("Nothing is sent until you tap “Check the page” on the next card. Some shops don't let Doddy's server read their pages; then Doddy tells you it couldn't read a price."))
        }
        .doddyCard(padding: 18)
    }

    @ViewBuilder
    private var pastedPageLines: some View {
        if let page = pastedPage {
            Label(String(format: NSLocalizedString("Page at %@", comment: "the shop a pasted link points to"), page.shop),
                  systemImage: "link")
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
            TextField("What is it? (optional)", text: $linkName)
                .font(.subheadline)
                .doddyField()
                .accessibilityIdentifier("shopping.linkName")
        } else if !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Label("That isn't a web address Doddy can read. It must start with https://.", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(Theme.error)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: How it works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 10) {
            DoddySectionTitle(title: "How it works")
            VStack(alignment: .leading, spacing: 10) {
                Label("You say what you need and what matters most. By voice works too: “find me a quiet dishwasher”.", systemImage: "1.circle")
                Label("Doddy looks for offers and reads each shop's own page. A price he couldn't confirm there isn't shown, and he says so.", systemImage: "2.circle")
                Label("You get up to three picks with the reason for each, side by side in “Compare”, and you can ask Doddy to watch a price.", systemImage: "3.circle")
                Label("The buy button opens the shop's own page in Safari. The shop takes the payment.", systemImage: "4.circle")
            }
            .font(.footnote)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .doddyCard()
        }
    }
}

/// One kind of shop on the Shopping screen: an icon, its name, what it covers and the shops by name.
private struct KindTile: View {
    let category: ShopCategory
    let highlight: Bool
    /// The shops' own names, joined; empty when the kind has none by name.
    let names: String

    private var titleStyle: Font.TextStyle { highlight ? .title3 : .headline }
    private var badgeSize: CGFloat { highlight ? 46 : 38 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                DoddyIconBadge(systemName: category.symbol, size: badgeSize, filled: highlight)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            Text(verbatim: category.title)
                .font(.system(titleStyle, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
            Text(verbatim: category.line)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if highlight {
                Label("This week's deals: leaflets and the cheapest shop for your list", systemImage: "newspaper")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !names.isEmpty {
                Text(verbatim: names)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(highlight ? 3 : 2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .doddyCard(padding: 16, accent: highlight)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
