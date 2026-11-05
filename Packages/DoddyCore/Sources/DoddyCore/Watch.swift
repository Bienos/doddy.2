import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// Price watch, stage 2 of shopping mode (docs/implementation/SHOPPING_WATCH.md, ADR-614). On a pick the
// user taps "Pilnuj ceny": Doddy's server reads that shop's own page a few times a day for 30 days
// and sends one notification when the price it read is at or below the user's number. It only
// notifies. It never buys, orders, signs in or fills in anything, and no model is involved.
//
// The rules the app keeps, as typed code the tests hold:
//  - the yes is bound to the exact words: the server's draft is approved only with the digest of
//    `PriceWatchDraft`'s canonical JSON, which is computed here and must equal the one the server
//    returns (fixture schemas/fixtures/watch_create_v1.json, computed independently with Python);
//  - nothing is said to be watching, dropped, finished or deleted unless the server said so, and a
//    state this version of the app doesn't know is never shown as active;
//  - "dropped" is never said without the price the server confirmed (`triggeredPriceMinor`);
//  - an approval whose answer never came back is `unknown`, never success, and is not sent again.

// MARK: - The draft (what the user says yes to)

/// What is watched and at what price. The digest binds the user's yes to exactly these fields and to the
/// promise itself (30 days, 4 checks a day). The price the server reads at the draft is not in it: it
/// varies, and the user approves the promise, not a quote.
public struct PriceWatchDraft: Equatable, Hashable, Sendable {
    /// How long a watch runs, and how often the server looks (the contract's constants; they are in the digest).
    public static let days = 30
    public static let checksPerDay = 4
    public static let maxTitle = 120
    public static let maxShop = 80
    public static let maxURL = 2_048
    /// The user's price in minor units: 1 to 1,000,000,000.
    public static let maxThresholdMinor = 1_000_000_000
    public static let defaultLanguage = "pl"

    public let title: String
    public let shop: String
    /// The shop's own page for the product. Always https.
    public let url: String
    /// The user's price in minor units (grosze), in `currency`.
    public let thresholdMinor: Int
    public let currency: String
    public let language: String

    /// Leading and trailing spaces of the three texts are trimmed; nothing else is changed.
    public init(title: String, shop: String, url: String, thresholdMinor: Int, currency: String = "PLN",
                language: String = PriceWatchDraft.defaultLanguage) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.shop = shop.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        self.thresholdMinor = thresholdMinor
        self.currency = currency
        self.language = language
    }

    /// Watching a pick's offer: the product's title and shop as the result card shows them (a title or shop
    /// longer than the server takes is cut with "…", and the card then shows exactly the cut text), the
    /// shop's own page (`url`, never the partner link), and the offer's currency.
    public init(watching offer: ShoppingOffer, thresholdMinor: Int, language: String = PriceWatchDraft.defaultLanguage) {
        self.init(title: Self.clipped(offer.title, to: Self.maxTitle), shop: Self.clipped(offer.shop, to: Self.maxShop),
                  url: offer.url, thresholdMinor: thresholdMinor, currency: offer.price.currency, language: language)
    }

    /// Hints before sending, in a fixed order; the server checks the same rules again and decides.
    /// Lengths count UTF-16 units, as the server's schema does (JavaScript string length).
    public func validationIssues() -> [WatchDraftIssue] {
        var issues: [WatchDraftIssue] = []
        if title.isEmpty { issues.append(.missingTitle) } else if title.utf16.count > Self.maxTitle { issues.append(.titleTooLong) }
        if shop.isEmpty { issues.append(.missingShop) } else if shop.utf16.count > Self.maxShop { issues.append(.shopTooLong) }
        if url.utf16.count > Self.maxURL { issues.append(.urlTooLong) } else if !Self.isHTTPSAddress(url) { issues.append(.urlNotHTTPS) }
        if thresholdMinor < 1 || thresholdMinor > Self.maxThresholdMinor { issues.append(.priceOutOfRange) }
        if !Self.isCurrencyCode(currency) { issues.append(.currencyNotACode) }
        if !ErrandDraft.isLanguageCode(language) { issues.append(.languageNotACode) }
        return issues
    }

    public var isValid: Bool { validationIssues().isEmpty }

    /// The user's price.
    public var threshold: Money { Money(minor: thresholdMinor, currency: currency) }

    /// The exact text the digest is taken over: the canonical JSON of `{checksPerDay, currency, days,
    /// language, shop, thresholdMinor, title, url}`, keys sorted, no spaces, strings escaped as
    /// JavaScript's JSON.stringify escapes them, `days` 30 and `checksPerDay` 4
    /// (fixture watch_create_v1.json).
    var canonicalJSON: String {
        "{\"checksPerDay\":\(Self.checksPerDay),\"currency\":\(ErrandDraft.jsonString(currency)),\"days\":\(Self.days),"
            + "\"language\":\(ErrandDraft.jsonString(language)),\"shop\":\(ErrandDraft.jsonString(shop)),"
            + "\"thresholdMinor\":\(thresholdMinor),\"title\":\(ErrandDraft.jsonString(title)),\"url\":\(ErrandDraft.jsonString(url))}"
    }

    /// SHA-256 (hex) over `canonicalJSON`. The app approves a preview only when its digest is this one,
    /// so the yes is bound to exactly these words, this price and this promise.
    public var digest: String {
        SHA256.hash(data: Data(canonicalJSON.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: The user's price

    /// 5% below the price, rounded DOWN to whole złoty (the card's suggestion; the user can type another).
    /// Below one whole unit the plain 5% below is used, so a very cheap product still gets a number. Nil when
    /// no number below the price fits the contract's range.
    public static func suggestedThresholdMinor(forPriceMinor price: Int) -> Int? {
        guard price > 1, price <= maxThresholdMinor else { return nil }
        let fivePercentBelow = price * 95 / 100
        let wholeUnits = fivePercentBelow / 100 * 100
        let suggestion = wholeUnits >= 100 ? wholeUnits : fivePercentBelow
        return suggestion >= 1 && suggestion < price ? suggestion : nil
    }

    /// What the user typed as their price ("1800", "1 799,90", "1799.9 zł") in minor units. Only digits, one
    /// comma or dot with at most two decimals, and an optional "zł" or the currency code after it. Anything
    /// else, zero, or a price over the contract's range is nil: the card asks again instead of guessing.
    public static func parseThresholdMinor(_ text: String, currency: String = "PLN") -> Int? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for suffix in ["zł", "zl", currency.lowercased()] where body.hasSuffix(suffix) {
            body = String(body.dropLast(suffix.count))
            break
        }
        // Spaces and no-break spaces group thousands ("1 800").
        body = String(body.unicodeScalars.filter { !$0.properties.isWhitespace })
        guard !body.isEmpty, body.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) || $0 == "," || $0 == "." }) else { return nil }
        // One separator at most ("1,800.50" is not guessed at), with digits on both sides of it.
        let parts = body.split(omittingEmptySubsequences: false) { $0 == "," || $0 == "." }
        guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty }), parts[0].count <= 12,
              parts.count == 1 || parts[1].count <= 2, let units = Int(parts[0]) else { return nil }
        let cents = parts.count == 2 ? Int(parts[1] + (parts[1].count == 1 ? "0" : "")) ?? 0 : 0
        let minor = units * 100 + cents
        return minor >= 1 && minor <= maxThresholdMinor ? minor : nil
    }

    /// A price as it is typed into the card's field: "1804", or "1799,90" in Polish and "1799.90" otherwise.
    /// No currency; `parseThresholdMinor` reads it back to the same amount.
    public static func typedText(forMinor minor: Int, _ language: NotificationLanguage) -> String {
        let whole = minor / 100
        let cents = minor % 100
        guard cents != 0 else { return String(whole) }
        return "\(whole)\(language == .polish ? "," : ".")\(cents < 10 ? "0\(cents)" : "\(cents)")"
    }

    // MARK: Checks

    /// `https://` and a host, nothing else asked (the contract's rule); no space or control character.
    static func isHTTPSAddress(_ text: String) -> Bool {
        guard text.lowercased().hasPrefix("https://"),
              !text.unicodeScalars.contains(where: { $0.value < 0x21 || $0.value == 0x7F || $0.properties.isWhitespace })
        else { return false }
        let rest = text.dropFirst("https://".count)
        var authority = rest[..<(rest.firstIndex(where: { "/?#".contains($0) }) ?? rest.endIndex)]
        if let at = authority.lastIndex(of: "@") { authority = authority[authority.index(after: at)...] }
        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else { return false }
            return authority.distance(from: authority.startIndex, to: close) > 1
        }
        let host = authority[..<(authority.firstIndex(of: ":") ?? authority.endIndex)]
        return !host.isEmpty
    }

    static func isCurrencyCode(_ text: String) -> Bool {
        text.unicodeScalars.count == 3 && text.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) }
    }

    /// At most `limit` UTF-16 units, cut between characters; a cut ends in "…" (which counts in the limit).
    static func clipped(_ text: String, to limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf16.count > limit else { return trimmed }
        var out = ""
        var used = 0
        for character in trimmed {
            let units = String(character).utf16.count
            guard used + units <= limit - 1 else { break }
            out.append(character)
            used += units
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

/// Why a draft can't be sent. Each names the request field the server's schema would name.
public enum WatchDraftIssue: Equatable, Sendable {
    case missingTitle, titleTooLong, missingShop, shopTooLong, urlNotHTTPS, urlTooLong
    case priceOutOfRange, currencyNotACode, languageNotACode

    public var field: String {
        switch self {
        case .missingTitle, .titleTooLong: "title"
        case .missingShop, .shopTooLong: "shop"
        case .urlNotHTTPS, .urlTooLong: "url"
        case .priceOutOfRange: "thresholdMinor"
        case .currencyNotACode: "currency"
        case .languageNotACode: "language"
        }
    }
}

extension ShoppingOffer {
    /// Only a price read from the shop's own page can be watched: the server reads that same page again.
    /// A price from the Google Shopping list isn't from a page Doddy could confirm, so there is no button.
    public var canWatchPrice: Bool {
        evidence == .shopPage && PriceWatchDraft.isHTTPSAddress(url) && PriceWatchDraft.isCurrencyCode(price.currency)
    }
}

// MARK: - What the server returns

/// Why the server couldn't read a price when it made the draft (`422 price_not_readable`).
public enum PriceUnreadableReason: String, Codable, Sendable, CaseIterable {
    /// The shop's site doesn't let automated readers in; Doddy doesn't get around that.
    case blocked
    /// The shop's robots.txt says no.
    case notAllowed = "not_allowed"
    /// The page has no price Doddy can read from its product data.
    case noPrice = "no_price"
    /// The page couldn't be read this time.
    case failed
    /// A reason this version of the app doesn't know.
    case unknown

    public init(from decoder: any Decoder) throws {
        self = PriceUnreadableReason(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

/// `201` from `POST /v1/watches`: a draft, nothing is watched yet. The approval is bound to `digest`.
public struct WatchPreview: Decodable, Equatable, Sendable {
    public let id: UUID
    public let digest: String
    public let title: String
    public let shop: String
    public let url: String
    public let thresholdMinor: Int
    public let currency: String
    public let language: String
    /// The price the server read from the page just now.
    public let currentMinor: Int
    public let checkedAt: Date
    /// When the draft lapses (10 minutes): after that it can't be approved.
    public let expiresAt: Date
    public let days: Int
    public let checksPerDay: Int

    public init(id: UUID, digest: String, title: String, shop: String, url: String, thresholdMinor: Int, currency: String,
                language: String, currentMinor: Int, checkedAt: Date, expiresAt: Date,
                days: Int = PriceWatchDraft.days, checksPerDay: Int = PriceWatchDraft.checksPerDay) {
        self.id = id
        self.digest = digest
        self.title = title
        self.shop = shop
        self.url = url
        self.thresholdMinor = thresholdMinor
        self.currency = currency
        self.language = language
        self.currentMinor = currentMinor
        self.checkedAt = checkedAt
        self.expiresAt = expiresAt
        self.days = days
        self.checksPerDay = checksPerDay
    }

    private enum CodingKeys: String, CodingKey {
        case id, digest, title, shop, url, thresholdMinor, currency, language, currentMinor, checkedAt, expiresAt, days, checksPerDay
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        digest = try c.decode(String.self, forKey: .digest)
        title = try c.decode(String.self, forKey: .title)
        shop = try c.decode(String.self, forKey: .shop)
        url = try c.decode(String.self, forKey: .url)
        thresholdMinor = try c.decode(Int.self, forKey: .thresholdMinor)
        currency = try c.decode(String.self, forKey: .currency)
        language = try c.decode(String.self, forKey: .language)
        currentMinor = try c.decode(Int.self, forKey: .currentMinor)
        checkedAt = try c.serverDate(.checkedAt)
        expiresAt = try c.serverDate(.expiresAt)
        days = try c.decode(Int.self, forKey: .days)
        checksPerDay = try c.decode(Int.self, forKey: .checksPerDay)
    }

    /// The price the server read.
    public var current: Money { Money(minor: currentMinor, currency: currency) }
    /// The user's price, as the server holds it.
    public var threshold: Money { Money(minor: thresholdMinor, currency: currency) }

    /// The server holds exactly what the user was shown, and its digest is for exactly that: the same
    /// title, shop, address, price, currency and language, the same promise (the days and checks the
    /// card says), and the digest the app computed itself. Anything else is never approved.
    public func matches(_ draft: PriceWatchDraft) -> Bool {
        title == draft.title && shop == draft.shop && url == draft.url && thresholdMinor == draft.thresholdMinor
            && currency == draft.currency && language == draft.language
            && days == PriceWatchDraft.days && checksPerDay == PriceWatchDraft.checksPerDay
            && digest == draft.digest
    }
}

/// `202` from `POST /v1/watches/{id}/approve`, or what the app has when the answer never came back.
public struct WatchApproval: Equatable, Sendable {
    /// Nil when the server's answer never reached the phone.
    public let id: UUID?
    /// `active` as the server said it, or `unknown`: it may have started, and it is not approved again.
    public let state: WatchState
    public let endsAt: Date?

    public init(id: UUID?, state: WatchState, endsAt: Date? = nil) {
        self.id = id
        self.state = state
        self.endsAt = endsAt
    }

    /// No trustworthy answer.
    public static let unknown = WatchApproval(id: nil, state: .unknown)

    public var isUnknown: Bool { state == .unknown }
    /// The server said it is active (for this watch, with an id): the only thing that may be called watching.
    public var isConfirmed: Bool { state == .active && id != nil }
}

public enum WatchState: String, Codable, Sendable, CaseIterable {
    /// Created and waiting for the user's yes (10 minutes). Not listed by the server.
    case draft
    case active
    /// The server read a price at or below the user's, once, and sent one notification.
    case triggered
    /// 30 days passed.
    case expired
    /// The user stopped it.
    case stopped
    /// Eight checks in a row couldn't read a price.
    case failed
    /// A state this version of the app doesn't know, or an approval whose answer never came back.
    /// Never shown as active.
    case unknown

    /// A newer server's state decodes as `unknown` instead of breaking the app.
    public init(from decoder: any Decoder) throws {
        self = WatchState(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    /// Only an active watch is being watched.
    public var isActive: Bool { self == .active }
    /// The watch is over (it ended one way or another).
    public var isFinished: Bool { self == .triggered || self == .expired || self == .stopped || self == .failed }
}

/// Why the server ended a watch as `failed`.
public enum WatchFailure: String, Codable, Sendable, CaseIterable {
    /// Eight checks in a row couldn't read a price.
    case unreadable
    case unknown

    public init(from decoder: any Decoder) throws {
        self = WatchFailure(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

/// One row of `GET /v1/watches` (newest first, no drafts), or `GET /v1/watches/{id}`.
public struct WatchSummary: Decodable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let state: WatchState
    public let title: String
    public let shop: String
    public let url: String
    public let thresholdMinor: Int
    public let currency: String
    public let language: String
    public let createdAt: Date
    /// Set at the approval (30 days on).
    public let endsAt: Date?
    /// A draft read by id: when it lapses.
    public let expiresAt: Date?
    /// The last check, whether or not it could read a price.
    public let lastCheckedAt: Date?
    /// The last price the server confirmed. Nil until one was.
    public let lastPriceMinor: Int?
    public let checksDone: Int
    public let triggeredAt: Date?
    public let triggeredPriceMinor: Int?
    public let failure: WatchFailure?

    public init(id: UUID, state: WatchState, title: String, shop: String, url: String, thresholdMinor: Int, currency: String = "PLN",
                language: String = "pl", createdAt: Date, endsAt: Date? = nil, expiresAt: Date? = nil, lastCheckedAt: Date? = nil,
                lastPriceMinor: Int? = nil, checksDone: Int = 0, triggeredAt: Date? = nil, triggeredPriceMinor: Int? = nil,
                failure: WatchFailure? = nil) {
        self.id = id
        self.state = state
        self.title = title
        self.shop = shop
        self.url = url
        self.thresholdMinor = thresholdMinor
        self.currency = currency
        self.language = language
        self.createdAt = createdAt
        self.endsAt = endsAt
        self.expiresAt = expiresAt
        self.lastCheckedAt = lastCheckedAt
        self.lastPriceMinor = lastPriceMinor
        self.checksDone = checksDone
        self.triggeredAt = triggeredAt
        self.triggeredPriceMinor = triggeredPriceMinor
        self.failure = failure
    }

    private enum CodingKeys: String, CodingKey {
        case id, state, title, shop, url, thresholdMinor, currency, language, createdAt, endsAt, expiresAt
        case lastCheckedAt, lastPriceMinor, checksDone, triggeredAt, triggeredPriceMinor, failure
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        state = try c.decode(WatchState.self, forKey: .state)
        title = try c.decode(String.self, forKey: .title)
        shop = try c.decode(String.self, forKey: .shop)
        url = try c.decode(String.self, forKey: .url)
        thresholdMinor = try c.decode(Int.self, forKey: .thresholdMinor)
        currency = try c.decode(String.self, forKey: .currency)
        language = try c.decode(String.self, forKey: .language)
        createdAt = try c.serverDate(.createdAt)
        endsAt = try c.serverDateIfPresent(.endsAt)
        expiresAt = try c.serverDateIfPresent(.expiresAt)
        lastCheckedAt = try c.serverDateIfPresent(.lastCheckedAt)
        lastPriceMinor = try c.decodeIfPresent(Int.self, forKey: .lastPriceMinor)
        checksDone = try c.decodeIfPresent(Int.self, forKey: .checksDone) ?? 0
        triggeredAt = try c.serverDateIfPresent(.triggeredAt)
        triggeredPriceMinor = try c.decodeIfPresent(Int.self, forKey: .triggeredPriceMinor)
        failure = try c.decodeIfPresent(WatchFailure.self, forKey: .failure)
    }

    /// The user's price.
    public var threshold: Money { Money(minor: thresholdMinor, currency: currency) }

    /// The last price the server confirmed.
    public var lastPrice: Money? { lastPriceMinor.map { Money(minor: $0, currency: currency) } }

    /// The price the server confirmed at the drop: only for a triggered watch, only with `triggeredPriceMinor`,
    /// and only when that price is at or below the user's (the contract's rule for a trigger). Without it
    /// nothing says the price dropped.
    public var confirmedDrop: Money? {
        guard state == .triggered, let price = triggeredPriceMinor, price <= thresholdMinor else { return nil }
        return Money(minor: price, currency: currency)
    }

    /// Only an active watch can be stopped (409 `not_stoppable` otherwise).
    public var canStop: Bool { state == .active }

    /// This row after the server answered `204` to its stop: stopped. Only an active watch changes; every
    /// other row stays as the server last said it.
    public func stopped() -> WatchSummary {
        guard state == .active else { return self }
        return WatchSummary(id: id, state: .stopped, title: title, shop: shop, url: url, thresholdMinor: thresholdMinor,
                            currency: currency, language: language, createdAt: createdAt, endsAt: endsAt, expiresAt: expiresAt,
                            lastCheckedAt: lastCheckedAt, lastPriceMinor: lastPriceMinor, checksDone: checksDone,
                            triggeredAt: triggeredAt, triggeredPriceMinor: triggeredPriceMinor, failure: failure)
    }
}

// MARK: - Failures

/// Why a watch wasn't made, approved, stopped or deleted, with what the app can tell the user.
public enum WatchError: Error, Equatable, Sendable {
    case server(ServerError)
    /// The server's schema refused a field (400 `invalid_request`), or the app refused it before sending
    /// (the same rules, `PriceWatchDraft.validationIssues`).
    case invalid(fields: [String])
    /// The server couldn't read a price from the page (422 `price_not_readable`).
    case priceNotReadable(PriceUnreadableReason)
    /// The page's price is in another currency than the user's (422 `currency_mismatch`).
    case currencyMismatch
    /// The price just read is already at or below the user's (422 `already_below`), as the server said it.
    case alreadyBelow(currentMinor: Int?)
    /// Not a draft any more, or it expired (409 `not_approvable`), with the state the server named.
    case notApprovable(state: WatchState?)
    /// The approval's digest isn't the draft's (409 `digest_mismatch`).
    case digestMismatch
    /// The account's active watches are at the server's limit (409 `too_many_open_watches`).
    case tooManyOpenWatches
    /// Only an active watch can be stopped (409 `not_stoppable`), with the state the server named.
    case notStoppable(state: WatchState?)
    /// The server has no such watch (404 `not_found`).
    case notFound
    /// Price watching is switched off or not set up on the server (503 `watches_disabled`).
    case watchesDisabled
    /// Too many requests (429).
    case rateLimited
    /// Another 409, with the server's code.
    case conflict(String)
    /// The server's preview doesn't hold exactly what the user was shown, so the app doesn't approve it.
    case previewMismatch
}

// MARK: - Words

/// The words the watch screens use, in the iPhone's language (Polish or English, like the other core
/// helpers). Pure functions, so the tests hold every sentence. Never says a price dropped without the price
/// the server confirmed, never says watching for a state the server didn't call active.
public enum WatchWords {
    /// The card's commitment (the contract's section 1), the same sentence on the card and in the tests.
    public static func promise(_ language: NotificationLanguage) -> String {
        let days = PriceWatchDraft.days
        let checks = PriceWatchDraft.checksPerDay
        switch language {
        case .polish: return "Sprawdzam stronę \(checks) razy dziennie przez \(days) dni, potem przestaję. Tylko dam Ci znać; niczego nie kupuję."
        case .english: return "I check the page \(checks) times a day for \(days) days, then I stop. I only tell you; I don't buy anything."
        }
    }

    /// One line on a watch in the list.
    public static func state(_ watch: WatchSummary, _ language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch watch.state {
        case .active:
            return polish ? "Pilnuję" : "Watching"
        case .triggered:
            // "Dropped" only with the price the server confirmed.
            guard let price = watch.confirmedDrop else {
                return polish ? "Nie mogę potwierdzić, że cena spadła" : "I can't confirm that the price dropped"
            }
            return polish ? "Cena spadła do \(price.text(language))" : "Price dropped to \(price.text(language))"
        case .expired:
            return polish ? "Skończone po \(PriceWatchDraft.days) dniach" : "Finished after \(PriceWatchDraft.days) days"
        case .stopped:
            return polish ? "Zatrzymane" : "Stopped"
        case .failed:
            return polish ? "Nie mogę już odczytać ceny" : "I can no longer read the price"
        case .draft:
            return polish ? "Czeka na Twoje „tak”" : "Waiting for your yes"
        case .unknown:
            return polish ? "Nieznany stan" : "Status not known"
        }
    }

    /// "Your price: 1 800,00 zł".
    public static func yourPrice(_ watch: WatchSummary, _ language: NotificationLanguage) -> String {
        (language == .polish ? "Twoja cena: " : "Your price: ") + watch.threshold.text(language)
    }

    /// "Last confirmed price: …", or nil until the server confirmed one (a failed check is never a price).
    public static func lastPrice(_ watch: WatchSummary, _ language: NotificationLanguage) -> String? {
        guard let price = watch.lastPrice else { return nil }
        return (language == .polish ? "Ostatnia potwierdzona cena: " : "Last confirmed price: ") + price.text(language)
    }

    /// What the card says after the server confirmed the watch is active.
    public static func started(threshold: Money, _ language: NotificationLanguage) -> String {
        switch language {
        case .polish:
            return "Pilnuję. Dam Ci znać, gdy cena spadnie do \(threshold.text(language)) lub niżej. Nic nie kupuję."
        case .english:
            return "I'm watching. I'll tell you when the price is \(threshold.text(language)) or lower. I don't buy anything."
        }
    }

    /// The approval's answer never came back and the server wasn't asked, or couldn't say: it may be running.
    public static func notSure(_ language: NotificationLanguage) -> String {
        switch language {
        case .polish:
            return "Nie mogę potwierdzić, że pilnowanie ruszyło; może działać. Sprawdź listę pilnowanych cen. Nie włączę go drugi raz sam."
        case .english:
            return "I couldn't confirm that the watch started; it may be running. Check your watched prices. I won't start it again by myself."
        }
    }

    /// The approval's answer never came back, but the server says the draft is still waiting.
    public static func notStartedYet(_ language: NotificationLanguage) -> String {
        switch language {
        case .polish: return "Pilnowanie jeszcze nie ruszyło: serwer nie dostał Twojego „tak”. Nic nie jest pilnowane. Możesz spróbować jeszcze raz."
        case .english: return "The watch hasn't started: the server didn't get your yes. Nothing is being watched. You can try again."
        }
    }

    /// Connections are paused in Settings, so nothing is sent.
    public static func paused(_ language: NotificationLanguage) -> String {
        switch language {
        case .polish: return "Połączenia są wstrzymane w Ustawieniach, więc Doddy nie może zacząć pilnować ceny. Nic nie zostało wysłane."
        case .english: return "Connections are paused in Settings, so Doddy can't start watching a price. Nothing was sent."
        }
    }

    /// The server isn't set up in this build.
    public static func noServer(_ language: NotificationLanguage) -> String {
        switch language {
        case .polish: return "Serwer Doddy’ego nie jest skonfigurowany w tej wersji, więc nie mogę pilnować cen."
        case .english: return "Doddy's server isn't set up in this build, so prices can't be watched."
        }
    }

    /// The price the user typed isn't a price.
    public static func notAPrice(_ language: NotificationLanguage) -> String {
        switch language {
        case .polish: return "Wpisz cenę cyframi, np. 1800 albo 1799,90."
        case .english: return "Type the price in numbers, like 1800 or 1799.90."
        }
    }

    /// Every refusal in words, and what was and wasn't done. `currency` is the watch's, for a price the
    /// server named.
    public static func problem(_ error: any Error, currency: String = "PLN", _ language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch error {
        case WatchError.priceNotReadable(let reason):
            switch reason {
            case .blocked:
                return polish
                    ? "Ten sklep nie wpuszcza automatycznych czytników, a Doddy tego nie obchodzi, więc nie mogę pilnować tej ceny."
                    : "This shop doesn't let automated readers in, and Doddy doesn't get around that, so I can't watch this price."
            case .notAllowed:
                return polish
                    ? "Strona tego sklepu nie zezwala na automatyczne czytanie, więc nie mogę pilnować tej ceny."
                    : "This shop's page doesn't allow automated reading, so I can't watch its price."
            case .noPrice:
                return polish
                    ? "Na tej stronie nie znalazłem ceny, którą umiem odczytać, więc nie mogę jej pilnować."
                    : "I couldn't find a price I can read on this page, so I can't watch it."
            case .failed, .unknown:
                return polish
                    ? "Nie udało się teraz odczytać tej strony. Nic nie jest pilnowane; spróbuj za chwilę."
                    : "I couldn't read this page just now. Nothing is being watched; try again in a moment."
            }
        case WatchError.currencyMismatch:
            return polish
                ? "Strona podaje cenę w innej walucie niż Twoja, więc nie mogę jej pilnować."
                : "The page shows its price in a different currency than yours, so I can't watch it."
        case WatchError.alreadyBelow(let current):
            let now = current.map { Money(minor: $0, currency: currency).text(language) }
            if polish { return "Ta cena jest już równa Twojej albo niższa" + (now.map { " (teraz \($0))" } ?? "") + ", więc nie ma czego pilnować." }
            return "That price is already at or below yours" + (now.map { " (now \($0))" } ?? "") + ", so there's nothing to watch for."
        case WatchError.tooManyOpenWatches:
            return polish
                ? "Pilnujesz już tylu cen, ile serwer Doddy’ego pozwala naraz. Zatrzymaj albo usuń jedną i spróbuj jeszcze raz."
                : "You're already watching as many prices as Doddy's server allows at once. Stop or delete one and try again."
        case WatchError.watchesDisabled:
            return polish
                ? "Pilnowanie cen jest wyłączone albo nieskonfigurowane na serwerze Doddy’ego. Nic nie jest pilnowane."
                : "Price watching is switched off or not set up on Doddy's server. Nothing is being watched."
        case WatchError.notApprovable:
            return polish
                ? "Ta propozycja wygasła albo już została użyta. Nic nie zostało włączone; zacznij od nowa."
                : "That offer to watch expired or was already used. Nothing was started; begin again."
        case WatchError.digestMismatch:
            return polish
                ? "Prośba zmieniła się, zanim ją zatwierdziłeś. Nic nie zostało włączone; zacznij od nowa."
                : "The request changed before it was approved. Nothing was started; begin again."
        case WatchError.previewMismatch:
            return polish
                ? "Serwer Doddy’ego nie ma dokładnie tego, co zobaczyłeś, więc niczego nie włączyłem."
                : "Doddy's server doesn't hold exactly what you were shown, so I didn't start it."
        case WatchError.invalid:
            return polish
                ? "Serwer Doddy’ego nie przyjął tej prośby. Sprawdź cenę i spróbuj jeszcze raz. Nic nie zostało włączone."
                : "Doddy's server didn't accept that request. Check the price and try again. Nothing was started."
        case WatchError.notStoppable(let state):
            if state == .stopped { return polish ? "To pilnowanie jest już zatrzymane." : "This watch is already stopped." }
            return polish
                ? "Tego pilnowania nie da się zatrzymać: już się skończyło."
                : "This watch can't be stopped: it has already ended."
        case WatchError.notFound:
            return polish ? "Serwer Doddy’ego nie ma już tego pilnowania." : "Doddy's server doesn't have this watch any more."
        case WatchError.conflict:
            return polish
                ? "Nie dało się tego zrobić: pilnowanie się zmieniło. Odśwież listę."
                : "That couldn't be done: the watch changed. Refresh the list."
        case WatchError.rateLimited, WatchError.server(.rateLimited), ServerError.rateLimited:
            return polish ? "Za dużo prób. Poczekaj chwilę i spróbuj jeszcze raz." : "Too many tries. Wait a moment and try again."
        case WatchError.server(.offline), ServerError.offline:
            return polish
                ? "Nie mogę połączyć się z serwerem Doddy’ego. Nic się nie zmieniło; spróbuj, gdy będziesz online."
                : "Couldn't reach Doddy's server. Nothing was changed; try again when you're online."
        default:
            return polish
                ? "Coś poszło nie tak na serwerze Doddy’ego. Nic nie zostało zmienione."
                : "Something went wrong on Doddy's server. Nothing was changed."
        }
    }
}
