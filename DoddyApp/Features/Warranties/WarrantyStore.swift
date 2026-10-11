import DoddyCore
import Foundation

/// Warranties (ADR-342), kept in the app's preferences on this iPhone. Every change is read back
/// before the screen says it happened.
enum WarrantyStore {
    private static var defaults: UserDefaults { .standard }

    static func current() -> Warranties {
        Warranties(stored: defaults.data(forKey: Warranties.storageKey))
    }

    /// The outcome, or nil when what's on disk isn't what was written.
    static func save(_ warranty: Warranty) -> Warranties.SaveOutcome? {
        var all = current()
        let outcome = all.save(warranty)
        guard outcome == .saved || outcome == .replaced else { return outcome }
        return write(all) ? outcome : nil
    }

    static func remove(_ id: UUID) -> Bool {
        var all = current()
        all.remove(id)
        return write(all)
    }

    /// Drops warranties whose note was deleted. Called when the notes change.
    static func prune(keeping noteIDs: Set<UUID>) {
        var all = current()
        let before = all.items.count
        all.keep(only: noteIDs)
        if all.items.count != before { _ = write(all) }
    }

    private static func write(_ all: Warranties) -> Bool {
        defaults.set(all.stored, forKey: Warranties.storageKey)
        return current() == all
    }
}
