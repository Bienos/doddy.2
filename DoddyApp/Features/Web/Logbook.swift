import DoddyCore
import Foundation

/// Logbook on this iPhone (ADR-602; on by default, decision 2026-11-09-usage-counts-on-by-default).
/// The rules are `LogbookModel` and `LogbookBuilder` in DoddyCore, tested on Linux. This file gives
/// them the app's own records: What Doddy did, the notes and lists, the tasks handed over and the
/// conversations the voice controller counted. Counts only leave the iPhone.
enum Logbook {
    @MainActor static let shared = LogbookModel(
        makeClient: { await LogbookClientFactory.ready() },
        renewClient: { await LogbookClientFactory.renewed() })

    /// Everything a day's counts are made from, read from the app's stores now.
    @MainActor static func sources(store: MemoryStore) -> LogbookSources {
        LogbookSources(
            activity: ActivityLogStore.shared.entries,
            notes: store.memories + store.lists.map(\.record),
            privateNoteIDs: PrivateNotesStore.current().ids,
            listItems: store.lists.flatMap(\.items),
            errands: ErrandsModel.shared.errands.map(LogbookErrand.init))
    }

    /// When Doddy comes to the front or goes to the back. Only after the notes were read: a failed
    /// read must never replace a day on the server with smaller counts.
    @MainActor static func sync(store: MemoryStore) {
        guard store.hasLoaded, store.loadError == nil else { return }
        let sources = sources(store: store)
        Task { await shared.sync(sources: sources) }
    }

    /// A finished conversation: its times, how it ended and its language, never its words.
    /// Private conversations are not counted.
    @MainActor static func conversationEnded(startedAt: Date, endedAt: Date, ended: String?, language: String?, isPrivate: Bool) {
        guard !isPrivate else { return }
        shared.recordConversation(LogbookConversation(startedAt: startedAt, endedAt: endedAt, ended: ended, language: language))
    }
}
