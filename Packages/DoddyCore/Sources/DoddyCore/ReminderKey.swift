import Foundation

/// Stops the same reminder being added twice: when the agent repeats a request, or the user says
/// "try again" after an add Doddy couldn't confirm (acceptance A-22). Each reminder Doddy adds
/// carries a marker URL with a key made from its text and due time. Before adding, the app looks
/// for an incomplete reminder with the same key; if there is one, nothing new is added.
public enum ReminderKey {
    public static let scheme = "doddy"
    private static let host = "reminder"

    /// Same text (ignoring case, accents and extra spaces) and same due minute or day → same key.
    public static func key(for draft: ReminderDraft, calendar: Calendar) -> String {
        let title = SearchFolding.fold(draft.title)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var due = "none"
        if let date = draft.due {
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            due = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            if draft.dueHasTime { due += String(format: "T%02d:%02d", parts.hour ?? 0, parts.minute ?? 0) }
        }
        return fnv1a64("\(title)|\(due)")
    }

    public static func markerURL(for draft: ReminderDraft, calendar: Calendar) -> URL {
        URL(string: "\(scheme)://\(host)/\(key(for: draft, calendar: calendar))")!
    }

    /// The key from a reminder's URL, or nil when Doddy didn't add it.
    public static func key(fromMarker url: URL?) -> String? {
        guard let url, url.scheme == scheme, url.host == host else { return nil }
        let key = url.lastPathComponent
        return key.count == 16 && key.allSatisfy(\.isHexDigit) ? key : nil
    }

    /// Stable across launches and devices (Swift's `Hasher` is not).
    private static func fnv1a64(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }
}
