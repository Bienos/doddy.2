import Foundation

// Shopping by kind of shop (owner, 13 Nov 2026: "jedzeniowe oddzielnie, ciuchowe oddzielnie, inne oddzielnie").
// The Shopping screen opens on five kinds; each kind lists the shops Doddy can work with there and what it does at
// each. The list is the code's own, nothing more:
//   - the leaflet chains Doddy's server reads or links to (`DealsChain`), each given its kind here, because the
//     server's data carries none;
//   - Shopify's catalogue (one search across Shopify shops, `v1/shopify/search`; there is no list of shops in it);
//   - "Find me this", which looks across shops in Poland (the Google Shopping list and the shops' own pages), and
//     "Check this", which reads one shop page the person pastes. These two work in every kind.
// A scoped "Find me this" sends the kind as one more line under the person's words, in the task's language, so the
// yes card shows it and the digest covers it like every other word (ErrandTyped.swift). No other field changes.
// Ported onto main's one-field Shopping (#407, #423); watched prices by kind and Compare are not part of this port.

/// The five kinds of shop on the Shopping screen.
public enum ShopCategory: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case groceries
    case fashion
    case electronics
    case home
    case other

    public var id: String { rawValue }

    /// The kind's name in a task's words: Polish for "pl", English otherwise. Fixed, so a task's words read the same
    /// whatever the app's language; the screen's own names come from the string catalog.
    public func requestName(language: String) -> String {
        let polish = language.lowercased() == "pl"
        switch self {
        case .groceries: return polish ? "Spożywcze i chemia" : "Groceries and household"
        case .fashion: return polish ? "Moda i buty" : "Fashion and shoes"
        case .electronics: return polish ? "Elektronika" : "Electronics"
        case .home: return polish ? "Dom i ogród" : "Home and garden"
        case .other: return polish ? "Inne" : "Other"
        }
    }
}

// MARK: - The kind in a task's words

/// The line a "Find me this" typed on a kind's page adds under the words.
public enum ShopCategoryRequest {
    static let polishLabel = "Kategoria: "
    static let englishLabel = "Category: "

    /// "Kategoria: Elektronika" (Polish for "pl") or "Category: Electronics".
    public static func line(_ category: ShopCategory, language: String) -> String {
        let label = language.lowercased() == "pl" ? polishLabel : englishLabel
        return label + category.requestName(language: language)
    }

    /// The words a scoped "Find me this" sends: the person's words, trimmed as every draft is, a blank line, then the
    /// kind's line. No kind: the words alone. Empty words stay empty, so the draft is refused as missing words and a
    /// kind is never sent on its own.
    public static func words(_ words: String, category: ShopCategory?, language: String) -> String {
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let category, !trimmed.isEmpty else { return trimmed }
        return trimmed + "\n\n" + line(category, language: language)
    }
}

// MARK: - The shops in each kind

extension DealsChain {
    /// Supermarkets, discounters, convenience shops and drugstores.
    static let groceryChains: [DealsChain] = [.biedronka, .lidl, .dino, .rossmann, .aldi, .kaufland, .carrefour, .auchan,
                                              .netto, .zabka, .delikatesy, .leclerc, .lewiatan, .natura]
    static let fashionChains: [DealsChain] = [.ccc, .deichmann]
    /// Komfort (floors, carpets, doors) and Action (home goods, decorations, garden, tools).
    static let homeChains: [DealsChain] = [.komfort, .action]

    /// The kind of shop this chain is. Pet shops (Maxi Zoo, zooplus) and a chain this app doesn't know are "other".
    public var category: ShopCategory {
        if Self.groceryChains.contains(self) { return .groceries }
        if Self.fashionChains.contains(self) { return .fashion }
        if Self.homeChains.contains(self) { return .home }
        return .other
    }
}

/// What Doddy can do at one shop, as a kind's page says it next to the shop's name.
public enum ShopCapability: String, CaseIterable, Hashable, Sendable {
    /// Doddy's server reads this chain's leaflet for "This week's deals".
    case leaflet
    /// Read only for an item of the chain's own kind (pets, shoes, home: ADR-667).
    case onlyItsKind
    /// Only a link to the chain's leaflet; Doddy doesn't read it.
    case leafletLink
    /// Shopify's catalogue: a search, and a cart prepared at the shop (no order, no payment).
    case searchAndCart
}

/// A shop (or Shopify's catalogue) on a kind's page.
public struct ShopListing: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    /// The shop's own name ("Żabka", "Shopify").
    public let name: String
    /// The leaflet chain, when it is one.
    public let chain: DealsChain?
    public let capabilities: [ShopCapability]

    public init(id: String, name: String, chain: DealsChain?, capabilities: [ShopCapability]) {
        self.id = id
        self.name = name
        self.chain = chain
        self.capabilities = capabilities
    }

    /// One entry for Shopify's whole catalogue: it is a search across shops, not one shop.
    public static let shopify = ShopListing(id: "shopify", name: "Shopify", chain: nil, capabilities: [.searchAndCart])
}

public enum ShopDirectory {
    /// The leaflet chains of a kind, in the request's order.
    public static func chains(in category: ShopCategory) -> [DealsChain] {
        DealsChain.all.filter { $0.category == category }
    }

    /// What Doddy can do at a chain: read its leaflet (only for its own kind of item, for a specialty chain), or link to it.
    public static func capabilities(of chain: DealsChain) -> [ShopCapability] {
        guard chain.isRead else { return [.leafletLink] }
        return DealsChain.specialty.contains(chain) ? [.leaflet, .onlyItsKind] : [.leaflet]
    }

    /// The shops on a kind's page: its chains, the ones Doddy reads first, then Shopify's catalogue when it is on in
    /// this build, for every kind but groceries (whose shops are the leaflet chains).
    public static func shops(in category: ShopCategory, shopify: Bool) -> [ShopListing] {
        let chains = Self.chains(in: category)
        let ordered = chains.filter(\.isRead) + chains.filter { !$0.isRead }
        var list = ordered.map { ShopListing(id: $0.rawValue, name: $0.name, chain: $0, capabilities: capabilities(of: $0)) }
        if shopify && category != .groceries { list.append(.shopify) }
        return list
    }
}
