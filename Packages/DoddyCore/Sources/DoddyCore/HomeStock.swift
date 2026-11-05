import Foundation

// What is already at home (Shopping list+, ADR-631, stage 2). One of the user's lists can be their
// At home list ("W domu", "Spiżarnia"); which one is kept on this iPhone. It never blocks an add:
// adding to another list still adds, and the items that are open on the At home list are named
// ("On your At home list: rice"), on screen and in Doddy's reply. Matching is the lists' exact-words
// rule (ListMatch.key) on the words without a quantity (ListItemWords): "ryż 1 kg" at home matches
// "ryż" added; "ryżu" does not, and "rice" never matches "ryż". Moving ticked items between the
// At home list and another list is an ordinary add to one list, with its usual Undo.
//
// Platforms: iPhone and iPad (lists, voice). Pure logic; tested on Linux.

public enum HomeStock {
    /// The At home list's id (a UUID string), kept on this iPhone. One list at a time.
    public static let preferenceKey = "lists.atHomeListID"

    /// The At home list, or nil when none is chosen or it no longer exists.
    public static func list(storedID: String?, in lists: [DoddyList]) -> DoddyList? {
        guard let storedID, let id = UUID(uuidString: storedID) else { return nil }
        return lists.first { $0.id == id }
    }

    /// The words of `texts` that are open on the At home list, once each, in the order given.
    /// Empty when there is no At home list or the add is to the At home list itself.
    public static func onHomeList(_ texts: [String], home: DoddyList?, addingTo listID: UUID) -> [String] {
        let positions = positionsOnHomeList(texts, home: home, addingTo: listID)
        return texts.indices.filter(positions.contains).map { texts[$0] }
    }

    /// Positions of `items` that are open on the At home list (a dish's ingredients card starts them
    /// unticked, like items already on the list). A repeated item counts once, at its first place.
    public static func positionsOnHomeList(_ items: [String], home: DoddyList?, addingTo listID: UUID) -> Set<Int> {
        guard let home, home.id != listID else { return [] }
        let open = Set(home.open.map { key($0.text) }.filter { !$0.isEmpty })
        var seen = Set<String>()
        var positions = Set<Int>()
        for (index, text) in items.enumerated() {
            let wanted = key(text)
            guard !wanted.isEmpty, open.contains(wanted), seen.insert(wanted).inserted else { continue }
            positions.insert(index)
        }
        return positions
    }

    /// The ticked items' words, in list order, to add to another list ("Add ticked to At home",
    /// or from the At home list "Add ticked to a list"). The ticks themselves stay.
    public static func tickedWords(of list: DoddyList) -> [String] {
        list.items.filter(\.isDone).map(\.text)
    }

    /// The words without a quantity, folded as lists match them.
    static func key(_ text: String) -> String {
        ListMatch.key(ListItemWords.read(text).product)
    }
}

extension VoiceToolReply {
    /// Added after an add's reply when some of the items added are open on the At home list. The
    /// list's name and the items are the user's words, so they go as data (ToolData). Empty when
    /// there are none.
    public static func onHomeList(_ items: [String], home: String) -> String {
        guard !items.isEmpty else { return "" }
        return "\nThese are also open on the user's At home list, so they may have them already. They were still added; "
            + "mention it in a few words and change nothing. The At home list's name, then the items:\n"
            + ToolData.block(["Name: \"\(ToolData.clean(home))\""] + items.map { "- \(ToolData.clean($0))" })
    }
}
