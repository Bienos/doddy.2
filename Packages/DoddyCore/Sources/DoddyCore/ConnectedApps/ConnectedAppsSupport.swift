import Foundation

/// The next local calendar date in the user's time zone (not "now + 24 h").
public enum LocalDay {
    public static func tomorrow(from now: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        let startOfToday = calendar.date(from: today) ?? now
        let next = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let c = calendar.dateComponents([.year, .month, .day], from: next)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Reads the URL the system authentication session returned. Only the configured scheme and
/// the allowlisted parameters are used; the server re-verifies everything regardless.
public enum ConnectionCallback {
    public static func result(from url: URL, expectedScheme: String, attemptId: UUID) -> CompletionResult? {
        guard url.scheme?.lowercased() == expectedScheme.lowercased(),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        func value(_ name: String) -> String? {
            let matches = items.filter { $0.name == name }
            return matches.count == 1 ? matches[0].value : nil
        }
        if let sessionUri = value("session_uri"), !sessionUri.isEmpty {
            return .verifier(sessionUri: sessionUri)
        }
        // A return for a different attempt is ignored rather than completed.
        if let attempt = value("attempt"), attempt.lowercased() != attemptId.uuidString.lowercased() { return nil }
        guard let status = value("status"), status == "success" || status == "failed" else { return nil }
        return .callback(status: status, connectedAccountId: value("connected_account_id"))
    }
}

public enum ConnectedAppsDates {
    private static func iso(_ fractional: Bool) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return f
    }

    public static func instant(_ string: String) -> Date? {
        iso(true).date(from: string) ?? iso(false).date(from: string)
    }

    /// Text for an explicitly saved memory. Built by the app from the event the user chose;
    /// the source is stated in the note itself.
    public static func memoryText(for event: CalendarEventItem, window: EventsWindow) -> String {
        guard !event.allDay, let start = instant(event.start), let end = instant(event.end),
              let zone = TimeZone(identifier: window.timeZone)
        else {
            return "\(event.title) — \(window.date), all day (from Google Calendar)"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let t = DateFormatter()
        t.locale = f.locale
        t.timeZone = zone
        t.dateFormat = "HH:mm"
        return "\(event.title) — \(f.string(from: start))–\(t.string(from: end)) \(window.timeZone) (from Google Calendar)"
    }
}
