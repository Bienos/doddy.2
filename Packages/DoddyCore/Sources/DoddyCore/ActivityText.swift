import Foundation

// "What Doddy did" in the iPhone's language (ADR-271). Rows are kept as Doddy wrote them, in
// English (the activity file and old rows don't change); they are translated when shown. App names
// and results come from fixed lists. Titles and Doddy's own fixed notes are looked up; anything
// else — the user's own words in the detail, a reason an app or server gave — is shown exactly as
// kept, so nothing is ever reworded into something it didn't say.

extension ActivityApp {
    public func title(_ language: NotificationLanguage) -> String {
        guard language == .polish else { return title }
        switch self {
        case .memories: return "Notatki"
        case .calendar: return "Kalendarz"
        case .reminders: return "Przypomnienia"
        case .contacts: return "Kontakty"
        case .timers: return "Minutniki"
        case .maps: return "Mapy"
        case .shortcuts: return "Skróty"
        case .messages: return "Wiadomości i e-mail"
        case .gmail, .drive, .notion, .todoist: return title
        case .web: return "Wyszukiwanie w sieci"
        }
    }

    /// "w Kalendarzu", "w Przypomnieniach": where Undo checked.
    fileprivate var polishLocative: String {
        switch self {
        case .calendar: "w Kalendarzu"
        case .reminders: "w Przypomnieniach"
        default: "w aplikacji \(title(.polish))"
        }
    }

    /// "Kalendarz", "Przypomnienia": what to check.
    fileprivate var polishAccusative: String { title(.polish) }
}

extension ActivityOutcome {
    public func text(_ language: NotificationLanguage) -> String {
        guard language == .polish else { return text }
        switch self {
        case .lookedUp: return "Sprawdzono"
        case .done: return "Zrobione"
        case .alreadyThere: return "Już było, nic nie dodano"
        case .opened: return "Otwarto"
        case .notSure: return "Nie wiadomo, czy się udało"
        case .notDone: return "Nie zrobiono"
        case .declined: return "Odrzucone"
        case .inProgress: return "W toku"
        }
    }
}

public enum ActivityText {
    /// Every title `ActivityRequest.describe` writes, in Polish.
    static let polishTitles: [String: String] = [
        "Searched your notes": "Przeszukano notatki",
        "Save a note": "Zapisz notatkę",
        "Read your calendar": "Odczytano kalendarz",
        "Add event": "Dodaj wydarzenie",
        "Add reminder": "Dodaj przypomnienie",
        "Remind about a note": "Przypomnij o notatce",
        "Looked for a contact": "Szukano kontaktu",
        "Read birthdays": "Odczytano urodziny",
        "Start timer": "Uruchom minutnik",
        "Open in Maps": "Otwórz w Mapach",
        "Run shortcut": "Uruchom skrót",
        "Draft a text": "Szkic SMS-a",
        "Draft an email": "Szkic e-maila",
        // Written before ADR-271 fixed the article; old rows still say it.
        "Draft a email": "Szkic e-maila",
        "Checked email": "Sprawdzono pocztę",
        "Create an email draft": "Utwórz szkic e-maila",
        "Looked for a file": "Szukano pliku",
        "Searched Notion": "Przeszukano Notion",
        "Read your tasks": "Odczytano zadania",
        "Add a task": "Dodaj zadanie",
        "Searched the web": "Wyszukano w sieci",
        "Add to a list": "Dodaj do listy",
        "Read a list": "Odczytano listę",
        "Tick on a list": "Odhacz na liście",
        "Remove from a list": "Usuń z listy",
        "Start a list": "Załóż listę",
        "Change event": "Zmień wydarzenie",
        "Change reminder": "Zmień przypomnienie",
        // From the default line (ADR-259, ADR-260), joined in the ADR-264 merge.
        "Delete event": "Usuń wydarzenie",
        "Delete reminder": "Usuń przypomnienie",
        "Set alarm": "Ustaw budzik",
    ]

    /// Doddy's own fixed notes, in Polish. Built from the same text the app writes, so they match.
    static let polishNotes: [String: String] = {
        var notes: [String: String] = [
            "Connections were paused.": "Połączenia były wstrzymane.",
            "Doddy couldn't confirm it went through.": "Doddy nie mógł potwierdzić, że się udało.",
            "Demo data from a test server, not your account.": "Dane demonstracyjne z serwera testowego, nie z Twojego konta.",
            ActivityLog.interruptedNote: "Doddy zamknął się, zanim to się skończyło. Sprawdź, zanim poprosisz ponownie, żeby nie zrobić tego dwa razy.",
            "Found in Reminders when you checked.": "Znalezione w Przypomnieniach przy sprawdzaniu.",
            "Not in Reminders when you checked. You can ask Doddy again.": "Nie było w Przypomnieniach przy sprawdzaniu. Możesz poprosić Doddy’ego ponownie.",
            "The conversation ended before you answered.": "Rozmowa skończyła się przed Twoją odpowiedzią.",
        ]
        for connection in VoiceConnection.allCases {
            notes["\(connection.title) isn't connected."] = "Brak połączenia: \(Self.polish(connection))."
        }
        for app in [ActivityApp.calendar, .reminders] {
            notes["You undid this. Checked in \(app.title)."] = "Cofnięto. Sprawdzone \(app.polishLocative)."
            notes["Not undone: it changed in \(app.title) since Doddy did this, so Doddy left it alone."] =
                "Nie cofnięto: zmieniło się \(app.polishLocative) po zmianie Doddy’ego, więc Doddy tego nie ruszył."
            notes["Doddy couldn't confirm the undo. Check \(app.title) before trying again."] =
                "Doddy nie mógł potwierdzić cofnięcia. Sprawdź \(app.polishAccusative), zanim spróbujesz ponownie."
        }
        return notes
    }()

    /// Why Undo didn't run (`ActivityUndo.blocked` and `DeviceConnections.undo`), in Polish.
    static let polishUndoReasons: [String: String] = {
        var reasons: [String: String] = [
            "Connections are paused in Settings.": "Połączenia są wstrzymane w Ustawieniach.",
            "Doddy couldn't read Reminders.": "Doddy nie mógł odczytać Przypomnień.",
        ]
        for connection in [VoiceConnection.calendar, .reminders] {
            reasons["\(connection.title) is off in Settings, Connections."] = "\(Self.polish(connection)): wyłączone w Ustawieniach, Połączenia."
            reasons["\(connection.title) isn't connected."] = "Brak połączenia: \(Self.polish(connection))."
        }
        return reasons
    }()

    private static func polish(_ connection: VoiceConnection) -> String {
        switch connection {
        case .calendar: "Kalendarz"
        case .reminders: "Przypomnienia"
        case .contacts: "Kontakty"
        case .timers: "Minutniki"
        case .maps: "Mapy"
        case .shortcuts: "Skróty"
        case .messages: "Wiadomości i e-mail"
        }
    }

    public static func title(_ english: String, _ language: NotificationLanguage) -> String {
        language == .polish ? polishTitles[english] ?? english : english
    }

    /// A note Doddy wrote, in Polish when it is one of Doddy's own. A reason an app or server
    /// gave is kept as it was (inside a translated frame for a failed undo).
    public static func note(_ english: String, _ language: NotificationLanguage) -> String {
        guard language == .polish else { return english }
        if let known = polishNotes[english] { return known }
        let prefix = "Not undone: ", suffix = " Nothing changed."
        if english.hasPrefix(prefix), english.hasSuffix(suffix), english.count > prefix.count + suffix.count {
            let reason = String(english.dropFirst(prefix.count).dropLast(suffix.count))
            return "Nie cofnięto: \(polishUndoReasons[reason] ?? reason) Nic się nie zmieniło."
        }
        return english
    }
}

extension ActivityEntry {
    /// "Kalendarz · Zrobione", "Kalendarz · Cofnięte".
    public func statusText(_ language: NotificationLanguage) -> String {
        guard language == .polish else { return statusText }
        if case .undone? = undoState { return "\(app.title(.polish)) · Cofnięte" }
        return "\(app.title(.polish)) · \(outcome.text(.polish))"
    }

    public func title(_ language: NotificationLanguage) -> String {
        ActivityText.title(title, language)
    }

    public func note(_ language: NotificationLanguage) -> String? {
        note.map { ActivityText.note($0, language) }
    }
}

extension ActivityPlanSummary {
    /// "Plan · 3 kroki", with Polish plural forms.
    public static func title(_ steps: [ActivityEntry], language: NotificationLanguage) -> String {
        guard language == .polish else { return title(steps) }
        let count = steps.compactMap(\.plan?.count).max() ?? steps.count
        let missing = count - steps.count
        return "Plan · \(count) \(polishSteps(count))" + (missing > 0 ? " (niewidoczne: \(missing))" : "")
    }

    /// "zrobione: 2 · niepewne: 1": a label and a count, so no plural forms are needed.
    public static func outcomes(_ steps: [ActivityEntry], language: NotificationLanguage) -> String {
        guard language == .polish else { return outcomes(steps) }
        let order: [(String, Set<ActivityOutcome>)] = [
            ("zrobione", [.done, .alreadyThere]),
            ("niepewne", [.notSure]),
            ("w toku", [.inProgress]),
            ("niezrobione", [.notDone]),
            ("odrzucone", [.declined]),
            ("otwarte", [.opened]),
            ("sprawdzone", [.lookedUp]),
        ]
        return order.compactMap { label, outcomes in
            let count = steps.filter { outcomes.contains($0.outcome) }.count
            return count > 0 ? "\(label): \(count)" : nil
        }.joined(separator: " · ")
    }

    /// 1 krok, 2–4 kroki, 5–21 kroków, 22–24 kroki …
    static func polishSteps(_ count: Int) -> String {
        if count == 1 { return "krok" }
        let ones = count % 10, tens = count % 100
        return (2...4).contains(ones) && !(12...14).contains(tens) ? "kroki" : "kroków"
    }
}
