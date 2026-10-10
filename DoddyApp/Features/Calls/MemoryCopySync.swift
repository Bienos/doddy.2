import DoddyCore
import Foundation
import Observation

/// Keeps the opt-in server copy of memories (used only to answer on phone calls) equal to what
/// is on this iPhone. Every change sends the full current list, so deletions and corrections
/// carry over. Does nothing unless the user turned on "Memory on calls".
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

    var isOn: Bool { UserDefaults.standard.bool(forKey: PreferenceKey.memoryCopyOn) }

    func schedule(_ records: [MemoryRecord], delay: Duration = .seconds(2)) {
        guard isOn, let client = ServerConfig.client() else { return }
        pending?.cancel()
        let items = MemoryCopyItem.from(records)
        pending = Task {
            // Collapses bursts of edits into one upload.
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            do {
                let count = try await client.replaceMemoryCopy(items)
                status = .copied(count: count, at: Date())
            } catch ServerError.notEnabled {
                // The server has no copy switched on (e.g. the server data was deleted): stop sending.
                UserDefaults.standard.set(false, forKey: PreferenceKey.memoryCopyOn)
                status = .idle
            } catch {
                status = .failed(UpdatesModel.text(for: error))
            }
        }
    }

    func stop() {
        pending?.cancel()
        status = .idle
    }
}
