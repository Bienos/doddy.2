import Foundation

// "Przed wyjściem" (ADR-661; research docs/research/2026-10-28/research_deals_better.md §5 #1, #5):
// what the chosen offers need before the till, per shop, from the server's flags and the days the
// leaflets print: open the chain's app (Lidl Plus coupons are activated in the app), show the card,
// take enough pieces for a multi-buy, the limit, the deposit, "while stocks last", "in selected
// shops", a price that starts later, the last day, and a last day that falls on a day the shops are
// closed (`ShoppingCalendar`). Built by code from the answer; the app words it. Nothing is guessed:
// an entry appears only when the answer holds it.
//
// Platforms: iPhone (the deals screen, the basket's share text, the voice tool's answer). Pure logic; tested on Linux.

public struct DealsChecklistEntry: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The chain's app: its coupons activated and the app scanned at the till.
        case openApp(DealsProgram?)
        case showCard(DealsProgram?)
        /// Take this many to get the offer (a multi-buy group, or the minimum quantity).
        case take(Int)
        case atMost(Int)
        case deposit
        case whileStocksLast
        case selectedStores
        /// The price isn't on yet: from this day.
        case startsOn(DealDay)
        /// Today is the price's last day.
        case lastDay
        /// The last day falls on a closed day: this is the last day to shop for it.
        case lastOpenDay(DealDay)
        /// Most of the chain's shops are closed today.
        case closedToday(ShoppingDayKind)
        /// The chain's shops close early today.
        case closesEarlyToday(hour: Int)
    }

    public let chain: DealsChain
    /// The product the entry is about; nil for the whole shop.
    public let product: String?
    public let kind: Kind

    public init(chain: DealsChain, product: String? = nil, kind: Kind) {
        self.chain = chain
        self.product = product
        self.kind = kind
    }
}

public struct DealsChecklistSection: Equatable, Sendable {
    public let chain: DealsChain
    public let entries: [DealsChecklistEntry]
}

public enum DealsChecklist {
    /// The checklist for a basket plan, a section per shop in the plan's order; shops with nothing
    /// to note are left out. `today` nil: no date notes.
    public static func sections(_ plan: BasketPlan, today: DealDay?) -> [DealsChecklistSection] {
        plan.chains.compactMap { chain in
            let lines = plan.lines.filter { $0.chain == chain }
            let found = shopEntries(chain, offers: lines.map(\.offer), today: today)
                + lines.flatMap { Self.entries(for: $0.offer, cost: $0.cost, today: today) }
            return found.isEmpty ? nil : DealsChecklistSection(chain: chain, entries: found)
        }
    }

    /// The entries for one offer bought alone (the deals screen's line).
    public static func entries(for offer: DealOffer, today: DealDay?) -> [DealsChecklistEntry] {
        entries(for: offer, cost: BasketSolver.cost(offer, quantity: 1), today: today)
    }

    static func shopEntries(_ chain: DealsChain, offers: [DealOffer], today: DealDay?) -> [DealsChecklistEntry] {
        var out: [DealsChecklistEntry] = []
        let program = DealsProgram.of(chain)
        if offers.contains(where: { $0.flags.contains(.app) }) { out.append(.init(chain: chain, kind: .openApp(program))) }
        if offers.contains(where: { $0.flags.contains(.card) }) { out.append(.init(chain: chain, kind: .showCard(program))) }
        if let today {
            let kind = ShoppingCalendar.kind(today)
            if ShoppingCalendar.isClosed(today, for: chain) {
                out.append(.init(chain: chain, kind: .closedToday(kind)))
            } else if case .closesEarly(let hour) = kind {
                out.append(.init(chain: chain, kind: .closesEarlyToday(hour: hour)))
            }
        }
        return out
    }

    static func entries(for offer: DealOffer, cost: LineCost, today: DealDay?) -> [DealsChecklistEntry] {
        let chain = offer.chain
        var kinds: [DealsChecklistEntry.Kind] = []
        if let e = offer.effective {
            // The offer works from `e.quantity` pieces: as many as the line counts when that is more,
            // or the next whole group when it costs nothing more.
            let more = cost.notes.compactMap { note -> Int? in if case .takeMore(let to) = note { to } else { nil } }.first
            kinds.append(.take(more ?? max(cost.quantity, e.quantity)))
        }
        if let limit = offer.limit { kinds.append(.atMost(limit)) }
        if offer.flags.contains(.deposit) { kinds.append(.deposit) }
        if offer.flags.contains(.stock) { kinds.append(.whileStocksLast) }
        if offer.flags.contains(.selectedStores) { kinds.append(.selectedStores) }
        if let today {
            if let from = offer.validFrom, from > today {
                kinds.append(.startsOn(from))
            }
            if let to = offer.validTo, to >= today {
                if to == today {
                    kinds.append(.lastDay)
                } else if ShoppingCalendar.isClosed(to, for: chain) {
                    let first = max(today, offer.validFrom ?? today)
                    if let open = ShoppingCalendar.lastOpenDay(from: first, through: to, for: chain), open != to {
                        kinds.append(open == today ? .lastDay : .lastOpenDay(open))
                    }
                }
            }
        }
        return kinds.map { DealsChecklistEntry(chain: chain, product: offer.product, kind: $0) }
    }
}
