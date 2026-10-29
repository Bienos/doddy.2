import Foundation

// The basket (docs/implementation/SHOPPING.md section 3, "Koszyk"): from one leaflet answer, where
// the user's items cost least in one shop, in two, or each at its cheapest. Pure and deterministic,
// summed in integer minor units by code (never a model, never floating point). Offers marked
// `check: true` are counted, and the plan says they need checking.
//
// Tie-breaks, so the same answer always gives the same basket:
// - an item's offer within one chain (and "everything cheapest" across chains): the lower cost of
//   the line (the price, for one piece with no conditions), then a confirmed offer (`check: false`) before an unconfirmed one, then the chain's place in
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
//
// Quantities and conditions (ADR-661): each item can come with how many the user needs (from the
// list's words, `pieces(for:size:)`), and each line is costed for that many by `cost(_:quantity:)`:
// a multi-buy ("2+1", "drugi za 5 zł") prices whole groups at the server's per-piece price and the
// rest at the leaflet price; a price "from 2 pieces" counts at least 2 and says so; beyond a
// per-customer limit the rest is at the regular price when the leaflet prints one, and otherwise the
// line says the price of the rest isn't known. An offer whose app or card the user said they don't
// use (`DealsPrograms`) isn't counted. Per-piece prices are rounded up to the grosz by the server, so
// a multi-buy group can come out up to a grosz a piece above the till.

/// One way to buy the items: which chains, which offer for each item, the total and the coverage.
public struct BasketPlan: Equatable, Sendable {
    /// One item and the offer chosen for it.
    public struct Line: Equatable, Sendable {
        /// The item's place in the answer's `items`.
        public let itemIndex: Int
        public let query: String
        public let offer: DealOffer
        /// The pieces counted and what they cost under the offer's conditions.
        public let cost: LineCost

        public init(itemIndex: Int, query: String, offer: DealOffer, cost: LineCost) {
            self.itemIndex = itemIndex
            self.query = query
            self.offer = offer
            self.cost = cost
        }

        public var chain: DealsChain { offer.chain }
        public var quantity: Int { cost.quantity }
        public var total: Money { cost.total }
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
    /// The sum of the lines' totals, in minor units.
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

/// What one line costs: the pieces counted and their total under the offer's conditions.
public struct LineCost: Equatable, Sendable {
    public enum Note: Equatable, Sendable {
        /// `groups` whole multi-buy groups of `size` pieces at the per-piece price.
        case groups(Int, size: Int)
        /// Taking `to` pieces costs no more than the pieces counted (the rest of a "2+1" group is free).
        case takeMore(to: Int)
        /// The price needs at least this many; that many are counted.
        case raisedToMinimum(Int)
        /// More than the per-customer limit: the rest at the regular price.
        case overLimit(Int)
        /// More than the per-customer limit and no regular price printed: the rest is counted at the
        /// leaflet price, which the shop won't give, so the total is too low by an amount not known.
        case overLimitUnpriced(Int)
    }

    public let quantity: Int
    public let total: Money
    public let notes: [Note]

    public init(quantity: Int, total: Money, notes: [Note] = []) {
        self.quantity = quantity
        self.total = total
        self.notes = notes
    }

    /// The total is a lower bound (the price beyond the limit isn't known).
    public var isLowerBound: Bool { notes.contains { if case .overLimitUnpriced = $0 { true } else { false } } }
}

public enum BasketSolver {
    public static let defaultCurrency = "PLN"
    /// 10,000,000.00 in minor units: a price above this isn't counted, so a sum can't overflow.
    public static let maxPrice = 1_000_000_000
    /// The most pieces of one item a line counts.
    public static let maxPieces = 99

    /// The basket for `result`, from the chains in `chains` (nil: every chain in the answer).
    /// `quantities[i]` is how much of item `i` the user needs, from the list's words (missing or
    /// nil: one pack; see `pieces(for:size:)`); offers whose app or card the user doesn't use
    /// (`programs`) aren't counted.
    /// `minimumSaving` (ADR-664, the user's own setting): a second shop is offered only when it saves at least this
    /// much for the same items (more items is always worth saying).
    public static func solve(_ result: DealsResult, chains allowed: Set<DealsChain>? = nil,
                             currency: String = defaultCurrency, quantities: [ListQuantity?] = [],
                             programs: DealsPrograms = .all, minimumSaving: Int = 0) -> Basket {
        let order = chainOrder(result)
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        // Per item, per chain: the offer whose line costs least there.
        var best: [[DealsChain: Candidate]] = []
        for (itemIndex, item) in result.items.enumerated() {
            let wanted = itemIndex < quantities.count ? quantities[itemIndex] : nil
            var perChain: [DealsChain: Candidate] = [:]
            for (index, offer) in item.offers.enumerated() where counts(offer, currency: currency) && programs.canGet(offer) {
                if let allowed, !allowed.contains(offer.chain) { continue }
                let candidate = Candidate(offer: offer, serverIndex: index, chainRank: rank[offer.chain] ?? order.count,
                                          cost: cost(offer, quantity: pieces(for: wanted, size: offer.size)))
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
                    lines.append(BasketPlan.Line(itemIndex: index, query: item.query, offer: pick.offer, cost: pick.cost))
                    total += pick.cost.total.minor
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
        if let candidate = pair, let single, candidate.covered == single.covered,
           single.total.minor - candidate.total.minor < max(minimumSaving, 1) { pair = nil }
        let everything = usable.isEmpty ? nil : plan(usable)

        var savings: Money?
        if let single, let pair, single.covered == pair.covered {
            savings = Money(minor: single.total.minor - pair.total.minor, currency: currency)
        }
        return Basket(bestSingleChain: single, bestPair: pair, everythingCheapest: everything, savings: savings)
    }

    /// What `quantity` pieces of `offer` cost under its conditions (see the header). Never above
    /// `maxPieces` pieces; at least one.
    public static func cost(_ offer: DealOffer, quantity wanted: Int) -> LineCost {
        let price = offer.price.minor
        let currency = offer.price.currency
        var notes: [LineCost.Note] = []
        var count = min(max(wanted, 1), maxPieces)
        if offer.needsMinimumQuantity, let minimum = offer.effective?.quantity, count < minimum {
            count = minimum
            notes.append(.raisedToMinimum(minimum))
        }
        // Pieces at the leaflet's price, under the mechanic.
        func promo(_ pieces: Int) -> Int {
            guard offer.isMultiBuy, let e = offer.effective else { return pieces * price }
            return (pieces / e.quantity) * e.quantity * e.price.minor + (pieces % e.quantity) * price
        }
        var promoPieces = count
        var rest = 0
        var total: Int
        if let limit = offer.limit, count > limit {
            promoPieces = limit
            rest = count - limit
            total = promo(limit)
            if let regular = offer.regularPrice, regular.currency == currency, regular.minor > price, regular.minor <= maxPrice {
                total += rest * regular.minor
                notes.append(.overLimit(limit))
            } else {
                total += rest * price
                notes.append(.overLimitUnpriced(limit))
            }
        } else {
            total = promo(count)
        }
        if offer.isMultiBuy, let e = offer.effective {
            let groups = promoPieces / e.quantity
            if groups > 0 { notes.append(.groups(groups, size: e.quantity)) }
            // A "2+1" bought as 2: the third costs nothing more (within the server's rounding to the grosz).
            let next = (groups + 1) * e.quantity
            if promoPieces % e.quantity != 0, rest == 0, next <= offer.limit ?? maxPieces, next <= maxPieces,
               promo(next) - total < e.quantity {
                notes.append(.takeMore(to: next))
            }
        }
        return LineCost(quantity: count, total: Money(minor: total, currency: currency), notes: notes)
    }

    /// How many packs of an offer a list quantity asks for: a count, packs, bottles or cans as they
    /// are (rounded up to whole pieces); grams or millilitres divided by the pack's size when its
    /// size was read in the same kind, rounded up; anything else, one. At most `maxPieces`.
    public static func pieces(for quantity: ListQuantity?, size: DealOffer.Size?) -> Int {
        guard let quantity, quantity.amount > 0 else { return 1 }
        func whole(_ value: Decimal) -> Int {
            var input = value
            var rounded = Decimal()
            NSDecimalRound(&rounded, &input, 0, .up)
            let n = NSDecimalNumber(decimal: rounded).intValue
            return min(max(n, 1), maxPieces)
        }
        switch quantity.kind {
        case .count, .pack, .bottle, .can:
            return whole(quantity.amount)
        case .mass, .volume:
            guard let size, size.value > 0, size.value.isFinite else { return 1 }
            let pack: Decimal
            switch (quantity.kind, size.unit) {
            case (.mass, .g), (.volume, .ml): pack = Decimal(size.value)
            case (.mass, .kg), (.volume, .l): pack = Decimal(size.value) * 1000
            default: return 1
            }
            return whole(quantity.baseAmount / pack)
        }
    }

    /// The cheapest of one item's offers in `currency` for one piece under its conditions, by the
    /// same tie-break the basket uses (cost, confirmed first, `chainOrder`, the server's order). Nil
    /// when none counts.
    public static func cheapest(_ offers: [DealOffer], chainOrder: [DealsChain] = [], currency: String = defaultCurrency) -> DealOffer? {
        cheapestIndex(offers, chainOrder: chainOrder, currency: currency).map { offers[$0] }
    }

    static func cheapestIndex(_ offers: [DealOffer], chainOrder: [DealsChain] = [], currency: String = defaultCurrency,
                              programs: DealsPrograms = .all) -> Int? {
        candidates(offers, chainOrder: chainOrder, currency: currency, programs: programs).min { $0.isBetter(than: $1) }?.serverIndex
    }

    /// The offer to show first for one item: the lowest price per kg, l or piece, in the unit most
    /// of its offers are priced in (kg, then l, then piece on a tie), so a kilo pack can beat a
    /// small one; when none has a unit price, the cheapest pack. A pack whose size wasn't read
    /// can't be called cheaper per kg, so it is never the pick while one with a size is there.
    /// The same rule as the server's order (SHOPPING.md section 2), worked out here too so an
    /// answer from an older server, sorted by pack price, shows the same pick. Under a multi-buy the
    /// price per kg is the one at the mechanic's quantity, and a price that asks for the chain's app
    /// or card, or for several pieces, counts 5% dearer for each (`conditionPenalty`), so a near tie
    /// goes to the price anyone gets (ADR-661). Offers the user can't get (`programs`) aren't picked.
    public static func bestValue(_ offers: [DealOffer], chainOrder: [DealsChain] = [], currency: String = defaultCurrency,
                                 programs: DealsPrograms = .all) -> DealOffer? {
        bestValueIndex(offers, chainOrder: chainOrder, currency: currency, programs: programs).map { offers[$0.index] }
    }

    /// The server's `CONDITION_PENALTY`.
    public static let conditionPenalty = 0.05

    /// The unit price an offer is ranked by in `per`, with the penalty; nil when it has none in `per`.
    static func rankValue(_ offer: DealOffer, per: DealOffer.UnitPer) -> Double? {
        guard let unit = offer.effective?.unitPrice ?? offer.unitPrice, unit.per == per, unit.minor > 0 else { return nil }
        let asks = (offer.needsProgram ? 1 : 0) + ((offer.effective?.quantity ?? 1) > 1 ? 1 : 0)
        return Double(unit.minor) * (1 + conditionPenalty * Double(asks))
    }

    /// `bestValue`'s index, with the unit it was compared in (nil when it was the cheapest pack).
    static func bestValueIndex(_ offers: [DealOffer], chainOrder: [DealsChain] = [], currency: String = defaultCurrency,
                               programs: DealsPrograms = .all) -> (index: Int, per: DealOffer.UnitPer?)? {
        let all = candidates(offers, chainOrder: chainOrder, currency: currency, programs: programs)
        let units: [DealOffer.UnitPer] = [.kg, .l, .szt]
        let counted = units.map { per in all.filter { rankValue($0.offer, per: per) != nil }.count }
        guard let most = counted.max(), most > 0, let unit = counted.firstIndex(of: most) else {
            return cheapestIndex(offers, chainOrder: chainOrder, currency: currency, programs: programs).map { ($0, nil) }
        }
        let per = units[unit]
        let best = all.filter { rankValue($0.offer, per: per) != nil }.min { a, b in
            let (ua, ub) = (rankValue(a.offer, per: per)!, rankValue(b.offer, per: per)!)
            return ua != ub ? ua < ub : a.isBetter(than: b)
        }
        return best.map { ($0.serverIndex, per) }
    }

    static func candidates(_ offers: [DealOffer], chainOrder: [DealsChain], currency: String,
                           programs: DealsPrograms = .all) -> [Candidate] {
        offers.indices.filter { counts(offers[$0], currency: currency) && programs.canGet(offers[$0]) }.map { index in
            Candidate(offer: offers[index], serverIndex: index, chainRank: chainOrder.firstIndex(of: offers[index].chain) ?? chainOrder.count,
                      cost: cost(offers[index], quantity: 1))
        }
    }

    // MARK: Plumbing

    struct Candidate {
        let offer: DealOffer
        let serverIndex: Int
        let chainRank: Int
        /// The line's cost for the quantity asked (one piece outside the basket).
        let cost: LineCost

        func isBetter(than other: Candidate) -> Bool {
            (cost.total.minor, offer.check ? 1 : 0, chainRank, serverIndex)
                < (other.cost.total.minor, other.offer.check ? 1 : 0, other.chainRank, other.serverIndex)
        }
    }

    static func counts(_ offer: DealOffer, currency: String) -> Bool {
        offer.price.currency == currency && offer.price.minor > 0 && offer.price.minor <= maxPrice
    }

    /// The answer's chain rows first, then chains seen only in offers, by identifier.
    public static func chainOrder(_ result: DealsResult) -> [DealsChain] {
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
