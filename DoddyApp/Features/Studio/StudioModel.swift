import DoddyCore
import Foundation
import Observation

// Studio (S0, ADR-584, docs/implementation/STUDIO.md): research briefs and infographics Doddy's
// server makes in the background and keeps until the user deletes them. The rules live in DoddyCore
// and on the server, which checks everything again. Nothing here says a job started, is ready or
// was deleted unless the server said so: a job whose approval answer never came back is "unknown",
// a file is opened only when its bytes are the ones the server described, and an item is called
// deleted only when the server said so and a fresh read of the list no longer has it.
//
// Free of SwiftUI and UIKit so it is type-checked on Linux (scripts/typecheck_app_logic.sh); the
// shared instance, which needs the app's server settings, is made in StudioView.swift.

/// What Studio needs from Doddy's messaging server: `DoddyServerClient`.
protocol StudioBackend: Sendable {
    /// True once this iPhone has an account on the messaging server. Checking never creates one.
    func hasAccount() async -> Bool
    func createStudioJob(_ job: StudioJob) async throws -> StudioPreview
    func approveStudioJob(_ id: UUID, digest: String) async throws -> StudioApproval
    func studioItems() async throws -> [StudioItemSummary]
    func studioItem(_ id: UUID) async throws -> StudioItem
    func studioFile(_ id: UUID, _ file: StudioFile) async throws -> Data
    func cancelStudioJob(_ id: UUID) async throws
    func deleteStudioItem(_ id: UUID) async throws -> StudioDeletion
}

extension DoddyServerClient: StudioBackend {}

@MainActor
@Observable
final class StudioModel {
    private let backendProvider: @MainActor () -> (any StudioBackend)?
    private var backend: (any StudioBackend)? { backendProvider() }
    private let defaults: UserDefaults
    /// Where opened files are kept for Quick Look and Share (the app's Caches folder). Never the
    /// only copy: the server has them until the user deletes the item.
    private let cacheDirectory: URL
    /// After the first job the user allows: ask for notifications, so "ready" can reach them.
    private let afterJobStarted: @MainActor () async -> Void

    /// Newest first, as the server listed them.
    private(set) var items: [StudioItemSummary] = []
    /// Items opened in this session, as the server last described them.
    private(set) var details: [UUID: StudioItem] = [:]
    /// Why the list couldn't be read. A failed read never shows as "nothing in Studio".
    private(set) var loadProblem: String?
    private(set) var hasLoaded = false
    private(set) var isRefreshing = false
    var message: String?

    /// The topic of each job allowed on this iPhone, shown until the server has a title. Ids and
    /// topics only, in UserDefaults; cleared with Delete everything.
    private(set) var topics: [String: String]
    private static let topicsKey = "studio.topics"

    init(backend: @escaping @MainActor () -> (any StudioBackend)?, defaults: UserDefaults = .standard, cacheDirectory: URL,
         afterJobStarted: @escaping @MainActor () async -> Void = {}) {
        self.backendProvider = backend
        self.defaults = defaults
        self.cacheDirectory = cacheDirectory
        self.afterJobStarted = afterJobStarted
        topics = defaults.dictionary(forKey: Self.topicsKey) as? [String: String] ?? [:]
    }

    var isServerConfigured: Bool { backend != nil }

    /// The title the server gave it, else the topic as the user said it, else a placeholder.
    func displayTitle(_ id: UUID, title: String?) -> String {
        if let title, !title.isEmpty { return title }
        if let topic = topics[id.uuidString] { return topic }
        return NSLocalizedString("Untitled", comment: "")
    }

    /// Something is still being made, so coming to the front asks again.
    var hasOpenItems: Bool { items.contains { $0.state.isOpen } }

    // MARK: The voice tool, after the user's yes

    /// Creates the job on the server and approves it with the digest of exactly this job. The
    /// returned text is the tool result for the agent. Never approves twice, never retries.
    func make(_ job: StudioJob) async -> String {
        guard let backend else { return VoiceToolReply.studioNotStarted(StudioError.studioDisabled) }
        let preview: StudioPreview
        do {
            preview = try await backend.createStudioJob(job)
        } catch {
            return VoiceToolReply.studioNotStarted(error)
        }
        // The client already compared the echo; checked again here so nothing else can approve it.
        guard preview.matches(job) else { return VoiceToolReply.studioNotStarted(StudioError.previewMismatch) }
        let approval: StudioApproval
        do {
            approval = try await backend.approveStudioJob(preview.id, digest: job.digest)
        } catch {
            return VoiceToolReply.studioNotStarted(error)
        }
        remember(topic: job.topic, for: preview.id)
        Task { await self.afterJobStarted() }
        Task { await self.refresh() }
        return approval.isConfirmed ? VoiceToolReply.studioStarted(job) : VoiceToolReply.studioMaybeStarted(job)
    }

    // MARK: Reading

    /// Reads the list from the server. Called when Studio opens, when Doddy comes to the front
    /// while something is being made, and after a job starts. Never makes a server account for
    /// someone who has never used Studio.
    func refresh() async {
        guard let backend, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let hasAccount = await backend.hasAccount()
        guard !topics.isEmpty || hasAccount else {
            hasLoaded = true
            return
        }
        do {
            items = try await backend.studioItems()
            loadProblem = nil
        } catch {
            loadProblem = Self.describe(error)
        }
        hasLoaded = true
    }

    /// The item's full description from the server.
    func open(_ id: UUID) async {
        guard let backend else { return }
        do {
            details[id] = try await backend.studioItem(id)
            message = nil
        } catch StudioError.notFound {
            details[id] = nil
            items.removeAll { $0.id == id }
            message = NSLocalizedString("This item isn't on Doddy's server any more.", comment: "")
        } catch {
            message = Self.describe(error)
        }
    }

    /// A local copy of one file for Quick Look and Share. Downloaded once, checked against the
    /// server's size and SHA-256 (in the client), written atomically; nil with a message otherwise.
    func localFile(_ id: UUID, _ file: StudioFile) async -> URL? {
        guard file.hasSafeName, let backend else { return nil }
        let folder = cacheDirectory.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let url = folder.appendingPathComponent(file.name, isDirectory: false)
        if let data = try? Data(contentsOf: url), data.count == file.bytes, StudioFileCheck.sha256(data) == file.sha256.lowercased() {
            return url
        }
        do {
            let data = try await backend.studioFile(id, file)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            message = Self.describe(error)
            return nil
        }
    }

    // MARK: The user's actions

    func cancel(_ id: UUID) async {
        guard let backend else { return }
        do {
            try await backend.cancelStudioJob(id)
        } catch {
            message = Self.describe(error)
            return
        }
        await refresh()
        await open(id)
    }

    /// Deletes the item on the server, then reads the list back. Said to be deleted only when the
    /// server said so and the list no longer has it; the copies kept here go after that.
    func delete(_ id: UUID) async -> Bool {
        guard let backend else {
            message = NSLocalizedString("Doddy's server isn't set up in this build, so this item can't be deleted from here.", comment: "")
            return false
        }
        let deletion: StudioDeletion
        do {
            deletion = try await backend.deleteStudioItem(id)
        } catch {
            message = Self.describe(error)
            return false
        }
        let listAfter = try? await backend.studioItems()
        guard StudioDeleteRule.isDeleted(id, serverSaid: deletion.deleted, listAfter: listAfter) else {
            message = NSLocalizedString("Doddy's server didn't confirm the item is gone, so it isn't shown as deleted. Pull down to check again.", comment: "")
            if let listAfter { items = listAfter }
            return false
        }
        items = listAfter ?? items.filter { $0.id != id }
        details[id] = nil
        forgetCopies(of: id)
        message = StudioDeleteRule.confirmation(deletion, language: .current)
        return true
    }

    /// Delete everything on this iPhone: the topics and the opened copies. The items themselves are
    /// on Doddy's server until they're deleted in Studio.
    func forgetLocal() {
        topics = [:]
        defaults.removeObject(forKey: Self.topicsKey)
        try? FileManager.default.removeItem(at: cacheDirectory)
        details = [:]
    }

    // MARK: Plumbing

    private func remember(topic: String, for id: UUID) {
        topics[id.uuidString] = topic
        defaults.set(topics, forKey: Self.topicsKey)
    }

    private func forgetCopies(of id: UUID) {
        topics[id.uuidString] = nil
        defaults.set(topics, forKey: Self.topicsKey)
        try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true))
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case StudioError.studioDisabled:
            return NSLocalizedString("Studio is switched off or not set up on Doddy's server.", comment: "")
        case StudioError.dailyCapReached:
            return NSLocalizedString("Today's spending limit for Studio is reached. Try again tomorrow.", comment: "")
        case StudioError.tooManyOpenItems:
            return NSLocalizedString("Doddy is already making as many things as the server allows. Try again when one is ready.", comment: "")
        case StudioError.fileRefused:
            return NSLocalizedString("The file that arrived isn't the one Doddy's server described, so it isn't opened.", comment: "")
        case StudioError.notFound:
            return NSLocalizedString("This item isn't on Doddy's server any more.", comment: "")
        case StudioError.conflict, StudioError.notApprovable:
            return NSLocalizedString("That couldn't be done: the item has already finished or changed. Pull down to check again.", comment: "")
        case StudioError.server(.offline), ServerError.offline:
            return NSLocalizedString("Doddy's server couldn't be reached. Check your internet connection.", comment: "")
        default:
            return UserFacingError.message(for: error)
        }
    }
}
