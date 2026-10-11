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
            // Private notes (ADR-308) are never read out by Siri.
            let outcome = PrivateNotes(stored: defaults.string(forKey: PrivateNotes.storageKey))
                .shareable(try await environment.recallService.recall(query, limit: 20))
            return SiriReadback.reply(outcome, question: query) { SiriReadback.savedText($0, now: now, calendar: calendar) }
        } catch {
            return SiriReadback.searchFailed
        }
    }
}
