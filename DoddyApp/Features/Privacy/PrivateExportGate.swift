import DoddyCore
import Foundation

/// The Face ID question before a private note goes into a file (Settings › Memories › Export, the encrypted
/// backup). A private note's words show only after Face ID (or the passcode), so they go into a file only after
/// it too (ADR-310). The rule is `PrivateNotesExport` in DoddyCore, tested on Linux; this asks iOS through
/// `AppLock`, the one place that does. Nothing is asked when no note in the file is private. A check that was
/// already passed this session (the private words are showing) is not asked again.
@MainActor
enum PrivateExportGate {
    enum Result: Equatable {
        /// Make the file; name these notes as private in it.
        case go(marked: Set<UUID>)
        /// Make nothing. The words say why.
        case stopped(String)
    }

    /// Thrown inside a share sheet's data closure, where there is nowhere to show a message: the share fails.
    struct Stopped: Error {}

    static var stoppedText: String {
        NSLocalizedString("Not made: Face ID didn't confirm it. Private notes can't go into a file without it.", comment: "Export or backup stopped: private notes need Face ID")
    }

    /// `records` are everything going into the file (notes and the records of lists). `reason` is what iOS shows
    /// in the Face ID sheet.
    static func check(records: [MemoryRecord], reason: String) async -> Result {
        let check = PrivateNotesExport.check(records: records, privateNotes: PrivateNotesStore.current())
        guard check.needsFaceID else { return .go(marked: []) }
        let confirmed = AppLock.shared.privateUnlocked ? true : await AppLock.shared.unlock(reason: reason)
        switch PrivateNotesExport.outcome(for: check, faceIDConfirmed: confirmed) {
        case .go(let marked): return .go(marked: marked)
        case .stop: return .stopped(stoppedText)
        }
    }

    /// The same for a share sheet's data closure: the notes to name as private, or the share fails.
    static func markedIDs(for records: [MemoryRecord]) async throws -> Set<UUID> {
        let reason = NSLocalizedString("Export Doddy's notes", comment: "Face ID reason: exporting notes that include private ones")
        switch await check(records: records, reason: reason) {
        case .go(let marked): return marked
        case .stopped: throw Stopped()
        }
    }
}
