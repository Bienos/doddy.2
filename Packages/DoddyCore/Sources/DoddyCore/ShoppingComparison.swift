import Foundation

// "Compare" on a shopping task's result (owner, 13 Nov 2026: "zawsze wyskakuje kilka opcji, porównywanie dogłębsze").
// The picks side by side, with only what the code can say from the result itself. Which price is the lowest, and by
// how much each other pick is above it, are sums over the prices the server's code registered (`Money`, integer
// minor units); nothing here is a model's judgement, and nothing is read from anywhere but the result.
//
// Honest limits, kept in code so a screen can't drift from them:
//   - the lowest price is marked only when every shown pick is in one currency, there are two picks or more, and
//     they don't all cost the same (a tie has no lowest);
//   - a pick whose offer isn't in the result is not compared (`ShoppingResult.picksInDisplayOrder` leaves it out);
//   - the result carries no returns policy, so none is compared; a missing delivery is said as missing, not guessed.
// Touches iPhone only in use (the Compare screen); the type is pure Foundation, as the rest of this package.

public struct ShoppingComparison: Equatable, Sendable {
    /// One pick, as one column of the Compare screen.
    public struct Column: Equatable, Sendable {
        public let pick: ShoppingPick
        public let offer: ShoppingOffer
        /// The lowest price of the shown picks: only when the prices can be compared and some pick costs more.
        /// Two picks at the same lowest price are both marked.
        public let isLowestPrice: Bool
        /// How much more than the lowest pick, in the same currency; nil for the lowest, or when the currencies differ.
        public let aboveLowest: Money?
        /// The price was read on the shop's own page (not taken from the Google Shopping list).
        public var priceCheckedOnPage: Bool { offer.evidence == .shopPage }
    }

    /// In the result card's order: best, cheapest, premium, alternative, then any role this app doesn't know.
    public let columns: [Column]

    /// True when the prices could be put against each other: two picks or more, all in one currency.
    public let pricesComparable: Bool

    public init(_ shopping: ShoppingResult) {
        let shown = shopping.picksInDisplayOrder
        let currencies = Set(shown.map { $0.offer.price.currency })
        let comparable = shown.count > 1 && currencies.count == 1
        let prices = shown.map { $0.offer.price.minor }
        let lowest = prices.min() ?? 0
        let highest = prices.max() ?? 0
        pricesComparable = comparable
        columns = shown.map { row in
            let minor = row.offer.price.minor
            let isLowest = comparable && minor == lowest && lowest < highest
            let above: Money? = comparable && minor > lowest ? Money(minor: minor - lowest, currency: row.offer.price.currency) : nil
            return Column(pick: row.pick, offer: row.offer, isLowestPrice: isLowest, aboveLowest: above)
        }
    }

    /// "Compare" is offered when there is something to put side by side: two picks or more with their offers.
    public static func isOffered(for shopping: ShoppingResult) -> Bool {
        shopping.picksInDisplayOrder.count > 1
    }
}
