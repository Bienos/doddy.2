import Foundation

/// What the "Save to Doddy" share extension hands to the app (ADR-309). The extension can't open
/// Doddy's database, so it only leaves this one item in the App Group folder; the app opens the
/// capture screen with it the next time it is active. Nothing is saved until Save there.
/// One item at a time: a new share replaces one that wasn't picked up yet.
public struct ShareInboxItem: Codable, Equatable, Sendable {
    /// Longer shared text is cut here; the capture screen still checks its own limit.
    public static let maxLength = 20_000
    /// Picked up later than this, the item is dropped instead of shown (it was never saved).
    public static let keptFor: TimeInterval = 7 * 24 * 60 * 60

    public let id: UUID
    public let text: String
    public let sharedAt: Date

    public init(id: UUID = UUID(), text: String, sharedAt: Date) {
        self.id = id
        self.text = text
        self.sharedAt = sharedAt
    }

    /// The text and the web link another app shared, as one note's words. Nil when there is
    /// nothing to keep. The link goes on its own line after the text, unless the text already has it.
    public static func compose(text: String?, link: String?, sharedAt: Date, id: UUID = UUID()) -> ShareInboxItem? {
        let words = clean(text ?? "")
        var parts: [String] = words.isEmpty ? [] : [words]
        if let link = link.map(clean), !link.isEmpty, isWebLink(link), !words.contains(link) {
            parts.append(link)
        }
        guard !parts.isEmpty else { return nil }
        return ShareInboxItem(id: id, text: String(parts.joined(separator: "\n").prefix(maxLength)), sharedAt: sharedAt)
    }

    /// True when it was shared too long ago to show, or its date is in the future (a clock change).
    public func isStale(now: Date) -> Bool {
        sharedAt > now.addingTimeInterval(60) || now.timeIntervalSince(sharedAt) > Self.keptFor
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decoded(_ data: Data) -> ShareInboxItem? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let item = try? decoder.decode(ShareInboxItem.self, from: data),
              !item.text.isEmpty, item.text.count <= maxLength else { return nil }
        return item
    }

    /// Only http and https links are kept as links; anything else is left out.
    static func isWebLink(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    /// Trims, and drops control characters other than line breaks and tabs (some apps share them).
    static func clean(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
