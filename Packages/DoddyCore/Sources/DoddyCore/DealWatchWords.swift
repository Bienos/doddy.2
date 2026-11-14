import Foundation

// What the price-alerts screen says (owner, 13 Nov 2026: "daj znać, gdy masło będzie poniżej 5 zł"; decision
// 2026-11-14-price-alerts-screen). Polish and English side by side, as `WatchWords` does for watched prices, so the
// wording is one tested place and the screens only show it. Rules the words keep:
//  - nothing is said to be saved, found or deleted unless the server's answer said so;
//  - what already matched when an alert was made is shown as "now in the leaflets" and said to be known: the server
//    never pushes it, only what turns up later;
//  - a chain read only in part is said, because a cheaper offer may be on a page nobody has read;
//  - the app says nothing about a price it didn't get from the server, and nothing about buying: an alert only tells.

public enum DealWatchWords {
    // MARK: The screen

    public static func title(_ l: NotificationLanguage) -> String { text(l, "Alerty cenowe", "Price alerts") }

    /// The Shopping row that opens the screen.
    public static func rowSubtitle(_ l: NotificationLanguage) -> String {
        text(l, "Daj znać, gdy w gazetce będzie to, czego szukam", "Tell me when the leaflets have what I'm after")
    }

    public static func intro(_ l: NotificationLanguage) -> String {
        text(l,
             "Powiedz, czego szukasz i, jeśli chcesz, do jakiej ceny. Raz dziennie, po odczytaniu gazetek, serwer Doddy’ego sprawdza je pod tym kątem i wysyła powiadomienie, gdy pojawi się coś nowego. Tylko daję znać; niczego nie kupuję. Serwer trzyma Twoje słowa, dopóki alert się nie skończy albo go nie usuniesz. Data końca jest na każdym alercie.",
             "Tell me what to look for and, if you like, up to what price. Once a day, after Doddy's server has read the shops' leaflets, it checks them for exactly that and sends a notification when something new turns up. I only tell you; I don't buy anything. The server keeps your words until the alert ends or you delete it. Each alert shows its end date.")
    }

    public static func empty(_ l: NotificationLanguage) -> String { text(l, "Nie masz jeszcze żadnych alertów.", "You have no alerts yet.") }
    public static func loading(_ l: NotificationLanguage) -> String { text(l, "Sprawdzam, co masz na serwerze…", "Checking what you have on the server…") }
    public static func add(_ l: NotificationLanguage) -> String { text(l, "Dodaj alert", "Add an alert") }
    public static func done(_ l: NotificationLanguage) -> String { text(l, "Gotowe", "Done") }
    public static func cancel(_ l: NotificationLanguage) -> String { text(l, "Anuluj", "Cancel") }
    public static func delete(_ l: NotificationLanguage) -> String { text(l, "Usuń", "Delete") }
    public static func deleteAsk(_ l: NotificationLanguage) -> String {
        text(l, "Usunąć ten alert wraz z tym, co znalazł?", "Delete this alert and what it found?")
    }
    public static func tryAgain(_ l: NotificationLanguage) -> String { text(l, "Spróbuj jeszcze raz", "Try again") }

    // MARK: The form

    public static func itemLabel(_ l: NotificationLanguage) -> String { text(l, "Czego szukać?", "What should I look for?") }
    public static func itemPlaceholder(_ l: NotificationLanguage) -> String { text(l, "np. masło", "e.g. butter") }
    public static func itemHint(_ l: NotificationLanguage) -> String {
        text(l, "Najwyżej \(DealWatchRequest.maxItemLength) znaków. Szukam tego samego, nie podobnych rzeczy.",
             "At most \(DealWatchRequest.maxItemLength) characters. I look for that, not for similar things.")
    }
    public static func priceLabel(_ l: NotificationLanguage) -> String {
        text(l, "Do jakiej ceny? (nieobowiązkowe)", "Up to what price? (optional)")
    }
    public static func pricePlaceholder(_ l: NotificationLanguage) -> String { text(l, "np. 5,00", "e.g. 5.00") }
    public static func priceProblem(_ l: NotificationLanguage) -> String {
        text(l, "To nie wygląda na cenę. Wpisz np. 5,00 albo zostaw puste.", "That doesn't look like a price. Type e.g. 5.00 or leave it empty.")
    }
    public static func shopsLabel(_ l: NotificationLanguage) -> String { text(l, "Sklepy", "Shops") }
    public static func allShops(_ l: NotificationLanguage) -> String { text(l, "Wszystkie sklepy z gazetkami", "All shops with leaflets") }
    public static func pickShops(_ l: NotificationLanguage) -> String { text(l, "Wybierz sklepy", "Pick shops") }
    public static func save(_ l: NotificationLanguage) -> String { text(l, "Zapisz alert", "Save the alert") }
    public static func saving(_ l: NotificationLanguage) -> String { text(l, "Zapisuję…", "Saving…") }

    // MARK: One alert

    /// "Do 5,00 zł" / "Każda cena".
    public static func priceLine(_ watch: DealWatch, _ l: NotificationLanguage) -> String {
        guard let price = watch.maxPrice else { return text(l, "Każda cena", "Any price") }
        return text(l, "Do \(price.text(l))", "Up to \(price.text(l))")
    }

    /// Every catalogued shop (or none named) reads as one phrase; otherwise the shops by name.
    public static func shopsLine(_ watch: DealWatch, _ l: NotificationLanguage) -> String {
        guard let chains = watch.chains, !chains.isEmpty, Set(chains) != Set(DealWatchRequest.catalogued) else { return allShops(l) }
        return chains.map(\.name).joined(separator: ", ")
    }

    /// When the alert ends; nil when the server's date can't be read (nothing is guessed).
    public static func endsLine(_ watch: DealWatch, now: Date, _ l: NotificationLanguage) -> String? {
        guard let ends = watch.endsDate else { return nil }
        let days = Int((ends.timeIntervalSince(now) / 86_400).rounded(.up))
        if days <= 1 { return text(l, "Kończy się w ciągu doby", "Ends within a day") }
        return text(l, "Kończy się za \(days) dni", "Ends in \(days) days")
    }

    /// New offers since the alert was made (those there when it was made are not counted).
    public static func foundLine(_ watch: DealWatch, _ l: NotificationLanguage) -> String {
        let n = watch.found
        if n == 0 { return text(l, "Nic nowego jeszcze nie znalazłem", "Nothing new found yet") }
        switch l {
        case .polish:
            if n == 1 { return "1 nowa oferta" }
            return "\(n) " + (isFew(n) ? "nowe oferty" : "nowych ofert")
        case .english:
            return n == 1 ? "1 new offer" : "\(n) new offers"
        }
    }

    public static func checkedLabel(_ l: NotificationLanguage) -> String { text(l, "Ostatnie sprawdzenie", "Last checked") }
    public static func neverChecked(_ l: NotificationLanguage) -> String {
        text(l, "Jeszcze nie sprawdzone: czekam na kolejny odczyt gazetek", "Not checked yet: waiting for the next leaflet read")
    }

    // MARK: What it found

    public static func matchesTitle(_ l: NotificationLanguage) -> String { text(l, "Teraz w gazetkach", "In the leaflets now") }
    public static func noMatchesNow(_ l: NotificationLanguage) -> String {
        text(l, "Teraz w gazetkach tego nie ma.", "It isn't in the leaflets right now.")
    }
    public static func readInPart(_ l: NotificationLanguage) -> String {
        text(l, "Niektóre gazetki odczytałem tylko w części: tańsza oferta może być na stronie, której nie czytałem.",
             "I read some leaflets only in part: a cheaper offer may be on a page I haven't read.")
    }

    /// What the form says after the server confirmed the alert (a 201 whose body was read). The offers it lists were
    /// already there, so they are never pushed.
    public static func saved(offers: Int, _ l: NotificationLanguage) -> String {
        if offers == 0 {
            return text(l, "Zapisane. Teraz w gazetkach tego nie ma; dam Ci znać, gdy się pojawi.",
                        "Saved. It isn't in the leaflets now; I'll tell you when it turns up.")
        }
        return text(l, "Zapisane. Teraz w gazetkach: \(offersCount(offers, l)). O tych już wiesz; dam Ci znać o kolejnych.",
                    "Saved. In the leaflets now: \(offersCount(offers, l)). You know about these; I'll tell you about new ones.")
    }

    /// "1 oferta", "3 oferty", "5 ofert" / "1 offer", "3 offers".
    public static func offersCount(_ n: Int, _ l: NotificationLanguage) -> String {
        switch l {
        case .polish: return n == 1 ? "1 oferta" : "\(n) " + (isFew(n) ? "oferty" : "ofert")
        case .english: return n == 1 ? "1 offer" : "\(n) offers"
        }
    }

    // MARK: When it didn't work

    /// One honest sentence per refusal. Nothing says "saved" or "deleted" unless the server said so.
    public static func refusal(_ error: DealWatchesError, _ l: NotificationLanguage) -> String {
        switch error {
        case .disabled:
            return text(l, "Alerty cenowe nie są jeszcze włączone na serwerze Doddy’ego. Nic nie zostało zapisane.",
                        "Price alerts aren't switched on yet on Doddy's server. Nothing was saved.")
        case .tooManyWatches:
            return text(l, "Masz już najwięcej alertów, jakie można mieć. Usuń jeden i spróbuj jeszcze raz. Nic nie zostało zapisane.",
                        "You have as many alerts as you can have. Delete one and try again. Nothing was saved.")
        case .serverFull:
            return text(l, "Serwer ma teraz komplet alertów. Spróbuj za jakiś czas. Nic nie zostało zapisane.",
                        "The server is full of alerts right now. Try again later. Nothing was saved.")
        case .invalid:
            return text(l, "Serwer nie przyjął tego alertu. Sprawdź słowa i cenę. Nic nie zostało zapisane.",
                        "The server didn't accept that alert. Check the words and the price. Nothing was saved.")
        case .notFound:
            return text(l, "Tego alertu już nie ma.", "That alert is gone.")
        case .outcomeUnknown:
            return text(l, "Nie mogę potwierdzić, że alert zapisał się na serwerze; może istnieć. Sprawdź listę, zanim dodasz go drugi raz. Nie dodam go sam jeszcze raz.",
                        "I couldn't confirm that the alert was saved on the server; it may exist. Check the list before you add it again. I won't add it again by myself.")
        case .server(.offline):
            return text(l, "Brak połączenia z serwerem Doddy’ego. Nic nie zostało zmienione.",
                        "I can't reach Doddy's server. Nothing was changed.")
        case .server:
            return text(l, "Serwer Doddy’ego nie odpowiedział tak, jak trzeba. Nic nie zostało zmienione; możesz spróbować jeszcze raz.",
                        "Doddy's server didn't answer as it should. Nothing was changed; you can try again.")
        }
    }

    /// Connections are paused in Settings, so nothing is sent.
    public static func paused(_ l: NotificationLanguage) -> String {
        text(l, "Połączenia są wstrzymane w Ustawieniach, więc nic nie wysyłam do serwera Doddy’ego.",
             "Connections are paused in Settings, so nothing is sent to Doddy's server.")
    }

    /// No Doddy messaging server in this build.
    public static func noServer(_ l: NotificationLanguage) -> String {
        text(l, "Serwer Doddy’ego nie jest skonfigurowany w tej wersji, więc alerty cenowe nie działają.",
             "Doddy's server isn't set up in this build, so price alerts don't work.")
    }

    // MARK: Plumbing

    private static func text(_ l: NotificationLanguage, _ polish: String, _ english: String) -> String {
        l == .polish ? polish : english
    }

    /// Polish "few" (2 to 4, but not 12 to 14): "2 oferty", while 5 to 21 and 12 to 14 take "ofert".
    private static func isFew(_ n: Int) -> Bool {
        let tail = n % 100
        return (2...4).contains(n % 10) && !(12...14).contains(tail)
    }
}
