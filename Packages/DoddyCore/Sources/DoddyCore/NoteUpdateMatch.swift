import Foundation

/// A saved note that a new note may replace (decision `2026-11-14-changed-facts-update-the-note`).
public struct NoteUpdateOffer: Equatable, Sendable {
    public let noteID: UUID
    /// The saved note's words as they are now (its current wording, after any correction): what the
    /// person is shown, and what the new words were compared with.
    public let oldText: String
    public let newText: String

    public init(noteID: UUID, oldText: String, newText: String) {
        self.noteID = noteID
        self.oldText = oldText
        self.newText = newText
    }
}

/// Spots a new note that changes an old one: "Mieszkam w Berlinie" when "Mieszkam w Warszawie" is saved,
/// "Gate code is 5555" beside "Gate code 4821". Today the second one just becomes another note next to
/// the first, and nothing says which is current. When these rules find exactly one saved note about the
/// same thing, the person is offered "update that note" (the old wording stays in its history, ADR-252)
/// beside "save as a new note". Rules, not a model, on the iPhone; nothing here saves or changes a note.
///
/// It only offers. A wrong offer costs one tap on "save as a new note"; a missed one leaves things as
/// they are today. So the rules are narrow on purpose, and a doubt is a no:
/// - **The same words with a different number**: every number in the new words differs from the old
///   note's, and the words that aren't numbers are the same (one side's a subset of the other's, at
///   least two of them). "Gate code 4821" and "Gate code is 5555"; a dentist at 14:00 and at 15:00.
///   Two birthdays on different people, or the office wifi and the home wifi, aren't the same words.
/// - **A fact with one value**: a short list of things a person has only one of at a time, where they
///   live and where they work. The new and old words name the same one and its first word differs
///   ("warszawie" and "berlinie"). Things that add up (what she likes, what he's allergic to) are
///   never on the list, so they are never replaced.
/// - **Exactly one note.** Two saved notes that both fit mean nobody knows which one changed: no offer.
/// - **Never a private note, a list or a sample.** A private note's words aren't read for a match and
///   so can't be put on a card (Face ID, `PrivateNotes`); the caller passes their ids.
///
/// Known misses and false offers, by design: "San Francisco" and "San Jose" look like the same place
/// (the first word of the value is compared), "Przeprowadziłem się do Warszawy" differs from "Mieszkam w
/// Warszawie" only by the case ending and is offered anyway, and a change worded in a way the lists
/// don't know (a new job without "pracuję") gets no offer. Add a phrase with its tests when one is missed.
public enum NoteUpdateMatch {
    /// The one saved note `newText` may replace, or nil. `notes` are every saved note; `privateIDs` are the
    /// ones the person hid behind Face ID.
    public static func offer(forNewText newText: String, notes: [MemoryRecord], privateIDs: Set<UUID> = []) -> NoteUpdateOffer? {
        guard !DuplicateNote.key(newText).isEmpty else { return nil }
        let matches = notes.filter { note in
            note.category != .list && note.source != .sampleFixture && !privateIDs.contains(note.id)
                && isSameThing(newText, note.currentText)
        }
        guard matches.count == 1, let note = matches.first else { return nil }
        return NoteUpdateOffer(noteID: note.id, oldText: note.currentText, newText: newText)
    }

    static func isSameThing(_ new: String, _ old: String) -> Bool {
        sameWordsOtherNumber(new, old) || sameFactOtherValue(new, old)
    }

    // MARK: The same words with a different number

    /// Fewest shared words that make two notes "the same thing": one word ("code") is too generic.
    static let fewestSharedWords = 2

    static func sameWordsOtherNumber(_ new: String, _ old: String) -> Bool {
        let newNumbers = RecallConflicts.numbers(in: new)
        let oldNumbers = RecallConflicts.numbers(in: old)
        guard !newNumbers.isEmpty, !oldNumbers.isEmpty, newNumbers != oldNumbers else { return false }
        let newWords = wordsWithoutNumbers(new)
        let oldWords = wordsWithoutNumbers(old)
        guard min(newWords.count, oldWords.count) >= fewestSharedWords else { return false }
        return newWords.isSubset(of: oldWords) || oldWords.isSubset(of: newWords)
    }

    private static func wordsWithoutNumbers(_ text: String) -> Set<String> {
        Set(SearchFolding.queryTerms(text).filter { !$0.contains(where: \.isNumber) })
    }

    // MARK: A fact with one value

    /// One thing a person has only one of at a time, and the ways of saying it (folded words, as
    /// `SearchFolding.tokens` writes them: no capitals, no accents, "ł" as "l").
    struct Slot {
        let name: String
        let phrases: [[String]]
    }

    static let slots: [Slot] = [
        Slot(name: "residence", phrases: [
            ["mieszkam", "w"], ["mieszkam", "we"], ["przeprowadzilem", "sie", "do"], ["przeprowadzilam", "sie", "do"],
            ["i", "live", "in"], ["i", "moved", "to"],
        ]),
        Slot(name: "workplace", phrases: [
            ["pracuje", "w"], ["pracuje", "we"], ["pracuje", "dla"], ["i", "work", "at"], ["i", "work", "for"], ["i", "work", "in"],
        ]),
    ]

    static func sameFactOtherValue(_ new: String, _ old: String) -> Bool {
        guard let newFact = fact(in: new), let oldFact = fact(in: old), newFact.slot == oldFact.slot else { return false }
        return newFact.value != oldFact.value
    }

    /// Which slot the words are about and the first word of its value ("warszawie", "berlin"), if they say one.
    static func fact(in text: String) -> (slot: String, value: String)? {
        let tokens = SearchFolding.tokens(text)
        for start in tokens.indices {
            for slot in slots {
                for phrase in slot.phrases where start + phrase.count < tokens.count {
                    if Array(tokens[start..<(start + phrase.count)]) == phrase {
                        return (slot.name, tokens[start + phrase.count])
                    }
                }
            }
        }
        return nil
    }
}
