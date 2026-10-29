import Foundation

// Leaflets ("Gazetki", docs/implementation/SHOPPING.md section 2): `POST /v1/deals/search` on
// Doddy's messaging server reads this week's official leaflets of Biedronka, Lidl, Dino, Rossmann,
// Aldi and Żabka on request (Aldi and Żabka since ADR-660); other chains come back as a link. The server keeps nothing but daily counts.
// The item names go to Doddy's server; nothing about the user goes to the chains.
//
// Days in a leaflet ("2026-10-23") are calendar days in Poland with no time of day, so they are
// kept as `DealDay` (the "YYYY-MM-DD" text as sent, checked to be a real day), never as a `Date`
// that a time zone could move.

// MARK: - Chains

/// A chain, by the server's identifier. A struct, not an enum, so a chain this app doesn't know
/// keeps its own name: two chains a newer server adds are never merged into one "unknown".
public struct DealsChain: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let biedronka = DealsChain(rawValue: "biedronka")
    public static let lidl = DealsChain(rawValue: "lidl")
    public static let dino = DealsChain(rawValue: "dino")
    public static let rossmann = DealsChain(rawValue: "rossmann")
    public static let aldi = DealsChain(rawValue: "aldi")
    public static let kaufland = DealsChain(rawValue: "kaufland")
    public static let carrefour = DealsChain(rawValue: "carrefour")
    public static let auchan = DealsChain(rawValue: "auchan")
    public static let netto = DealsChain(rawValue: "netto")
    public static let zabka = DealsChain(rawValue: "zabka")

    /// Read on request (the server's default when no chains are asked for).
    public static let read: [DealsChain] = [.biedronka, .lidl, .dino, .rossmann, .aldi, .zabka]
    /// Answered with a link to the chain's leaflet page only.
    public static let linkOnly: [DealsChain] = [.kaufland, .carrefour, .auchan, .netto]
    /// Every chain a request may name, in the contract's order.
    public static let all: [DealsChain] = read + linkOnly

    /// The request accepts it.
    public var isKnown: Bool { Self.all.contains(self) }
    public var isRead: Bool { Self.read.contains(self) }

    /// The chain's own name ("Żabka"); the identifier for one this app doesn't know.
    public var name: String {
        switch rawValue {
        case "biedronka": "Biedronka"
        case "lidl": "Lidl"
        case "dino": "Dino"
        case "rossmann": "Rossmann"
        case "aldi": "Aldi"
        case "kaufland": "Kaufland"
        case "carrefour": "Carrefour"
        case "auchan": "Auchan"
        case "netto": "Netto"
        case "zabka": "Żabka"
        default: rawValue
        }
    }

    public var description: String { rawValue }

    /// What the agent or the user said ("Żabka", " LIDL "), when it names a known chain.
    public static func named(_ text: String) -> DealsChain? {
        let key = PolishText.fold(text.trimmingCharacters(in: .whitespacesAndNewlines))
        return all.first { $0.rawValue == key }
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - The request

/// `POST /v1/deals/search`: 1 to 12 items of 1 to 60 characters, the chains (nil: the server's
/// four read chains) and a two-letter language.
public struct DealsRequest: Codable, Equatable, Hashable, Sendable {
    public static let maxItems = 12
    public static let maxItemLength = 60

    /// What to look for, in the user's words; each trimmed, nothing else changed.
    public let items: [String]
    /// Nil asks for the server's default (the four read chains). Asked chains keep their order;
    /// a chain named twice is kept once.
    public let chains: [DealsChain]?
    public let language: String

    public init(items: [String], chains: [DealsChain]? = nil, language: String = ErrandDraft.defaultLanguage) {
        self.items = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let chains, !chains.isEmpty {
            var seen = Set<DealsChain>()
            self.chains = chains.filter { seen.insert($0).inserted }
        } else {
            self.chains = nil
        }
        self.language = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The chains the server will check: those asked, or its default.
    public var chainsAsked: [DealsChain] { chains ?? DealsChain.read }

    /// Hints before sending, in a fixed order; the server checks the same limits again and
    /// decides. Lengths count UTF-16 units, as the server's schema does.
    public func validationIssues() -> [DealsRequestIssue] {
        var issues: [DealsRequestIssue] = []
        if items.isEmpty { issues.append(.noItems) }
        if items.count > Self.maxItems { issues.append(.tooManyItems) }
        if items.contains(where: \.isEmpty) { issues.append(.emptyItem) }
        if items.contains(where: { $0.utf16.count > Self.maxItemLength }) { issues.append(.itemTooLong) }
        if let chains, chains.contains(where: { !$0.isKnown }) { issues.append(.unknownChain) }
        if !ErrandDraft.isLanguageCode(language) { issues.append(.languageNotACode) }
        return issues
    }

    public var isValid: Bool { validationIssues().isEmpty }

    private enum CodingKeys: String, CodingKey { case items, chains, language }

    /// Exactly the contract's fields; `chains` only when some were asked for.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items)
        try c.encodeIfPresent(chains, forKey: .chains)
        try c.encode(language, forKey: .language)
    }
}

public enum DealsRequestIssue: Equatable, Sendable, CaseIterable {
    case noItems, tooManyItems, emptyItem, itemTooLong, unknownChain, languageNotACode

    /// For the agent, in the style of the other tools' `invalid` reasons.
    public var reason: String {
        switch self {
        case .noItems: "missing items"
        case .tooManyItems: "items has more than \(DealsRequest.maxItems) entries"
        case .emptyItem: "an item is empty"
        case .itemTooLong: "an item is longer than \(DealsRequest.maxItemLength) characters"
        case .unknownChain: "chains must be some of " + DealsChain.all.map(\.rawValue).joined(separator: ", ")
        case .languageNotACode: "language must be a two-letter code such as pl or en"
        }
    }

    /// The request field the issue is about, as the server's `fields` name it.
    public var field: String {
        switch self {
        case .noItems, .tooManyItems, .emptyItem, .itemTooLong: "items"
        case .unknownChain: "chains"
        case .languageNotACode: "language"
        }
    }
}

// MARK: - The answer

/// A calendar day as a leaflet gives it: "YYYY-MM-DD", kept exactly as sent and checked to be a
/// real day. Ordered by the day.
public struct DealDay: RawRepresentable, Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard rawValue.utf8.count == 10, parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), day >= 1, day <= Self.days(in: month, of: year) else { return nil }
        self.rawValue = rawValue
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day with no time and no time zone.
    public var dateComponents: DateComponents { DateComponents(year: year, month: month, day: day) }

    public var description: String { rawValue }

    public static func < (a: DealDay, b: DealDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        let text = try c.decode(String.self)
        guard let day = DealDay(rawValue: text) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a YYYY-MM-DD day")
        }
        self = day
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    static func days(in month: Int, of year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}

/// The `200` answer of `POST /v1/deals/search`, exactly the contract's shape (fixture
/// `deals_search_v1.json`, `response`). `checkedAt` is kept as sent.
public struct DealsResult: Codable, Equatable, Sendable {
    public let checkedAt: String
    /// One row per chain asked for, in the server's order.
    public let chains: [DealsChainReport]
    /// One row per item asked for, in the request's order.
    public let items: [DealsItemResult]
    /// "Search further" (ADR-666); absent from a server older than it, or with nothing to suggest.
    public let further: DealsFurther?

    public init(checkedAt: String, chains: [DealsChainReport], items: [DealsItemResult], further: DealsFurther? = nil) {
        self.checkedAt = checkedAt
        self.chains = chains
        self.items = items
        self.further = further
    }

    /// How many chains were read for this answer (for the card on Home).
    public var readChainCount: Int { chains.filter { $0.status.wasRead }.count }

    public var checkedDate: Date? { ServerDates.parse(checkedAt) }

    /// The report for one chain, when the server sent one.
    public func report(for chain: DealsChain) -> DealsChainReport? {
        chains.first { $0.chain == chain }
    }
}

/// "Search further" under the answer (ADR-666): addresses for the person to open, which Doddy never fetches.
/// The server builds them from the request alone, after the offers are picked, so they change no pick or order.
public struct DealsFurther: Codable, Equatable, Sendable {
    /// Chains Doddy doesn't read that weren't asked for, with their leaflet page.
    public let leaflets: [DealsLeafletLink]
    /// Per item, in the request's order: its search page at each shop, in the server's order.
    public let searches: [DealsItemSearch]

    public init(leaflets: [DealsLeafletLink], searches: [DealsItemSearch]) {
        self.leaflets = leaflets
        self.searches = searches
    }

    /// Only https addresses with a host; nothing when none is left.
    public var openable: DealsFurther? {
        let leaflets = leaflets.filter { Self.isOpenable($0.url) }
        let searches = searches.compactMap { search -> DealsItemSearch? in
            let links = search.links.filter { Self.isOpenable($0.openURL) }
            return links.isEmpty ? nil : DealsItemSearch(item: search.item, links: links)
        }
        return leaflets.isEmpty && searches.isEmpty ? nil : DealsFurther(leaflets: leaflets, searches: searches)
    }

    /// The shops named in the searches, in order, once each.
    public var shopNames: [String] {
        var seen: [String] = []
        for link in searches.flatMap(\.links) where !seen.contains(link.shop) { seen.append(link.shop) }
        return seen
    }

    public var hasPartnerLink: Bool { searches.contains { $0.links.contains(where: \.isPartner) } }

    public static func isOpenable(_ text: String) -> Bool {
        guard let url = URL(string: text), url.scheme == "https", let host = url.host, !host.isEmpty else { return false }
        return true
    }
}

public struct DealsLeafletLink: Codable, Equatable, Sendable {
    public let chain: DealsChain
    public let url: String

    public init(chain: DealsChain, url: String) {
        self.chain = chain
        self.url = url
    }
}

public struct DealsItemSearch: Codable, Equatable, Sendable {
    /// The item in the user's words.
    public let item: String
    public let links: [DealsSearchLink]

    public init(item: String, links: [DealsSearchLink]) {
        self.item = item
        self.links = links
    }
}

public struct DealsSearchLink: Codable, Equatable, Sendable {
    public let shop: String
    /// The shop's own search page.
    public let url: String
    /// The same page through an affiliate network (ADR-612), only where a programme covers the shop.
    public let buyUrl: String?

    public init(shop: String, url: String, buyUrl: String? = nil) {
        self.shop = shop
        self.url = url
        self.buyUrl = buyUrl
    }

    public var isPartner: Bool { buyUrl != nil }
    /// What a tap opens: the partner link when there is one, said under it before the tap.
    public var openURL: String { buyUrl ?? url }
}

/// What happened at one chain.
public struct DealsChainReport: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable, CaseIterable {
        /// Read; its offers are in `items`.
        case checked
        /// Read, and nothing in it matched the items.
        case noMatch = "no_match"
        /// No leaflet for this week was found.
        case noLeaflet = "no_leaflet"
        /// The chain's site blocked the reader (a 403, 429, a challenge or a captcha). Never retried around.
        case blocked
        case failed
        /// Not read: only a link to the chain's leaflet page.
        case linkOnly = "link_only"
        /// A status this version of the app doesn't know. Never read as checked.
        case unknown

        public init(from decoder: any Decoder) throws {
            self = Status(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }

        /// The leaflet was read (whether or not anything matched).
        public var wasRead: Bool { self == .checked || self == .noMatch }
    }

    public struct Leaflet: Codable, Equatable, Sendable {
        public let title: String?
        public let url: String
        public let validFrom: DealDay?
        public let validTo: DealDay?

        public init(title: String? = nil, url: String, validFrom: DealDay? = nil, validTo: DealDay? = nil) {
            self.title = title
            self.url = url
            self.validFrom = validFrom
            self.validTo = validTo
        }
    }

    /// Fewer pages read than were worth reading (the server's page cap, its time limit, a page it
    /// couldn't fetch or read). The rest weren't checked, so a cheaper offer may be on them.
    public struct Pages: Codable, Equatable, Sendable {
        public let read: Int
        /// Every page worth reading: all of an image-only leaflet such as Biedronka's.
        public let of: Int

        public init(read: Int, of: Int) {
            self.read = read
            self.of = of
        }
    }

    public let chain: DealsChain
    public let status: Status
    /// The leaflet read, for `checked` (and when the server gives it for others).
    public let leaflet: Leaflet?
    /// The chain's leaflet page, for `link_only`.
    public let leafletUrl: String?
    /// Only when the leaflet was read in part (`checked` or `failed`); nil when it was read whole or
    /// the server is older. A value that doesn't make sense (read not below of) is dropped.
    public let pages: Pages?

    public init(chain: DealsChain, status: Status, leaflet: Leaflet? = nil, leafletUrl: String? = nil, pages: Pages? = nil) {
        self.chain = chain
        self.status = status
        self.leaflet = leaflet
        self.leafletUrl = leafletUrl
        self.pages = pages
    }

    private enum CodingKeys: String, CodingKey { case chain, status, leaflet, leafletUrl, pages }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chain = try c.decode(DealsChain.self, forKey: .chain)
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .unknown
        leaflet = try c.decodeIfPresent(Leaflet.self, forKey: .leaflet)
        leafletUrl = try c.decodeIfPresent(String.self, forKey: .leafletUrl)
        let pages = try? c.decodeIfPresent(Pages.self, forKey: .pages)
        self.pages = pages.flatMap { $0.read >= 0 && $0.read < $0.of ? $0 : nil }
    }
}

/// The offers found for one item, cheapest first as the server sorted them (at most 6).
public struct DealsItemResult: Codable, Equatable, Sendable {
    public let query: String
    public let offers: [DealOffer]
    /// Promotions printed without a price that fit the item (ADR-661): a mechanic for a range, never a price.
    public let promotions: [DealPromotion]
    /// Products of another kind in the item's family (ADR-662: "masło roślinne" for "masło"), at most three:
    /// shown apart as "similar, not the same", never picked for the item or counted in the basket.
    public let similar: [DealOffer]

    public init(query: String, offers: [DealOffer], promotions: [DealPromotion] = [], similar: [DealOffer] = []) {
        self.query = query
        self.offers = offers
        self.promotions = promotions
        self.similar = similar
    }

    private enum CodingKeys: String, CodingKey { case query, offers, promotions, similar }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query = try c.decode(String.self, forKey: .query)
        offers = try c.decodeIfPresent([DealOffer].self, forKey: .offers) ?? []
        promotions = (try? c.decodeIfPresent([DealPromotion].self, forKey: .promotions)) ?? []
        similar = Array(((try? c.decodeIfPresent([DealOffer].self, forKey: .similar)) ?? []).prefix(3))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(query, forKey: .query)
        try c.encode(offers, forKey: .offers)
        if !promotions.isEmpty { try c.encode(promotions, forKey: .promotions) }
        if !similar.isEmpty { try c.encode(similar, forKey: .similar) }
    }
}

/// A promotion the leaflet prints without a price: its range ("Wszystkie kawy mielone Jacobs") and its
/// mechanic in the server's code words ("1+1", "druga sztuka za 5,00 zł", "−30%"). The price is on the shelf.
public struct DealPromotion: Codable, Equatable, Sendable {
    public let chain: DealsChain
    public let text: String
    public let mechanic: String
    public let conditions: [String]
    public let flags: [DealOffer.Flag]
    public let validFrom: DealDay?
    public let validTo: DealDay?
    public let source: DealOffer.Source

    public init(chain: DealsChain, text: String, mechanic: String, conditions: [String] = [], flags: [DealOffer.Flag] = [],
                validFrom: DealDay? = nil, validTo: DealDay? = nil, source: DealOffer.Source) {
        self.chain = chain
        self.text = text
        self.mechanic = mechanic
        self.conditions = conditions
        self.flags = flags
        self.validFrom = validFrom
        self.validTo = validTo
        self.source = source
    }

    private enum CodingKeys: String, CodingKey { case chain, text, mechanic, conditions, flags, validFrom, validTo, source }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chain = try c.decode(DealsChain.self, forKey: .chain)
        text = try c.decode(String.self, forKey: .text)
        mechanic = try c.decode(String.self, forKey: .mechanic)
        conditions = try c.decodeIfPresent([String].self, forKey: .conditions) ?? []
        flags = ((try? c.decodeIfPresent([DealOffer.Flag].self, forKey: .flags)) ?? []).filter { $0 != .unknown }
        validFrom = try c.decodeIfPresent(DealDay.self, forKey: .validFrom)
        validTo = try c.decodeIfPresent(DealDay.self, forKey: .validTo)
        source = try c.decode(DealOffer.Source.self, forKey: .source)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(chain, forKey: .chain)
        try c.encode(text, forKey: .text)
        try c.encode(mechanic, forKey: .mechanic)
        try c.encode(conditions, forKey: .conditions)
        if !flags.isEmpty { try c.encode(flags, forKey: .flags) }
        try c.encodeIfPresent(validFrom, forKey: .validFrom)
        try c.encodeIfPresent(validTo, forKey: .validTo)
        try c.encode(source, forKey: .source)
    }
}

/// One leaflet offer, as the server's code read and checked it.
public struct DealOffer: Codable, Equatable, Sendable {
    public enum SizeUnit: String, Codable, Sendable, CaseIterable {
        case g, kg, ml, l, szt
        case unknown

        public init(from decoder: any Decoder) throws {
            self = SizeUnit(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public enum UnitPer: String, Codable, Sendable, CaseIterable {
        case kg, l, szt
        case unknown

        public init(from decoder: any Decoder) throws {
            self = UnitPer(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    /// Who read the name and price.
    public enum ReadBy: String, Codable, Sendable, CaseIterable {
        /// The chain's own product data.
        case leafletData = "leaflet_data"
        /// Claude Haiku read the leaflet page's image.
        case pageImage = "page_image"
        case unknown

        public init(from decoder: any Decoder) throws {
            self = ReadBy(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public struct Size: Codable, Equatable, Sendable {
        public let value: Double
        public let unit: SizeUnit

        public init(value: Double, unit: SizeUnit) {
            self.value = value
            self.unit = unit
        }
    }

    /// Computed by the server's code from the price and the size, never read. In the price's currency.
    public struct UnitPrice: Codable, Equatable, Sendable {
        public let minor: Int
        public let per: UnitPer

        public init(minor: Int, per: UnitPer) {
            self.minor = minor
            self.per = per
        }
    }

    public struct Source: Codable, Equatable, Sendable {
        public let url: String
        public let page: Int?

        public init(url: String, page: Int? = nil) {
            self.url = url
            self.page = page
        }
    }

    public let chain: DealsChain
    public let product: String
    public let price: Money
    public let size: Size?
    public let unitPrice: UnitPrice?
    public let regularPrice: Money?
    /// The lowest price in the last 30 days, when the leaflet states it (Omnibus).
    public let lowest30d: Money?
    /// App, card, minimum quantity, "2+1": at most 4, as the leaflet says them.
    public let conditions: [String]
    public let validFrom: DealDay?
    public let validTo: DealDay?
    public let source: Source
    public let readBy: ReadBy
    public let ean: String?
    /// True when the server's code could not confirm the offer (a regular price at or below the
    /// price, a 30-day price below the promo, a unit price that doesn't follow from the size, a
    /// low-confidence read). Missing reads as true: unconfirmed is never shown as confirmed.
    public let check: Bool

    /// What the price needs or carries (ADR-661), as the server's code read it from the conditions.
    public enum Flag: String, Codable, Sendable, CaseIterable {
        /// The chain's app or an app coupon.
        case app
        /// The chain's loyalty card.
        case card
        /// A container deposit is added at the till.
        case deposit
        /// While stocks last.
        case stock
        /// Only in some of the chain's shops.
        case selectedStores = "selected_stores"
        /// The leaflet's own lowest price of the last 30 days is not above this price: not a real reduction.
        case notACut = "not_a_cut"
        case unknown

        public init(from decoder: any Decoder) throws {
            self = Flag(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    /// The price of one piece when buying `quantity` under the offer's mechanic ("2+1", "drugi za 5 zł",
    /// "co druga −50%", or a minimum quantity, when it equals the price), worked out by the server's code.
    public struct Effective: Codable, Equatable, Sendable {
        public let price: Money
        public let quantity: Int
        public let unitPrice: UnitPrice?

        public init(price: Money, quantity: Int, unitPrice: UnitPrice? = nil) {
            self.price = price
            self.quantity = quantity
            self.unitPrice = unitPrice
        }
    }

    public let flags: [Flag]
    public let effective: Effective?
    /// The real reduction in percent against the leaflet's own 30-day lowest price, when that is above.
    public let cut: Int?
    /// At most this many per customer.
    public let limit: Int?

    public init(chain: DealsChain, product: String, price: Money, size: Size? = nil, unitPrice: UnitPrice? = nil,
                regularPrice: Money? = nil, lowest30d: Money? = nil, conditions: [String] = [], validFrom: DealDay? = nil,
                validTo: DealDay? = nil, source: Source, readBy: ReadBy = .leafletData, ean: String? = nil, check: Bool = false,
                flags: [Flag] = [], effective: Effective? = nil, cut: Int? = nil, limit: Int? = nil) {
        self.flags = flags
        self.effective = effective
        self.cut = cut
        self.limit = limit
        self.chain = chain
        self.product = product
        self.price = price
        self.size = size
        self.unitPrice = unitPrice
        self.regularPrice = regularPrice
        self.lowest30d = lowest30d
        self.conditions = conditions
        self.validFrom = validFrom
        self.validTo = validTo
        self.source = source
        self.readBy = readBy
        self.ean = ean
        self.check = check
    }

    private enum CodingKeys: String, CodingKey {
        case chain, product, price, size, unitPrice, regularPrice, lowest30d, conditions, validFrom, validTo, source, readBy, ean, check
        case flags, effective, cut, limit
    }

    private struct CutValue: Codable { let percent: Int }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(chain, forKey: .chain)
        try c.encode(product, forKey: .product)
        try c.encode(price, forKey: .price)
        try c.encodeIfPresent(size, forKey: .size)
        try c.encodeIfPresent(unitPrice, forKey: .unitPrice)
        try c.encodeIfPresent(regularPrice, forKey: .regularPrice)
        try c.encodeIfPresent(lowest30d, forKey: .lowest30d)
        try c.encode(conditions, forKey: .conditions)
        try c.encodeIfPresent(validFrom, forKey: .validFrom)
        try c.encodeIfPresent(validTo, forKey: .validTo)
        try c.encode(source, forKey: .source)
        try c.encode(readBy, forKey: .readBy)
        try c.encodeIfPresent(ean, forKey: .ean)
        try c.encode(check, forKey: .check)
        if !flags.isEmpty { try c.encode(flags, forKey: .flags) }
        try c.encodeIfPresent(effective, forKey: .effective)
        try c.encodeIfPresent(cut.map { CutValue(percent: $0) }, forKey: .cut)
        try c.encodeIfPresent(limit, forKey: .limit)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chain = try c.decode(DealsChain.self, forKey: .chain)
        product = try c.decode(String.self, forKey: .product)
        price = try c.decode(Money.self, forKey: .price)
        size = try c.decodeIfPresent(Size.self, forKey: .size)
        unitPrice = try c.decodeIfPresent(UnitPrice.self, forKey: .unitPrice)
        regularPrice = try c.decodeIfPresent(Money.self, forKey: .regularPrice)
        lowest30d = try c.decodeIfPresent(Money.self, forKey: .lowest30d)
        conditions = try c.decodeIfPresent([String].self, forKey: .conditions) ?? []
        validFrom = try c.decodeIfPresent(DealDay.self, forKey: .validFrom)
        validTo = try c.decodeIfPresent(DealDay.self, forKey: .validTo)
        source = try c.decode(Source.self, forKey: .source)
        readBy = try c.decodeIfPresent(ReadBy.self, forKey: .readBy) ?? .unknown
        ean = try c.decodeIfPresent(String.self, forKey: .ean)
        check = try c.decodeIfPresent(Bool.self, forKey: .check) ?? true
        // ADR-661 fields: an older server sends none; a value that doesn't make sense is dropped, never trusted.
        flags = ((try? c.decodeIfPresent([Flag].self, forKey: .flags)) ?? []).filter { $0 != .unknown }
        let one = price
        let effective = (try? c.decodeIfPresent(Effective.self, forKey: .effective)) ?? nil
        self.effective = effective.flatMap { e in
            e.quantity >= 2 && e.quantity <= 99 && e.price.minor > 0 && e.price.minor <= one.minor && e.price.currency == one.currency ? e : nil
        }
        let cut = (try? c.decodeIfPresent(CutValue.self, forKey: .cut)) ?? nil
        self.cut = cut.flatMap { (1...99).contains($0.percent) ? $0.percent : nil }
        let limit = (try? c.decodeIfPresent(Int.self, forKey: .limit)) ?? nil
        self.limit = limit.flatMap { $0 >= 1 && $0 <= 999 ? $0 : nil }
    }

    /// The price is for a mechanic over several pieces ("2+1", "drugi za"), not for one bought alone.
    public var isMultiBuy: Bool { effective.map { $0.price.minor < price.minor } ?? false }
    /// The price needs buying at least `effective.quantity` (the leaflet's price is the price at that
    /// quantity, so one bought alone costs the regular price).
    public var needsMinimumQuantity: Bool { effective.map { $0.price.minor == price.minor } ?? false }
    /// The price needs the chain's app or card.
    public var needsProgram: Bool { flags.contains(.app) || flags.contains(.card) }

    /// The unit price as money, in the price's currency.
    public var unitPriceMoney: Money? { unitPrice.map { Money(minor: $0.minor, currency: price.currency) } }
}

// MARK: - The voice tool

extension VoiceToolRequest {
    /// `{items, chains?}`: the items in the user's words, and the chains by name. Refused, never
    /// cut or guessed: the agent hears why and asks the user. Leaflets are Polish, so the language
    /// is Polish; the app may build its own request in another.
    static func parseFindDeals(_ args: Arguments, name: String) -> VoiceToolRequest {
        let items: [String]
        switch args.stringList("items") {
        case .absent: return .invalid(name: name, reason: DealsRequestIssue.noItems.reason)
        case .list(let list): items = list
        case .notStrings: return .invalid(name: name, reason: "items must be a list of short texts")
        }
        var chains: [DealsChain]?
        switch args.stringList("chains") {
        case .absent: chains = nil
        case .list(let names):
            var known: [DealsChain] = []
            for raw in names {
                guard let chain = DealsChain.named(raw) else { return .invalid(name: name, reason: DealsRequestIssue.unknownChain.reason) }
                known.append(chain)
            }
            chains = known
        case .notStrings: return .invalid(name: name, reason: DealsRequestIssue.unknownChain.reason)
        }
        let request = DealsRequest(items: items, chains: chains)
        let issues = request.validationIssues()
        guard issues.isEmpty else { return .invalid(name: name, reason: issues.map(\.reason).joined(separator: "; ")) }
        return .findDeals(request)
    }
}

/// The card before `find_deals` runs (ASK-01). It reads public leaflets and changes nothing, so a
/// spoken yes or a tap answers it. Whether leaflet look-ups join the public look-ups that run at
/// once (`AskFirst.publicLookups`) is an open owner decision (SHOPPING.md), so for now it asks.
public enum DealsAsk {
    /// `polish`: the app is shown in Polish (`NotificationLanguage`). The card is drawn as it is, so its
    /// words are chosen here (ADR-666); other languages get the English card.
    public static func card(_ request: DealsRequest, polish: Bool = false) -> AskCard {
        if polish {
            let chains = request.chainsAsked.map { $0.isRead ? $0.name : "\($0.name) (tylko link do gazetki)" }
            return AskCard(
                title: "Sprawdzić tegotygodniowe gazetki?",
                lines: [
                    "Produkty: " + request.items.joined(separator: ", "),
                    "Sklepy: " + chains.joined(separator: ", "),
                    "Doddy czyta gazetki na swoim serwerze. Do sklepów nie trafia nic, co cię identyfikuje; Rossmann dostaje nazwy produktów jako wyszukiwanie.",
                ],
                confirmLabel: "Tak, sprawdź")
        }
        let chains = request.chainsAsked.map { $0.isRead ? $0.name : "\($0.name) (leaflet link only)" }
        return AskCard(
            title: "Check this week's leaflets?",
            lines: [
                "Items: " + request.items.joined(separator: ", "),
                "Shops: " + chains.joined(separator: ", "),
                "Doddy reads the leaflets on its server. Nothing that identifies you goes to the shops; Rossmann gets the item names as a search.",
            ],
            confirmLabel: "Yes, check")
    }
}

/// What `find_deals` returns to the agent: per item the best value offer (the lowest price per kg,
/// l or piece where the sizes are known, else the cheapest pack) with its chain, price,
/// conditions and last day, "needs checking" where the server's code couldn't confirm it; the
/// chains that weren't read and why; and one line on the basket from `BasketSolver`. Everything
/// from the leaflets is between the data markers, with the markers removed from inside. Nothing
/// is added that the answer doesn't hold. Bounded: never longer than `maxCharacters`.
/// Since ADR-661 also: the price per piece under a multi-buy, a real cut or "not a real cut"
/// against the 30-day low, a price that isn't on yet, a last day on a closed day, the promotions
/// printed without a price, the kinds an item's offers span (one question the agent may ask), the
/// offers left out for an app the user doesn't use, and the "before you go" notes of the one-shop basket.
public enum DealsResultText {
    public static let maxCharacters = 4_000
    /// Other chains' prices shown after an item's cheapest offer.
    static let othersShown = 3
    static let promotionsShown = 2
    static let checklistShown = 6

    public static func forAgent(_ result: DealsResult, language: String = ErrandDraft.defaultLanguage,
                                maxCharacters: Int = maxCharacters, programs: DealsPrograms = .all,
                                quantities: [ListQuantity?] = [], today: DealDay? = nil, minimumSaving: Int = 0) -> String {
        let clip = ErrandsPrompt.clip
        let money = { (amount: Money) in amount.text(language: language) }
        let found = result.items.contains { !$0.offers.isEmpty }
        let header = found
            ? "found: Doddy's server read the leaflets below just now. Prices, conditions and dates are as the leaflets showed them; an offer marked \"needs checking\" couldn't be confirmed by Doddy's code, so say so. Only say what is below; never add a price, a shop or an offer."
            : "nothing found: none of the items is in the leaflets Doddy's server read just now. Say so plainly; never suggest a price or an offer that isn't below."
        // The basket and what wasn't read come first, so a long answer is cut in the items, not there.
        var data: [String] = []
        let basket = BasketSolver.solve(result, quantities: quantities, programs: programs, minimumSaving: minimumSaving)
        if let line = basketLine(basket, money) { data.append(line) }
        if let single = basket.bestSingleChain, let line = checklistLine(single, today: today) { data.append(line) }
        data += chainLines(result)
        if let line = variantsLine(result) { data.append(line) }
        let order = BasketSolver.chainOrder(result)
        for item in result.items {
            let query = "\"\(clip(item.query, DealsRequest.maxItemLength))\""
            let promotions = promotionsText(item, money)
            let similar = similarText(item, money)
            let leftOut = item.offers.filter { !programs.canGet($0) }.compactMap { DealsProgram.of($0.chain)?.name }
            let leftOutText = leftOut.isEmpty ? nil
                : "left out: \(leftOut.count) offer\(leftOut.count == 1 ? "" : "s") needing \(Array(Set(leftOut)).sorted().joined(separator: ", ")), which the user said they don't use"
            guard let best = BasketSolver.bestValueIndex(item.offers, chainOrder: order, programs: programs) else {
                var text = item.offers.isEmpty
                    ? "- \(query): nothing in the leaflets read"
                    : leftOut.count == item.offers.count
                        ? "- \(query): only offers the user can't get"
                        : "- \(query): \(item.offers.count) offer\(item.offers.count == 1 ? "" : "s") without a price in \(BasketSolver.defaultCurrency) Doddy's code could compare; the user can see them on screen"
                if let leftOutText { text += " · " + leftOutText }
                if let promotions { text += " · " + promotions }
                if let similar { text += " · " + similar }
                data.append(text)
                continue
            }
            let index = best.index
            let cheapest = item.offers[index]
            let label = best.per.map { "lowest price per \($0.rawValue) at" } ?? "cheapest at"
            var parts = ["- \(query): \(label) \(name(cheapest.chain))", "\"\(clip(cheapest.product, 160))\"", offerPrice(cheapest, money)]
            if !cheapest.conditions.isEmpty {
                parts.append("conditions: " + cheapest.conditions.prefix(4).map { clip($0, 80) }.joined(separator: "; "))
            }
            parts += offerNotes(cheapest, money, today: today)
            if cheapest.check { parts.append("needs checking") }
            let others = item.offers.indices.filter { $0 != index && programs.canGet(item.offers[$0]) }.prefix(othersShown).map { other in
                let offer = item.offers[other]
                let each = offer.isMultiBuy ? offer.effective.map { " (\($0.quantity) for \(money($0.price)) each)" } ?? "" : ""
                return "\(name(offer.chain)) \(money(offer.price))" + each + (offer.check ? " (needs checking)" : "")
            }
            if !others.isEmpty { parts.append("also: " + others.joined(separator: ", ")) }
            if let leftOutText { parts.append(leftOutText) }
            if let promotions { parts.append(promotions) }
            if let similar { parts.append(similar) }
            data.append(parts.joined(separator: " · "))
        }
        data.append("Read at: \(clip(result.checkedAt, 40))")
        return ErrandResultText.bounded(header: header, data: data, footer: footer(result), maxCharacters: maxCharacters, cutNote: cutNote)
    }

    /// A chain's name, cleaned: one this app doesn't know is named by the server's identifier.
    static func name(_ chain: DealsChain) -> String { ErrandsPrompt.clip(chain.name, 40) }

    /// Outside the data markers: the app's own words. Since ADR-666 the app puts a card on Home that opens this
    /// list, so the agent may say once that it's on the screen, and names the shops of "search further".
    static func footer(_ result: DealsResult) -> String {
        var text = "This list is in the app now: a card on Home opens it. You may tell them so once, in a few words."
        if let further = result.further?.openable, !further.shopNames.isEmpty {
            text += " It also has links to search for the items at " + further.shopNames.joined(separator: ", ") + "."
        }
        return text + " Links to the leaflets are on the user's screen; don't read them out."
    }
    static let cutNote = "(Cut short: the rest is on the user's screen.)"

    static func offerPrice(_ offer: DealOffer, _ money: (Money) -> String) -> String {
        var text = money(offer.price)
        if let unit = offer.unitPriceMoney, let per = offer.unitPrice?.per, per != .unknown {
            text += " (\(money(unit))/\(per.rawValue))"
        }
        if let regular = offer.regularPrice { text += ", regular \(money(regular))" }
        if let lowest = offer.lowest30d { text += ", lowest in 30 days \(money(lowest))" }
        return text
    }

    /// What the price line holds beyond the price: the per-piece price under a multi-buy, the real
    /// cut (or that it isn't one), the limit, and the days.
    static func offerNotes(_ offer: DealOffer, _ money: (Money) -> String, today: DealDay?) -> [String] {
        var notes: [String] = []
        if let e = offer.effective {
            notes.append(offer.isMultiBuy
                ? "when buying \(e.quantity): \(money(e.price)) each (one alone: \(money(offer.price)))"
                : "this price only when buying at least \(e.quantity)")
        }
        if let cut = offer.cut {
            notes.append("a real cut of \(cut)% against its lowest price in the last 30 days")
        } else if offer.flags.contains(.notACut) {
            notes.append("not lower than its lowest price in the last 30 days, so not a real cut")
        }
        if let today, let from = offer.validFrom, from > today { notes.append("not on yet: from \(from.rawValue)") }
        if let to = offer.validTo {
            var text = "until \(to.rawValue)"
            if let today, to > today, ShoppingCalendar.isClosed(to, for: offer.chain),
               let open = ShoppingCalendar.lastOpenDay(from: max(today, offer.validFrom ?? today), through: to, for: offer.chain), open != to {
                text += " (shops are closed that day; the last day to shop is \(open.rawValue))"
            }
            notes.append(text)
        }
        return notes
    }

    /// The promotions printed without a price that fit the item, as the server worded them.
    static func promotionsText(_ item: DealsItemResult, _ money: (Money) -> String) -> String? {
        guard !item.promotions.isEmpty else { return nil }
        let clip = ErrandsPrompt.clip
        let parts = item.promotions.prefix(promotionsShown).map { p in
            var text = "\(name(p.chain)) \"\(clip(p.text, 120))\" \(clip(p.mechanic, 40))"
            if !p.conditions.isEmpty { text += " (\(p.conditions.prefix(3).map { clip($0, 60) }.joined(separator: "; ")))" }
            if let to = p.validTo { text += " until \(to.rawValue)" }
            return text
        }
        return "promotions printed without a price, so the price is on the shelf: " + parts.joined(separator: "; ")
    }

    /// Products of another kind in the item's family, said as such.
    static func similarText(_ item: DealsItemResult, _ money: (Money) -> String) -> String? {
        guard !item.similar.isEmpty else { return nil }
        let parts = item.similar.prefix(2).map { "\(name($0.chain)) \"\(ErrandsPrompt.clip($0.product, 120))\" \(money($0.price))" + ($0.check ? " (needs checking)" : "") }
        return "similar, not the same (never call it the item): " + parts.joined(separator: "; ")
    }

    /// The first item whose offers span different kinds the user didn't say, as one question the agent may ask.
    static func variantsLine(_ result: DealsResult) -> String? {
        for item in result.items {
            guard let variants = DealsVariants.split(item) else { continue }
            let kinds = variants.map { "\($0.label) (\($0.offerIndices.count))" }.joined(separator: ", ")
            return "The offers for \"\(ErrandsPrompt.clip(item.query, DealsRequest.maxItemLength))\" are of different kinds: \(kinds). If it matters, ask the user once which they mean; ask nothing else."
        }
        return nil
    }

    /// The one-shop basket's "before you go" notes, in a line.
    static func checklistLine(_ plan: BasketPlan, today: DealDay?) -> String? {
        let clip = ErrandsPrompt.clip
        let entries = DealsChecklist.sections(plan, today: today).flatMap(\.entries)
        guard !entries.isEmpty else { return nil }
        let texts = entries.prefix(checklistShown).map { entry -> String in
            let product = entry.product.map { "\"\(clip($0, 60))\": " } ?? ""
            return "\(name(entry.chain)): \(product)\(agentText(entry.kind))"
        }
        return "Before going (one-shop basket): " + texts.joined(separator: "; ")
    }

    static func agentText(_ kind: DealsChecklistEntry.Kind) -> String {
        switch kind {
        case .openApp(let program): "open the \(program?.name ?? "chain's") app, activate its coupons and scan it at the till"
        case .showCard(let program): "show the \(program?.name ?? "loyalty") card"
        case .take(let n): "take \(n) to get the offer"
        case .atMost(let n): "at most \(n) per customer"
        case .deposit: "a deposit is added at the till"
        case .whileStocksLast: "while stocks last"
        case .selectedStores: "only in some shops"
        case .startsOn(let day): "not on until \(day.rawValue)"
        case .lastDay: "today is the last day"
        case .lastOpenDay(let day): "the last day to shop for it is \(day.rawValue)"
        case .closedToday: "most shops are closed today"
        case .closesEarlyToday(let hour): "shops close at \(hour):00 today"
        }
    }

    static func chainLines(_ result: DealsResult) -> [String] {
        var read: [String] = []
        var partial: [String] = []
        var nothing: [String] = []
        var notRead: [String] = []
        for report in result.chains {
            let name = Self.name(report.chain)
            switch report.status {
            case .checked:
                var text = name
                if let leaflet = report.leaflet {
                    let days = [leaflet.validFrom?.rawValue, leaflet.validTo?.rawValue].compactMap { $0 }
                    if !days.isEmpty { text += " (\(days.joined(separator: " to ")))" }
                }
                read.append(text)
                if let pages = report.pages { partial.append("\(name) \(pages.read) of \(pages.of) pages") }
            case .noMatch: nothing.append(name)
            case .noLeaflet: notRead.append("\(name): no leaflet found for this week")
            case .blocked: notRead.append("\(name): its site blocked Doddy's reader")
            case .failed:
                if let pages = report.pages, pages.read > 0 {
                    notRead.append("\(name): only \(pages.read) of \(pages.of) pages could be read, and nothing matched in them")
                } else {
                    notRead.append("\(name): couldn't be read")
                }
            case .linkOnly: notRead.append("\(name): not read, only a link to its leaflet (on screen)")
            case .unknown: notRead.append("\(name): not known whether it was read")
            }
        }
        var out: [String] = []
        if !read.isEmpty { out.append("Leaflets read: " + read.joined(separator: ", ")) }
        if !partial.isEmpty {
            out.append("Read only in part, so a cheaper offer may be on the pages not read: " + partial.joined(separator: ", "))
        }
        if !nothing.isEmpty { out.append("Read, nothing matched: " + nothing.joined(separator: ", ")) }
        if !notRead.isEmpty { out.append("Not checked: " + notRead.joined(separator: "; ")) }
        return out
    }

    static func basketLine(_ basket: Basket, _ money: (Money) -> String) -> String? {
        guard let single = basket.bestSingleChain else { return nil }
        func plan(_ plan: BasketPlan) -> String {
            let names = plan.chains.map(name).joined(separator: " + ")
            return "\(names), \(plan.covered) of \(plan.itemCount) items, "
                + (plan.lines.contains { $0.cost.isLowerBound } ? "at least " : "") + money(plan.total)
                + (plan.lines.contains { $0.quantity > 1 } ? " for the quantities on the list" : "")
                + (plan.needsChecking ? " (some need checking)" : "")
        }
        var text = "Basket (summed by Doddy's code): one shop: " + plan(single)
        if let pair = basket.bestPair {
            text += "; two shops: " + plan(pair)
            if let savings = basket.savings { text += ", \(money(savings)) less than one shop" }
        }
        return text
    }
}

extension VoiceToolReply {
    /// `find_deals` didn't run, with the server's reason. Nothing was looked up.
    public static func dealsNotChecked(_ error: any Error) -> String {
        let said: String = switch error {
        case DealsError.dealsDisabled: "leaflet checks are switched off or not set up on Doddy's server."
        case DealsError.dailyLimit: "the user has used today's leaflet checks; they can check again tomorrow."
        case DealsError.invalid(let fields):
            "Doddy's server refused the request" + (fields.isEmpty ? "." : " (\(fields.map(ToolData.clean).joined(separator: ", "))).")
        case DealsError.server(.offline), ServerError.offline: "Doddy's server couldn't be reached."
        case DealsError.server(.rateLimited), ServerError.rateLimited: "Doddy's server is busy right now."
        default: "something went wrong on Doddy's server."
        }
        return "failed: the leaflets weren't checked: \(said) Nothing was looked up."
    }
}
