import DoddyCore
import Foundation

/// List templates (ADR-334), kept in the app's preferences on this iPhone. Every change is
/// read back before the screen says it happened.
enum ListTemplateStore {
    private static var defaults: UserDefaults { .standard }

    static func current() -> ListTemplates {
        ListTemplates(stored: defaults.data(forKey: ListTemplates.storageKey))
    }

    /// The outcome, or nil when the templates on disk aren't what was written.
    static func save(_ list: DoddyList) -> ListTemplates.SaveOutcome? {
        var templates = current()
        let outcome = templates.save(list)
        switch outcome {
        case .empty, .full: return outcome
        case .saved, .replaced:
            guard write(templates) else { return nil }
            return outcome
        }
    }

    static func remove(_ id: UUID) -> Bool {
        var templates = current()
        templates.remove(id)
        return write(templates)
    }

    private static func write(_ templates: ListTemplates) -> Bool {
        defaults.set(templates.stored, forKey: ListTemplates.storageKey)
        return current() == templates
    }
}
