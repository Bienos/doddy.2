import Foundation

/// How much of the user's data one question may carry off the device. Matches the gateway's limits
/// (`gateway/src/validate.js`); the gateway rejects anything larger rather than truncating it.
public struct GroundingBudget: Equatable, Sendable {
    public let maxMemories: Int
    public let maxTotalScalars: Int

    public init(maxMemories: Int = 5, maxTotalScalars: Int = 12_000) {
        self.maxMemories = maxMemories
        self.maxTotalScalars = maxTotalScalars
    }

    public static let standard = GroundingBudget()
}

/// Chooses which saved notes may be sent with a question: only notes that matched it, never sample
/// fixtures, never more than the budget, and never shortened (a cut-off note could change its meaning).
public enum GroundingSelector {
    public static func select(from candidates: [MemoryCandidate], budget: GroundingBudget = .standard) -> [MemoryCandidate] {
        var chosen: [MemoryCandidate] = []
        var seen = Set<UUID>()
        var total = 0
        for candidate in candidates {
            if chosen.count == budget.maxMemories { break }
            guard candidate.record.source.isEligibleForPersonalRecall,
                  !candidate.matchedTerms.isEmpty,
                  !seen.contains(candidate.memoryID)
            else { continue }
            let size = candidate.record.currentText.unicodeScalars.count
            guard total + size <= budget.maxTotalScalars else { continue } // skip, try smaller ones
            seen.insert(candidate.memoryID)
            total += size
            chosen.append(candidate)
        }
        return chosen
    }
}
