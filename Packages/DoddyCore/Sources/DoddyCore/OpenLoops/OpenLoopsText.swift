import Foundation

/// The words of the open-loops page (ADR-728), in Polish and English like `ParcelStatuses` and
/// `NoteReminderCopy`; the other languages show English until the catalogs have them. Plain sentences,
/// no exclamation marks, no promises: a line says what the source says and nothing about how the person
/// is doing. Clock times are not written here; the screen shows `when` with the iPhone's own formatter.
public enum OpenLoopsText {
    /// Working name, still the owner's to confirm (ADR-728).
    public static func screenTitle(_ language: NotificationLanguage) -> String {
        language == .polish ? "Na oku" : "On the radar"
    }

    public static func emptyLine(_ language: NotificationLanguage) -> String {
        language == .polish
            ? "Nic teraz nie czeka. Gdy ustawisz przypomnienie, zlecisz mi zadanie albo poprosisz o pilnowanie ceny, pojawi się tutaj."
            : "Nothing is waiting right now. When you set a reminder, hand me a task or ask me to watch a price, it shows up here."
    }

    public static func sectionTitle(_ section: OpenLoopSection, _ language: NotificationLanguage) -> String {
        switch (section, language) {
        case (.today, .polish): "Dziś"
        case (.today, .english): "Today"
        case (.waiting, .polish): "Czeka"
        case (.waiting, .english): "Waiting"
        case (.watching, .polish): "Pilnuję"
        case (.watching, .english): "Watching"
        case (.later, .polish): "Później"
        case (.later, .english): "Later"
        }
    }

    public static func moreLine(_ count: Int, _ language: NotificationLanguage) -> String {
        language == .polish ? "I jeszcze \(count)" : "And \(count) more"
    }

    /// A row with no words of its own (a private note, an item the person never named).
    public static func sourceName(_ source: OpenLoopSource, _ language: NotificationLanguage) -> String {
        switch (source, language) {
        case (.noteReminder, .polish): "Przypomnienie o notatce"
        case (.noteReminder, .english): "Note reminder"
        case (.appleReminder, .polish): "Przypomnienie"
        case (.appleReminder, .english): "Reminder"
        case (.calendarEvent, .polish): "Wydarzenie"
        case (.calendarEvent, .english): "Event"
        case (.errand, .polish): "Zadanie"
        case (.errand, .english): "Task"
        case (.priceWatch, .polish): "Pilnowana cena"
        case (.priceWatch, .english): "Watched price"
        case (.parcel, .polish): "Paczka"
        case (.parcel, .english): "Parcel"
        }
    }

    public static func title(_ item: OpenLoopItem, _ language: NotificationLanguage) -> String {
        switch item.title {
        case .text(let text): text
        case .hidden: sourceName(item.source, language)
        }
    }

    /// What the page says when a source could not be read. It never reads as "nothing there".
    public static func unavailableLine(_ source: OpenLoopSource, _ language: NotificationLanguage) -> String {
        let name: String
        switch (source, language) {
        case (.noteReminder, .polish): name = "przypomnienia na notatkach"
        case (.noteReminder, .english): name = "reminders on notes"
        case (.appleReminder, .polish): name = "przypomnienia Apple"
        case (.appleReminder, .english): name = "Apple Reminders"
        case (.calendarEvent, .polish): name = "kalendarz"
        case (.calendarEvent, .english): name = "the calendar"
        case (.errand, .polish): name = "zadania"
        case (.errand, .english): name = "tasks"
        case (.priceWatch, .polish): name = "pilnowane ceny"
        case (.priceWatch, .english): name = "watched prices"
        case (.parcel, .polish): name = "paczki"
        case (.parcel, .english): name = "parcels"
        }
        return language == .polish ? "Nie mogę teraz odczytać: \(name)." : "Can't read right now: \(name)."
    }

    public static func status(_ status: OpenLoopStatus, _ language: NotificationLanguage) -> String {
        let pl = language == .polish
        switch status {
        case .overdue: return pl ? "Po terminie" : "Overdue"
        case .dueToday(let hasTime): return pl ? (hasTime ? "Na dziś" : "Na dziś, bez godziny") : (hasTime ? "Due today" : "Due today, no time")
        case .scheduled: return pl ? "Zaplanowane" : "Scheduled"
        case .noDate: return pl ? "Bez daty" : "No date"
        case .repeating(let rule):
            switch rule {
            case .daily: return pl ? "Co dzień" : "Every day"
            case .weekdays: return pl ? "W dni robocze" : "On weekdays"
            case .weekly: return pl ? "Co tydzień" : "Every week"
            case .monthly: return pl ? "Co miesiąc" : "Every month"
            }
        case .atPlace(let name): return pl ? "Przy miejscu: \(name)" : "At a place: \(name)"
        case .nudgeSet(let lead): return pl ? "Przypomnienie \(lead) min przed" : "Reminder \(lead) min before"
        case .nudgeAtOldTime: return pl ? "Przypomnienie jest ustawione na dawną godzinę" : "The reminder is set for the old time"
        case .queued: return pl ? "W kolejce" : "Queued"
        case .running: return pl ? "W toku" : "Running"
        case .finished: return pl ? "Gotowe, wynik czeka" : "Done, the result is waiting"
        case .failed: return pl ? "Nie udało się" : "Didn't work out"
        case .watching(let last, let threshold):
            let target = threshold.text(language)
            guard let last else { return pl ? "Sprawdzam cenę. Twoja kwota: \(target)" : "Checking the price. Your price: \(target)" }
            return pl ? "Ostatnio: \(last.text(language)). Twoja kwota: \(target)" : "Last seen: \(last.text(language)). Your price: \(target)"
        case .priceReached(let price):
            guard let price else { return pl ? "Cena osiągnięta" : "Price reached" }
            return pl ? "Cena osiągnięta: \(price.text(language))" : "Price reached: \(price.text(language))"
        case .parcel(let kind):
            switch kind {
            case .preparing: return pl ? "Nadawca przygotowuje" : "Being prepared"
            case .inTransit: return pl ? "W drodze" : "On its way"
            case .readyForPickup: return pl ? "Czeka na odbiór" : "Ready to collect"
            case .delivered: return pl ? "Dostarczona" : "Delivered"
            case .problem: return pl ? "Wymaga uwagi" : "Needs attention"
            case .returned: return pl ? "Wróciła do nadawcy" : "Returned to the sender"
            case .unknown: return pl ? "Status nieznany" : "Status unknown"
            }
        case .cannotConfirm: return pl ? "Nie mogę tego potwierdzić" : "Can't confirm this"
        }
    }
}
