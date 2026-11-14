import Foundation

// Deal watches (owner, 13 Nov 2026: "daj znać, gdy masło będzie poniżej 5 zł"; decision
// docs/decisions/2026-11-13-leaflet-results-and-deal-watches.md; fixture schemas/fixtures/deal_watch_v1.json). The
// messaging server keeps the item's words (encrypted), an optional price and optional chains, and checks them in code
// against its leaflet catalog after the catalog's scans, at most once a day, with no page read and no model. A match is
// the item itself (by its words or its brand), never a similar product, only an offer the server's code stands behind,
// and at or under the price when one is set. A new match sends one push whose payload is only
// `{"doddy": {"kind": "deal-watch"}}` (`ServerPushKind.dealWatch`); the app reads the matches when it opens.
// These are the contract's types only: the screens are the app's (not here).

/// `POST /v1/deal-watches`: the item in the user's words, an optional price in grosze, optional chains and the
/// language of the push.
public struct DealWatchRequest: Encodable, Equatable, Sendable {
    public static let maxItemLength = 60
    public static let maxPriceMinor = 10_000_000
    /// The chains the server's leaflet catalog reads: the only ones a watch can name.
    public static let catalogued: [DealsChain] = [
        .biedronka, .lidl, .dino, .aldi, .zabka, .delikatesy, .leclerc, .komfort, .lewiatan, .natura, .action,
    ]
    public static let languages = ["pl", "en"]

    /// In the user's words, trimmed, nothing else changed.
    public let item: String
    /// An offer counts at or under this many grosze; nil: any price.
    public let maxPriceMinor: Int?
    /// Nil: every catalogued chain. A chain named twice is kept once.
    public let chains: [DealsChain]?
    public let language: String

    public init(item: String, maxPriceMinor: Int? = nil, chains: [DealsChain]? = nil, language: String = "pl") {
        self.item = item.trimmingCharacters(in: .whitespacesAndNewlines)
        self.maxPriceMinor = maxPriceMinor
        if let chains, !chains.isEmpty {
            var seen = Set<DealsChain>()
            self.chains = chains.filter { seen.insert($0).inserted }
        } else {
            self.chains = nil
        }
        self.language = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Hints before sending, in a fixed order; the server checks again and decides. Lengths count UTF-16 units.
    public func validationIssues() -> [DealWatchRequestIssue] {
        var issues: [DealWatchRequestIssue] = []
        if item.isEmpty { issues.append(.emptyItem) }
        if item.utf16.count > Self.maxItemLength { issues.append(.itemTooLong) }
        if let p = maxPriceMinor, p < 1 || p > Self.maxPriceMinor { issues.append(.priceOutOfRange) }
        if let chains, chains.contains(where: { !Self.catalogued.contains($0) }) { issues.append(.chainNotCatalogued) }
        if !Self.languages.contains(language) { issues.append(.languageNotSupported) }
        return issues
    }

    public var isValid: Bool { validationIssues().isEmpty }

    private enum CodingKeys: String, CodingKey { case item, maxPriceMinor, chains, language }

    /// Exactly the contract's fields; the optional ones only when set (the server's body is strict).
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(item, forKey: .item)
        try c.encodeIfPresent(maxPriceMinor, forKey: .maxPriceMinor)
        try c.encodeIfPresent(chains, forKey: .chains)
        try c.encode(language, forKey: .language)
    }
}

public enum DealWatchRequestIssue: Equatable, Sendable, CaseIterable {
    case emptyItem, itemTooLong, priceOutOfRange, chainNotCatalogued, languageNotSupported

    /// The request field the issue is about, as the server's `fields` name it.
    public var field: String {
        switch self {
        case .emptyItem, .itemTooLong: "item"
        case .priceOutOfRange: "maxPriceMinor"
        case .chainNotCatalogued: "chains"
        case .languageNotSupported: "language"
        }
    }
}

/// One watch as the server keeps it. Dates are kept as sent.
public struct DealWatch: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let item: String
    public let maxPriceMinor: Int?
    public let chains: [DealsChain]?
    public let language: String
    public let createdAt: String
    /// The watch ends (and is deleted, with what it found) then.
    public let endsAt: String
    /// The last time the server checked it against the catalog; nil until the first check after a scan.
    public let lastCheckedAt: String?
    /// Offers that turned up after the watch was made (those already there when it was made are not counted).
    public let found: Int

    public init(id: String, item: String, maxPriceMinor: Int? = nil, chains: [DealsChain]? = nil, language: String, createdAt: String,
                endsAt: String, lastCheckedAt: String? = nil, found: Int = 0) {
        self.id = id
        self.item = item
        self.maxPriceMinor = maxPriceMinor
        self.chains = chains
        self.language = language
        self.createdAt = createdAt
        self.endsAt = endsAt
        self.lastCheckedAt = lastCheckedAt
        self.found = found
    }

    private enum CodingKeys: String, CodingKey { case id, item, maxPriceMinor, chains, language, createdAt, endsAt, lastCheckedAt, found }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        item = try c.decode(String.self, forKey: .item)
        maxPriceMinor = (try? c.decodeIfPresent(Int.self, forKey: .maxPriceMinor)) ?? nil
        chains = (try? c.decodeIfPresent([DealsChain].self, forKey: .chains)) ?? nil
        language = try c.decode(String.self, forKey: .language)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        endsAt = try c.decode(String.self, forKey: .endsAt)
        lastCheckedAt = (try? c.decodeIfPresent(String.self, forKey: .lastCheckedAt)) ?? nil
        found = max(0, (try? c.decodeIfPresent(Int.self, forKey: .found)) ?? 0)
    }

    /// The price in the request's currency, when one was set.
    public var maxPrice: Money? { maxPriceMinor.map { Money(minor: $0, currency: "PLN") } }
    public var endsDate: Date? { ServerDates.parse(endsAt) }
}

/// When the catalog last read one chain, and whether it read all of it.
public struct DealWatchChainState: Codable, Equatable, Sendable {
    public let chain: DealsChain
    public let readAt: String
    public let complete: Bool

    public init(chain: DealsChain, readAt: String, complete: Bool) {
        self.chain = chain
        self.readAt = readAt
        self.complete = complete
    }

    public var readDate: Date? { ServerDates.parse(readAt) }
}

/// `201` of `POST /v1/deal-watches`: the watch, and what matches it in the catalog right now (shown at once and never
/// pushed: a push is for an offer that turns up later).
public struct DealWatchCreated: Codable, Equatable, Sendable {
    public let watch: DealWatch
    public let checkedAt: String
    public let offers: [DealOffer]
    public let chains: [DealWatchChainState]

    public init(watch: DealWatch, checkedAt: String, offers: [DealOffer], chains: [DealWatchChainState]) {
        self.watch = watch
        self.checkedAt = checkedAt
        self.offers = offers
        self.chains = chains
    }
}

/// `200` of `GET /v1/deal-watches`: the account's watches, newest first.
public struct DealWatchList: Codable, Equatable, Sendable {
    public let watches: [DealWatch]

    public init(watches: [DealWatch]) { self.watches = watches }
}

/// `200` of `GET /v1/deal-watches/{id}/offers`: the watch's matches in the catalog now, cheapest first (at most 20), and
/// each catalogued chain's last read. Offers the server marks `similar` never come here; one that would is dropped.
public struct DealWatchMatches: Codable, Equatable, Sendable {
    public let id: String
    public let checkedAt: String
    public let offers: [DealOffer]
    public let chains: [DealWatchChainState]

    public init(id: String, checkedAt: String, offers: [DealOffer], chains: [DealWatchChainState]) {
        self.id = id
        self.checkedAt = checkedAt
        self.offers = offers
        self.chains = chains
    }

    private enum CodingKeys: String, CodingKey { case id, checkedAt, offers, chains }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        checkedAt = try c.decode(String.self, forKey: .checkedAt)
        offers = (try c.decodeIfPresent([DealOffer].self, forKey: .offers) ?? []).filter { !$0.isSimilarOnly }
        chains = (try? c.decodeIfPresent([DealWatchChainState].self, forKey: .chains)) ?? []
    }

    /// Some chain's leaflets were read only in part: a cheaper offer may be on a page not read.
    public var readInPart: Bool { chains.contains { !$0.complete } }
}

/// The refusals of the deal-watch routes, by the server's `error` code.
public enum DealWatchRefusal: String, Sendable, CaseIterable {
    case invalidRequest = "invalid_request"
    case notFound = "not_found"
    case tooManyWatches = "too_many_watches"
    case serverFull = "server_full"
    case disabled = "deal_watches_disabled"
}
