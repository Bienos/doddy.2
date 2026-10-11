import DoddyCore
import Foundation
import WidgetKit

/// Keeps the widgets' snapshot (ADR-219) equal to what is in Doddy: rewritten after notes, lists,
/// pins or reminders change, and read back. Ticks from a widget arrive here, in the app's process
/// (`ToggleListItemIntent`), and go through the same store as a tick in the app.
@MainActor
final class WidgetSync {
    static let shared = WidgetSync()

    weak var store: MemoryStore?
    weak var reminders: NoteReminderStore?
    /// The last write's problem, for Settings; nil after a good write.
    private(set) var problem: String?
    private var lastWritten: WidgetSnapshot?

    private init() {}

    /// False when this build isn't signed with the App Group: widgets can't be given anything.
    var isAvailable: Bool { WidgetSnapshotFile.url != nil }

    static var isOn: Bool {
        UserDefaults.standard.object(forKey: PreferenceKey.widgetsShowContent) as? Bool ?? true
    }

    func refresh(now: Date = .now) {
        guard let store, store.hasLoaded else { return }
        let snapshot = WidgetSnapshot.make(
            memories: store.memories, lists: store.lists,
            pinned: PinnedNotes(stored: UserDefaults.standard.string(forKey: PreferenceKey.pinnedNotes)),
            reminders: reminders?.reminders ?? [],
            showReminderText: UserDefaults.standard.bool(forKey: PreferenceKey.showNoteTextInNotifications),
            isOn: Self.isOn, now: now)
        // The Apple Watch gets the same content, under its own switch (ADR-232).
        PhoneWatchLink.shared.send(WidgetSnapshot.make(
            memories: store.memories, lists: store.lists,
            pinned: PinnedNotes(stored: UserDefaults.standard.string(forKey: PreferenceKey.pinnedNotes)),
            reminders: reminders?.reminders ?? [],
            showReminderText: UserDefaults.standard.bool(forKey: PreferenceKey.showNoteTextInNotifications),
            isOn: true, now: now))
        guard isAvailable else { return }
        // Same content as last time: no write, no widget reload (the time stamp alone isn't news).
        if let lastWritten, lastWritten.isOn == snapshot.isOn, lastWritten.pinned == snapshot.pinned,
           lastWritten.reminders == snapshot.reminders, lastWritten.lists == snapshot.lists { return }
        do {
            try WidgetSnapshotFile.write(snapshot)
            lastWritten = snapshot
            problem = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            problem = NSLocalizedString("Widgets couldn't be updated, so they may show older notes or lists. Open the widget's note in Doddy to see what is saved.", comment: "")
        }
    }

    /// A widget tap on a list item. Only changes the item when the widget showed it as it is now;
    /// returns what the read-back store says happened.
    func tick(listID: UUID, itemID: UUID, shownDone: Bool) async -> WidgetTick {
        guard let store else { return .failed }
        await store.reload()
        let item = store.list(id: listID)?.items.first { $0.id == itemID }
        guard let item, let wanted = WidgetTick.wanted(item: item, shownDone: shownDone) else {
            refresh()
            return .notFound
        }
        let outcome: WidgetTick
        do {
            let changed = try await store.setDone([item], done: wanted, listID: listID)
            outcome = WidgetTick.outcome(after: changed, itemID: itemID, wantedDone: wanted)
        } catch {
            outcome = .failed
        }
        refresh()
        return outcome
    }
}
