import DoddyCore
import Foundation
import Observation

/// Keeps the opt-in server copy of memories (used only to answer on phone calls) equal to what
/// is on this iPhone. Every change sends the full current list, so deletions and corrections
/// carry over. Does nothing unless the user turned on "Memory on calls".
///
/// Private notes (ADR-310) are never in the server copy. Every upload leaves them out here, with
/// the private set read from this iPhone just before sending, so a caller that passes every
/// note can't put a private one on the server.
@MainActor
@Observable
final class MemoryCopySync {
    enum Status: Equatable {
        case idle
        case copied(count: Int, at: Date)
        case failed(String)
    }

    static let shared = MemoryCopySync()
    private(set) var status: Status = .idle
    private var pending: Task<Void, Never>?
    /// True from the moment a change is waiting until the server confirmed the copy. A failed or
    /// cut-off upload leaves it set, and `retryIfNeeded` sends the current list again, so a memory
    /// deleted while offline doesn't stay on the server (DOD-06).
    private(set) var needsRetry = false

    var isOn: Bool { UserDefaults.standard.bool(forKey: PreferenceKey.memoryCopyOn) }

    func schedule(_ records: [MemoryRecord], delay: Duration = .seconds(2)) {
        guard isOn, let client = ServerConfig.client() else { return }
        pending?.cancel()
        needsRetry = true
        pending = Task {
            // Collapses bursts of edits into one upload.
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            // Read after the wait, so a note made private in the meantime is left out too.
            let items = MemoryCopyItem.from(records, excluding: PrivateNotesStore.current())
            do {
                let count = try await client.replaceMemoryCopy(items)
                // The server holds a filtered copy now, even if a newer change cancelled this task.
                Self.confirmCleanup()
                guard !Task.isCancelled else { return }
                needsRetry = false
                status = .copied(count: count, at: Date())
            } catch ServerError.notEnabled {
                // The server has no copy switched on (e.g. the server data was deleted): stop sending.
                UserDefaults.standard.set(false, forKey: PreferenceKey.memoryCopyOn)
                needsRetry = false
                status = .idle
            } catch {
                // A newer change cancelled this one; that upload reports for both.
                guard !Task.isCancelled else { return }
                status = .failed(UpdatesModel.text(for: error))
            }
        }
    }

    /// At launch and when Doddy comes to the front: sends the current list again if the last
    /// upload didn't go through, or once to replace a copy from before private notes were left
    /// out (`MemoryCopyResend`). `notesLoaded` must be false when reading the notes failed.
    func retryIfNeeded(_ records: [MemoryRecord], notesLoaded: Bool) {
        let cleanupConfirmed = UserDefaults.standard.bool(forKey: MemoryCopyResend.privateNotesCleanupKey)
        guard MemoryCopyResend.isDue(copyOn: isOn, notesLoaded: notesLoaded,
                                     lastUploadFailed: needsRetry, cleanupConfirmed: cleanupConfirmed) else { return }
        schedule(records, delay: .zero)
    }

    /// Only after the server confirmed an upload; every upload leaves private notes out.
    private static func confirmCleanup() {
        UserDefaults.standard.set(true, forKey: MemoryCopyResend.privateNotesCleanupKey)
    }

    /// Uploads now and waits for the server's answer, for callers that must say what happened
    /// (switching the copy on, Delete all). Throws when the copy couldn't be replaced; it is then
    /// tried again by `retryIfNeeded`. Does nothing when the copy is off.
    func uploadNow(_ records: [MemoryRecord]) async throws {
        guard isOn, let client = ServerConfig.client() else { return }
        pending?.cancel()
        needsRetry = true
        do {
            let count = try await client.replaceMemoryCopy(MemoryCopyItem.from(records, excluding: PrivateNotesStore.current()))
            Self.confirmCleanup()
            needsRetry = false
            status = .copied(count: count, at: Date())
        } catch ServerError.notEnabled {
            // No copy on the server, so there is nothing to replace.
            UserDefaults.standard.set(false, forKey: PreferenceKey.memoryCopyOn)
            needsRetry = false
            status = .idle
        } catch {
            status = .failed(UpdatesModel.text(for: error))
            throw error
        }
    }

    func stop() {
        pending?.cancel()
        needsRetry = false
        status = .idle
    }
}
