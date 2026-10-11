import Foundation

/// Links that open a place in the app, e.g. from the landing page's "Open Doddy" button.
/// Only navigation: a link never saves, deletes or sends anything.
public enum DeepLink: String, CaseIterable, Sendable {
    case home, memories, settings
    /// The parking widget (ADR-315): opens the saved spot in Maps, if there is one.
    case parking

    public static let scheme = "doddy"

    /// `doddy://home`, `doddy://memories`, `doddy://settings`, `doddy://parking`. A bare `doddy://` opens Home.
    /// Anything else, including other schemes and unknown places, returns nil.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        let place = (url.host ?? "").lowercased()
        if place.isEmpty {
            self = .home
        } else if let link = DeepLink(rawValue: place) {
            self = link
        } else {
            return nil
        }
    }

    public var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }
}
