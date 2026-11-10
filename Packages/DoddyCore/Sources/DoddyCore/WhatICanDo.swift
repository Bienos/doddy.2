import Foundation

/// The features "What I can do" lists (Home › ••• › What I can do), in words a person would use, each with an
/// honest status worked out from the build (decision 2026-11-09-what-i-can-do). The words follow
/// `docs/design/BRAND_GUIDELINES.md` §3 (product voice: calm, literal, short) and are listed with their status
/// rules in `docs/design/WHAT_I_CAN_DO_COPY.md`.
public enum DoddyAbility: String, CaseIterable, Sendable {
    case talk
    case notes
    case lists
    case reminders
    case messages
    case phoneCalls
    case callsForYou
    case tasks
    case leaflets
    case translator

    /// The release-scope feature that gates this row: hidden in the build, the row isn't listed at all.
    public var feature: Feature? {
        switch self {
        case .messages: .messages
        case .phoneCalls: .phoneCalls
        case .callsForYou: .callCases
        case .tasks: .errands
        case .leaflets: .deals
        case .translator: .translator
        case .talk, .notes, .lists, .reminders: nil
        }
    }

    /// The catalog entry that says whether the code is in this build at all.
    public var capability: Capability? {
        switch self {
        case .talk: .voiceInput
        case .notes, .lists: .memoryStorage
        case .reminders: .reminders
        case .messages: .textAssistant
        case .phoneCalls: .phoneCalls
        case .callsForYou, .tasks, .leaflets, .translator: nil
        }
    }

    /// Works only through Doddy's messaging server.
    public var needsServer: Bool {
        switch self {
        case .messages, .phoneCalls, .callsForYou, .tasks, .leaflets: true
        case .talk, .notes, .lists, .reminders, .translator: false
        }
    }
}

public enum AbilityStatus: Equatable, Sendable {
    /// Built, tested, and used on a phone.
    case ready
    /// Built and tested in code; still being tried on real phones.
    case inTesting
    /// Built, but this build has no address for Doddy's server.
    case needsServer
    /// Built, but no real call has been placed or answered yet (S2_CALLS_STATUS, CALL_CASES_STATUS).
    case notTriedOnARealCall
    /// The catalog says the code isn't in this build.
    case notInThisVersion
}

public struct AbilityRow: Equatable, Sendable, Identifiable {
    public let ability: DoddyAbility
    public let status: AbilityStatus
    public let title: String
    public let does: String
    public let youControl: String
    public let statusText: String
    public var id: DoddyAbility { ability }
}

public enum WhatICanDo {
    /// No phone call, either way, has been recorded as working (9 Nov 2026). Change this only together with a
    /// recorded real call in `docs/implementation/S2_CALLS_STATUS.md` or `CALL_CASES_STATUS.md`.
    public static let realCallRecorded = false

    /// The rows for this build, in the order shown. A feature the release scope hides isn't listed.
    public static func rows(
        catalog: CapabilityCatalog, scope: ReleaseScope, serverConfigured: Bool,
        language: NotificationLanguage = .english
    ) -> [AbilityRow] {
        DoddyAbility.allCases.compactMap { ability in
            if let feature = ability.feature, !scope.shows(feature) { return nil }
            let status = status(of: ability, catalog: catalog, serverConfigured: serverConfigured)
            let words = text(ability, language)
            return AbilityRow(
                ability: ability, status: status, title: words.title, does: words.does,
                youControl: words.youControl, statusText: statusText(status, language))
        }
    }

    public static func status(of ability: DoddyAbility, catalog: CapabilityCatalog, serverConfigured: Bool) -> AbilityStatus {
        if let capability = ability.capability, case .notImplemented = catalog.status(of: capability) {
            return .notInThisVersion
        }
        if ability.needsServer, !serverConfigured { return .needsServer }
        switch ability {
        case .phoneCalls, .callsForYou:
            return realCallRecorded ? .inTesting : .notTriedOnARealCall
        case .notes:
            return .ready
        case .talk, .lists, .reminders, .messages, .tasks, .leaflets, .translator:
            return .inTesting
        }
    }

    public static func statusText(_ status: AbilityStatus, _ language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch status {
        case .ready: return polish ? "Gotowe" : "Ready"
        case .inTesting: return polish ? "W testach" : "In testing"
        case .needsServer:
            return polish
                ? "Wymaga konfiguracji · ta wersja nie ma połączenia z serwerem Doddy’ego"
                : "Needs setup · this build isn’t connected to Doddy’s server"
        case .notTriedOnARealCall: return polish ? "Jeszcze niesprawdzone na prawdziwej rozmowie" : "Not tried on a real call yet"
        case .notInThisVersion: return polish ? "Nie w tej wersji" : "Not in this version"
        }
    }

    public struct Words: Equatable, Sendable {
        public let title: String
        public let does: String
        public let youControl: String
    }

    // Product voice (BRAND_GUIDELINES §3): sentence case, short sentences, curly apostrophes, no exclamation marks,
    // no em dashes; second person for the reader, "Doddy" in the third person. Polish is written for Polish
    // readers (§3.8), with the app's capitalised Ty forms and no gendered past-tense verbs for Doddy.
    public static func text(_ ability: DoddyAbility, _ language: NotificationLanguage) -> Words {
        switch (ability, language) {
        case (.talk, .english):
            Words(title: "Talk to Doddy",
                  does: "Ask out loud and get a short answer. Doddy can look things up in your notes while you talk.",
                  youControl: "Your voice is sent only while a conversation is on. What leaves this iPhone shows where.")
        case (.talk, .polish):
            Words(title: "Porozmawiaj z Doddym",
                  does: "Pytasz na głos i dostajesz krótką odpowiedź. W trakcie rozmowy Doddy może zajrzeć do Twoich notatek.",
                  youControl: "Głos jest wysyłany tylko w trakcie rozmowy. Dokąd, pokazuje ekran „Co opuszcza tego iPhone’a”.")

        case (.notes, .english):
            Words(title: "Notes",
                  does: "Save something in your own words and find it again later.",
                  youControl: "Only what you save is kept. It stays on this iPhone unless you choose otherwise in Settings.")
        case (.notes, .polish):
            Words(title: "Notatki",
                  does: "Zapisz coś własnymi słowami i znajdź to później.",
                  youControl: "Zostaje tylko to, co zapiszesz. Zostaje na tym iPhonie, chyba że w Ustawieniach wybierzesz inaczej.")

        case (.lists, .english):
            Words(title: "Lists",
                  does: "Shopping and to-do lists, by voice or by typing.",
                  youControl: "You decide what goes on them.")
        case (.lists, .polish):
            Words(title: "Listy",
                  does: "Listy zakupów i rzeczy do zrobienia, głosem albo pisząc.",
                  youControl: "Ty decydujesz, co na nie trafia.")

        case (.reminders, .english):
            Words(title: "Reminders and calendar",
                  does: "Ask in a conversation and Doddy prepares a reminder or a calendar event.",
                  youControl: "Nothing is added until you confirm it on screen.")
        case (.reminders, .polish):
            Words(title: "Przypomnienia i kalendarz",
                  does: "Poproś w rozmowie, a Doddy przygotuje przypomnienie albo wydarzenie w kalendarzu.",
                  youControl: "Nic nie zostanie dodane, dopóki nie potwierdzisz tego na ekranie.")

        case (.messages, .english):
            Words(title: "Messages",
                  does: "Type a question instead of talking. You can add a photo or a file.",
                  youControl: "Off until you agree to it. Answers come from Claude, through Doddy’s server.")
        case (.messages, .polish):
            Words(title: "Wiadomości",
                  does: "Napisz pytanie zamiast mówić. Możesz dołączyć zdjęcie albo plik.",
                  youControl: "Wyłączone, dopóki się nie zgodzisz. Odpowiada Claude, przez serwer Doddy’ego.")

        case (.phoneCalls, .english):
            Words(title: "Phone calls",
                  does: "Call Doddy’s number and talk, or let Doddy call you.",
                  youControl: "Only your verified number gets through, and only after your PIN. Your notes are used only if you allow it.")
        case (.phoneCalls, .polish):
            Words(title: "Rozmowy telefoniczne",
                  does: "Zadzwoń na numer Doddy’ego albo pozwól Doddy’emu zadzwonić do Ciebie.",
                  youControl: "Połączy się tylko Twój zweryfikowany numer i dopiero po PIN-ie. Notatki są używane tylko, jeśli na to pozwolisz.")

        case (.callsForYou, .english):
            Words(title: "Calls for you",
                  does: "Doddy rings a business with one question for you, like whether your laptop is ready.",
                  youControl: "Nothing is dialled until you approve the call card. Doddy says it’s an AI.")
        case (.callsForYou, .polish):
            Words(title: "Połączenia za Ciebie",
                  does: "Doddy dzwoni do firmy z jednym pytaniem od Ciebie, na przykład czy laptop jest już gotowy.",
                  youControl: "Doddy nie dzwoni, dopóki nie zatwierdzisz karty połączenia. Od razu mówi, że jest AI.")

        case (.tasks, .english):
            Words(title: "Tasks",
                  does: "Hand Doddy a bigger job, like comparing flights. Doddy works on it in the background.",
                  youControl: "Nothing is booked, bought or sent.")
        case (.tasks, .polish):
            Words(title: "Sprawy",
                  does: "Zleć Doddy’emu większą sprawę, na przykład porównanie lotów. Doddy zajmuje się nią w tle.",
                  youControl: "Nic nie zostanie zarezerwowane, kupione ani wysłane.")

        case (.leaflets, .english):
            Words(title: "Cheapest this week",
                  does: "Doddy reads this week’s shop leaflets and finds the cheapest offers.",
                  youControl: "Doddy buys nothing.")
        case (.leaflets, .polish):
            Words(title: "Najtaniej w tym tygodniu",
                  does: "Doddy przegląda gazetki sklepów z tego tygodnia i szuka najtańszych ofert.",
                  youControl: "Doddy niczego nie kupuje.")

        case (.translator, .english):
            Words(title: "Translate",
                  does: "Doddy translates between you and someone who speaks another language.",
                  youControl: "You start it and you stop it.")
        case (.translator, .polish):
            Words(title: "Tłumacz",
                  does: "Doddy tłumaczy rozmowę między Tobą a kimś, kto mówi w innym języku.",
                  youControl: "Ty decydujesz, kiedy zaczyna i kiedy kończy.")
        }
    }
}

extension WhatICanDo {
    /// "Say, for example": one thing a person could ask, shown on the feature's scene in What I can do
    /// (owner, 9 Nov 2026: show the features more vividly). An example of asking, never the person's data
    /// and never a claim that it was done. Messages is typed, so its example is something to type.
    public static func example(_ ability: DoddyAbility, _ language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch ability {
        case .talk: return polish ? "Ile to 15% z 240 zł?" : "What’s 15% of 240?"
        case .notes: return polish ? "Zapisz: rower stoi na poziomie −2." : "Note: the bike is on level −2."
        case .lists: return polish ? "Dopisz mleko i chleb do zakupów." : "Add milk and bread to the shopping list."
        case .reminders: return polish ? "Przypomnij mi jutro o 8, żeby zadzwonić do mamy." : "Remind me at 8 tomorrow to call Mum."
        case .messages: return polish ? "Co jest na tym zdjęciu?" : "What’s in this photo?"
        case .phoneCalls: return polish ? "Zadzwoń do mnie za godzinę." : "Call me in an hour."
        case .callsForYou: return polish ? "Zadzwoń do serwisu i zapytaj, czy laptop jest gotowy." : "Ring the repair shop and ask if my laptop is ready."
        case .tasks: return polish ? "Porównaj loty do Lizbony w maju." : "Compare flights to Lisbon in May."
        case .leaflets: return polish ? "Gdzie w tym tygodniu jest najtańsze masło?" : "Where’s butter cheapest this week?"
        case .translator: return polish ? "Tłumacz, rozmawiam z kimś po hiszpańsku." : "Translate, I’m talking to someone in Spanish."
        }
    }

    /// "Say" or "Type", over the example.
    public static func exampleLead(_ ability: DoddyAbility, _ language: NotificationLanguage) -> String {
        let typed = ability == .messages
        switch language {
        case .polish: return typed ? "Napisz na przykład" : "Powiedz na przykład"
        case .english: return typed ? "Type, for example" : "Say, for example"
        }
    }
}
