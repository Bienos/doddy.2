import Foundation

// "What Doddy did" in the iPhone's language (ADR-275). Rows are kept as Doddy wrote them, in
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
        case .gmail, .drive, .notion, .todoist, .outlook: return title
        case .web: return "Wyszukiwanie w sieci"
        case .exchangeRates: return "Kursy walut"
        case .blik: return "Przelewy BLIK"
        case .presentations: return "Prezentacje"
        case .steps: return "Kroki"
        case .photos: return "Zdjęcia"
        case .camera: return "Aparat"
        }
    }
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
        case .shown: return "Pokazano do wysłania"
        }
    }
}

public enum ActivityText {
    /// Every title `ActivityRequest.describe` writes, in Polish.
    static let polishTitles: [String: String] = [
        "Searched your notes": "Przeszukano notatki",
        "Save a note": "Zapisz notatkę",
        "Read your calendar": "Odczytano kalendarz",
        "Looked for free time": "Szukano wolnego czasu",
        "Remind when to leave": "Przypomnij, kiedy wyjść",
        "Add event": "Dodaj wydarzenie",
        "Add reminder": "Dodaj przypomnienie",
        "Remind about a note": "Przypomnij o notatce",
        "Looked for a contact": "Szukano kontaktu",
        "Read birthdays": "Odczytano urodziny",
        "Start timer": "Uruchom minutnik",
        "Open in Maps": "Otwórz w Mapach",
        "Run shortcut": "Uruchom skrót",
        "Draft a text": "Szkic SMS-a",
        "Prepare a BLIK transfer": "Przygotuj przelew BLIK",
        "Make a presentation": "Przygotuj prezentację",
        "Read steps": "Odczytano kroki",
        "Looked through photos": "Przejrzano zdjęcia",
        "Open the camera": "Otwórz aparat",
        "Draft an email": "Szkic e-maila",
        // Written before ADR-275 fixed the article; old rows still say it.
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
        // From the default line (ADR-259, ADR-260), joined in the ADR-268 merge.
        "Delete event": "Usuń wydarzenie",
        "Delete reminder": "Usuń przypomnienie",
        "Set alarm": "Ustaw budzik",
        // Round 3 (ADR-280, ADR-283), joined in the PR #34 merge.
        "Read alarms": "Odczytano budziki",
        "Turn off alarm": "Wyłącz budzik",
        "Delete events": "Usuń wydarzenia",
        "Move reminders": "Przenieś przypomnienia",
        // Round 4 (ADR-300 onwards).
        "Converted currency": "Przeliczono walutę",
        "Save parking spot": "Zapisz miejsce parkowania",
        "Found parking spot": "Odczytano miejsce parkowania",
        "Clear parking spot": "Usuń miejsce parkowania",
        "Read an email": "Przeczytano e-mail",
        "Complete a task": "Ukończ zadanie",
        "Move a task": "Przesuń zadanie",
        "Add ingredients to a list": "Dodaj składniki do listy",
        // Round 5.
        "Create a reply draft": "Utwórz szkic odpowiedzi",
        "Send an email": "Wyślij e-mail",
        "Send a reply": "Wyślij odpowiedź",
        "Forward an email": "Przekaż e-mail",
        "Archive or mark an email": "Zarchiwizuj lub oznacz e-mail",
        "Move an email to Trash": "Przenieś e-mail do kosza",
        "Read the Google Calendar": "Odczytano Kalendarz Google",
        "Add a Google Calendar event": "Dodaj wydarzenie w Kalendarzu Google",
        "Change a Google Calendar event": "Zmień wydarzenie w Kalendarzu Google",
        "Delete a Google Calendar event": "Usuń wydarzenie z Kalendarza Google",
        "Answer a Google Calendar invitation": "Odpowiedz na zaproszenie w Kalendarzu Google",
        "Add an Outlook event": "Dodaj wydarzenie w Outlooku",
        "Change an Outlook event": "Zmień wydarzenie w Outlooku",
        "Delete an Outlook event": "Usuń wydarzenie z Outlooka",
        "Accept an Outlook invitation": "Przyjmij zaproszenie w Outlooku",
        "Decline an Outlook invitation": "Odrzuć zaproszenie w Outlooku",
        "Send an Outlook email": "Wyślij e-mail z Outlooka",
        "Send an Outlook reply": "Wyślij odpowiedź z Outlooka",
        "Forward an Outlook email": "Przekaż e-mail z Outlooka",
        "Archive or bin an Outlook email": "Zarchiwizuj lub usuń e-mail w Outlooku",
        "Mark an Outlook email": "Oznacz e-mail w Outlooku",
        "Rename a task": "Zmień nazwę zadania",
        "Create a Notion page": "Utwórz stronę w Notion",
        "Add to a Notion page": "Dodaj do strony w Notion",
        "Move a Notion page to the trash": "Przenieś stronę Notion do kosza",
        "Create a Google Doc": "Utwórz Dokument Google",
        "Search the news": "Wyszukano wiadomości",
        "Find places": "Wyszukano miejsca",
        // ADR-564
        "Ask Claude": "Zapytano Claude’a",
        "Make a document with Claude": "Zlecono Claude’owi dokument",
        "Read a Notion page": "Odczytano stronę Notion",
    ]

    /// Doddy's own fixed notes, in Polish. Built from the same text the app writes, so they match.
    static let polishNotes: [String: String] = {
        var notes: [String: String] = [
            "Connections were paused.": "Połączenia były wstrzymane.",
            "Doddy couldn't confirm it went through.": "Doddy nie mógł potwierdzić, że się udało.",
            "Demo data from a test server, not your account.": "Dane demonstracyjne z serwera testowego, nie z Twojego konta.",
            "Doddy didn't send any money. You send it in your bank app.": "Doddy nie wysłał żadnych pieniędzy. Wysyłasz je w aplikacji banku.",
            ActivityLog.interruptedNote: "Doddy zamknął się, zanim to się skończyło. Sprawdź, zanim poprosisz ponownie, żeby nie zrobić tego dwa razy.",
            "Found in Reminders when you checked.": "Znalezione w Przypomnieniach przy sprawdzaniu.",
            "Not in Reminders when you checked. You can ask Doddy again.": "Nie było w Przypomnieniach przy sprawdzaniu. Możesz poprosić Doddy’ego ponownie.",
            "The conversation ended before you answered.": "Rozmowa skończyła się przed Twoją odpowiedzią.",
            // Settled from Doddy's own notes and lists (ADR-321).
            "Found in your notes when Doddy checked.": "Znalezione w notatkach przy sprawdzaniu.",
            "Not in your notes when Doddy checked, so it didn't happen. You can ask again.":
                "Nie było w notatkach przy sprawdzaniu, więc to się nie stało. Możesz poprosić ponownie.",
            "Found in your lists when Doddy checked.": "Znalezione na listach przy sprawdzaniu.",
            "Not in your lists when Doddy checked, so it didn't happen. You can ask again.":
                "Nie było na listach przy sprawdzaniu, więc to się nie stało. Możesz poprosić ponownie.",
            ActivityLog.partlyNote: "Zmieniono tylko część z nich.",
        ]
        for connection in VoiceConnection.allCases {
            notes["\(connection.title) isn't connected."] = "Brak połączenia: \(Self.polish(connection))."
        }
        // Where Undo checked (ActivityUndo.placeName): Calendar, Reminders or the list (ADR-276).
        let places = [("Calendar", "w Kalendarzu", "Kalendarz"), ("Reminders", "w Przypomnieniach", "Przypomnienia"), ("the list", "na liście", "listę"), ("your notes", "w notatkach", "notatki")]
        for (place, locative, accusative) in places {
            notes["You undid this. Checked in \(place)."] = "Cofnięto. Sprawdzone \(locative)."
            notes["Not undone: it changed in \(place) since Doddy did this, so Doddy left it alone."] =
                "Nie cofnięto: zmieniło się \(locative) po zmianie Doddy’ego, więc Doddy tego nie ruszył."
            notes["Doddy couldn't confirm the undo. Check \(place) before trying again."] =
                "Doddy nie mógł potwierdzić cofnięcia. Sprawdź \(accusative), zanim spróbujesz ponownie."
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

    static func polish(_ connection: VoiceConnection) -> String {
        switch connection {
        case .calendar: "Kalendarz"
        case .reminders: "Przypomnienia"
        case .contacts: "Kontakty"
        case .timers: "Minutniki"
        case .maps: "Mapy"
        case .shortcuts: "Skróty"
        case .messages: "Wiadomości i e-mail"
        case .blik: "Przelewy BLIK"
        case .presentations: "Prezentacje"
        case .steps: "Kroki"
        case .photos: "Zdjęcia"
        case .camera: "Aparat"
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
        if let settled = ActionStatusText.polishNote(english) { return settled }
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
