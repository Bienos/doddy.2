import DoddyCore
import Foundation

/// What Siri says for "Ask Doddy what I saved" (ADR-248): the same on-device search as
/// Memories → Find, turned into words by `SiriReadback`. Kept apart from the App Intent so it
/// type-checks without App Intents.
@MainActor
enum SiriNoteLookup {
    static func isAllowed(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: PreferenceKey.siriReadsNotes) as? Bool ?? true
    }

    static func spokenAnswer(
        for query: String, environment: AppEnvironment, defaults: UserDefaults = .standard,
        now: Date = .now, calendar: Calendar = .current
    ) async -> String {
        guard isAllowed(defaults) else { return SiriReadback.switchedOff }
        guard environment.storageProblem == nil else { return SiriReadback.storageUnavailable }
        guard !query.allSatisfy(\.isWhitespace) else { return SiriReadback.emptyQuery }
        do {
            // Private notes (ADR-310) are never read out by Siri.
            let outcome = PrivateNotes(stored: defaults.string(forKey: PrivateNotes.storageKey))
                .shareable(try await environment.recallService.recall(query, limit: 20))
            return SiriReadback.reply(outcome, question: query) { SiriReadback.savedText($0, now: now, calendar: calendar) }
        } catch {
            return SiriReadback.searchFailed
        }
    }

    /// Doddy's pose for an answer (ADR-313), the same meanings as everywhere: listening when a
    /// note was found, shrug when none was (or only part of the question matched), facepalm when
    /// the notes couldn't be searched, shush when reading aloud is switched off.
    static func pose(forAnswer answer: String) -> IslandPose {
        switch answer {
        case SiriReadback.switchedOff: return .shush
        case SiriReadback.storageUnavailable, SiriReadback.searchFailed: return .facepalm
        case SiriReadback.emptyQuery: return .listening
        case RecallCopy.noMatch: return .shrug
        default:
            // A partial match starts by saying what no note has (SiriReadback.reply).
            return answer.hasPrefix("No saved note") || answer.hasPrefix("No single note") ? .shrug : .listening
        }
    }
}
