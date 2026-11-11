import Foundation

/// A real, publicly reachable entry point operated by a food-delivery provider.
///
/// This is an external handoff, NOT a merchant API integration: opening one of these
/// URLs never means that Doddy selected items, created a cart, paid or placed an order.
/// The provider asks for the delivery address and handles its own login and checkout.
public enum FoodDeliveryProvider: String, CaseIterable, Identifiable, Sendable {
    case uberEats
    case glovo
    case wolt
    case pyszne
    case boltFood

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .uberEats: "Uber Eats"
        case .glovo: "Glovo"
        case .wolt: "Wolt"
        case .pyszne: "Pyszne.pl"
        case .boltFood: "Bolt Food"
        }
    }

    /// Only official, browser-reachable URLs individually verified on 11 Nov 2026.
    /// No inferred search parameters, custom app schemes, account tokens or redirectors.
    public var orderURL: URL {
        let value: String
        switch self {
        case .uberEats: value = "https://www.ubereats.com/pl/near-me"
        case .glovo: value = "https://glovoapp.com/pl/pl/warszawa/categories/jedzenie_1"
        case .wolt: value = "https://wolt.com/pl/pol/warsaw"
        case .pyszne: value = "https://www.pyszne.pl/"
        case .boltFood: value = "https://food.bolt.eu/"
        }
        // Every URL above is source-controlled and verified. A malformed constant is a programming error.
        return URL(string: value)!
    }

    /// Glovo and Wolt links intentionally lead to real Warsaw city listings. The
    /// other links ask the provider to determine the user's delivery address.
    public var showsWarsawListing: Bool {
        self == .glovo || self == .wolt
    }

    /// No provider has granted Doddy API permissions to submit consumer purchases.
    /// Fail closed until a separately authorized integration is implemented.
    public var canOrderInsideDoddy: Bool { false }
}
