import Foundation

/// "Note saved" in the Dynamic Island (ADR-338): a Live Activity that shows the conversation's
/// saved card for a few seconds after a note is saved and read back on the capture screen, then
/// goes away by itself. It never carries the note's words. Started only after the store
/// confirmed the save, so it can't claim a save that didn't happen. Optional: off in Settings,
/// or when Live Activities are off for Doddy, nothing shows and the save is unchanged.
///
/// Whether iOS shows an app's own Live Activity in the island while that app is in front is
/// the device check (Mac checklist 4m); on the Lock Screen it shows either way.
@MainActor
enum SavedNoteIsland {
    /// How long the card stays before the app ends it.
    static let showFor: TimeInterval = 8
    private static var current: ToolLiveActivity?
    private static var ending: Task<Void, Never>?

    static var isOn: Bool {
        UserDefaults.standard.object(forKey: PreferenceKey.savedIsland) as? Bool ?? true
    }

    /// Called once per confirmed save. A card still showing from a save moments ago is
    /// replaced, not stacked.
    static func flash(at now: Date = Date()) {
        guard isOn else { return }
        ending?.cancel()
        current?.end(final: nil)
        let island = ToolLiveActivity(kind: .noteSaved)
        island.show(.init(isPaused: false, endsAt: nil, isFinished: true), startedAt: now, duration: 0)
        current = island
        ending = Task {
            try? await Task.sleep(for: .seconds(showFor))
            guard !Task.isCancelled else { return }
            island.end(final: nil)
            if current === island { current = nil }
        }
    }

    /// At launch: a card left by a killed app is removed with the other leftovers
    /// (`ToolLiveActivity.endLeftovers`); nothing to restore here.
    static func reset() {
        ending?.cancel()
        current = nil
    }
}
