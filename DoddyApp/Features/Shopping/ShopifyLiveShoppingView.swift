import DoddyCore
import Foundation
import SwiftUI

// Live Shopify commerce via Doddy's authenticated backend and Shop MCP (UCP).
// NO locally invented products, cached prices, payment tokens or order placement.
// Opened from the Shopping screen ("Shopify shops", docs/implementation/SHOPPING.md "Shopify"). The screen and the server
// route come from PR #332; the voice tools that PR also holds are not part of this.
struct ShopifyResult: Decodable, Sendable {
    let products: [ShopifyProduct]
    let messages: [String]
    let source: String
    let market: String
}
struct ShopifyProduct: Decodable, Identifiable, Sendable {
    let productId: String
    let title: String
    let variants: [ShopifyVariant]
    var id: String { productId }
}
struct ShopifyVariant: Decodable, Identifiable, Sendable {
    let variantId: String
    let title: String
    let merchant: String
    let shop: String
    let priceMinor: Int
    let currency: String
    let available: Bool
    let productURL: String?
    var id: String { variantId }
}
struct ShopifyCheckoutTotal: Decodable, Sendable {
    let type: String
    let displayText: String
    let amount: Int
}
struct ShopifyCheckoutLink: Decodable, Sendable {
    let type: String
    let title: String
    let url: String
}
struct ShopifyCheckout: Decodable, Identifiable, Sendable {
    let checkoutURL: String
    let shop: String
    let seller: String
    let currency: String?
    let totalMinor: Int?
    let messages: [String]
    let totals: [ShopifyCheckoutTotal]
    let links: [ShopifyCheckoutLink]
    let status: String
    var id: String { checkoutURL }
}

enum ShopifyLiveClient {
    struct Search: Encodable { let query: String }
    struct Prepare: Encodable {
        let variantId: String
        let shop: String
        let quantity: Int
    }
    enum Problem: Error { case unavailable, signIn, invalidReply, server }

    @MainActor
    static func call<Body: Encodable, Result: Decodable>(path: String, body: Body) async throws -> Result {
        guard let server = DeviceSession.serverURL() else { throw Problem.unavailable }
        await DeviceSession.ensure(server: server)
        guard let token = KeychainSessionStore.read()?.token(for: server), !token.isEmpty else { throw Problem.signIn }
        let data = try JSONEncoder().encode(body)
        let request = HTTPRequest(
            method: "POST",
            url: server.appendingPathComponent(path),
            headers: ["authorization": "Bearer \(token)", "accept": "application/json", "content-type": "application/json"],
            body: data
        )
        let result = try await URLSessionTransport.shared.send(request)
        guard result.status == 200 else { throw Problem.server }
        guard let decoded = try? JSONDecoder().decode(Result.self, from: result.body) else { throw Problem.invalidReply }
        return decoded
    }

    @MainActor
    static func search(_ query: String) async throws -> ShopifyResult {
        try await call(path: "v1/shopify/search", body: Search(query: query))
    }

    @MainActor
    static func prepare(_ variant: ShopifyVariant, quantity: Int = 1) async throws -> ShopifyCheckout {
        guard (1...10).contains(quantity) else { throw Problem.invalidReply }
        return try await call(path: "v1/shopify/checkout",
                              body: Prepare(variantId: variant.variantId, shop: variant.shop, quantity: quantity))
    }
}

// The screen, redrawn in Doddy's colours on 13 Nov 2026 (owner: "ten sklep Shopify trzeba zrobić redesign w środku"):
// a search field with the orange button, the products as a grid of cards (title, price or "from" price, how many
// shops offer it), a product's page with each shop's offer side by side (the lowest marked only from the prices
// Shopify returned, in one currency), and the cart sheet. The calls are the same two (`ShopifyLiveClient`); Shopify
// returns no product picture to Doddy's server, so the cards show none rather than a made-up one.

/// User-triggered genuine catalog discovery; merchant checkout remains external.
/// Making a cart/checkout is not a purchase and does not save a card on Doddy.
struct ShopifyLiveShoppingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var query = ""
    @State private var products: [ShopifyProduct] = []
    @State private var messages: [String] = []
    @State private var fetching = false
    @State private var error: String?
    @State private var searched = false
    @FocusState private var typing: Bool

    private var canSearch: Bool {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !fetching && (2...160).contains(words.count)
    }

    var body: some View {
        NavigationStack {
            DoddyPage {
                DoddyPageHeader(eyebrow: "Shopping", title: "Shopify shops",
                                subtitle: "Real products of shops that sell through Shopify. Doddy can prepare a cart at the shop; you finish and pay there.")
                searchCard
                if fetching {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Searching live merchant offers…").font(.subheadline).foregroundStyle(Theme.ink)
                    }
                    .doddyCard()
                }
                if let error {
                    DoddyNotice(text: Text(verbatim: error), isProblem: true)
                }
                if searched && !fetching && products.isEmpty && error == nil {
                    DoddyNotice(text: Text("No Shopify offers found for this search. Try other words."))
                }
                if !messages.isEmpty {
                    notices
                }
                if !products.isEmpty {
                    grid
                }
                DoddyFinePrint(text: Text("The words you search for go to Doddy's server and from there to Shopify's Shop service, only when you tap search. This is not a comparison of all shops, only Shopify shops. Prices are the shops' catalogue prices; the shop works out the final amount."))
            }
            .navigationTitle("Shopify shops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(for: ShopifyProductPage.self) { page in
                ShopifyProductView(product: page.product)
            }
        }
    }

    // MARK: Search

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("What are you shopping for?", text: $query)
                .font(.body)
                .submitLabel(.search)
                .focused($typing)
                .onSubmit { Task { await search() } }
                .doddyField()
                .accessibilityIdentifier("shopify.search.query")
            Button {
                typing = false
                Task { await search() }
            } label: {
                Label("Search Shopify shops", systemImage: "magnifyingglass")
            }
            .buttonStyle(DoddyAccentButtonStyle())
            .disabled(!canSearch)
            .accessibilityIdentifier("shopify.search.submit")
        }
        .doddyCard(padding: 18, accent: true)
    }

    private var notices: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shopify notices").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            ForEach(messages, id: \.self) { message in
                Text(verbatim: message).font(.footnote).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .doddyCard()
    }

    // MARK: Products

    private var columns: [GridItem] {
        textSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 12) {
            DoddySectionTitle(title: "Found in Shopify shops")
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(products) { product in
                    NavigationLink(value: ShopifyProductPage(product: product)) {
                        ShopifyProductCard(product: product)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shopify.product")
                }
            }
        }
    }

    @MainActor
    private func search() async {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...160).contains(words.count), !fetching else { return }
        // "Pause all connections" (Settings › Connections) stops a search here as it does everywhere else.
        guard !UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) else {
            error = ShopifyText.paused
            return
        }
        fetching = true
        searched = false
        error = nil
        products = []
        messages = []
        defer { fetching = false; searched = true }
        do {
            let found = try await ShopifyLiveClient.search(words)
            products = found.products
            messages = found.messages
        } catch {
            self.error = NSLocalizedString("Couldn't load Shopify offers. Check your connection and Doddy account, then try again.", comment: "")
        }
    }
}

/// A product's page, pushed by value.
private struct ShopifyProductPage: Hashable {
    let product: ShopifyProduct

    static func == (lhs: ShopifyProductPage, rhs: ShopifyProductPage) -> Bool { lhs.product.productId == rhs.product.productId }
    func hash(into hasher: inout Hasher) { hasher.combine(product.productId) }
}

/// Prices and counts the code works out from what Shopify returned; nothing is guessed.
enum ShopifyText {
    static var paused: String {
        NSLocalizedString("Connections are paused (Settings › Connections), so nothing is sent to Shopify shops.", comment: "")
    }

    /// ISO 4217 minor units are not always hundredths (JPY: 0, KWD: 3).
    static func price(_ minor: Int, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let places = max(0, min(3, formatter.maximumFractionDigits))
        let amount = Double(minor) / pow(10, Double(places))
        return formatter.string(from: NSNumber(value: amount)) ?? "\(minor) \(currency)"
    }

    /// The available offers in the first available offer's currency (prices in another currency aren't compared).
    static func comparable(_ product: ShopifyProduct) -> [ShopifyVariant] {
        let available = product.variants.filter(\.available)
        guard let currency = available.first?.currency else { return [] }
        return available.filter { $0.currency == currency }
    }

    /// The lowest available price, and whether the offers' prices differ (then the card says "from").
    static func lowest(_ product: ShopifyProduct) -> (variant: ShopifyVariant, differs: Bool)? {
        let offers = comparable(product)
        guard let low = offers.min(by: { $0.priceMinor < $1.priceMinor }) else { return nil }
        let differs = offers.contains { $0.priceMinor != low.priceMinor }
        return (variant: low, differs: differs)
    }

    /// The shops offering it, by name, each once.
    static func merchants(_ product: ShopifyProduct) -> [String] {
        var seen = Set<String>()
        return product.variants.map(\.merchant).filter { seen.insert($0).inserted }
    }
}

/// One product in the grid: no picture (Shopify's answer to Doddy's server carries none), its title, the price or
/// the lowest available price, and the shop or how many shops offer it.
private struct ShopifyProductCard: View {
    let product: ShopifyProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DoddyIconBadge(systemName: "bag", size: 34, filled: false)
            Text(verbatim: product.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
            priceLine
            Text(verbatim: shopsLine)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .doddyCard(padding: 14)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var priceLine: some View {
        if let lowest = ShopifyText.lowest(product) {
            let text = ShopifyText.price(lowest.variant.priceMinor, currency: lowest.variant.currency)
            Text(verbatim: lowest.differs ? String(format: NSLocalizedString("from %@", comment: "the lowest of several prices"), text) : text)
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .foregroundStyle(Theme.ink)
        } else {
            Text("Not available now")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var shopsLine: String {
        let names = ShopifyText.merchants(product)
        if names.count == 1, let name = names.first { return name }
        return String(format: NSLocalizedString("Offered by %lld shops", comment: "Shopify shops offering one product"), names.count)
    }
}

/// A product's page: each shop's offer (variant) with its catalogue price, and "Prepare checkout" on an available one.
private struct ShopifyProductView: View {
    let product: ShopifyProduct
    @State private var checkout: ShopifyCheckout?
    @State private var preparingVariant: String?
    @State private var error: String?

    private var lowestID: String? {
        let offers = ShopifyText.comparable(product)
        guard offers.count > 1, let low = ShopifyText.lowest(product), low.differs else { return nil }
        return low.variant.variantId
    }

    var body: some View {
        DoddyPage {
            VStack(alignment: .leading, spacing: 6) {
                Text("Shopify shops").textCase(.uppercase)
                    .font(.caption2.weight(.semibold)).tracking(1.2)
                    .foregroundStyle(Theme.secondaryText)
                Text(verbatim: product.title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Catalog price. The merchant calculates the final amount.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                DoddyNotice(text: Text(verbatim: error), isProblem: true)
            }
            ForEach(product.variants) { variant in
                ShopifyOfferCard(variant: variant, isLowest: variant.variantId == lowestID,
                                 preparing: preparingVariant == variant.variantId,
                                 busy: preparingVariant != nil) {
                    Task { await prepare(variant) }
                }
            }
            DoddyFinePrint(text: Text("“Prepare checkout” sends that offer's variant, the shop's address and the quantity to Doddy's server and from there to Shopify, so the shop can make a cart. It places no order and takes no payment."))
        }
        .navigationTitle(Text(verbatim: product.title))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $checkout) { details in
            ShopifyCartSheet(details: details)
        }
    }

    @MainActor
    private func prepare(_ variant: ShopifyVariant) async {
        guard preparingVariant == nil else { return }
        guard !UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) else {
            error = ShopifyText.paused
            return
        }
        preparingVariant = variant.variantId
        error = nil
        defer { preparingVariant = nil }
        do {
            checkout = try await ShopifyLiveClient.prepare(variant)
        } catch {
            self.error = NSLocalizedString("The merchant couldn't create a checkout. Nothing was purchased. Search again or view the merchant's store.", comment: "")
        }
    }
}

/// One shop's offer of a product.
private struct ShopifyOfferCard: View {
    let variant: ShopifyVariant
    let isLowest: Bool
    let preparing: Bool
    let busy: Bool
    let prepare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: variant.merchant).font(.headline).foregroundStyle(Theme.ink)
                    if !variant.title.isEmpty {
                        Text(verbatim: variant.title).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 8)
                Text(verbatim: ShopifyText.price(variant.priceMinor, currency: variant.currency))
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            }
            if isLowest {
                Label("Lowest price here", systemImage: "arrow.down.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.inkOnOrange)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.orangeCue, in: Capsule())
            }
            if !variant.available {
                Text("Not available now").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            }
            if variant.available {
                Button(action: prepare) {
                    if preparing {
                        ProgressView().tint(Theme.inkOnOrange)
                    } else {
                        Label("Prepare checkout", systemImage: "cart.badge.plus")
                    }
                }
                .buttonStyle(DoddyAccentButtonStyle())
                .disabled(busy)
                .accessibilityIdentifier("shopify.checkout.\(variant.id)")
            }
            if let raw = variant.productURL, let url = URL(string: raw), url.scheme == "https" {
                Link(destination: url) {
                    Label("View at merchant", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1) }
                }
            }
        }
        .doddyCard(padding: 16, accent: isLowest)
    }
}

/// The cart the shop made: the merchant, the totals it gave, its terms, its messages, and the link to finish at the
/// shop. Nothing was ordered or paid: the screen says so, because the server's status is "awaiting the buyer".
private struct ShopifyCartSheet: View {
    let details: ShopifyCheckout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DoddyPage {
                DoddyPageHeader(eyebrow: "Shopify shops", title: "Your checkout",
                                subtitle: "Checkout prepared. No order was placed and no payment was made.")
                merchant
                if let currency = details.currency {
                    totals(currency)
                }
                if !details.links.isEmpty {
                    policies
                }
                if !details.messages.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Important information").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                        ForEach(details.messages, id: \.self) { message in
                            Text(verbatim: message).font(.footnote).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .doddyCard()
                }
                if let url = URL(string: details.checkoutURL), url.scheme == "https" {
                    Link(destination: url) {
                        Label("Continue at merchant checkout", systemImage: "arrow.up.right.square")
                            .font(.headline)
                            .foregroundStyle(Theme.inkOnOrange)
                            .padding(.horizontal, 18)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.orangeCue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                DoddyFinePrint(text: Text("You finish and pay on the shop's own page. Doddy doesn't see the payment."))
            }
            .navigationTitle("Your checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var merchant: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Merchant").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            Text(verbatim: details.seller).font(.headline).foregroundStyle(Theme.ink)
            Text(verbatim: details.shop).font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .doddyCard()
    }

    private func totals(_ currency: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Merchant totals").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            ForEach(Array(details.totals.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: line.displayText).font(.subheadline).foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    Text(verbatim: ShopifyText.price(line.amount, currency: currency))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                }
            }
            Text("Shipping and tax may change after you enter your address.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .doddyCard()
    }

    private var policies: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Merchant terms and policies").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            ForEach(Array(details.links.enumerated()), id: \.offset) { _, policy in
                if let url = URL(string: policy.url), url.scheme == "https" {
                    Link(destination: url) {
                        Label(policy.title, systemImage: "arrow.up.right")
                            .font(.subheadline)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                }
            }
        }
        .doddyCard()
    }
}
