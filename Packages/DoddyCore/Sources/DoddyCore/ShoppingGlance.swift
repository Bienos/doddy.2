import Foundation

// The Shopping screens at a glance (owner, 13 Nov 2026: "to musi być dobrze zrobione … graficznie i animacyjnie,
// kreatywnie, ale tak, żeby to było łatwe do ogarnięcia"): the look-and-motion pass on the screens of decision
// 2026-11-13-shopping-one-field. These are the rules behind the pictures, so the views draw and never decide:
//   - `DealChip`: one leaflet condition as a small chip of a known kind (the shop's app, a card, "2+1", a minimum,
//     a limit, a deposit, while stocks last, some shops only), always in the words the server's code wrote, and at
//     most one chip for the day, from the dates the leaflet prints ("not on until Thu", "today is the last day",
//     "buy by Sat" when the last day is a closed day, "until Sat"). A kind only picks the chip's icon.
//   - `BasketTabs.plan(for:)`: the plan behind each tab, so a tab can show its total before it is opened;
//     `secondShopGain` and `savingsLine(_:)`: what a second shop gains, worded once.
//   - `DealsResult.chainsRead`, `chainsNotRead`, `foundNothing` and `DealsRequest.leafletsAsked`: which leaflets a
//     check asks for and which the answer says were read (only what the request and the answer hold: the screen
//     shows no per-shop progress while it waits), and an answer with nothing in it at all.
// Nothing here prices, rounds or guesses: every amount is `BasketSolver`'s, summed in grosze (DOD-02).
//
// Platforms: iPhone (Shopping). Pure logic; tested on Linux.

/// One small chip under a leaflet line: a condition in the server's words, or the line's day.
public struct DealChip: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable, CaseIterable {
        /// The chain's app or an app coupon.
        case app
        /// The chain's loyalty card.
        case card
        /// "2+1", "druga sztuka za 5 zł", "co druga sztuka −50%".
        case multiBuy
        /// "przy zakupie 2 szt.": the price needs at least this many.
        case minimum
        /// "max 2 szt.": at most this many per customer.
        case limit
        /// A container deposit is added at the till.
        case deposit
        /// While stocks last.
        case stock
        /// Only in some of the chain's shops.
        case someShops
        /// Any other condition the server wrote ("tylko online").
        case other
        /// The price isn't on yet: from `day`.
        case startsOn
        /// Today is the price's last day.
        case lastDay
        /// The last day falls on a day the shops are closed: buy by `day`.
        case buyBy
        /// The leaflet's last day, `day`.
        case until
    }

    public let kind: Kind
    /// The condition as the server's code wrote it; nil for a day chip, which the app words.
    public let text: String?
    /// The day of a `startsOn`, `buyBy` or `until` chip.
    public let day: DealDay?

    public init(kind: Kind, text: String? = nil, day: DealDay? = nil) {
        self.kind = kind
        self.text = text
        self.day = day
    }

    /// A chip about the day rather than a condition.
    public var isDay: Bool {
        switch kind {
        case .startsOn, .lastDay, .buyBy, .until: true
        default: false
        }
    }

    /// The kind of one condition, from the words the server's code writes for each (`conditionText` in
    /// server/messaging/src/deals/service.ts, Polish and English). A condition no rule knows is `other`.
    public static func kind(of condition: String) -> Kind {
        let folded = SearchFolding.fold(condition)
        let words = SearchFolding.tokens(folded: folded)
        func word(_ exact: String...) -> Bool { words.contains { exact.contains($0) } }
        func starts(_ prefixes: String...) -> Bool { words.contains { w in prefixes.contains { w.hasPrefix($0) } } }
        if starts("kaucj", "deposit") { return .deposit }
        if starts("wyczerpan") || folded.contains("while stocks") { return .stock }
        if starts("wybran") || folded.contains("selected store") || folded.contains("some shops") { return .someShops }
        if starts("kart", "card") { return .card }
        if starts("aplikac") || word("app", "apps", "aplikacja") || folded.contains("lidl plus") { return .app }
        if folded.contains("przy zakupie") || folded.contains("when buying") || word("min") { return .minimum }
        if word("max", "maks", "limit") || folded.contains("per customer") || folded.contains("na klienta") { return .limit }
        if folded.range(of: #"\d\s*\+\s*\d"#, options: .regularExpression) != nil
            || starts("sztuk") || folded.contains("the second") || folded.contains("every ") {
            return .multiBuy
        }
        return .other
    }

    /// The chips for one offer: its conditions in the server's order (each once, blank ones left out), then at most
    /// one day chip. The day chip follows `DealsChecklist` ("Before you go"): a price not on yet, today as the last
    /// day, a last day on which the shops are closed; otherwise the last day the leaflet prints, when it is still
    /// ahead. `today` nil (the calendar couldn't be read): the printed last day, as printed.
    public static func chips(for offer: DealOffer, today: DealDay?) -> [DealChip] {
        var chips: [DealChip] = []
        var seen = Set<String>()
        for condition in offer.conditions {
            let text = condition.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, seen.insert(SearchFolding.fold(text)).inserted else { continue }
            chips.append(DealChip(kind: kind(of: text), text: text))
        }
        if let day = dayChip(offer, today: today) { chips.append(day) }
        return chips
    }

    static func dayChip(_ offer: DealOffer, today: DealDay?) -> DealChip? {
        guard let today else { return offer.validTo.map { DealChip(kind: .until, day: $0) } }
        for entry in DealsChecklist.entries(for: offer, today: today) {
            switch entry.kind {
            case .startsOn(let day): return DealChip(kind: .startsOn, day: day)
            case .lastDay: return DealChip(kind: .lastDay)
            case .lastOpenDay(let day): return DealChip(kind: .buyBy, day: day)
            default: continue
            }
        }
        if let to = offer.validTo, to > today { return DealChip(kind: .until, day: to) }
        return nil
    }
}

extension BasketPlan {
    /// The total is a lower bound: a line's price beyond a per-customer limit isn't printed ("at least").
    public var totalIsLowerBound: Bool { lines.contains { $0.cost.isLowerBound } }
}

extension BasketTabs {
    /// What a second shop gains over one, when the "Two shops" tab is there.
    public enum SecondShopGain: Equatable, Sendable {
        /// The same items for this much less.
        case saves(Money)
        /// More items: the pair has `pair` of them, the single shop `single`.
        case moreItems(pair: Int, single: Int)
    }

    /// The plan a tab shows and whose total its title carries: the single shop, the pair, or every item at its
    /// cheapest. Nil when the tab has no plan (no pair; no offer counted anywhere).
    public func plan(for tab: Tab) -> BasketPlan? {
        switch tab {
        case .oneShop: oneShop
        case .twoShops: twoShops
        case .eachItem: everything
        }
    }

    /// Nil when there is no pair, or no single shop to compare it with.
    public var secondShopGain: SecondShopGain? {
        guard let pair = twoShops else { return nil }
        if let savings, savings.minor > 0 { return .saves(savings) }
        if let single = oneShop, pair.covered > single.covered { return .moreItems(pair: pair.covered, single: single.covered) }
        return nil
    }

    /// The saving in one line, said as a fact and not a push (the choice stays the person's, ADR-664):
    /// "Oszczędzasz 3,20 zł w dwóch sklepach" / "You save PLN 3.20 in two shops". Nil unless two shops cost less for
    /// the same items.
    public func savingsLine(_ language: NotificationLanguage) -> String? {
        guard case .saves(let money)? = secondShopGain else { return nil }
        switch language {
        case .polish: return "Oszczędzasz \(money.text(.polish)) w dwóch sklepach"
        case .english: return "You save \(money.text(.english)) in two shops"
        }
    }
}

extension DealsResult {
    /// The chains whose leaflets were read for this answer (whether or not anything matched), in the answer's order.
    public var chainsRead: [DealsChain] { chains.filter { $0.status.wasRead }.map(\.chain) }

    /// The chains asked for whose leaflets weren't read (blocked, failed, no leaflet, link only, unknown).
    public var chainsNotRead: [DealsChain] { chains.filter { !$0.status.wasRead }.map(\.chain) }

    /// Not one item has an offer, a promotion or a similar product: the answer has nothing to show but the next step.
    public var foundNothing: Bool {
        !items.isEmpty && items.allSatisfy { $0.offers.isEmpty && $0.promotions.isEmpty && $0.similar.isEmpty }
    }
}

extension DealsRequest {
    /// The leaflets this check asks Doddy's server to read, in the request's order (link-only chains left out).
    /// What the screen names while it waits: the request's content, not a progress report.
    public var leafletsAsked: [DealsChain] { chainsAsked.filter(\.isRead) }
}
