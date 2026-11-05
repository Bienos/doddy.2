import DoddyCore
import Foundation
import Observation

/// The state behind Settings › Connections › Training log (sport plan stage 3, ADR-642): whether the
/// person said yes to keeping a log, the sessions kept, the weekly review of them and a file to take
/// away. All rules live in DoddyCore (`TrainingLogRepository`, `TrainingReview`); this class only asks
/// the store and keeps what it answered. It does not open the store until the person needs it, so
/// nothing is created on a phone where the log was never turned on. Nothing here leaves the iPhone.
@MainActor
@Observable
final class TrainingLogModel {
    private(set) var consent: TrainingLogConsent = .neverAsked
    /// Newest first.
    private(set) var sessions: [LoggedSession] = []
    private(set) var review: TrainingReviewResult?
    /// Why the last action couldn't be confirmed, in words for the screen.
    private(set) var problem: String?
    /// The export file, once made. Removed when the screen goes away.
    private(set) var exportURL: URL?
    private(set) var isLoaded = false

    @ObservationIgnored private var repository: (any TrainingLogRepository)?
    @ObservationIgnored private let storeExists: () -> Bool
    @ObservationIgnored private let open: () throws -> any TrainingLogRepository
    @ObservationIgnored private let plan: @MainActor () -> TrainingPlan?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let exportDirectory: URL

    init(open: @escaping () throws -> any TrainingLogRepository, storeExists: @escaping () -> Bool,
         plan: @escaping @MainActor () -> TrainingPlan? = { nil }, now: @escaping () -> Date = { .now },
         exportDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("training-log-export", isDirectory: true)) {
        self.open = open
        self.storeExists = storeExists
        self.plan = plan
        self.now = now
        self.exportDirectory = exportDirectory
    }

    // MARK: Reading

    /// Reads what is kept. With no store on the phone and none opened yet, nothing is read or created.
    func load() async {
        guard repository != nil || storeExists() else {
            consent = .neverAsked
            sessions = []
            review = nil
            isLoaded = true
            return
        }
        await refresh()
    }

    /// The review in words, in the app's language where the review has one (Polish or English).
    func reviewText(language: NotificationLanguage = .current) -> String? {
        review.map { TrainingReview.message($0, language: language) }
    }

    // MARK: Acting

    /// The yes, or taking it back. Taking it back stops saving; it does not delete.
    func setKeeping(_ on: Bool) async {
        do {
            let store = try store()
            if on {
                consent = try await store.grantConsent()
            } else {
                consent = try await store.withdrawConsent()
            }
            problem = nil
        } catch {
            problem = Self.message(error)
        }
        await refresh()
    }

    /// True only when the session was saved and read back.
    @discardableResult
    func record(_ session: LoggedSession) async -> Bool {
        do {
            _ = try await store().record(session)
            await refresh()
            return true
        } catch {
            problem = Self.message(error)
            return false
        }
    }

    func delete(_ id: UUID) async {
        do {
            try await store().delete(id: id)
            problem = nil
        } catch {
            problem = Self.message(error)
        }
        await refresh()
    }

    /// True only when nothing is left. The yes stays as it was.
    @discardableResult
    func deleteAll() async -> Bool {
        do {
            _ = try await store().deleteAll()
            problem = nil
            await refresh()
            return true
        } catch {
            problem = Self.message(error)
            await refresh()
            return false
        }
    }

    // MARK: Export

    /// Writes everything kept to one JSON file the person can share. It is read back before it is offered.
    func prepareExport() async {
        do {
            let data = try await store().export().json()
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            let url = exportDirectory.appendingPathComponent("doddy-training-log.json")
            try data.write(to: url, options: Self.exportOptions)
            guard let back = try? Data(contentsOf: url), back == data else { throw CocoaError(.fileWriteUnknown) }
            exportURL = url
            problem = nil
        } catch {
            exportURL = nil
            problem = Self.message(error)
        }
    }

    /// The file is a copy of health data: it does not stay in the temporary folder.
    func discardExport() {
        try? FileManager.default.removeItem(at: exportDirectory)
        exportURL = nil
    }

    // MARK: Pieces

    private func store() throws -> any TrainingLogRepository {
        if let repository { return repository }
        let opened = try open()
        repository = opened
        return opened
    }

    private func refresh() async {
        do {
            let store = try store()
            consent = try await store.consent()
            sessions = try await store.sessions(from: nil)
            review = TrainingReview.review(sessions: sessions, plan: plan(), now: now())
        } catch {
            problem = Self.message(error)
        }
        isLoaded = true
    }

    private static var exportOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtection]
        #else
        [.atomic]
        #endif
    }

    /// Words for the screen. The store's errors say what rule was broken; none is shown as a code.
    nonisolated static func message(_ error: Error) -> String {
        guard let error = error as? TrainingLogError else {
            return String(format: NSLocalizedString("The training log couldn't be opened (%@).", comment: ""),
                          error.localizedDescription)
        }
        switch error {
        case .consentMissing:
            return NSLocalizedString("Turn on the training log first. Nothing was saved.", comment: "")
        case .invalid(.emptySession):
            return NSLocalizedString("Add at least one set, or the minutes you ran.", comment: "")
        case .invalid(.tooManySets):
            return NSLocalizedString("A session can have up to 40 sets.", comment: "")
        case .invalid(.inTheFuture):
            return NSLocalizedString("The day can't be more than one day ahead.", comment: "")
        case .invalid:
            return NSLocalizedString("A number is out of range. Reps 0 to 200, weight 0 to 500 kg, reps left 0 to 10, minutes 1 to 600.", comment: "")
        case .notFound:
            return NSLocalizedString("That session is already gone.", comment: "")
        case .verificationFailed:
            return NSLocalizedString("Doddy couldn't confirm that was saved on this iPhone. Nothing was kept.", comment: "")
        case .corruptRecord:
            return NSLocalizedString("A saved session couldn't be read. It is still on this iPhone; delete the log to start again.", comment: "")
        }
    }
}
