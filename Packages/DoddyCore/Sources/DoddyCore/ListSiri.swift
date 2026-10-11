import Foundation

// Lists from Siri, Shortcuts and the Action Button (ADR-226): "Add milk to my shopping list in
// Doddy", "What's on my shopping list in Doddy?", "Tick milk on my shopping list in Doddy". The
// app intents use the same exact matching and the same read-back store calls as voice and the
// list screen; these are only the words Siri says back, in the iPhone's language (Polish or
// English), built from what the store returned.

public enum ListSiri {
    /// Items said or typed in one go: split on commas, semicolons and new lines, cleaned the same
    /// way as everywhere else, at most `ListLimits.itemsPerList`. "and" is not a separator, so
    /// "salt and pepper crisps" stays one item.
    public static func items(from spoken: String) -> [String] {
        spoken.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .compactMap { ListText.cleaned(String($0)) }
            .prefix(ListLimits.itemsPerList)
            .map { $0 }
    }

    public static func added(_ result: ListAddResult, list: String, _ language: NotificationLanguage) -> String {
        let pl = language == .polish
        var parts: [String] = []
        if result.added.isEmpty {
            parts.append(pl ? "Nic nie dodałem do listy \(list)." : "Nothing new was added to \(list).")
        } else {
            let words = result.added.map(\.text).joined(separator: ", ")
            parts.append(pl ? "Dodane do listy \(list): \(words)." : "Added to \(list): \(words).")
        }
        if !result.alreadyThere.isEmpty {
            let words = result.alreadyThere.joined(separator: ", ")
            parts.append(pl ? "Już jest na liście: \(words)." : "Already on it: \(words).")
        }
        if !result.tooLong.isEmpty {
            parts.append(pl ? "Za długie, nie dodane: \(result.tooLong.count)." : "Too long, not added: \(result.tooLong.count).")
        }
        if !result.noRoom.isEmpty {
            parts.append(pl ? "Lista jest pełna, nie dodane: \(result.noRoom.count)." : "The list is full, not added: \(result.noRoom.count).")
        }
        return parts.joined(separator: " ")
    }

    /// Open items in list order, up to `ListLimits.readAloud`; the rest are counted.
    public static func read(_ list: DoddyList, _ language: NotificationLanguage) -> String {
        let pl = language == .polish
        let open = list.open
        guard !open.isEmpty else {
            return pl ? "Na liście \(list.name) nic nie zostało." : "Nothing left on \(list.name)."
        }
        let shown = open.prefix(ListLimits.readAloud).map(\.text).joined(separator: ", ")
        let more = open.count - min(open.count, ListLimits.readAloud)
        if pl {
            return "Na liście \(list.name) zostało \(open.count): \(shown)" + (more > 0 ? " i jeszcze \(more)." : ".")
        }
        return "\(list.name) has \(open.count) left: \(shown)" + (more > 0 ? ", and \(more) more." : ".")
    }

    public static func ticked(_ item: ListItem, list: String, _ language: NotificationLanguage) -> String {
        language == .polish ? "Odhaczone na liście \(list): \(item.text)." : "Ticked on \(list): \(item.text)."
    }

    public static func notOnList(_ said: String, list: String, _ language: NotificationLanguage) -> String {
        language == .polish ? "Na liście \(list) nie ma „\(said)”. Nic się nie zmieniło." : "\"\(said)\" isn't on \(list). Nothing changed."
    }

    public static func several(_ said: String, options: [ListItem], list: String, _ language: NotificationLanguage) -> String {
        let names = options.prefix(4).map(\.text).joined(separator: ", ")
        return language == .polish
            ? "„\(said)” pasuje do kilku pozycji na liście \(list): \(names). Nic nie odhaczyłem; powiedz dokładniej."
            : "\"\(said)\" matches several items on \(list): \(names). Nothing was ticked; say which one."
    }

    public static func nothingToAdd(_ language: NotificationLanguage) -> String {
        language == .polish ? "Nie usłyszałem, co dodać. Nic nie dodałem." : "I didn't get what to add, so nothing was added."
    }

    public static func listGone(_ language: NotificationLanguage) -> String {
        language == .polish ? "Tej listy już nie ma w Doddym." : "That list isn't in Doddy any more."
    }

    public static func failed(_ language: NotificationLanguage) -> String {
        language == .polish ? "Nie udało się. Lista się nie zmieniła." : "That didn't work. The list hasn't changed."
    }
}
