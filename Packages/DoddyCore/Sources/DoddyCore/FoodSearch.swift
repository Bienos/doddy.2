import Foundation

// Home › Food's search (owner, 13 Nov 2026: "ja mówię, że chcę burgera i to mi pokazuje burgery … najbliżej mnie";
// decision `2026-11-13-food-search-nearby`). The person types a dish and a delivery address; the iPhone asks Apple
// Maps for food places near that address, and this file judges the answer: restaurants, cafés and bakeries only,
// nearest first, within `maxKilometres`, each once. It knows no price, menu, delivery fee or whether a place
// delivers: Apple Maps doesn't say, and no delivery app publishes it (decision `2026-11-11-food-button`), so the
// screen never says where it's cheapest.
//
// Platforms: iPhone (Home › Food). Pure logic; tested on Linux.

/// What kind of food place Apple Maps says a result is.
public enum FoodPlaceKind: String, Equatable, Hashable, Sendable {
    case restaurant, cafe, bakery
}

/// One Apple Maps result, as plain values. `kind` is nil when Apple Maps gave no food category.
public struct FoodSearchResult: Equatable, Sendable {
    public let name: String
    public let address: String
    public let kind: FoodPlaceKind?
    public let latitude: Double
    public let longitude: Double
    /// The number Apple Maps lists for the place, as given, or nil.
    public let phone: String?

    public init(name: String, address: String, kind: FoodPlaceKind?, latitude: Double, longitude: Double,
                phone: String? = nil) {
        self.name = name
        self.address = address
        self.kind = kind
        self.latitude = latitude
        self.longitude = longitude
        self.phone = phone
    }
}

/// A food place near the delivery address, with how far it is in a straight line.
public struct NearbyFoodPlace: Equatable, Identifiable, Sendable {
    public let name: String
    public let address: String
    public let kind: FoodPlaceKind
    public let latitude: Double
    public let longitude: Double
    public let kilometres: Double
    /// `tel:` for the number Apple Maps listed, when it reads as a plain number; nil otherwise.
    public let callURL: URL?

    public var id: String { name + "|" + address }

    /// Apple Maps at this place, by its name and position (Apple's place card has the hours and directions).
    public var mapsURL: URL? {
        var parts = URLComponents(string: "https://maps.apple.com/")
        parts?.queryItems = [
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f", latitude, longitude)),
        ]
        return parts?.url
    }
}

public enum FoodSearch {
    /// Places further than this from the delivery address aren't shown (delivery apps rarely reach further).
    public static let maxKilometres = 10.0
    /// The most places shown for one search.
    public static let maxResults = 15
    /// The longest dish (or restaurant name) searched for.
    public static let dishMaxLength = 60
    /// The longest delivery address searched for.
    public static let addressMaxLength = 160

    /// The dish as typed, trimmed. Nil when it is empty, more than one line or longer than `dishMaxLength`:
    /// refused, never cut, so Apple Maps gets only what the person sees.
    public static func dish(_ text: String) -> String? { line(text, max: dishMaxLength) }

    /// The delivery address as typed, trimmed, by the same rule (`addressMaxLength`).
    public static func address(_ text: String) -> String? { line(text, max: addressMaxLength) }

    static func line(_ text: String, max: Int) -> String? {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, words.count <= max,
              !words.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return words
    }

    /// From Apple Maps' results near `here`: the food places (a result with no food category is dropped), with
    /// a name and a real position, within `maxKilometres`, nearest first (by name when as near), each name and
    /// address once, at most `limit`.
    public static func nearby(_ results: [FoodSearchResult], here: (latitude: Double, longitude: Double),
                              limit: Int = FoodSearch.maxResults) -> [NearbyFoodPlace] {
        let places: [NearbyFoodPlace] = results.compactMap { result in
            guard let kind = result.kind, isPosition(result.latitude, result.longitude) else { return nil }
            let name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let km = MyShops.kilometres(here.latitude, here.longitude, result.latitude, result.longitude)
            guard km <= maxKilometres else { return nil }
            return NearbyFoodPlace(
                name: name, address: result.address.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind,
                latitude: result.latitude, longitude: result.longitude, kilometres: km, callURL: callURL(result.phone))
        }
        let sorted = places.sorted { a, b in
            a.kilometres != b.kilometres ? a.kilometres < b.kilometres : a.name < b.name
        }
        var seen = Set<String>()
        var out: [NearbyFoodPlace] = []
        for place in sorted where out.count < limit {
            if seen.insert(place.id).inserted { out.append(place) }
        }
        return out
    }

    /// `tel:` for a listed number: digits with an optional leading +, written with the spaces, dashes, dots or
    /// brackets listings use. Anything else (letters, pauses, `*` or `#`, a + in the middle) is nil, so a listing
    /// can only ever ring a plain number, and only after the person taps (iOS asks before it calls).
    public static func callURL(_ phone: String?) -> URL? {
        guard let phone = phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty, phone.count <= 32
        else { return nil }
        var digits = ""
        for (index, character) in phone.enumerated() {
            if character.isASCII && character.isNumber {
                digits.append(character)
            } else if character == "+" && index == 0 {
                continue
            } else if phoneSeparators.contains(character) {
                continue
            } else {
                return nil
            }
        }
        guard (5...15).contains(digits.count) else { return nil }
        return URL(string: "tel:" + (phone.hasPrefix("+") ? "+" : "") + digits)
    }

    /// What listings write between a number's digits.
    private static let phoneSeparators: Set<Character> = [" ", "-", ".", "(", ")", "\u{00A0}"]

    private static func isPosition(_ latitude: Double, _ longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
            && !(latitude == 0 && longitude == 0)
    }
}
