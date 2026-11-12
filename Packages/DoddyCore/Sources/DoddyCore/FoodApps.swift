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
}

public enum FoodApps {
    /// In the order the screen lists them. The pages are the providers' front pages: their search addresses
    /// aren't published, so Doddy doesn't pass a search in.
    public static let all: [FoodApp] = [
        app("ubereats", "Uber Eats", "https://www.ubereats.com"),
        app("wolt", "Wolt", "https://wolt.com"),
        app("glovo", "Glovo", "https://glovoapp.com"),
        app("pyszne", "Pyszne.pl", "https://www.pyszne.pl"),
    ].filter(\.isOpenable)

    private static func app(_ id: String, _ name: String, _ address: String) -> FoodApp {
        // The addresses are literals above; a typo fails `FoodAppsTests` instead of crashing a build.
        FoodApp(id: id, name: name, url: URL(string: address) ?? URL(fileURLWithPath: "/"))
    }
}
