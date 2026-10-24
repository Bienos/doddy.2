import Foundation

// The basket (docs/implementation/SHOPPING.md section 3, "Koszyk"): from one leaflet answer, where
// the user's items cost least in one shop, in two, or each at its cheapest. Pure and deterministic,
// summed in integer minor units by code (never a model, never floating point). Offers marked
// `check: true` are counted, and the plan says they need checking.
//
// Tie-breaks, so the same answer always gives the same basket:
// - an item's offer within one chain (and "everything cheapest" across chains): the lower price,
//   then a confirmed offer (`check: false`) before an unconfirmed one, then the chain's place in
//   the chain order, then the server's own order;
// - plans: more items covered, then the lower total, then fewer unconfirmed offers, then the
//   chain order (of the first chain, then the second).
// Two shops are offered only when they beat the best single shop: more items, or the same items
// for less. Otherwise a second trip buys nothing, and `bestPair` is nil.
// The chain order is the order of the answer's `chains` rows (the request's order), then any
// chain seen only in offers, by identifier.
//
// Only offers in one currency (PLN unless asked otherwise) are summed; an offer in another, or
// with a price that isn't positive or is above `maxPrice`, isn't counted.

/// One way to buy the items: which chains, which offer for each item, the total and the coverage.
public struct BasketPlan: Equatable, Sendable {
    /// One item and the offer chosen for it.
    public struct Line: Equatable, Sendable {
        /// The item's place in the answer's `items`.
        public let itemIndex: Int
        public let query: String
        public let offer: DealOffer

        public var chain: DealsChain { offer.chain }
        /// The leaflet's conditions (app, card, minimum quantity, "2+1"), carried along.
        public var conditions: [String] { offer.conditions }
        public var needsChecking: Bool { offer.check }
    }

    /// The chains the plan uses, in the chain order.
    public let chains: [DealsChain]
    /// The covered items, in the answer's order.
    public let lines: [Line]
    /// The items no allowed chain has, in the answer's order.
    public let missing: [String]
    /// The sum of the chosen offers' prices, in minor units.
    public let total: Money

    /// How many items the answer has.
    public var itemCount: Int { lines.count + missing.count }
    public var covered: Int { lines.count }
    /// Every item has an offer.
    public var coversAll: Bool { missing.isEmpty }
    /// Some chosen offer couldn't be confirmed by the server's code.
    public var needsChecking: Bool { lines.contains(where: \.needsChecking) }
    var uncheckedCount: Int { lines.filter(\.needsChecking).count }
    /// "5 of 6" in English, "5 z 6" in Polish.
    public func coverage(_ language: NotificationLanguage) -> String {
        "\(covered) \(language == .polish ? "z" : "of") \(itemCount)"
    }
}

public struct Basket: Equatable, Sendable {
    /// Every item in one shop: the most items, then the lowest total.
    public let bestSingleChain: BasketPlan?
    /// Two shops, each item at the cheaper of the two: the most items, then the lowest total. Nil
    /// unless it beats `bestSingleChain` (more items, or the same items for less), so it always
    /// uses both shops.
    public let bestPair: BasketPlan?
    /// Each item at its cheapest anywhere, in as many shops as that takes.
    public let everythingCheapest: BasketPlan?
    /// How much less the pair costs than the single shop: only when both cover the same number of
    /// items; nil otherwise (more items for more money isn't a saving).
    public let savings: Money?
}

public enum BasketSolver {
    public static let defaultCurrency = "PLN"
    /// 10,000,000.00 in minor units: a price above this isn't counted, so a sum can't overflow.
    public static let maxPrice = 1_000_000_000

    /// The basket for `result`, from the chains in `chains` (nil: every chain in the answer).
    public static func solve(_ result: DealsResult, chains allowed: Set<DealsChain>? = nil,
                             currency: String = defaultCurrency) -> Basket {
        let order = chainOrder(result)
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        // Per item, per chain: the cheapest offer there.
        var best: [[DealsChain: Candidate]] = []
        for item in result.items {
            var perChain: [DealsChain: Candidate] = [:]
            for (index, offer) in item.offers.enumerated() where counts(offer, currency: currency) {
                if let allowed, !allowed.contains(offer.chain) { continue }
                let candidate = Candidate(offer: offer, serverIndex: index, chainRank: rank[offer.chain] ?? order.count)
                if let held = perChain[offer.chain], !candidate.isBetter(than: held) { continue }
                perChain[offer.chain] = candidate
            }
            best.append(perChain)
        }
        let usable = order.filter { chain in best.contains { $0[chain] != nil } }

        func plan(_ chains: [DealsChain]) -> BasketPlan {
            var lines: [BasketPlan.Line] = []
            var missing: [String] = []
            var total = 0
            for (index, item) in result.items.enumerated() {
                let pick = chains.compactMap { best[index][$0] }.min { $0.isBetter(than: $1) }
                if let pick {
                    lines.append(BasketPlan.Line(itemIndex: index, query: item.query, offer: pick.offer))
                    total += pick.offer.price.minor
                } else {
                    missing.append(item.query)
                }
            }
            let used = Set(lines.map(\.chain))
            return BasketPlan(chains: order.filter(used.contains), lines: lines, missing: missing, total: Money(minor: total, currency: currency))
        }

        let single = usable.map { plan([$0]) }.min { better($0, $1, rank: rank) }
        var pairs: [BasketPlan] = []
        for (i, first) in usable.enumerated() {
            for second in usable.dropFirst(i + 1) { pairs.append(plan([first, second])) }
        }
        // Only a pair that beats the best single shop: one that leaves a shop unused, or costs as
        // much for the same items, is a second trip for nothing.
        var pair = pairs.min { better($0, $1, rank: rank) }
        if let candidate = pair, let single, !beats(candidate, single) { pair = nil }
        let everything = usable.isEmpty ? nil : plan(usable)

        var savings: Money?
        if let single, let pair, single.covered == pair.covered {
            savings = Money(minor: single.total.minor - pair.total.minor, currency: currency)
        }
        return Basket(bestSingleChain: single, bestPair: pair, everythingCheapest: everything, savings: savings)
    }

    /// The cheapest of one item's offers in `currency`, by the same tie-break the basket uses
    /// (price, confirmed first, `chainOrder`, the server's order). Nil when none counts.
    public static func cheapest(_ offers: [DealOffer], chainOrder: [DealsChain] = [], currency: String = defaultCurrency) -> DealOffer? {
        cheapestIndex(offers, chainOrder: chainOrder, currency: currency).map { offers[$0] }
    }

    static func cheapestIndex(_ offers: [DealOffer], chainOrder: [DealsChain] = [], currency: String = defaultCurrency) -> Int? {
        let candidates = offers.indices.filter { counts(offers[$0], currency: currency) }.map { index in
            Candidate(offer: offers[index], serverIndex: index, chainRank: chainOrder.firstIndex(of: offers[index].chain) ?? chainOrder.count)
        }
        return candidates.min { $0.isBetter(than: $1) }?.serverIndex
    }

    // MARK: Plumbing

    struct Candidate {
        let offer: DealOffer
        let serverIndex: Int
        let chainRank: Int

        func isBetter(than other: Candidate) -> Bool {
            (offer.price.minor, offer.check ? 1 : 0, chainRank, serverIndex)
                < (other.offer.price.minor, other.offer.check ? 1 : 0, other.chainRank, other.serverIndex)
        }
    }

    static func counts(_ offer: DealOffer, currency: String) -> Bool {
        offer.price.currency == currency && offer.price.minor > 0 && offer.price.minor <= maxPrice
    }

    /// The answer's chain rows first, then chains seen only in offers, by identifier.
    static func chainOrder(_ result: DealsResult) -> [DealsChain] {
        var order: [DealsChain] = []
        for chain in result.chains.map(\.chain) where !order.contains(chain) { order.append(chain) }
        let extra = Set(result.items.flatMap { $0.offers.map(\.chain) }).subtracting(order)
        return order + extra.sorted { $0.rawValue < $1.rawValue }
    }

    /// More items, or the same items for less.
    static func beats(_ a: BasketPlan, _ b: BasketPlan) -> Bool {
        a.covered != b.covered ? a.covered > b.covered : a.total.minor < b.total.minor
    }

    /// More items, then the lower total, then fewer unconfirmed offers, then the chain order.
    static func better(_ a: BasketPlan, _ b: BasketPlan, rank: [DealsChain: Int]) -> Bool {
        if a.covered != b.covered { return a.covered > b.covered }
        if a.total.minor != b.total.minor { return a.total.minor < b.total.minor }
        if a.uncheckedCount != b.uncheckedCount { return a.uncheckedCount < b.uncheckedCount }
        let ranks = { (plan: BasketPlan) in plan.chains.map { rank[$0] ?? Int.max } }
        return ranks(a).lexicographicallyPrecedes(ranks(b))
    }
}
