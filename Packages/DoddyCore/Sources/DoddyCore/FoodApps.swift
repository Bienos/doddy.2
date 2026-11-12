import Foundation

/// A food-delivery app or site that Home's "Food" screen offers (owner, 11 Nov 2026: "maybe other button like
/// food, as I add other ones as well there"). A row only opens the provider's own front page: the app, when it
/// is installed (an https link is a universal link), otherwise the website. Doddy doesn't read the order,
/// place it, or log in to anything (decision `2026-11-11-food-button`).
///
/// To add one: a line in `FoodApps.all` and its host in `FoodAppsTests`.
public struct FoodApp: Identifiable, Equatable, Sendable {
    /// Stable, lower-case; the screen's accessibility identifier is built from it.
    public let id: String
    /// The brand's own name. Never translated.
    public let name: String
    public let url: URL

    /// An https page with a host: the only kind a row may open. Anything else (another scheme, no host)
    /// is never shown.
    public var isOpenable: Bool {
        url.scheme?.lowercased() == "https" && !(url.host ?? "").isEmpty
    }

    /// The app's own host without "www.": a restaurant's page must be on it or on a subdomain of it.
    var pageHost: String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The longest page address taken (the same bound as the server's `foodPage`).
    public static let pageMaxLength = 300

    /// A restaurant's own page on this app (decision `2026-11-12-food-restaurant-pages`): an https address on this
    /// app's own host (or a subdomain), with no sign-in details or port, and a path beyond the front page. The
    /// query and fragment are dropped (tracking, sessions). Anything else is nil: the address came from a search
    /// result, which is data, so it is checked here again before anything opens.
    public func page(from address: String) -> URL? {
        guard address.count <= Self.pageMaxLength, let host = pageHost,
              var parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil, parts.port == nil,
              let given = parts.host?.lowercased(), given == host || given.hasSuffix("." + host)
        else { return nil }
        guard parts.path.split(separator: "/").isEmpty == false else { return nil }
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }
}

public enum FoodApps {
    /// In the order the screen lists them. The pages are the providers' front pages: their search addresses
    /// aren't published, so Doddy doesn't pass a search in.
    public static let all: [FoodApp] = [
        app("ubereats", "Uber Eats", "https://www.ubereats.com"),
        app("wolt", "Wolt", "https://wolt.com"),
        app("glovo", "Glovo", "https://glovoapp.com"),
        app("bolt", "Bolt Food", "https://food.bolt.eu"),
        app("pyszne", "Pyszne.pl", "https://www.pyszne.pl"),
    ].filter(\.isOpenable)

    /// The app a person named, by voice or typed: its id or name, in any case, with spaces, dots and dashes
    /// ignored ("Uber Eats", "ubereats", "Bolt", "pyszne.pl"). Nil for anything else; Doddy never guesses
    /// between apps (decision `2026-11-12-food-by-voice`).
    public static func named(_ text: String) -> FoodApp? {
        let key = normalised(text)
        guard !key.isEmpty else { return nil }
        let aliases = ["uber": "ubereats", "boltfood": "bolt", "pysznepl": "pyszne"]
        let id = aliases[key] ?? key
        return all.first { $0.id == id || normalised($0.name) == key }
    }

    private static func normalised(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func app(_ id: String, _ name: String, _ address: String) -> FoodApp {
        // The addresses are literals above; a typo fails `FoodAppsTests` instead of crashing a build.
        FoodApp(id: id, name: name, url: URL(string: address) ?? URL(fileURLWithPath: "/"))
    }
}
