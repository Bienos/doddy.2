import DoddyCore
import Foundation

extension PinnedNotes {
    static let fullMessage = "You can pin up to \(maxPins) notes. Unpin one first."

    /// Pins or unpins `id` in the stored preference string (`PreferenceKey.pinnedNotes`) and
    /// returns what happened. Nothing is written when the limit is reached (ADR-144).
    @discardableResult
    static func toggle(_ id: UUID, stored: inout String, existing: [MemoryRecord]) -> Change {
        var pins = PinnedNotes(stored: stored)
        let change = pins.toggle(id, existing: existing)
        if change != .full { stored = pins.stored }
        return change
    }
}
