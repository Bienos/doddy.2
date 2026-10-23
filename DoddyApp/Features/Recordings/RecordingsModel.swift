import DoddyCore
import Foundation
import Observation

/// The list of recordings (ADR-588), a page at a time. Everything shown is read from the store on
/// this iPhone; a recording still being written out is never shown as ready.
@MainActor
@Observable
final class RecordingsModel {
    var category: RecordingCategory = .all {
        didSet { if oldValue != category { Task { await reload() } } }
    }

    private(set) var items: [RecordingListItem] = []
    private(set) var hasMore = false
    private(set) var hasLoaded = false
    private(set) var problem: String?

    private let pageSize = 30
    private var repository: (any RecordingRepository)? { AppEnvironment.shared.recordingRepository }

    var isAvailable: Bool { repository != nil }

    /// Reads again from the top, keeping as many rows as are shown.
    func reload() async {
        guard let repository else {
            hasLoaded = true
            return
        }
        let wanted = max(pageSize, items.count)
        do {
            let fetched = try await repository.recordings(category: category, limit: wanted, offset: 0)
            items = fetched
            hasMore = fetched.count == wanted
            problem = nil
        } catch {
            problem = NSLocalizedString("Doddy couldn't read your recordings. Nothing was changed.", comment: "")
        }
        hasLoaded = true
    }

    func loadMore() async {
        guard let repository, hasMore else { return }
        do {
            let next = try await repository.recordings(category: category, limit: pageSize, offset: items.count)
            items += next
            hasMore = next.count == pageSize
        } catch {
            problem = NSLocalizedString("Doddy couldn't read your recordings. Nothing was changed.", comment: "")
        }
    }

    /// Deletes every recording, its words and its audio. One being made is stopped and saved first.
    func deleteAll() async -> Bool {
        guard let repository else { return false }
        await RecordingCoordinator.shared.stop()
        do {
            try await repository.deleteAll()
            AppEnvironment.shared.recordingFiles.removeAll()
            items = []
            hasMore = false
            return true
        } catch {
            problem = NSLocalizedString("Doddy couldn't delete your recordings. They are still on this iPhone.", comment: "")
            return false
        }
    }

    /// Deletes the recording, its words and its audio. False if it is the one being made now.
    func delete(_ id: UUID) async -> Bool {
        guard let repository, RecordingCoordinator.shared.session?.id != id else { return false }
        do {
            _ = try await repository.delete(id: id)
            AppEnvironment.shared.recordingFiles.remove(recordingID: id)
            items.removeAll { $0.recording.id == id }
            return true
        } catch {
            problem = NSLocalizedString("Doddy couldn't delete that recording. Nothing was changed.", comment: "")
            return false
        }
    }
}
