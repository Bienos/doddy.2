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

/// User-triggered genuine catalog discovery; merchant checkout remains external.
/// Making a cart/checkout is not a purchase and does not save a card on Doddy.
/// Redesigned 13 Nov 2026 (owner: "Shopify … redesign w środku … wyszukujesz, porównujesz, wyskakują kilka opcji"):
/// an orange hero with the search, a summary of what came back (offers, shops, the price range), sorting, and each
/// product as a card whose offers are compared side by side with the cheapest marked. Every price is Shopify's
/// catalog price as the server returned it; nothing is cached or invented here.
struct ShopifyLiveShoppingView: View {
    private enum Sort: Hashable { case relevance, cheapest }

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var products: [ShopifyProduct] = []
    @State private var messages: [String] = []
    @State private var checkout: ShopifyCheckout?
    @State private var fetching = false
    @State private var preparingVariant: String?
    @State private var error: String?
    @State private var searched = false
    @State private var sort: Sort = .relevance
    @State private var availableOnly = false
    private var polish: Bool { NotificationLanguage.current == .polish }
    private func tr(_ pl: String, _ en: String) -> String { polish ? pl : en }

    /// One product and its offers as shown: cheapest first, and only those in stock when asked.
    private struct ProductOffers: Identifiable {
        let product: ShopifyProduct
        let offers: [ShopifyVariant]
        var id: String { product.id }
    }

    /// The products in the chosen order, each with its offers cheapest first (and only those in stock, when asked).
    private var shown: [ProductOffers] {
        let rows: [ProductOffers] = products.compactMap { product in
            let offers = product.variants
                .filter { !availableOnly || $0.available }
                .sorted { $0.priceMinor < $1.priceMinor }
            return offers.isEmpty ? nil : ProductOffers(product: product, offers: offers)
        }
        guard sort == .cheapest else { return rows }
        return rows.sorted { ($0.offers.first?.priceMinor ?? .max) < ($1.offers.first?.priceMinor ?? .max) }
    }

    private var allOffers: [ShopifyVariant] { shown.flatMap { $0.offers } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DoddyHero(title: tr("Sklepy Shopify", "Shopify shops"),
                              subtitle: tr("Szukam w prawdziwych sklepach Shopify i porównuję oferty. Kupujesz u sprzedawcy.",
                                           "I search real Shopify shops and compare their offers. You buy from the merchant."),
                              pose: .kneelingInspect) {
                        DoddyAskField(placeholder: tr("Czego szukasz? np. kurtka przeciwdeszczowa", "What are you after? e.g. a rain jacket"),
                                      text: $query, systemImage: "bag", isBusy: fetching, identifier: "shopify.search.query") {
                            Task { await search() }
                        }
                    }
                    if fetching {
                        HStack(spacing: 12) {
                            ProgressView().tint(Theme.accentText)
                            Text(verbatim: tr("Szukam ofert sklepów…", "Searching live merchant offers…"))
                        }
                        .doddyCard()
                    }
                    if let error {
                        Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle") }
                            .foregroundStyle(Theme.error)
                            .doddyCard()
                    }
                    if searched && !fetching && products.isEmpty && error == nil {
                        Text(verbatim: tr("Nie znalazłem ofert Shopify dla tego zapytania. Spróbuj innych słów.",
                                          "No Shopify offers found for this search. Try other words."))
                            .doddyCard()
                    }
                    if !products.isEmpty {
                        comparisonSummary
                        DoddyChipRow {
                            DoddyChip(title: tr("Trafność", "Best match"), isSelected: sort == .relevance) { sort = .relevance }
                            DoddyChip(title: tr("Najtaniej", "Cheapest"), systemImage: "arrow.down", isSelected: sort == .cheapest) { sort = .cheapest }
                            DoddyChip(title: tr("Tylko dostępne", "In stock only"), systemImage: "checkmark", isSelected: availableOnly) { availableOnly.toggle() }
                        }
                    }
                    if !messages.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: tr("Uwagi Shopify", "Shopify notices")).font(.footnote.weight(.semibold))
                            ForEach(messages, id: \.self) { message in
                                Text(verbatim: message).font(.footnote)
                            }
                        }
                        .doddyCard()
                    }
                    ForEach(shown) { row in
                        productCard(row.product, offers: row.offers)
                    }
                    DoddyFootnote(text: tr(
                        "Słowa, których szukasz, trafiają na serwer Doddy'ego i stamtąd do usługi Shop firmy Shopify, dopiero gdy dotkniesz szukania. To nie jest porównanie wszystkich sklepów: tylko sklepy Shopify. Ceny są katalogowe; ostateczną kwotę i dostawę podaje sprzedawca. Doddy nie pobiera płatności.",
                        "The words you search for go to Doddy's server and from there to Shopify's Shop service, only when you tap search. This is not a comparison of all shops, only Shopify shops. Prices are catalog prices; the merchant gives the final amount and delivery. Doddy never takes payment."))
                }
                .padding(16)
                .readableColumn()
            }
            .scrollDismissesKeyboard(.interactively)
            .doddyScreen()
            .navigationTitle(tr("Sklepy Shopify", "Shopify shops"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Zamknij", "Close")) { dismiss() }
                }
            }
            .sheet(item: $checkout) { details in
                NavigationStack {
                    List {
                        Section(tr("Sprzedawca", "Merchant")) {
                            Text(details.seller)
                            Text(details.shop).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        if let currency = details.currency {
                            Section(tr("Kwoty podane przez sprzedawcę", "Merchant totals")) {
                                ForEach(Array(details.totals.enumerated()), id: \.offset) { _, line in
                                    HStack {
                                        Text(line.displayText)
                                        Spacer(minLength: 8)
                                        Text(price(line.amount, currency: currency))
                                    }
                                }
                                Text(tr("Dostawa i podatki mogą zmienić się po podaniu adresu.",
                                        "Shipping and tax may change after you enter your address."))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        if !details.links.isEmpty {
                            Section(tr("Warunki sprzedawcy", "Merchant terms and policies")) {
                                ForEach(Array(details.links.enumerated()), id: \.offset) { _, policy in
                                    if let url = URL(string: policy.url), url.scheme == "https" {
                                        Link(destination: url) {
                                            Label(policy.title, systemImage: "arrow.up.right")
                                        }
                                    }
                                }
                            }
                        }
                        if !details.messages.isEmpty {
                            Section(tr("Ważne informacje", "Important information")) {
                                ForEach(details.messages, id: \.self) { Text($0).font(.footnote) }
                            }
                        }
                        Section {
                            if let url = URL(string: details.checkoutURL), url.scheme == "https" {
                                Link(destination: url) {
                                    Label(tr("Dokończ zakup u sprzedawcy", "Continue at merchant checkout"),
                                          systemImage: "arrow.up.right.square")
                                }
                            }
                            Text(tr("Koszyk przygotowany. Nie złożono zamówienia ani nie pobrano pieniędzy.",
                                    "Checkout prepared. No order was placed and no payment was made."))
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .navigationTitle(tr("Twój koszyk", "Your checkout"))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(tr("Zamknij", "Close")) { checkout = nil }
                        }
                    }
                }
            }
        }
    }

    /// "7 offers from 4 shops · 129 zł to 189 zł": what the search found, before the cards.
    private var comparisonSummary: some View {
        let offers = allOffers
        let shops = Set(offers.map(\.shop)).count
        let low = offers.map(\.priceMinor).min()
        let high = offers.map(\.priceMinor).max()
        let currency = offers.first?.currency ?? "PLN"
        let sameCurrency = offers.allSatisfy { $0.currency == currency }
        return HStack(spacing: 12) {
            DoddySymbolTile(systemImage: "chart.bar.xaxis", size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: String(format: tr("Ofert: %lld · sklepów: %lld", "%lld offers · %lld shops"), offers.count, shops))
                    .font(.headline)
                if sameCurrency, let low, let high {
                    Text(verbatim: low == high ? price(low, currency: currency)
                                               : tr("od \(price(low, currency: currency)) do \(price(high, currency: currency))",
                                                    "\(price(low, currency: currency)) to \(price(high, currency: currency))"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .doddyCard(padding: 14)
        .accessibilityElement(children: .combine)
    }

    private func productCard(_ product: ShopifyProduct, offers: [ShopifyVariant]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: product.title)
                .font(.system(.headline, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            if offers.count > 1, let low = offers.first, let high = offers.last, low.currency == high.currency, high.priceMinor > low.priceMinor {
                Text(verbatim: String(format: tr("Różnica między ofertami: %@", "Spread between offers: %@"), price(high.priceMinor - low.priceMinor, currency: low.currency)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
            }
            ForEach(Array(offers.enumerated()), id: \.element.id) { index, variant in
                offerRow(variant, isCheapest: index == 0 && offers.count > 1)
            }
        }
        .doddyCard()
    }

    private func offerRow(_ variant: ShopifyVariant, isCheapest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(verbatim: variant.merchant).font(.subheadline.weight(.semibold))
                        if isCheapest { DoddyTag(text: tr("Najtaniej", "Cheapest"), strong: true) }
                    }
                    if !variant.title.isEmpty {
                        Text(verbatim: variant.title).font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    Text(verbatim: variant.available ? tr("Dostępne", "In stock") : tr("Niedostępne", "Out of stock"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(variant.available ? Theme.confirmed : Theme.secondaryText)
                }
                Spacer(minLength: 8)
                Text(verbatim: price(variant.priceMinor, currency: variant.currency))
                    .font(.system(.title3, design: .rounded, weight: .heavy))
            }
            HStack(spacing: 8) {
                if variant.available {
                    Button {
                        Task { await prepare(variant) }
                    } label: {
                        Label(tr("Przygotuj koszyk", "Prepare checkout"), systemImage: "cart.badge.plus")
                    }
                    .buttonStyle(DoddyInkButtonStyle())
                    .disabled(preparingVariant != nil || fetching)
                    .accessibilityIdentifier("shopify.checkout.\(variant.id)")
                }
                if let raw = variant.productURL, let url = URL(string: raw), url.scheme == "https" {
                    Link(destination: url) {
                        Label(tr("W sklepie", "At the shop"), systemImage: "arrow.up.right")
                    }
                    .buttonStyle(DoddyOutlineButtonStyle())
                }
                if preparingVariant == variant.variantId {
                    ProgressView().tint(Theme.accentText)
                }
            }
        }
        .padding(12)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @MainActor
    private func search() async {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...160).contains(words.count), !fetching, preparingVariant == nil else { return }
        // "Pause all connections" (Settings › Connections) stops a search here as it does everywhere else.
        guard !UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) else {
            error = pausedText
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
            self.error = tr("Nie mogę pobrać ofert Shopify. Sprawdź połączenie lub konto Doddy i spróbuj ponownie.",
                            "Couldn't load Shopify offers. Check your connection and Doddy account, then try again.")
        }
    }

    @MainActor
    private func prepare(_ variant: ShopifyVariant) async {
        guard preparingVariant == nil, !fetching else { return }
        guard !UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) else {
            error = pausedText
            return
        }
        preparingVariant = variant.variantId
        error = nil
        defer { preparingVariant = nil }
        do {
            checkout = try await ShopifyLiveClient.prepare(variant)
        } catch {
            self.error = tr(
                "Nie udało się utworzyć koszyka u sprzedawcy. Nic nie zostało kupione. Wróć do wyników lub spróbuj wyszukać produkt ponownie.",
                "The merchant couldn't create a checkout. Nothing was purchased. Search again or view the merchant's store."
            )
        }
    }

    private var pausedText: String {
        tr("Połączenia są wstrzymane (Ustawienia › Połączenia), więc nic nie wysyłam do sklepów Shopify.",
           "Connections are paused (Settings › Connections), so nothing is sent to Shopify shops.")
    }

    private func price(_ minor: Int, currency: String) -> String {
        // ISO 4217 minor units are not always hundredths (JPY: 0, KWD: 3).
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let places = max(0, min(3, formatter.maximumFractionDigits))
        let amount = Double(minor) / pow(10, Double(places))
        return formatter.string(from: NSNumber(value: amount)) ?? "\(minor) \(currency)"
    }
}
