import Foundation

// Shopping mode, stage 1 (docs/implementation/SHOPPING.md, ADR-607 to ADR-610): the result of a
// shopping task ("Znajdź mi to"), next to the research card's fields. No price ever comes from the
// model: every offer here was registered by a tool the server's code ran, and the code wrote its
// price, shop, link and time. The model's picks name offers by id, and a pick whose offer isn't
// here is never shown. Money is always integer minor units (grosze) with an ISO currency code.

// MARK: - Money

/// An amount in minor units (grosze for PLN) and an ISO 4217 code. Never a floating-point number,
/// so sums are exact. Every currency is treated as having two decimal places, as the contract
/// writes them.
public struct Money: Codable, Hashable, Sendable {
    public let minor: Int
    public let currency: String

    public init(minor: Int, currency: String = "PLN") {
        self.minor = minor
        self.currency = currency
    }

    /// The separator `text(.polish)` writes between thousands and before the currency: U+00A0
    /// NO-BREAK SPACE, the one the server writes (server/messaging/src/shopping/money.ts), so a
    /// price never breaks across lines and the app's text equals the server's.
    public static let polishSpace = "\u{00A0}"

    /// Polish: "1 899,00 zł" (no-break spaces; another currency's code in place of "zł").
    /// English: "PLN 1,899.00". A negative amount gets a leading "-" on the number.
    public func text(_ language: NotificationLanguage) -> String {
        let magnitude = minor.magnitude
        let whole = magnitude / 100
        let fraction = magnitude % 100
        let cents = fraction < 10 ? "0\(fraction)" : "\(fraction)"
        let sign = minor < 0 ? "-" : ""
        switch language {
        case .polish:
            let unit = currency == "PLN" ? "zł" : currency
            return "\(sign)\(Self.grouped(whole, Self.polishSpace)),\(cents)\(Self.polishSpace)\(unit)"
        case .english:
            return "\(currency) \(sign)\(Self.grouped(whole, ",")).\(cents)"
        }
    }

    /// For a two-letter language code: Polish for "pl", English otherwise.
    public func text(language code: String) -> String {
        text(code.lowercased() == "pl" ? .polish : .english)
    }

    static func grouped(_ value: UInt, _ separator: String) -> String {
        let digits = Array(String(value))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out += separator }
            out.append(digit)
        }
        return out
    }
}

// MARK: - The shopping result

/// One offer a tool run by the server's code registered (`find_offers` or `check_offer_page`).
public struct ShoppingOffer: Codable, Equatable, Sendable, Identifiable {
    /// Where the price came from.
    public enum Evidence: String, Codable, Sendable, CaseIterable {
        /// Read from the shop's own page (its schema.org Product/Offer data).
        case shopPage = "shop_page"
        /// From the Google Shopping list (the offer source), not checked on the shop's page.
        case listing
        /// A kind this version of the app doesn't know. Never shown as checked.
        case unknown

        public init(from decoder: any Decoder) throws {
            self = Evidence(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }

        /// For the result card, next to the price, in the iPhone's language (SHOPPING.md wording).
        public func label(_ language: NotificationLanguage) -> String {
            switch (self, language) {
            case (.shopPage, .polish): "Cena sprawdzona na stronie sklepu"
            case (.shopPage, .english): "Price checked on the shop's page"
            case (.listing, .polish): "Cena z listy Google Shopping"
            case (.listing, .english): "Price from the Google Shopping list"
            case (.unknown, .polish): "Nie wiadomo, skąd jest ta cena"
            case (.unknown, .english): "Where this price came from isn't known"
            }
        }

        /// For the voice agent: a few words after the price.
        public var agentWords: String {
            switch self {
            case .shopPage: "checked on the shop's page"
            case .listing: "from the Google Shopping list"
            case .unknown: "source of the price not known"
            }
        }
    }

    /// `o1`, `o2`, …: what the picks refer to.
    public let id: String
    public let title: String
    public let shop: String
    public let price: Money
    /// The shop's delivery text, as the source gave it.
    public let delivery: String?
    public let url: String
    public let site: String?
    public let evidence: Evidence
    /// When the code saw this price.
    public let seenAt: Date
    /// 8 to 14 digits, when the source gave one.
    public let gtin: String?
    /// Doddy's short words on the offer ("42 dB · 10 kompletów"), never a price.
    public let notes: String?

    public init(id: String, title: String, shop: String, price: Money, delivery: String? = nil, url: String, site: String? = nil,
                evidence: Evidence, seenAt: Date, gtin: String? = nil, notes: String? = nil) {
        self.id = id
        self.title = title
        self.shop = shop
        self.price = price
        self.delivery = delivery
        self.url = url
        self.site = site
        self.evidence = evidence
        self.seenAt = seenAt
        self.gtin = gtin
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey { case id, title, shop, price, delivery, url, site, evidence, seenAt, gtin, notes }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        shop = try c.decode(String.self, forKey: .shop)
        price = try c.decode(Money.self, forKey: .price)
        delivery = try c.decodeIfPresent(String.self, forKey: .delivery)
        url = try c.decode(String.self, forKey: .url)
        site = try c.decodeIfPresent(String.self, forKey: .site)
        // A missing evidence is not a checked price.
        evidence = try c.decodeIfPresent(Evidence.self, forKey: .evidence) ?? .unknown
        seenAt = try c.serverDate(.seenAt)
        gtin = try c.decodeIfPresent(String.self, forKey: .gtin)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    /// `seenAt` is written as the server writes it (ISO 8601 with milliseconds), whatever date
    /// strategy the encoder has, so the result kept on the iPhone reads back unchanged.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(shop, forKey: .shop)
        try c.encode(price, forKey: .price)
        try c.encodeIfPresent(delivery, forKey: .delivery)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(site, forKey: .site)
        try c.encode(evidence.rawValue, forKey: .evidence)
        try c.encode(ShoppingDates.format(seenAt), forKey: .seenAt)
        try c.encodeIfPresent(gtin, forKey: .gtin)
        try c.encodeIfPresent(notes, forKey: .notes)
    }
}

/// One of the model's picks, by offer id. The why and the trade-off are the model's words (the
/// server already removed any sentence with an amount that isn't an offer's price or the budget);
/// `overBudget` was computed by the server's code.
public struct ShoppingPick: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable, CaseIterable {
        /// "Mój wybór": the best fit for the user's priorities.
        case best
        /// The cheapest picked offer (the server relabels it when another pick is cheaper).
        case cheapest
        /// "Bez kompromisów": the best regardless of budget.
        case premium
        case alternative
        /// A role this version of the app doesn't know; shown last, as another option.
        case unknown

        public init(from decoder: any Decoder) throws {
            self = Role(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }

        /// The order picks are shown in: best, cheapest, premium, alternative, then unknown.
        public var displayRank: Int {
            switch self {
            case .best: 0
            case .cheapest: 1
            case .premium: 2
            case .alternative: 3
            case .unknown: 4
            }
        }

        /// For the result card, in the iPhone's language.
        public func label(_ language: NotificationLanguage) -> String {
            switch (self, language) {
            case (.best, .polish): "Mój wybór"
            case (.best, .english): "My pick"
            case (.cheapest, .polish): "Najtańsza"
            case (.cheapest, .english): "Cheapest"
            case (.premium, .polish): "Bez kompromisów"
            case (.premium, .english): "No compromises"
            case (.alternative, .polish): "Inna opcja"
            case (.alternative, .english): "Another option"
            case (.unknown, .polish): "Inna opcja"
            case (.unknown, .english): "Another option"
            }
        }
    }

    public let role: Role
    public let offerId: String
    public let why: String
    public let tradeoff: String?
    /// How far the price is above the user's budget, when it is.
    public let overBudget: Money?

    public init(role: Role, offerId: String, why: String, tradeoff: String? = nil, overBudget: Money? = nil) {
        self.role = role
        self.offerId = offerId
        self.why = why
        self.tradeoff = tradeoff
        self.overBudget = overBudget
    }
}

/// `result.shopping` (SHOPPING.md, "Result"). Exactly the server's schema; lists the server may
/// leave out read as empty.
public struct ShoppingResult: Codable, Equatable, Sendable {
    /// Counted by the server's code.
    public struct Stats: Codable, Equatable, Sendable {
        public let offersSeen: Int
        public let shops: Int

        public init(offersSeen: Int, shops: Int) {
            self.offersSeen = offersSeen
            self.shops = shops
        }
    }

    /// The user's order, from the task.
    public let priorities: [String]
    /// The budget the user gave, when they gave one.
    public let budget: Money?
    public let offers: [ShoppingOffer]
    public let picks: [ShoppingPick]
    /// Doddy's words: how it chose (at most 3), what to watch out for, what isn't known, and what
    /// it left out and why (at most 4 each).
    public let howChosen: [String]
    public let watchOuts: [String]
    public let unknowns: [String]
    public let rejected: [String]
    public let stats: Stats?

    public init(priorities: [String] = [], budget: Money? = nil, offers: [ShoppingOffer], picks: [ShoppingPick],
                howChosen: [String] = [], watchOuts: [String] = [], unknowns: [String] = [], rejected: [String] = [],
                stats: Stats? = nil) {
        self.priorities = priorities
        self.budget = budget
        self.offers = offers
        self.picks = picks
        self.howChosen = howChosen
        self.watchOuts = watchOuts
        self.unknowns = unknowns
        self.rejected = rejected
        self.stats = stats
    }

    private enum CodingKeys: String, CodingKey { case priorities, budget, offers, picks, howChosen, watchOuts, unknowns, rejected, stats }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        priorities = try c.decodeIfPresent([String].self, forKey: .priorities) ?? []
        budget = try c.decodeIfPresent(Money.self, forKey: .budget)
        offers = try c.decode([ShoppingOffer].self, forKey: .offers)
        picks = try c.decode([ShoppingPick].self, forKey: .picks)
        howChosen = try c.decodeIfPresent([String].self, forKey: .howChosen) ?? []
        watchOuts = try c.decodeIfPresent([String].self, forKey: .watchOuts) ?? []
        unknowns = try c.decodeIfPresent([String].self, forKey: .unknowns) ?? []
        rejected = try c.decodeIfPresent([String].self, forKey: .rejected) ?? []
        stats = try c.decodeIfPresent(Stats.self, forKey: .stats)
    }

    /// The registered offer the pick names; nil when there is none (then the pick isn't shown).
    public func offer(for pick: ShoppingPick) -> ShoppingOffer? {
        offers.first { $0.id == pick.offerId }
    }

    /// The first `best` pick whose offer is here.
    public var bestPick: ShoppingPick? {
        picks.first { $0.role == .best && offer(for: $0) != nil }
    }

    /// The picks to show, with their offers: best, cheapest, premium, alternative, then any role
    /// this app doesn't know; the server's order within a role. A pick without its offer is left
    /// out, never filled in.
    public var picksInDisplayOrder: [(pick: ShoppingPick, offer: ShoppingOffer)] {
        picks.enumerated()
            .compactMap { index, pick in offer(for: pick).map { (index, pick, $0) } }
            .sorted { ($0.1.role.displayRank, $0.0) < ($1.1.role.displayRank, $1.0) }
            .map { (pick: $0.1, offer: $0.2) }
    }
}

/// Times in the shopping and leaflet answers, as the server writes them.
enum ShoppingDates {
    /// ISO 8601 with milliseconds, UTC: what `ServerDates.parse` reads back to the same instant.
    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// "2026-10-24 14:02" in the calendar's time zone, for the voice agent.
    static func local(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }
}

// MARK: - What the voice agent hears

/// The shopping block of a `check_errands` reply (ErrandResultText): the picks with the prices,
/// shops, evidence and times the server's code wrote, then Doddy's notes. Links stay on the card.
/// Every line is cleaned (no data markers, one line); the caller puts them between the markers.
enum ShoppingResultText {
    static func lines(_ shopping: ShoppingResult, language: String, calendar: Calendar) -> [String] {
        let clip = ErrandsPrompt.clip
        let money = { (amount: Money) in amount.text(language: language) }
        var out: [String] = []
        let shown = shopping.picksInDisplayOrder
        if shown.isEmpty {
            out.append("Picks: none that Doddy's code could match to an offer, so there is nothing to recommend.")
        } else {
            out.append("Picks (prices, shops and times are the offers' own, written by Doddy's code; never change them):")
        }
        for (pick, offer) in shown {
            var parts = [
                "- \(roleWords(pick.role)): \"\(clip(offer.title, 160))\"",
                "\(money(offer.price)) at \(clip(offer.shop, 80))",
                "price \(offer.evidence.agentWords), \(ShoppingDates.local(offer.seenAt, calendar: calendar))",
            ]
            if let over = pick.overBudget { parts.append("\(money(over)) over the budget") }
            if let delivery = offer.delivery { parts.append("delivery: \(clip(delivery, 120))") }
            parts.append("why: \(clip(pick.why, 200))")
            if let tradeoff = pick.tradeoff { parts.append("trade-off: \(clip(tradeoff, 200))") }
            if let notes = offer.notes { parts.append("notes: \(clip(notes, 160))") }
            out.append(parts.joined(separator: " · "))
        }
        if !shopping.priorities.isEmpty {
            out.append("What the user said matters most, in order: " + shopping.priorities.map { "\"\(clip($0, 40))\"" }.joined(separator: ", "))
        }
        if let budget = shopping.budget { out.append("Budget the user gave: \(money(budget))") }
        let notes: [(String, [String])] = [
            ("How Doddy chose", shopping.howChosen), ("Watch out", shopping.watchOuts),
            ("Not known", shopping.unknowns), ("Left out", shopping.rejected),
        ]
        for (label, list) in notes where !list.isEmpty {
            out.append("\(label): " + list.map { "\"\(clip($0, 200))\"" }.joined(separator: "; "))
        }
        if let stats = shopping.stats {
            out.append("Offers Doddy looked at: \(stats.offersSeen), from \(stats.shops) shop\(stats.shops == 1 ? "" : "s").")
        }
        return out
    }

    static func roleWords(_ role: ShoppingPick.Role) -> String {
        switch role {
        case .best: "Best pick"
        case .cheapest: "Cheapest"
        case .premium: "No compromises"
        case .alternative: "Another option"
        case .unknown: "Another option"
        }
    }
}
