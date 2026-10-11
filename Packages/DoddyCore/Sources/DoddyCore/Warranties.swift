import Foundation

// Warranties and receipts (ADR-342). A note (usually a photo of a receipt, read on the iPhone)
// can carry a warranty: the purchase date and how many months it lasts, both checked and
// changeable by the user before anything is kept. Doddy suggests them from the note's words and
// never decides on its own; a reminder a month before the end is a normal note reminder, set
// only when the user taps. Kept on this iPhone in the app's preferences. Not legal advice: the
// length is whatever the receipt or the user says.

public struct Warranty: Codable, Equatable, Sendable, Identifiable {
    /// The note it belongs to.
    public let id: UUID
    public var purchased: Date
    public var months: Int
    /// What the user calls it, shown in the list; the note's first line by default.
    public var title: String

    public init(id: UUID, purchased: Date, months: Int, title: String) {
        self.id = id
        self.purchased = purchased
        self.months = months
        self.title = title
    }

    public func ends(calendar: Calendar) -> Date {
        calendar.date(byAdding: .month, value: months, to: purchased) ?? purchased
    }

    /// 09:00 a month before the end, or nil when that has already passed.
    public func reminderDate(calendar: Calendar, now: Date) -> Date? {
        guard let monthBefore = calendar.date(byAdding: .month, value: -1, to: ends(calendar: calendar)),
              let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: monthBefore),
              morning > now else { return nil }
        return morning
    }
}

/// What the receipt's words suggest. Every field may be missing; the sheet asks for what is.
public struct WarrantySuggestion: Equatable, Sendable {
    public let purchased: Date?
    public let months: Int?
}

public enum WarrantyReading {
    public static let defaultMonths = 24
    public static let monthsRange = 1...120

    /// The latest date in the text that isn't in the future (a receipt's other dates, like a
    /// return-by date, are usually later), and a warranty length only from a line that says
    /// warranty in English, Polish or German.
    public static func suggest(from text: String, now: Date, calendar: Calendar) -> WarrantySuggestion {
        let dates = self.dates(in: text, calendar: calendar).filter { $0 <= now }
        return WarrantySuggestion(purchased: dates.max(), months: months(in: text))
    }

    static func dates(in text: String, calendar: Calendar) -> [Date] {
        var found: [Date] = []
        // 31.12.2026, 31-12-2026, 31/12/2026, 31.12.26
        let dayFirst = try! NSRegularExpression(pattern: #"(?<![0-9])([0-3]?[0-9])[./-]([01]?[0-9])[./-]((?:20)?[0-9]{2})(?![0-9])"#)
        // 2026-12-31
        let yearFirst = try! NSRegularExpression(pattern: #"(?<![0-9])(20[0-9]{2})-([01][0-9])-([0-3][0-9])(?![0-9])"#)
        let range = NSRange(text.startIndex..., in: text)
        for match in dayFirst.matches(in: text, range: range) {
            let parts = (1...3).compactMap { Range(match.range(at: $0), in: text).map { Int(text[$0]) ?? 0 } }
            guard parts.count == 3 else { continue }
            let year = parts[2] < 100 ? 2000 + parts[2] : parts[2]
            if let date = make(year: year, month: parts[1], day: parts[0], calendar: calendar) { found.append(date) }
        }
        for match in yearFirst.matches(in: text, range: range) {
            let parts = (1...3).compactMap { Range(match.range(at: $0), in: text).map { Int(text[$0]) ?? 0 } }
            guard parts.count == 3 else { continue }
            if let date = make(year: parts[0], month: parts[1], day: parts[2], calendar: calendar) { found.append(date) }
        }
        return found
    }

    static func make(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard (2000...2099).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var parts = DateComponents()
        (parts.year, parts.month, parts.day) = (year, month, day)
        guard let date = calendar.date(from: parts),
              calendar.component(.day, from: date) == day else { return nil }  // no 31 February
        return date
    }

    static func months(in text: String) -> Int? {
        let warrantyWords = ["warrant", "guarant", "gwaranc", "garantie", "rękojm"]
        let number = try! NSRegularExpression(pattern: #"(?<![0-9])([0-9]{1,3})\s*(m-?cy|mies[a-ząę]*|months?|mths?|mo\b|monat[a-z]*|lat[a]?\b|rok[u]?\b|years?|yrs?|jahre?)"#,
                                              options: [.caseInsensitive])
        for line in text.split(whereSeparator: \.isNewline).map({ String($0) }) {
            let lower = line.lowercased()
            guard warrantyWords.contains(where: lower.contains) else { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = number.firstMatch(in: line, range: range),
                  let valueRange = Range(match.range(at: 1), in: line),
                  let unitRange = Range(match.range(at: 2), in: line),
                  let value = Int(line[valueRange]) else { continue }
            let unit = line[unitRange].lowercased()
            let isYears = ["lat", "rok", "year", "yr", "jahr"].contains(where: unit.hasPrefix)
            let months = isYears ? value * 12 : value
            if monthsRange.contains(months) { return months }
        }
        return nil
    }
}

/// The warranties the user kept, newest end last. At most `limit`.
public struct Warranties: Equatable, Sendable {
    public static let storageKey = "warranties"
    public static let limit = 200
    public private(set) var items: [Warranty]

    public init(stored: Data?) {
        items = stored.flatMap { try? JSONDecoder().decode([Warranty].self, from: $0) } ?? []
    }

    public var stored: Data { (try? JSONEncoder().encode(items)) ?? Data() }

    public enum SaveOutcome: Equatable, Sendable { case saved, replaced, full, invalid }

    public mutating func save(_ warranty: Warranty) -> SaveOutcome {
        guard WarrantyReading.monthsRange.contains(warranty.months) else { return .invalid }
        var cleaned = warranty
        cleaned.title = String(warranty.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        if let index = items.firstIndex(where: { $0.id == warranty.id }) {
            items[index] = cleaned
            return .replaced
        }
        guard items.count < Self.limit else { return .full }
        items.append(cleaned)
        return .saved
    }

    public mutating func remove(_ id: UUID) { items.removeAll { $0.id == id } }

    public func warranty(for id: UUID) -> Warranty? { items.first { $0.id == id } }

    /// Soonest end first; ended ones after the running ones.
    public func sorted(calendar: Calendar, now: Date) -> [Warranty] {
        items.sorted { a, b in
            let (endA, endB) = (a.ends(calendar: calendar), b.ends(calendar: calendar))
            let (doneA, doneB) = (endA < now, endB < now)
            if doneA != doneB { return !doneA }
            return doneA ? endA > endB : endA < endB
        }
    }

    /// Only for notes that still exist: a deleted note's warranty goes with it.
    public mutating func keep(only noteIDs: Set<UUID>) { items.removeAll { !noteIDs.contains($0.id) } }
}
