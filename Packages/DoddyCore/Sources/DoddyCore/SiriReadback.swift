import Foundation

// Siri reads a note back (ADR-214): "Hey Siri, ask Doddy what I saved" → "What are you looking
// for?" → "gate code" → Siri says the stored note. The search is the same on-device recall as
// Memories → Find; this file only turns its outcome into what Siri says. Rules, not a model:
// the note's own words, when it was saved, and nothing else. Never a guess.

public enum SiriReadback {
    /// Longest stretch of one note Siri reads; the rest is left for the app.
    public static let maxSpokenNoteLength = 280
    /// Word matches read out at most; any more are counted.
    public static let maxNotesRead = 2

    public static let switchedOff = "Reading notes aloud is turned off in Doddy's settings. Open Doddy to search your notes."
    public static let storageUnavailable = "Doddy can't open your saved notes right now. Open Doddy to see what's wrong."
    public static let searchFailed = "Doddy couldn't search your notes just now. Try again, or open Doddy."
    public static let emptyQuery = "Say a word from the note you're looking for."

    /// What Siri says for one search. `savedText` phrases when a note was saved ("on 3 October").
    public static func reply(_ outcome: RecallOutcome, savedText: (Date?) -> String) -> String {
        guard case .matches(let all) = outcome, !all.isEmpty else { return RecallCopy.noMatch }
        let words = all.filter { !$0.isMeaningMatch }
        let related = all.filter(\.isMeaningMatch)

        guard !words.isEmpty else {
            // Meaning matches share no word with the question: offered as a maybe, one at most.
            let note = related[0]
            return "No note uses those words. This one might be what you mean, saved \(savedText(note.record.capturedAt)): \(quoted(note.record.currentText))"
        }

        // Notes that give different numbers for the same thing are both read, never one picked.
        let disagreeing = RecallConflicts.flagged(words)
        let disagreeingNotes = words.filter { disagreeing.contains($0.memoryID) }
        if disagreeingNotes.count >= 2 {
            let read = disagreeingNotes.prefix(maxNotesRead)
                .map { "saved \(savedText($0.record.capturedAt)): \(quoted($0.record.currentText))" }
            var text = "Two of your notes give different numbers. One, \(read[0]) The other, \(read[1]) Check which one is current."
            if words.count > read.count { text += " \(more(words.count - read.count)) Open Doddy to see them." }
            return text
        }

        if words.count == 1 {
            let note = words[0]
            return "You saved this \(savedText(note.record.capturedAt)): \(quoted(note.record.currentText))"
        }
        let read = words.prefix(maxNotesRead)
        var text = "I found \(words.count) notes. The closest match, saved \(savedText(read[0].record.capturedAt)): \(quoted(read[0].record.currentText))"
        if read.count > 1 {
            text += " Next, saved \(savedText(read[1].record.capturedAt)): \(quoted(read[1].record.currentText))"
        }
        if words.count > read.count { text += " \(more(words.count - read.count)) Open Doddy to see them." }
        return text
    }

    /// "today", "yesterday", "on 3 October", "on 3 October 2025"; "at an unknown time" without a date.
    public static func savedText(_ date: Date?, now: Date, calendar: Calendar) -> String {
        guard let date else { return "at an unknown time" }
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        let parts = calendar.dateComponents([.day, .month, .year], from: date)
        let month = monthNames[(parts.month ?? 1) - 1]
        let sameYear = parts.year == calendar.component(.year, from: now)
        return "on \(parts.day ?? 1) \(month)\(sameYear ? "" : " \(parts.year ?? 0)")"
    }

    /// The note's words in quotes, line breaks as pauses, cut at a word if very long.
    static func quoted(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        guard flat.count > maxSpokenNoteLength else { return "“\(flat)”." }
        let cut = flat.prefix(maxSpokenNoteLength)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return "“\(atWord)…” It goes on; open Doddy for the rest."
    }

    static func more(_ n: Int) -> String {
        n == 1 ? "There's one more." : "There are \(n) more."
    }

    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
}
