import DoddyCore
import SwiftUI

// One kind of shop (owner, 13 Nov 2026: "jedzeniowe oddzielnie, ciuchowe oddzielnie, inne oddzielnie, i one powinny
// mieć bardziej rozbudowane, co można zrobić"). Pushed from the Shopping screen's tiles. What it holds, all from
// paths that already exist:
//   - for groceries, "This week's deals" first: the leaflets and "cheapest this week" as one screen (DealsScreen);
//   - "Find me this" scoped to the kind (the kind is a line under the words, shown on the yes card);
//   - what Doddy can do here, and the shops by name with what Doddy does at each (ShopDirectory in DoddyCore: the
//     leaflet chains and Shopify's catalogue; nothing Doddy can't reach);
//   - Shopify's search for every kind but groceries;
//   - the watched prices of this kind (a watch's kind is read from the task its pick came from, or its chain).
// Nothing is bought here; every price shown elsewhere is one the server read on a shop's page or leaflet.

struct ShoppingCategoryView: View {
    let category: ShopCategory
    private let errands = ErrandsModel.shared
    private let watches = WatchModel.shared
    @State private var showShopify = false

    init(category: ShopCategory) {
        self.category = category
    }

    private var scope: ReleaseScope { ReleaseScopeStore.current }
    private var shops: [ShopListing] { ShopDirectory.shops(in: category, shopify: scope.shows(.shopifyShopping)) }

    var body: some View {
        DoddyPage {
            header
            if category == .groceries && scope.shows(.deals) {
                ShoppingDealsCard()
            }
            if !errands.isServerConfigured {
                DoddyNotice(text: Text("Doddy's server isn't set up in this build, so tasks can't run yet."), isProblem: true)
            }
            if scope.shows(.errands) {
                ShoppingFindCard(category: category)
            }
            abilities
            shopsSection
            if category != .groceries && scope.shows(.shopifyShopping) {
                DoddyLinkRow(systemImage: "bag", title: "Search Shopify shops",
                             subtitle: "Products of shops that sell through Shopify, with a cart prepared at the shop. You pay there.") {
                    showShopify = true
                }
                .accessibilityIdentifier("shopping.shopify")
            }
            if scope.shows(.priceWatch) {
                watchedSection
            }
            finePrint
        }
        .navigationTitle(Text(verbatim: category.title))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShopify) { ShopifyLiveShoppingView() }
        .task {
            if scope.shows(.priceWatch) && !watches.hasLoaded { await watches.refresh() }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if category == .groceries {
            DoddyPageHeader(eyebrow: "Shopping", title: LocalizedStringKey(category.title),
                            subtitle: "This week's leaflets, the cheapest shop for each thing on your list, and anything else found for you.")
        } else {
            DoddyPageHeader(eyebrow: "Shopping", title: LocalizedStringKey(category.title),
                            subtitle: "Doddy looks across shops in Poland, puts up to three picks side by side and can watch a price for you.")
        }
    }

    // MARK: What Doddy can do here

    private var abilities: some View {
        VStack(alignment: .leading, spacing: 12) {
            DoddySectionTitle(title: "What Doddy can do here")
            VStack(alignment: .leading, spacing: 14) {
                if scope.shows(.errands) {
                    CapabilityRow(systemImage: "magnifyingglass", title: "Find and compare",
                                  subtitle: "Up to three picks from shops in Poland, each price read on the shop's own page, with the reason for each.")
                }
                if scope.shows(.priceWatch) {
                    CapabilityRow(systemImage: "bell", title: "Hunt for a deal",
                                  subtitle: "Give your price on a pick or a pasted link; Doddy tells you once when the shop's page shows it or less.")
                }
                if category == .groceries && scope.shows(.deals) {
                    CapabilityRow(systemImage: "newspaper", title: "Leaflets",
                                  subtitle: "Doddy reads the chains' leaflets and shows where each thing on your list is cheapest.")
                }
                if category != .groceries && scope.shows(.shopifyShopping) {
                    CapabilityRow(systemImage: "cart.badge.plus", title: "Search and cart",
                                  subtitle: "In Shopify shops: a cart prepared at the shop. No order is placed and Doddy takes no payment.")
                }
            }
            .doddyCard()
        }
    }

    // MARK: The shops by name

    @ViewBuilder
    private var shopsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DoddySectionTitle(title: "Shops by name")
            if shops.isEmpty || shops == [ShopListing.shopify] {
                Text("No shop of this kind is connected by name yet. “Find me this” looks across shops in Poland that Google Shopping lists and reads their own pages.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !shops.isEmpty {
                ChipFlow(spacing: 8) {
                    ForEach(shops) { shop in
                        ShopChip(shop: shop)
                    }
                }
                .accessibilityIdentifier("shopping.shops")
            }
        }
    }

    // MARK: Watched prices of this kind

    /// The watches whose kind is this one. Read from the tasks and watches already on this iPhone.
    private var watchedHere: Set<UUID> {
        let mine = watches.watches.filter { watch in
            ShopDirectory.category(ofWatchedPage: watch.url, shop: watch.shop, in: errands.errands) == category
        }
        return Set(mine.map(\.id))
    }

    private var watchedSection: some View {
        let ids = watchedHere
        return VStack(alignment: .leading, spacing: 10) {
            DoddySectionTitle(title: "Watched prices here")
            if ids.isEmpty {
                Text("Nothing of this kind is watched yet. On a pick, tap “Watch the price” and give the price you'd pay.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .doddyCard()
                    .accessibilityIdentifier("shopping.categoryWatchHint")
            } else {
                WatchesSection(showsHeading: false, only: ids)
            }
        }
    }

    // MARK: Fine print

    private var finePrint: some View {
        VStack(alignment: .leading, spacing: 6) {
            DoddyFinePrint(text: Text("“Find me this” sends your words, what matters most and this kind to Doddy's server and to Anthropic, whose Claude does the research, only after you say yes. Search phrases go to Google Shopping through Serper, and Doddy's server opens shops' pages."))
            if category == .groceries && scope.shows(.deals) {
                DoddyFinePrint(text: Text("Leaflets: your items go to Doddy's server, which answers from the shops' own leaflets and uses Anthropic's Claude to read them. Nothing that identifies you goes to a shop."))
            }
            if category != .groceries && scope.shows(.shopifyShopping) {
                DoddyFinePrint(text: Text("Shopify: the words you search for go to Doddy's server and from there to Shopify's Shop service, only when you tap search."))
            }
        }
    }
}

// MARK: - The groceries' "This week's deals" card

/// The way into "This week's deals" on the groceries page, with the last check's numbers when there is one in memory.
struct ShoppingDealsCard: View {
    private let model = DealsModel.shared

    private var readCount: Int { ShopDirectory.chains(in: .groceries).filter(\.isRead).count }

    var body: some View {
        NavigationLink {
            DealsScreen()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    DoddyIconBadge(systemName: "newspaper", size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("This week's deals")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text(verbatim: String(format: NSLocalizedString("The leaflets of %lld shops and where each thing on your list is cheapest, in one place.", comment: "the groceries' deals card"), readCount))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let result = model.lastResult {
                    Text(verbatim: String(format: NSLocalizedString("Your last check: %lld items, %lld leaflets read.", comment: "kept in memory until Doddy closes"),
                                          result.items.count, result.readChainCount))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                HStack(spacing: 8) {
                    Text("Open this week's deals")
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
                .font(.headline)
                .foregroundStyle(Theme.inkOnOrange)
                .padding(.horizontal, 18)
                .frame(minHeight: 52)
                .background(Theme.orangeCue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .doddyCard(padding: 18, accent: true)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shopping.deals")
    }
}

// MARK: - Parts

/// One thing Doddy can do: an icon, a name and a line.
private struct CapabilityRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DoddyIconBadge(systemName: systemImage, size: 34, filled: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.footnote).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A shop's name, no logo, with what Doddy does there underneath.
private struct ShopChip: View {
    let shop: ShopListing

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: shop.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(verbatim: shop.capabilities.map(\.words).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Words for the kinds

extension ShopCategory {
    /// The kind's name on the screen.
    var title: String {
        switch self {
        case .groceries: NSLocalizedString("Groceries & household", comment: "a kind of shop")
        case .fashion: NSLocalizedString("Fashion & shoes", comment: "a kind of shop")
        case .electronics: NSLocalizedString("Electronics", comment: "a kind of shop")
        case .home: NSLocalizedString("Home & garden", comment: "a kind of shop")
        case .other: NSLocalizedString("Other", comment: "a kind of shop")
        }
    }

    /// What the kind covers, on its tile.
    var line: String {
        switch self {
        case .groceries: NSLocalizedString("Food, drugstore and cleaning", comment: "a kind of shop's tile")
        case .fashion: NSLocalizedString("Clothes, shoes and accessories", comment: "a kind of shop's tile")
        case .electronics: NSLocalizedString("Phones, laptops, TV and audio", comment: "a kind of shop's tile")
        case .home: NSLocalizedString("Furniture, decor, tools and garden", comment: "a kind of shop's tile")
        case .other: NSLocalizedString("Pets, toys, sport and the rest", comment: "a kind of shop's tile")
        }
    }

    var symbol: String {
        switch self {
        case .groceries: "cart"
        case .fashion: "tshirt"
        case .electronics: "headphones"
        case .home: "house"
        case .other: "square.grid.2x2"
        }
    }
}

extension ShopCapability {
    /// Under a shop's name: what Doddy does there.
    var words: String {
        switch self {
        case .leaflet: NSLocalizedString("leaflet", comment: "what Doddy does at a shop")
        case .onlyItsKind: NSLocalizedString("for its kind of items", comment: "what Doddy does at a shop")
        case .leafletLink: NSLocalizedString("link to its leaflet", comment: "what Doddy does at a shop")
        case .searchAndCart: NSLocalizedString("search & cart", comment: "what Doddy does at a shop")
        }
    }
}
