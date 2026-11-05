import Foundation

// "Moje sklepy" (ADR-663; research docs/research/2026-10-28/research_deals_better.md §5 #10): the shops the user
// goes to, picked on the iPhone from an Apple Maps search near them. They set which chains a leaflet check asks
// for, say which shop to check when an offer is "w wybranych sklepach", and open Apple's place card (hours,
// directions). Kept on this iPhone only (the app stores `stored`); nothing about them goes to Doddy's server.
// The search itself is Apple's (the chain names and roughly where the user is go to Apple Maps, as for a place
// reminder); this file only judges its results: a result is a chain's shop when its name names the chain, and
// the nearest within `maxKilometres` is offered per chain.
//
// Platforms: iPhone (Cheapest this week › My shops). Pure logic; tested on Linux.

/// A shop the user picked.
public struct MyShop: Codable, Equatable, Hashable, Sendable {
    public let chain: DealsChain
    public let name: String
    public let address: String
    public let latitude: Double
    public let longitude: Double

    public init(chain: DealsChain, name: String, address: String, latitude: Double, longitude: Double) {
        self.chain = chain
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Apple Maps at this shop, by its name and place (Apple's place card shows its hours).
    public var mapsURL: URL? {
        var parts = URLComponents(string: "https://maps.apple.com/")
        parts?.queryItems = [
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f", latitude, longitude)),
        ]
        return parts?.url
    }
}

/// One Apple Maps result, as plain values.
public struct ShopSearchResult: Equatable, Sendable {
    public let name: String
    public let address: String
    public let latitude: Double
    public let longitude: Double

    public init(name: String, address: String, latitude: Double, longitude: Double) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A shop found near the user, with how far it is.
public struct NearbyShop: Equatable, Sendable {
    public let shop: MyShop
    public let kilometres: Double
}

public struct MyShops: Equatable, Sendable {
    public static let maxShops = 12
    /// Results further than this aren't offered.
    public static let maxKilometres = 15.0

    public let shops: [MyShop]

    public init(shops: [MyShop] = []) {
        var seen = Set<MyShop>()
        self.shops = Array(shops.filter { seen.insert($0).inserted }.prefix(Self.maxShops))
    }

    /// The chains of the user's shops, in the order they were added, read chains and link-only chains alike.
    public var chains: [DealsChain] {
        var out: [DealsChain] = []
        for shop in shops where !out.contains(shop.chain) { out.append(shop.chain) }
        return out
    }

    public func shops(of chain: DealsChain) -> [MyShop] { shops.filter { $0.chain == chain } }

    public func adding(_ shop: MyShop) -> MyShops { MyShops(shops: shops + [shop]) }
    public func removing(_ shop: MyShop) -> MyShops { MyShops(shops: shops.filter { $0 != shop }) }
    public func contains(_ shop: MyShop) -> Bool { shops.contains(shop) }

    // MARK: Stored form

    /// JSON, for the app's storage on this iPhone.
    public var stored: String {
        (try? JSONEncoder().encode(shops)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    /// From the stored JSON; anything that doesn't read as shops is an empty list, never a guess.
    public init(stored: String) {
        let shops = (try? JSONDecoder().decode([MyShop].self, from: Data(stored.utf8))) ?? []
        self.init(shops: shops.filter { $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 })
    }

    // MARK: Judging Apple Maps results

    /// The words a chain's shops carry in Apple Maps names ("Lidl", "ALDI", "Żabka", "Dino Polska").
    static func names(_ chain: DealsChain) -> [String] {
        switch chain {
        case .biedronka: ["biedronka"]
        case .lidl: ["lidl"]
        case .dino: ["dino"]
        case .rossmann: ["rossmann"]
        case .aldi: ["aldi"]
        case .zabka: ["zabka"]
        case .kaufland: ["kaufland"]
        case .carrefour: ["carrefour"]
        case .auchan: ["auchan"]
        case .netto: ["netto"]
        default: [SearchFolding.fold(chain.name)]
        }
    }

    /// Whether a result's name names the chain, as a word ("Dino" yes, "Dinozaur Park" no).
    public static func names(_ result: ShopSearchResult, chain: DealsChain) -> Bool {
        let words = SearchFolding.tokens(result.name)
        return names(chain).contains { words.contains($0) }
    }

    /// From one chain's search results near `here`, the shops that are that chain's, nearest first, within
    /// `maxKilometres`, at most `limit`.
    public static func nearby(_ results: [ShopSearchResult], chain: DealsChain, here: (latitude: Double, longitude: Double),
                              limit: Int = 3) -> [NearbyShop] {
        var seen = Set<String>()
        return results
            .filter { names($0, chain: chain) && $0.latitude.isFinite && $0.longitude.isFinite }
            .map { r in
                NearbyShop(shop: MyShop(chain: chain, name: r.name, address: r.address, latitude: r.latitude, longitude: r.longitude),
                           kilometres: kilometres(here.latitude, here.longitude, r.latitude, r.longitude))
            }
            .filter { $0.kilometres <= maxKilometres }
            .sorted { $0.kilometres < $1.kilometres }
            .filter { seen.insert("\($0.shop.name)|\($0.shop.address)").inserted }
            .prefix(limit).map { $0 }
    }

    /// Great-circle distance (haversine), in kilometres.
    public static func kilometres(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0
        let toRad = Double.pi / 180
        let dLat = (lat2 - lat1) * toRad
        let dLon = (lon2 - lon1) * toRad
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * toRad) * cos(lat2 * toRad) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }

    /// "1,2 km" in Polish, "1.2 km" in English; under one kilometre in metres, to the nearest 50.
    public static func distanceText(_ km: Double, polish: Bool) -> String {
        if km < 1 { return "\(max(50, Int((km * 1000 / 50).rounded()) * 50)) m" }
        let text = String(format: "%.1f km", km)
        return polish ? text.replacingOccurrences(of: ".", with: ",") : text
    }
}
