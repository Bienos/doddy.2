import Foundation

// The action status model (ADR-319 to ADR-322) and voice session recovery (ADR-360) in the
// iPhone's language, as "What Doddy did" is (ADR-275): kept in English, translated when shown.
// The user's own words, list names and what an app or server said stay exactly as kept.

extension ActionStatus {
    public func text(_ language: NotificationLanguage) -> String {
        guard language == .polish else { return text }
        switch self {
        case .proposed: return "Czeka na Ciebie"
        case .pending: return "W toku"
        case .confirmed: return "Potwierdzone"
        case .failed: return "Nie zrobiono"
        case .unknown: return "Nie wiadomo, czy się udało"
        case .declined: return "Odrzucone"
        case .handedOff: return "Otwarto inną aplikację"
        }
    }
}

extension ActivityReceipt {
    /// "Read back from Calendar at 10:02". `time` is the read time as the phone shows times.
    public func heading(_ language: NotificationLanguage, time: String) -> String {
        language == .polish ? "Odczytane z: \(app.title(.polish)), \(time)" : "Read back from \(app.title) at \(time)"
    }

    /// The lines as kept, with Doddy's own labels translated. Titles, list names, items and dates
    /// stay as they were read back.
    public func lines(_ language: NotificationLanguage) -> [String] {
        guard language == .polish else { return lines }
        return lines.map(ActionStatusText.polishLine)
    }
}

extension ActivityEntry {
    /// "In progress 10:02 → Not sure it happened 10:02 → Confirmed 10:05", without "proposed".
    public func historyText(_ language: NotificationLanguage, time: (Date) -> String) -> String {
        history.filter { $0.status != .proposed }
            .map { "\($0.status.text(language)) \(time($0.at))" }
            .joined(separator: " → ")
    }
}

extension PlanBlock {
    /// The line a blocked step shows on the plan card, in the iPhone's language.
    public func screenText(_ language: NotificationLanguage) -> String {
        guard language == .polish else { return screenText }
        switch self {
        case .paused: return "Pominięto: połączenia są wstrzymane"
        case .notConnected(let connection): return "Brak połączenia: \(ActivityText.polish(connection))"
        case .onlineAccount(let screen, _): return screen
        case .tooManyTries(let app, let count):
            return "Próbowano \(count) \(ActionStatusText.polishTimes(count)) w ciągu doby bez potwierdzenia. Najpierw sprawdź: \(app.title(.polish))."
        }
    }
}

extension SessionRecovery {
    /// `status(_:connected:)` in the iPhone's language. A reason a service gave stays as it was.
    public static func status(_ end: VoiceSessionEnd, connected: Bool, language: NotificationLanguage) -> (title: String, detail: String?) {
        let english = status(end, connected: connected)
        guard language == .polish else { return english }
        switch end {
        case .userEnded, .doddyEnded:
            return ("Rozmowa zakończona", nil)
        case .stoppedListening:
            return ("Przestano słuchać", "Mikrofon Doddy’ego jest wyłączony.")
        case .dropped(.offline):
            return ("Jesteś offline", "Głos Doddy’ego potrzebuje internetu.")
        case .dropped(let drop) where !connected:
            if case .error(let message) = drop, !message.isEmpty { return ("Nie udało się połączyć", message) }
            return ("Nie udało się połączyć", "Sprawdź połączenie z internetem i spróbuj ponownie.")
        case .dropped:
            return ("Rozmowa została przerwana",
                    "Przerwała się przed zakończeniem, więc Doddy nie słyszał niczego dalej. Nic nie zostało przez to zapisane.")
        }
    }
}

enum ActionStatusText {
    /// Labels Doddy puts at the start of a receipt line, and the summaries Doddy's server writes.
    static let polishPrefixes: [(String, String)] = [
        ("List: ", "Lista: "),
        ("Added: ", "Dodano: "),
        ("Already on the list: ", "Już na liście: "),
        ("Too long: ", "Za długie: "),
        ("No room: ", "Brak miejsca: "),
        ("Ticked: ", "Odhaczono: "),
        ("Removed: ", "Usunięto: "),
        ("Rings at ", "Dzwoni o "),
        ("Alarm ", "Budzik "),
        ("Repeats ", "Powtarza się: "),
        // Leave reminders (LeaveByActions).
        ("Leave at ", "Wyjście o "),
        ("Place: ", "Miejsce: "),
        ("Arrive by ", "Na miejscu do "),
    ]

    static let polishSummaries: [String: String] = [
        "Gmail draft created (not sent).": "Utworzono szkic w Gmailu (niewysłany).",
        "Todoist task added.": "Dodano zadanie w Todoist.",
        "Todoist task completed.": "Zadanie w Todoist ukończone.",
        "Todoist task due date changed.": "Zmieniono termin zadania w Todoist.",
    ]

    static func polishLine(_ line: String) -> String {
        let firstTry = " Answer from the first try; nothing ran again."
        if line.hasSuffix(firstTry), let summary = polishSummaries[String(line.dropLast(firstTry.count))] {
            return summary + " Odpowiedź z pierwszej próby; nic nie uruchomiono ponownie."
        }
        if let summary = polishSummaries[line] { return summary }
        for (english, polish) in polishPrefixes where line.hasPrefix(english) {
            return polish + line.dropFirst(english.count)
        }
        return line
    }

    /// Notes with a list name or a count in them (ADR-319, ADR-321).
    static func polishNote(_ english: String) -> String? {
        if let list = between(english, "Found in the list “", "” when Doddy checked.") {
            return "Znalezione na liście „\(list)” przy sprawdzaniu."
        }
        if let list = between(english, "Not in the list “", "” when Doddy checked, so it didn't happen. You can ask again.") {
            return "Nie było na liście „\(list)” przy sprawdzaniu, więc to się nie stało. Możesz poprosić ponownie."
        }
        // The 3-try stop (VoiceToolReply.retryStopped, shown as the row's note).
        let stop = /^Doddy has tried this (\d+) times in the last day without a confirmed result, so it did not try again\. Ask the user to look in (.+) themselves; it may already be there\.$/
        if let match = english.firstMatch(of: stop), let count = Int(match.1),
           let app = ActivityApp.allCases.first(where: { $0.title == String(match.2) }) {
            return "Doddy próbował tego \(count) \(polishTimes(count)) w ciągu doby bez potwierdzenia, więc nie spróbował ponownie. Sprawdź w aplikacji \(app.title(.polish)); może już tam jest."
        }
        return nil
    }

    /// 1 raz, 2+ razy.
    static func polishTimes(_ count: Int) -> String { count == 1 ? "raz" : "razy" }

    private static func between(_ text: String, _ prefix: String, _ suffix: String) -> String? {
        guard text.hasPrefix(prefix), text.hasSuffix(suffix), text.count > prefix.count + suffix.count else { return nil }
        return String(text.dropFirst(prefix.count).dropLast(suffix.count))
    }
}
