import AppIntents
import DoddyCore
import Foundation
import Observation

/// Doddy's filter for the user's iOS Focus modes (ADR-312), added in Settings, Focus, on a
/// Focus. iOS runs `perform()` in Doddy's process when that Focus starts, and again with the
/// default values (nothing changed) when it ends. App target only.
struct DoddyFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Doddy during this Focus"
    static var description: IntentDescription? {
        IntentDescription("Put one list first in your lists while this Focus is on.")
    }

    @Parameter(title: "List to show first")
    var list: DoddyListEntity?

    var displayRepresentation: DisplayRepresentation {
        var parts: [String] = []
        if let list { parts.append(list.name) }
        return DisplayRepresentation(title: "Doddy", subtitle: parts.isEmpty ? nil : "\(parts.joined(separator: " · "))")
    }

    func perform() async throws -> some IntentResult {
        let settings = FocusFilterSettings(listFirstID: list?.id)
        await FocusFilterState.shared.apply(settings)
        return .result()
    }
}

/// The Focus filter in effect, kept in UserDefaults so it holds across launches until iOS says
/// the Focus ended.
@MainActor
@Observable
final class FocusFilterState {
    static let shared = FocusFilterState()

    private(set) var settings: FocusFilterSettings

    private init() {
        settings = FocusFilterSettings(stored: UserDefaults.standard.string(forKey: FocusFilterSettings.storageKey))
    }

    func apply(_ new: FocusFilterSettings) {
        settings = new
        if new.changesNothing {
            UserDefaults.standard.removeObject(forKey: FocusFilterSettings.storageKey)
        } else {
            UserDefaults.standard.set(new.stored, forKey: FocusFilterSettings.storageKey)
        }
    }
}
