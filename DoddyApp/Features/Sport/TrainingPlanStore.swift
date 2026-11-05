import DoddyCore
import Foundation
import Observation

/// The training plan the person kept (sport mode step 4, ADR-625): one plan, as JSON in the app's
/// protected container. Every write is read back before the screen says it's kept, and a file that
/// isn't exactly the plan Doddy's engine makes for its answers is never shown as Doddy's. Nothing
/// here leaves the iPhone: not sent, not synced, and its folder is left out of iCloud and computer
/// backups.
@MainActor
@Observable
final class TrainingPlanStore {
    static let shared = TrainingPlanStore()

    enum State: Equatable {
        case nothingKept
        case plan(SavedTrainingPlan)
        /// The file reads, but it isn't this Doddy's plan for its answers (an older version made it,
        /// or it was changed). It stays until the person deletes it or keeps a new plan.
        case notThisDoddysPlan
        /// The file can't be read. Not written over until the person decides.
        case unreadable
    }

    private(set) var state: State = .nothingKept
    /// Why the last save or delete couldn't be confirmed.
    private(set) var problem: String?
    private let fileURL: URL?

    init(fileURL: URL? = TrainingPlanStore.defaultURL()) {
        self.fileURL = fileURL
        load()
    }

    var saved: SavedTrainingPlan? {
        if case .plan(let saved) = state { return saved }
        return nil
    }

    func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            state = .nothingKept
            return
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            state = .unreadable
            return
        }
        switch SavedTrainingPlan.read(data) {
        case .plan(let saved): state = .plan(saved)
        case .notThisDoddysPlan: state = .notThisDoddysPlan
        case .unreadable: state = .unreadable
        }
    }

    /// True only when the plan was written and read back exactly. It replaces a plan kept before.
    @discardableResult
    func keep(_ plan: TrainingPlan, start: PlanStart, now: Date = .now) -> Bool {
        guard let fileURL else {
            problem = NSLocalizedString("Doddy has no place on this iPhone to keep a plan. Nothing was kept.", comment: "")
            return false
        }
        let saved = SavedTrainingPlan(plan: plan, start: start, savedAt: now)
        do {
            var folder = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Health data stays out of iCloud, backups included (App Store 5.1.3).
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            try saved.encoded().write(to: fileURL, options: Self.writeOptions)
            guard let back = try? Data(contentsOf: fileURL), SavedTrainingPlan.read(back) == .plan(saved) else {
                throw CocoaError(.fileWriteUnknown)
            }
            state = .plan(saved)
            problem = nil
            return true
        } catch {
            load()
            problem = String(format: NSLocalizedString("Doddy couldn't confirm the plan was kept on this iPhone (%@). Check below what is kept now.", comment: ""),
                             error.localizedDescription)
            return false
        }
    }

    /// True only when the file is gone.
    @discardableResult
    func delete() -> Bool {
        guard let fileURL else { return true }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            guard !FileManager.default.fileExists(atPath: fileURL.path) else { throw CocoaError(.fileWriteUnknown) }
            state = .nothingKept
            problem = nil
            return true
        } catch {
            load()
            problem = String(format: NSLocalizedString("Doddy couldn't delete the plan from this iPhone (%@). It is still kept.", comment: ""),
                             error.localizedDescription)
            return false
        }
    }

    /// Readable only while the iPhone is unlocked: the answers behind a plan are health data.
    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtection]
        #else
        [.atomic]
        #endif
    }

    /// Application Support/Sport/training-plan.json. UI-test launches get a new file each time.
    private static func defaultURL() -> URL? {
        let fileManager = FileManager.default
        if ProcessInfo.processInfo.arguments.contains("-inMemoryStore") {
            return fileManager.temporaryDirectory.appendingPathComponent("training-plan-\(UUID().uuidString).json")
        }
        guard let support = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        return support.appendingPathComponent("Sport", isDirectory: true).appendingPathComponent("training-plan.json")
    }
}
