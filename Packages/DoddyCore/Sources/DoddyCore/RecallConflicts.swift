import Foundation

/// Spots search matches that may disagree (PRD item 4, ADR-171). Deliberately narrow: two or more
/// notes that matched the *same* query words but contain *different numbers* (codes, times,
/// amounts, dates written in digits). It only flags; it never hides a note or picks a winner,
/// because only the user knows which one is current.
public enum RecallConflicts {
    /// Ids of the notes that may disagree with another note in `candidates`.
    public static func flagged(_ candidates: [MemoryCandidate]) -> Set<UUID> {
        var groups: [Set<String>: [MemoryCandidate]] = [:]
        for candidate in candidates where !candidate.matchedTerms.isEmpty {
            groups[Set(candidate.matchedTerms.map { $0.lowercased() }), default: []].append(candidate)
        }
        var result: Set<UUID> = []
        for group in groups.values where group.count > 1 {
            let withNumbers = group.compactMap { candidate -> (UUID, Set<String>)? in
                let found = numbers(in: candidate.record.currentText)
                return found.isEmpty ? nil : (candidate.memoryID, found)
            }
            guard Set(withNumbers.map(\.1)).count > 1 else { continue }
            result.formUnion(withNumbers.map(\.0))
        }
        return result
    }

    /// Runs of ASCII digits, leading zeros kept ("0042" and "42" are different codes).
    static func numbers(in text: String) -> Set<String> {
        var found: Set<String> = []
        var current = ""
        for character in text {
            if character.isASCII, character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                found.insert(current)
                current = ""
            }
        }
        if !current.isEmpty { found.insert(current) }
        return found
    }
}
