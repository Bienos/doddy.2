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
struct ShopifyLiveShoppingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var products: [ShopifyProduct] = []
    @State private var messages: [String] = []
    @State private var checkout: ShopifyCheckout?
    @State private var fetching = false
    @State private var preparingVariant: String?
    @State private var error: String?
    @State private var searched = false
    private var polish: Bool { NotificationLanguage.current == .polish }
    private func tr(_ pl: String, _ en: String) -> String { polish ? pl : en }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(tr(
                        "Prawdziwe produkty sklepów Shopify, dostępne według danych dostawcy. Cenę końcową i dostawę potwierdzisz u sprzedawcy. Doddy nie pobiera płatności.",
                        "Real Shopify merchant listings. Price and delivery are confirmed by the merchant at checkout. Doddy never takes payment."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    Text(tr(
                        "Słowa, których szukasz, trafiają na serwer Doddy'ego i stamtąd do usługi Shop firmy Shopify, dopiero gdy dotkniesz szukania. To nie jest porównanie wszystkich sklepów: tylko sklepy Shopify.",
                        "The words you search for go to Doddy's server and from there to Shopify's Shop service, only when you tap search. This is not a comparison of all shops, only Shopify shops."
                    ))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)

                    HStack(spacing: 10) {
                        TextField(tr("Czego szukasz?", "What are you shopping for?"), text: $query)
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                            .accessibilityIdentifier("shopify.search.query")
                        Button {
                            Task { await search() }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.body.weight(.semibold))
                        }
                        .disabled(fetching || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                        .accessibilityIdentifier("shopify.search.submit")
                    }
                }

                if fetching {
                    ProgressView(tr("Szukam ofert sklepów…", "Searching live merchant offers…"))
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.error) }
                }
                if searched && !fetching && products.isEmpty && error == nil {
                    Section {
                        Text(tr("Nie znalazłem ofert Shopify dla tego zapytania. Spróbuj innych słów.",
                                "No Shopify offers found for this search. Try other words."))
                    }
                }

                if !messages.isEmpty {
                    Section(tr("Uwagi Shopify", "Shopify notices")) {
                        ForEach(messages, id: \.self) { message in
                            Text(message).font(.footnote)
                        }
                    }
                }

                ForEach(products) { product in
                    Section(product.title) {
                        ForEach(product.variants) { variant in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(variant.merchant).font(.subheadline.weight(.semibold))
                                        if !variant.title.isEmpty {
                                            Text(variant.title).font(.caption).foregroundStyle(Theme.secondaryText)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    Text(price(variant.priceMinor, currency: variant.currency))
                                        .font(.subheadline.weight(.semibold))
                                }
                                Text(tr("Cena katalogowa. Ostateczną kwotę wylicza sprzedawca.",
                                        "Catalog price. The merchant calculates the final amount."))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.secondaryText)
                                HStack(spacing: 12) {
                                    if variant.available {
                                        Button {
                                            Task { await prepare(variant) }
                                        } label: {
                                            Label(tr("Przygotuj koszyk", "Prepare checkout"), systemImage: "cart.badge.plus")
                                        }
                                        .disabled(preparingVariant != nil || fetching)
                                        .accessibilityIdentifier("shopify.checkout.\(variant.id)")
                                    }
                                    if let raw = variant.productURL, let url = URL(string: raw), url.scheme == "https" {
                                        Link(destination: url) {
                                            Label(tr("Zobacz w sklepie", "View at merchant"), systemImage: "arrow.up.right")
                                        }
                                    }
                                }
                                .font(.footnote.weight(.medium))
                                if preparingVariant == variant.variantId {
                                    ProgressView()
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
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
