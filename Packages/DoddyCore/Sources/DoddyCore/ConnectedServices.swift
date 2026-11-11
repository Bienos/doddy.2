import Foundation

// DODDY Connected Services, stage 2. Data comes ONLY from a link/description the person supplied.
// This file makes no network requests, has no provider credentials, and cannot book or buy.

/// A provider whose public booking page a user chooses to keep on this iPhone.
public enum BookingService: String, Codable, CaseIterable, Sendable {
    case booksy
    case simplyBook

    public var title: String {
        switch self {
        case .booksy: "Booksy"
        case .simplyBook: "SimplyBook.me"
        }
    }

    public static func identify(_ url: URL) -> BookingService? {
        guard url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased() else { return nil }
        if allowed(host, domain: "booksy.com") || allowed(host, domain: "booksy.pl") { return .booksy }
        // A SimplyBook.me booking page is hosted on a business's subdomain; not the platform landing page.
        if host != "simplybook.me" && allowed(host, domain: "simplybook.me") { return .simplyBook }
        return nil
    }

    /// Only user-shared links. No network call and no inference from a site name without a real URL.
    public static func sharedBookingURL(in text: String) -> URL? {
        for word in text.split(whereSeparator: \.isWhitespace) {
            let token = String(word).trimmingCharacters(in: CharacterSet(charactersIn: "<>()[]{}\"',;"))
            guard token.count <= 1500, let url = URL(string: token),
                  identify(url) != nil, url.path != "" && url.path != "/" else { continue }
            return url
        }
        return nil
    }

    private static func allowed(_ host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}

/// A bookmark is NOT a connected account or a confirmed reservation.
public struct SavedBookingService: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let url: String
    public let provider: BookingService

    public var bookingURL: URL? { URL(string: url) }

    /// A public booking shortcut must not silently persist OAuth/password/session URLs in defaults.
    private static func hasCredentialQuery(in url: URL) -> Bool {
        let sensitive = Set(["token", "access_token", "refresh_token", "auth", "api_key",
                             "secret", "session", "sessionid", "password", "code"])
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.contains { sensitive.contains($0.name.lowercased()) }
    }

    public init?(id: UUID = UUID(), name: String, url: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(cleanName.count), !cleanName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              cleanURL.count <= 1500, let parsed = URL(string: cleanURL), let provider = BookingService.identify(parsed),
              parsed.path != "" && parsed.path != "/",
              parsed.fragment == nil,
              !Self.hasCredentialQuery(in: parsed) else { return nil }
        self.id = id
        self.name = cleanName
        self.url = parsed.absoluteString
        self.provider = provider
    }
}

/// JSON suitable for on-device @AppStorage; invalid, duplicate and oversized records are dropped.
public struct SavedBookingServices: Equatable, Sendable {
    public static let maxCount = 24
    public let items: [SavedBookingService]

    public init(items: [SavedBookingService] = []) {
        var seen = Set<String>()
        self.items = Array(items.filter { item in
            guard let url = URL(string: item.url), BookingService.identify(url) == item.provider else { return false }
            return seen.insert(item.url).inserted
        }.prefix(Self.maxCount))
    }

    public init(stored: String) {
        let decoded = (try? JSONDecoder().decode([SavedBookingService].self, from: Data(stored.utf8))) ?? []
        self.init(items: decoded.compactMap {
            SavedBookingService(id: $0.id, name: $0.name, url: $0.url)
        })
    }

    public var stored: String {
        let data = (try? JSONEncoder().encode(items)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    public func adding(name: String, url: String) -> SavedBookingServices? {
        guard let new = SavedBookingService(name: name, url: url),
              !items.contains(where: { $0.url == new.url }),
              items.count < Self.maxCount else { return nil }
        return SavedBookingServices(items: items + [new])
    }

    public func removing(id: UUID) -> SavedBookingServices {
        SavedBookingServices(items: items.filter { $0.id != id })
    }
}

/// Extracts a Vinted item link supplied through Share Sheet. No Vinted pages are read or indexed.
public struct SharedVintedListing: Equatable, Sendable {
    public let url: URL

    public init?(sharedText: String) {
        for word in sharedText.split(whereSeparator: \.isWhitespace) {
            let token = String(word).trimmingCharacters(in: CharacterSet(charactersIn: "<>()[]{}\"',;"))
            guard token.count <= 1500, let candidate = URL(string: token),
                  candidate.scheme?.lowercased() == "https",
                  candidate.user == nil, candidate.password == nil, candidate.port == nil,
                  let host = candidate.host?.lowercased(),
                  host == "vinted.pl" || host.hasSuffix(".vinted.pl")
                      || host == "vinted.com" || host.hasSuffix(".vinted.com"),
                  candidate.path.split(separator: "/").contains("items") else { continue }
            self.url = candidate
            return
        }
        return nil
    }

    /// Text-only task for Doddy research. URLs must never enter the typed errand (its existing policy forbids links).
    /// Only the person's supplied product description and asking price leave the iPhone if they later approve the task.
    public static func comparisonPrompt(product: String, askingPrice: String, polish: Bool) -> String? {
        let name = product.trimmingCharacters(in: .whitespacesAndNewlines)
        let asking = askingPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...120).contains(name.count), !name.contains("://"),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              (asking.isEmpty || asking.range(of: #"^[0-9]{1,6}(?:[,.][0-9]{1,2})?$"#, options: .regularExpression) != nil) else { return nil }
        let price = asking.isEmpty ? "" : (polish ? " Cena podana przeze mnie: \(asking) zł." : " My stated asking price: PLN \(asking).")
        return polish
            ? "Porównaj ceny używanego produktu \(name) z cenami nowych i używanych odpowiedników w Polsce. Podaj tylko ceny, które można zweryfikować w źródłach. To nie jest weryfikacja autentyczności przedmiotu z Vinted.\(price)"
            : "Research comparable used and new prices in Poland for \(name). Only quote prices backed by checkable sources. This is not an authenticity check of a Vinted listing.\(price)"
    }
}
