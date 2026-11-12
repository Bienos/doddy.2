import Foundation

// "Sprawdź to" (docs/strategy/SKLEP_PROPOZYCJA_2026-11.md, section 10.1): the person is looking at a
// product in a shop and shares, or pastes, its address. This reads the address out of that text and
// makes the words a price watch needs (the product's title and the shop) from what was shared. It
// fetches nothing and decides nothing about the price: Doddy's server reads the page when the watch's
// first step asks, and says so when the page gives no price (SHOPPING_WATCH.md section 2). So a link
// to anything that is not a shop simply ends there with "couldn't read a price", never a made-up one.

/// The first web address in a shared or pasted text, with the title and shop made from it.
public struct SharedShopPage: Equatable, Sendable {
    /// The address exactly as shared (tracking parameters included: the page is read as the person saw it). Always https.
    public let url: String
    /// The host without a leading "www.", as the shop's name when nothing better is known.
    public let shop: String
    /// The words shared next to the address, tidied, or the shop's name when there were none.
    public let title: String

    /// The first https address in `text`, or nil. Not a link: plain http, a file or other scheme, an
    /// address with a name or password in it, one with no host, one longer than a watch takes. A text
    /// with two addresses takes the first: the person shared one thing.
    public static func parse(_ text: String) -> SharedShopPage? {
        let punctuation = CharacterSet(charactersIn: "<>()[]{}\"'\u{201C}\u{201D}\u{2018}\u{2019},;")
        var words: [String] = []
        var found: (url: String, host: String)?
        for part in text.split(whereSeparator: \.isWhitespace) {
            let candidate = String(part).trimmingCharacters(in: punctuation)
            if found == nil, let page = Self.address(candidate) {
                found = page
            } else {
                words.append(String(part))
            }
        }
        guard let found else { return nil }
        let shop = Self.clean(host: found.host)
        let title = Self.tidied(words.joined(separator: " "))
        return SharedShopPage(
            url: found.url,
            shop: PriceWatchDraft.clipped(shop, to: PriceWatchDraft.maxShop),
            title: PriceWatchDraft.clipped(title.isEmpty ? shop : title, to: PriceWatchDraft.maxTitle))
    }

    /// The same page with the person's own name for it, when they gave one: tidied and cut like a shared
    /// title. Empty words leave the title as it was.
    public func titled(_ words: String) -> SharedShopPage {
        let name = Self.tidied(words)
        guard !name.isEmpty else { return self }
        return SharedShopPage(url: url, shop: shop, title: PriceWatchDraft.clipped(name, to: PriceWatchDraft.maxTitle))
    }

    /// The price watch for this page and the person's price. The same draft, digest and yes card as a
    /// watch started from a pick; the currency is złoty because the card asks for the price in złoty.
    public func watchDraft(thresholdMinor: Int, language: String = PriceWatchDraft.defaultLanguage) -> PriceWatchDraft {
        PriceWatchDraft(title: title, shop: shop, url: url, thresholdMinor: thresholdMinor, currency: "PLN", language: language)
    }

    // MARK: Reading

    private static func address(_ candidate: String) -> (url: String, host: String)? {
        guard candidate.lowercased().hasPrefix("https://"), candidate.utf16.count <= PriceWatchDraft.maxURL,
              !candidate.unicodeScalars.contains(where: { $0.value < 0x21 || $0.value == 0x7F }),
              let parts = URLComponents(string: candidate), parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil,
              let host = parts.host?.lowercased(), host.contains("."), !host.hasSuffix(".") else { return nil }
        return (candidate, host)
    }

    private static func clean(host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Spaces made one, and the separators an app puts between a title and its address ("Kurtka – ", "| ")
    /// taken off both ends. Nothing inside the words is changed.
    private static func tidied(_ words: String) -> String {
        let flat = words.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-\u{2013}\u{2014}|:\u{00B7}\u{2022}"))
        return flat.trimmingCharacters(in: separators)
    }
}

extension SharedShopPage: Identifiable {
    /// One page per address, so a sheet can be opened for it.
    public var id: String { url }
}
