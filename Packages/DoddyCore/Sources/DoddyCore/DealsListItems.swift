import Foundation

// "Sprawdź moją listę" (ADR-661; research docs/research/2026-10-28/research_deals_better.md §5 #3):
// the items to look up from a shopping list's open items, or from what the user typed, with the
// quantity read from their words ("3 jajka", "2 kg mąki", `ListItemWords`) kept for the basket and
// only the product sent to Doddy's server. Within the request's limits: the first `maxItems`
// different products, each at most `maxItemLength` long; what doesn't fit is counted, never cut, so
// the screen and the agent can say what wasn't checked.
//
// Platforms: iPhone (the deals screen's "From my list", the voice tool). Pure logic; tested on Linux.

public extension ListQuantity {
    /// A bare count of pieces.
    static func pieces(_ count: Int) -> ListQuantity { ListQuantity(amount: Decimal(count), unit: nil) }
}

public struct DealsListItems: Equatable, Sendable {
    /// The products to look up, in the list's order.
    public let items: [String]
    /// The quantity read for each item (nil: none said), same order.
    public let quantities: [ListQuantity?]
    /// The entries left out: over `DealsRequest.maxItems`, or too long to send.
    public let leftOut: [String]

    /// From item texts in order (a list's open items, or the typed items).
    public static func read(_ texts: [String]) -> DealsListItems {
        var items: [String] = []
        var quantities: [ListQuantity?] = []
        var leftOut: [String] = []
        var seen: [String: Int] = [:]
        for text in texts {
            let words = ListItemWords.read(text)
            let product = words.product.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !product.isEmpty else { continue }
            let key = SearchFolding.fold(product)
            if let index = seen[key] {
                // The same product twice ("mleko", "2 l mleka"): one look-up, the quantities added when they add up.
                if let a = quantities[index], let b = words.quantity, a.kind == b.kind {
                    quantities[index] = ListQuantity.total([a, b]).first
                } else if quantities[index] == nil {
                    quantities[index] = words.quantity
                }
                continue
            }
            guard product.utf16.count <= DealsRequest.maxItemLength, items.count < DealsRequest.maxItems else {
                leftOut.append(text)
                continue
            }
            seen[key] = items.count
            items.append(product)
            quantities.append(words.quantity)
        }
        return DealsListItems(items: items, quantities: quantities, leftOut: leftOut)
    }
}
