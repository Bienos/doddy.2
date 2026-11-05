import Foundation

// A product's barcode on a list (Shopping list+, ADR-631, stage 3). The iPhone reads the barcode
// from a photo itself (Vision); this file checks the digits, builds the one Open Food Facts address
// the app may ask, reads the answer and keeps the app under Open Food Facts' limit. The iPhone asks
// Open Food Facts directly, never through Doddy's server: Open Food Facts allows 15 product reads a
// minute per IP address, and through a server every user would share one address. Only the
// barcode digits are sent. Nothing is added to a list without the user's tap on the answer.
//
// Open Food Facts' data is under the Open Database License (ODbL); the answer card says where it
// came from. Checked on https://openfoodfacts.github.io/openfoodfacts-server/api/ on 24 Oct 2026.
//
// Platforms: iPhone and iPad (lists). Pure logic; tested on Linux.

/// A retail barcode (GTIN-8, -12, -13 or -14) whose check digit is right.
public struct ProductBarcode: Equatable, Hashable, Sendable {
    /// Digits only, as printed under the bars.
    public let digits: String

    /// Nil unless `raw` is 8, 12, 13 or 14 digits (spaces and dashes ignored) with a valid GS1
    /// check digit. Nothing else is ever sent anywhere.
    public init?(_ raw: String) {
        let digits = raw.filter { $0 != " " && $0 != "-" }
        guard [8, 12, 13, 14].contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let values = digits.compactMap { $0.wholeNumberValue }
        guard values.count == digits.count, Self.checkDigitIsValid(values) else { return nil }
        self.digits = digits
    }

    /// GS1: from the right, leaving out the check digit, weights 3, 1, 3, 1…; the check digit makes
    /// the sum a multiple of ten.
    static func checkDigitIsValid(_ values: [Int]) -> Bool {
        guard let check = values.last else { return false }
        var sum = 0
        for (offset, value) in values.dropLast().reversed().enumerated() {
            sum += value * (offset % 2 == 0 ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == check
    }
}

/// What Open Food Facts says a barcode is: only what the list needs.
public struct OpenFoodFactsProduct: Equatable, Sendable {
    public static let maxName = 120
    public static let maxBrand = 60
    public static let maxQuantity = 30

    public let code: String
    public let name: String
    /// The first brand Open Food Facts lists.
    public let brand: String?
    /// The package size as Open Food Facts writes it ("1 l", "500 g").
    public let quantity: String?

    public init(code: String, name: String, brand: String?, quantity: String?) {
        self.code = code
        self.name = name
        self.brand = brand
        self.quantity = quantity
    }

    /// The words that go on the list: the name, then the brand and the size when the name doesn't
    /// already say them ("Mleko UHT 3,2% Łaciate 1 l"). Never longer than a list item may be: the
    /// size goes first, then the brand, then the name is cut.
    public var itemText: String {
        let folded = SearchFolding.fold(name)
        let brand = brand.flatMap { folded.contains(SearchFolding.fold($0)) ? nil : $0 }
        let quantity = quantity.flatMap { folded.replacingOccurrences(of: " ", with: "")
            .contains(SearchFolding.fold($0).replacingOccurrences(of: " ", with: "")) ? nil : $0 }
        for parts in [[name, brand, quantity], [name, brand], [name]] {
            let text = parts.compactMap { $0 }.joined(separator: " ")
            if ListText.fitsItemLength(text) { return text }
        }
        return String(String.UnicodeScalarView(name.unicodeScalars.prefix(ListLimits.itemLength)))
    }
}

public enum OpenFoodFactsAnswer: Equatable, Sendable {
    case found(OpenFoodFactsProduct)
    /// Open Food Facts has no such product, or no name for it.
    case notFound
    /// Not the answer expected; nothing is shown from it.
    case unreadable
}

public enum OpenFoodFacts {
    /// The fields asked for; nothing else is read.
    public static let fields = ["code", "product_name", "product_name_pl", "product_name_en", "brands", "quantity"]
    /// The answer for one product with these fields is a few hundred bytes.
    public static let maxBytes = 256 * 1024
    public static let timeout: TimeInterval = 10
    /// Open Food Facts allows 15 product reads a minute per IP address; the app stays below it.
    public static let lookupsPerMinute = 10
    public static let attribution = "Open Food Facts (ODbL)"

    /// The one address the app asks, built from checked digits only.
    public static func productURL(for code: ProductBarcode) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "world.openfoodfacts.org"
        components.path = "/api/v2/product/\(code.digits)"
        components.queryItems = [URLQueryItem(name: "fields", value: fields.joined(separator: ","))]
        // The parts are fixed or digits, so this always makes a URL.
        return components.url!
    }

    /// Open Food Facts asks every app to name itself: "AppName/Version (contact)".
    public static func userAgent(appVersion: String) -> String {
        let version = appVersion.filter { $0.isASCII && ($0.isNumber || $0 == ".") }
        return "Doddy/\(version.isEmpty ? "1" : version) (https://doddy.lol)"
    }

    /// Reads the answer to `productURL(for: code)`. The product must be the one asked for (leading
    /// zeros aside); the name is the Polish one, else the main one, else the English one.
    public static func parse(_ data: Data, code: ProductBarcode) -> OpenFoodFactsAnswer {
        guard data.count <= maxBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { return .unreadable }
        let status = root["status"]
        let found = (status as? Int) == 1 || (status as? String) == "success"
        let missing = (status as? Int) == 0 || (status as? String) == "failure"
        guard found else { return missing ? .notFound : .unreadable }
        guard let product = root["product"] as? [String: Any] else { return .unreadable }
        let answeredCode = (root["code"] as? String) ?? (product["code"] as? String) ?? code.digits
        guard sameCode(answeredCode, code.digits) else { return .unreadable }
        let name = ["product_name_pl", "product_name", "product_name_en"].lazy
            .compactMap { cleaned(product[$0], max: OpenFoodFactsProduct.maxName) }.first
        guard let name else { return .notFound }
        let brand = (product["brands"] as? String)?.split(separator: ",").first
            .flatMap { cleaned(String($0), max: OpenFoodFactsProduct.maxBrand) }
        let quantity = cleaned(product["quantity"], max: OpenFoodFactsProduct.maxQuantity).flatMap(withoutEstimateMark)
        return .found(OpenFoodFactsProduct(code: code.digits, name: name, brand: brand, quantity: quantity))
    }

    /// Package sizes often end with the EU estimate sign, written "℮" or "e" ("400 g e"): it says the
    /// size is an average, so it is dropped and "400 g" is read as the quantity (stage 1).
    static func withoutEstimateMark(_ quantity: String) -> String? {
        var text = quantity
        for mark in [" ℮", "℮", " e"] where text.hasSuffix(mark) {
            text.removeLast(mark.count)
            break
        }
        return ListText.cleaned(text)
    }

    private static func sameCode(_ a: String, _ b: String) -> Bool {
        func trimmed(_ s: String) -> Substring { s.drop { $0 == "0" } }
        return trimmed(a) == trimmed(b)
    }

    /// One line, no control characters, cut to `max` characters; nil when empty or not text.
    private static func cleaned(_ value: Any?, max: Int) -> String? {
        guard let text = value as? String else { return nil }
        let plain = String(String.UnicodeScalarView(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        guard let line = ListText.cleaned(plain) else { return nil }
        return line.count <= max ? line : String(line.prefix(max)).trimmingCharacters(in: .whitespaces)
    }
}

/// At most `limit` look-ups in any `seconds`: kept by the app so it never reaches a service's own limit.
public struct LookupWindow: Equatable, Sendable {
    public let limit: Int
    public let seconds: TimeInterval
    public private(set) var times: [Date] = []

    public init(limit: Int, seconds: TimeInterval) {
        self.limit = limit
        self.seconds = seconds
    }

    /// True, and counted, when one more look-up fits now; false (and not counted) when it doesn't.
    /// A clock that went back clears the window rather than blocking for good.
    public mutating func take(now: Date) -> Bool {
        times.removeAll { now.timeIntervalSince($0) >= seconds || $0 > now }
        guard times.count < limit else { return false }
        times.append(now)
        return true
    }
}
