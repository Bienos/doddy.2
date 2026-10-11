import DoddyCore
import Foundation

/// "The usual" (ADR-343), kept in the app's preferences on this iPhone.
enum UsualItemsStore {
    private static var defaults: UserDefaults { .standard }

    static func current() -> UsualItems { UsualItems(stored: defaults.data(forKey: UsualItems.storageKey)) }

    /// Counts new ticks after the lists reload. Cheap when nothing changed.
    static func record(_ lists: [DoddyList]) {
        var usual = current()
        if usual.record(lists) { defaults.set(usual.stored, forKey: UsualItems.storageKey) }
    }

    /// True when it reads back forgotten.
    static func forget(listNamed name: String) -> Bool {
        var usual = current()
        usual.forget(listNamed: name)
        defaults.set(usual.stored, forKey: UsualItems.storageKey)
        return current() == usual
    }
}
