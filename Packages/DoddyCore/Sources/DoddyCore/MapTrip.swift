import Foundation

/// How to travel on a route in Apple Maps (owner, 10 Nov 2026: "wyznacz mi trasę").
public enum MapTravelMode: String, Equatable, Sendable, CaseIterable {
    case driving, walking, transit

    /// The agent's word; anything else is no mode, and Maps picks.
    public static func parse(_ text: String?) -> MapTravelMode? {
        guard let text = text?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty else { return nil }
        switch text {
        case "driving", "drive", "car": return .driving
        case "walking", "walk", "foot": return .walking
        case "transit", "public_transport", "public transport", "bus", "tram", "metro", "train": return .transit
        default: return nil
        }
    }

    /// Apple Maps' `dirflg`.
    var directionsFlag: String {
        switch self {
        case .driving: "d"
        case .walking: "w"
        case .transit: "r"
        }
    }
}

/// What `open_map` shows: one place, or a route to it. A route opens Maps with directions; the
/// start is where the iPhone is unless the user named one.
public struct MapTrip: Equatable, Sendable {
    public var place: String
    public var from: String?
    public var mode: MapTravelMode?

    public init(place: String, from: String? = nil, mode: MapTravelMode? = nil) {
        self.place = place
        self.from = from
        self.mode = mode
    }

    /// A route was asked for: a start, a way to travel, or both.
    public var isRoute: Bool { from != nil || mode != nil }

    public var url: URL? {
        isRoute ? OpenLinks.directions(to: place, from: from, mode: mode) : OpenLinks.map(place: place)
    }
}

extension OpenLinks {
    /// Directions in Apple Maps. Without `from`, Maps starts where the iPhone is.
    public static func directions(to place: String, from: String? = nil, mode: MapTravelMode? = nil) -> URL? {
        let encode = { (text: String) in text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text }
        var query = "daddr=\(encode(place))"
        if let from { query += "&saddr=\(encode(from))" }
        if let mode { query += "&dirflg=\(mode.directionsFlag)" }
        return URL(string: "https://maps.apple.com/?" + query)
    }
}
