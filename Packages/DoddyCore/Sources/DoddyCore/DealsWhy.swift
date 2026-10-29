import Foundation

// "Dlaczego to?" (ADR-664; research docs/research/2026-10-28/research_deals_better.md §5 #11): one sentence, written
// by code, on why an offer is the one shown first for an item, and "Przypomnij w dniu startu" (§5 #5): the words
// and the day of a local notification the user asks for when a leaflet price starts later. Both from the answer
// only; nothing guessed.
//
// Platforms: iPhone (the deals screen). Pure logic; tested on Linux.

public enum DealsWhy: Equatable, Sendable {
    /// The only offer for the item.
    case only
    /// The lowest price per kg, l or piece (under its mechanic when it has one); the next one, when there is one.
    case lowestPerUnit(per: DealOffer.UnitPer, value: Money, next: (chain: DealsChain, value: Money)?)
    /// No sizes to compare: the cheapest pack; the next one, when there is one.
    case cheapestPack(next: (chain: DealsChain, price: Money)?)

    public static func == (a: DealsWhy, b: DealsWhy) -> Bool {
        switch (a, b) {
        case (.only, .only): true
        case let (.lowestPerUnit(p1, v1, n1), .lowestPerUnit(p2, v2, n2)): p1 == p2 && v1 == v2 && n1?.chain == n2?.chain && n1?.value == n2?.value
        case let (.cheapestPack(n1), .cheapestPack(n2)): n1?.chain == n2?.chain && n1?.price == n2?.price
        default: false
        }
    }

    /// Why `BasketSolver.bestValue` picks its offer among `offers`; nil when it picks none.
    public static func reason(_ offers: [DealOffer], chainOrder: [DealsChain] = [], programs: DealsPrograms = .all) -> DealsWhy? {
        guard let pick = BasketSolver.bestValueIndex(offers, chainOrder: chainOrder, programs: programs) else { return nil }
        let best = offers[pick.index]
        let others = offers.indices.filter { $0 != pick.index && programs.canGet(offers[$0]) && BasketSolver.counts(offers[$0], currency: best.price.currency) }
        if others.isEmpty { return .only }
        let unitOf = { (o: DealOffer) in o.effective?.unitPrice ?? o.unitPrice }
        if let per = pick.per, let unit = unitOf(best), unit.per == per {
            let next = others.compactMap { i -> (DealsChain, Money, Double)? in
                guard let u = unitOf(offers[i]), u.per == per, let rank = BasketSolver.rankValue(offers[i], per: per) else { return nil }
                return (offers[i].chain, Money(minor: u.minor, currency: best.price.currency), rank)
            }.min { $0.2 < $1.2 }
            return .lowestPerUnit(per: per, value: Money(minor: unit.minor, currency: best.price.currency), next: next.map { ($0.0, $0.1) })
        }
        let next = others.map { offers[$0] }.min { $0.price.minor < $1.price.minor }
        return .cheapestPack(next: next.map { ($0.chain, $0.price) })
    }
}

/// A local notification on the day a leaflet price starts, at 8:00 in Poland, when the user asks for one.
public enum DealStartReminder {
    public static let hour = 8
    static let prefix = "doddy.deal-start."

    /// One per offer and day: asking twice replaces, never doubles.
    public static func id(_ offer: DealOffer) -> String? {
        guard let from = offer.validFrom else { return nil }
        let key = SearchFolding.fold("\(offer.chain.rawValue)|\(offer.product)|\(offer.price.minor)")
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return prefix + "\(from.rawValue)." + String(hash, radix: 16)
    }

    public static func isDealStart(notificationID: String) -> Bool { notificationID.hasPrefix(prefix) }

    /// Only for a price that starts after today.
    public static func canRemind(_ offer: DealOffer, today: DealDay?) -> Bool {
        guard let from = offer.validFrom, let today else { return false }
        return from > today
    }

    public static func title(_ language: NotificationLanguage) -> String {
        language == .polish ? "Promocja od dziś" : "On offer from today"
    }

    /// "Masło Extra 82% w Biedronce: 4,99 zł (cena z gazetki)." The leaflet's own words and the code's price.
    public static func body(_ offer: DealOffer, _ language: NotificationLanguage) -> String {
        let product = ErrandsPrompt.clip(offer.product, 80)
        let price = offer.price.text(language)
        return language == .polish
            ? "\(product), \(offer.chain.name): \(price) (cena z gazetki, w sklepie może być inna)."
            : "\(product), \(offer.chain.name): \(price) (the leaflet's price; in the shop it can differ)."
    }
}
