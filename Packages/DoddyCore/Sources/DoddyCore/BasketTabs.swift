import Foundation

// The leaflet answer as three tabs (owner, 12–13 Nov 2026, docs/strategy/PRZEGLAD_APLIKACJI_2026-11-12.md 1.5;
// decision 2026-11-13-shopping-one-field): where to go with the list.
//   - One shop: the shop where most items cost least (`BasketSolver`'s best single chain), its total and what it lacks.
//   - Two shops: only when `BasketSolver` offers a pair, so only when it covers more items or saves at least the
//     person's own minimum (ADR-664). When it doesn't, `noSecondShop` says why, with the saving when there is one.
//   - Each item separately: per item its cheapest line for the quantity asked and, under it, the other shops' lines
//     (`BasketSolver.options`), so the first line of each row is exactly the line "everything at its cheapest" takes.
// Every amount is the solver's, summed in grosze from the leaflet prices the server parsed; nothing here prices,
// rounds or guesses anything (DOD-02). One item has no "shops" to choose between, so it is shown as its own row only.
//
// Platforms: iPhone (Shopping › the leaflet answer). Pure logic; tested on Linux.

public struct BasketTabs: Equatable, Sendable {
    public enum Tab: String, CaseIterable, Equatable, Sendable {
        case oneShop, twoShops, eachItem
    }

    /// Why there is no "Two shops" tab.
    public enum NoSecondShop: Equatable, Sendable {
        /// No pair covers more items, or the same items for less.
        case savesNothing
        /// The best pair would save this much for the same items: less than the person's minimum.
        case savesTooLittle(saving: Money, minimum: Money)
    }

    /// One item: its cheapest line anywhere and the other shops' lines, cheapest first.
    public struct ItemRow: Equatable, Sendable {
        /// The item's place in the answer's `items`.
        public let itemIndex: Int
        public let query: String
        /// Nil when no offer counts (none found, another currency, or only an app the person doesn't use).
        public let cheapest: BasketPlan.Line?
        public let others: [BasketPlan.Line]

        public init(itemIndex: Int, query: String, cheapest: BasketPlan.Line?, others: [BasketPlan.Line]) {
            self.itemIndex = itemIndex
            self.query = query
            self.cheapest = cheapest
            self.others = others
        }

        /// The other shops in one line: "Lidl 5,49 zł · Dino 5,99 zł (check)". A total that is a lower bound says
        /// "at least"; an offer Doddy's code couldn't confirm says so. Nil when there are none.
        public func othersText(_ language: NotificationLanguage) -> String? {
            guard !others.isEmpty else { return nil }
            return others.map { line in
                var text = line.chain.name + " "
                if line.cost.isLowerBound { text += language == .polish ? "co najmniej " : "at least " }
                text += line.total.text(language)
                if line.needsChecking { text += language == .polish ? " (sprawdź)" : " (check)" }
                return text
            }.joined(separator: " · ")
        }
    }

    public let oneShop: BasketPlan?
    public let twoShops: BasketPlan?
    /// How much less two shops cost than one, for the same items; nil when they cover more (or there's no pair).
    public let savings: Money?
    /// Set only when there is one shop and no second: why.
    public let noSecondShop: NoSecondShop?
    /// One row per item, in the answer's order.
    public let eachItem: [ItemRow]
    /// Every item at its cheapest, in as many shops as that takes: the total of "each item separately".
    public let everything: BasketPlan?

    public init(oneShop: BasketPlan?, twoShops: BasketPlan?, savings: Money?, noSecondShop: NoSecondShop?,
                eachItem: [ItemRow], everything: BasketPlan?) {
        self.oneShop = oneShop
        self.twoShops = twoShops
        self.savings = savings
        self.noSecondShop = noSecondShop
        self.eachItem = eachItem
        self.everything = everything
    }

    /// The tabs to show, in this order. One item: only its row. No offer counted anywhere: only the rows (which say
    /// so). Otherwise one shop, two shops when there is a pair, and each item.
    public var tabs: [Tab] {
        guard !eachItem.isEmpty else { return [] }
        guard eachItem.count > 1 else { return [.eachItem] }
        var tabs: [Tab] = []
        if oneShop != nil { tabs.append(.oneShop) }
        if twoShops != nil { tabs.append(.twoShops) }
        tabs.append(.eachItem)
        return tabs
    }

    /// The tab shown first: one shop when there is one.
    public var firstTab: Tab? { tabs.first }

    /// The tabs for `result`, with the same quantities, loyalty apps and minimum saving as the basket.
    public static func make(_ result: DealsResult, currency: String = BasketSolver.defaultCurrency,
                            quantities: [ListQuantity?] = [], programs: DealsPrograms = .all,
                            minimumSaving: Int = 0) -> BasketTabs {
        let basket = BasketSolver.solve(result, currency: currency, quantities: quantities, programs: programs,
                                        minimumSaving: minimumSaving)
        let options = BasketSolver.options(result, currency: currency, quantities: quantities, programs: programs)
        let rows = result.items.enumerated().map { index, item in
            let lines = index < options.count ? options[index] : []
            return ItemRow(itemIndex: index, query: item.query, cheapest: lines.first, others: Array(lines.dropFirst()))
        }
        var noSecondShop: NoSecondShop?
        if let single = basket.bestSingleChain, basket.bestPair == nil, result.items.count > 1 {
            noSecondShop = .savesNothing
            // The pair the minimum held back, if any: the same solve with no minimum.
            if minimumSaving > 0,
               let free = BasketSolver.solve(result, currency: currency, quantities: quantities, programs: programs).bestPair,
               free.covered == single.covered, single.total.minor > free.total.minor {
                noSecondShop = .savesTooLittle(saving: Money(minor: single.total.minor - free.total.minor, currency: currency),
                                               minimum: Money(minor: minimumSaving, currency: currency))
            }
        }
        return BasketTabs(oneShop: basket.bestSingleChain, twoShops: basket.bestPair, savings: basket.savings,
                          noSecondShop: noSecondShop, eachItem: rows, everything: basket.everythingCheapest)
    }
}

extension DealsResult {
    /// The same answer with each item in `kinds` (by its place) narrowed to the offers of the kind picked for it
    /// (`DealsVariants`), so the tabs count only that kind ("kawa" → "mielona"). An item with no pick, a pick that
    /// isn't one of its kinds, or a place out of range is left as it was. Nothing else changes.
    public func narrowed(to kinds: [Int: String]) -> DealsResult {
        guard !kinds.isEmpty else { return self }
        let items = self.items.enumerated().map { index, item -> DealsItemResult in
            guard let picked = kinds[index], !picked.isEmpty,
                  let variant = DealsVariants.split(item)?.first(where: { $0.label == picked }) else { return item }
            return DealsItemResult(query: item.query, offers: variant.offerIndices.map { item.offers[$0] },
                                   promotions: item.promotions, similar: item.similar)
        }
        return DealsResult(checkedAt: checkedAt, chains: chains, items: items, further: further)
    }
}
