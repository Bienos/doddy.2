import Foundation

// Leaflets ("Gazetki", docs/implementation/SHOPPING.md section 2): `POST /v1/deals/search` on
// Doddy's messaging server reads this week's official leaflets of Biedronka, Lidl, Dino and
// Rossmann on request; other chains come back as a link. The server keeps nothing but daily counts.
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
    public static let kaufland = DealsChain(rawValue: "kaufland")
    public static let carrefour = DealsChain(rawValue: "carrefour")
    public static let auchan = DealsChain(rawValue: "auchan")
    public static let netto = DealsChain(rawValue: "netto")
    public static let zabka = DealsChain(rawValue: "zabka")

    /// Read on request (the server's default when no chains are asked for).
    public static let read: [DealsChain] = [.biedronka, .lidl, .dino, .rossmann]
    /// Answered with a link to the chain's leaflet page only.
    public static let linkOnly: [DealsChain] = [.kaufland, .carrefour, .auchan, .netto, .zabka]
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

    public init(checkedAt: String, chains: [DealsChainReport], items: [DealsItemResult]) {
        self.checkedAt = checkedAt
        self.chains = chains
        self.items = items
    }

    public var checkedDate: Date? { ServerDates.parse(checkedAt) }

    /// The report for one chain, when the server sent one.
    public func report(for chain: DealsChain) -> DealsChainReport? {
        chains.first { $0.chain == chain }
    }
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

    public let chain: DealsChain
    public let status: Status
    /// The leaflet read, for `checked` (and when the server gives it for others).
    public let leaflet: Leaflet?
    /// The chain's leaflet page, for `link_only`.
    public let leafletUrl: String?

    public init(chain: DealsChain, status: Status, leaflet: Leaflet? = nil, leafletUrl: String? = nil) {
        self.chain = chain
        self.status = status
        self.leaflet = leaflet
        self.leafletUrl = leafletUrl
    }

    private enum CodingKeys: String, CodingKey { case chain, status, leaflet, leafletUrl }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chain = try c.decode(DealsChain.self, forKey: .chain)
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .unknown
        leaflet = try c.decodeIfPresent(Leaflet.self, forKey: .leaflet)
        leafletUrl = try c.decodeIfPresent(String.self, forKey: .leafletUrl)
    }
}

/// The offers found for one item, cheapest first as the server sorted them (at most 6).
public struct DealsItemResult: Codable, Equatable, Sendable {
    public let query: String
    public let offers: [DealOffer]

    public init(query: String, offers: [DealOffer]) {
        self.query = query
        self.offers = offers
    }

    private enum CodingKeys: String, CodingKey { case query, offers }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query = try c.decode(String.self, forKey: .query)
        offers = try c.decodeIfPresent([DealOffer].self, forKey: .offers) ?? []
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

    public init(chain: DealsChain, product: String, price: Money, size: Size? = nil, unitPrice: UnitPrice? = nil,
                regularPrice: Money? = nil, lowest30d: Money? = nil, conditions: [String] = [], validFrom: DealDay? = nil,
                validTo: DealDay? = nil, source: Source, readBy: ReadBy = .leafletData, ean: String? = nil, check: Bool = false) {
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
    }

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
    public static func card(_ request: DealsRequest) -> AskCard {
        let chains = request.chainsAsked.map { $0.isRead ? $0.name : "\($0.name) (leaflet link only)" }
        return AskCard(
            title: "Check this week's leaflets?",
            lines: [
                "Items: " + request.items.joined(separator: ", "),
                "Shops: " + chains.joined(separator: ", "),
                "Doddy reads the leaflets on its server; nothing about you is sent to the shops.",
            ],
            confirmLabel: "Yes, check")
    }
}

/// What `find_deals` returns to the agent: per item the cheapest offer with its chain, price,
/// conditions and last day, "needs checking" where the server's code couldn't confirm it; the
/// chains that weren't read and why; and one line on the basket from `BasketSolver`. Everything
/// from the leaflets is between the data markers, with the markers removed from inside. Nothing
/// is added that the answer doesn't hold. Bounded: never longer than `maxCharacters`.
public enum DealsResultText {
    public static let maxCharacters = 4_000
    /// Other chains' prices shown after an item's cheapest offer.
    static let othersShown = 3

    public static func forAgent(_ result: DealsResult, language: String = ErrandDraft.defaultLanguage,
                                maxCharacters: Int = maxCharacters) -> String {
        let clip = ErrandsPrompt.clip
        let money = { (amount: Money) in amount.text(language: language) }
        let found = result.items.contains { !$0.offers.isEmpty }
        let header = found
            ? "found: Doddy's server read the leaflets below just now. Prices, conditions and dates are as the leaflets showed them; an offer marked \"needs checking\" couldn't be confirmed by Doddy's code, so say so. Only say what is below; never add a price, a shop or an offer."
            : "nothing found: none of the items is in the leaflets Doddy's server read just now. Say so plainly; never suggest a price or an offer that isn't below."
        // The basket and what wasn't read come first, so a long answer is cut in the items, not there.
        var data: [String] = []
        if let line = basketLine(BasketSolver.solve(result), money) { data.append(line) }
        data += chainLines(result)
        let order = BasketSolver.chainOrder(result)
        for item in result.items {
            let query = "\"\(clip(item.query, DealsRequest.maxItemLength))\""
            guard let index = BasketSolver.cheapestIndex(item.offers, chainOrder: order) else {
                data.append(item.offers.isEmpty
                    ? "- \(query): nothing in the leaflets read"
                    : "- \(query): \(item.offers.count) offer\(item.offers.count == 1 ? "" : "s") without a price in \(BasketSolver.defaultCurrency) Doddy's code could compare; the user can see them on screen")
                continue
            }
            let cheapest = item.offers[index]
            var parts = ["- \(query): cheapest at \(name(cheapest.chain))", "\"\(clip(cheapest.product, 160))\"", offerPrice(cheapest, money)]
            if !cheapest.conditions.isEmpty {
                parts.append("conditions: " + cheapest.conditions.prefix(4).map { clip($0, 80) }.joined(separator: "; "))
            }
            if let to = cheapest.validTo { parts.append("until \(to.rawValue)") }
            if cheapest.check { parts.append("needs checking") }
            let others = item.offers.indices.filter { $0 != index }.prefix(othersShown).map { other in
                let offer = item.offers[other]
                return "\(name(offer.chain)) \(money(offer.price))" + (offer.check ? " (needs checking)" : "")
            }
            if !others.isEmpty { parts.append("also: " + others.joined(separator: ", ")) }
            data.append(parts.joined(separator: " · "))
        }
        data.append("Read at: \(clip(result.checkedAt, 40))")
        return ErrandResultText.bounded(header: header, data: data, footer: footer, maxCharacters: maxCharacters, cutNote: cutNote)
    }

    /// A chain's name, cleaned: one this app doesn't know is named by the server's identifier.
    static func name(_ chain: DealsChain) -> String { ErrandsPrompt.clip(chain.name, 40) }

    static let footer = "Links to the leaflets are on the user's screen; don't read them out."
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

    static func chainLines(_ result: DealsResult) -> [String] {
        var read: [String] = []
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
            case .noMatch: nothing.append(name)
            case .noLeaflet: notRead.append("\(name): no leaflet found for this week")
            case .blocked: notRead.append("\(name): its site blocked Doddy's reader")
            case .failed: notRead.append("\(name): couldn't be read")
            case .linkOnly: notRead.append("\(name): not read, only a link to its leaflet (on screen)")
            case .unknown: notRead.append("\(name): not known whether it was read")
            }
        }
        var out: [String] = []
        if !read.isEmpty { out.append("Leaflets read: " + read.joined(separator: ", ")) }
        if !nothing.isEmpty { out.append("Read, nothing matched: " + nothing.joined(separator: ", ")) }
        if !notRead.isEmpty { out.append("Not checked: " + notRead.joined(separator: "; ")) }
        return out
    }

    static func basketLine(_ basket: Basket, _ money: (Money) -> String) -> String? {
        guard let single = basket.bestSingleChain else { return nil }
        func plan(_ plan: BasketPlan) -> String {
            let names = plan.chains.map(name).joined(separator: " + ")
            return "\(names), \(plan.covered) of \(plan.itemCount) items, \(money(plan.total))"
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
