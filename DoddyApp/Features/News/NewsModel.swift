import DoddyCore
import Foundation
import Observation

/// State for Settings → Daily news. Edits are a local draft until "Save" succeeds.
@MainActor
@Observable
final class NewsModel {
    struct OwnTopic: Identifiable, Equatable {
        let id = UUID()
        var label: String
        var keywordsText: String
    }

    private(set) var client: DoddyServerClient?
    private(set) var loaded: NewsSettings?
    private(set) var catalog: [NewsCatalogTopic] = []
    private(set) var digests: [NewsDigest] = []
    private(set) var isWorking = false
    private(set) var message: String?

    // Draft
    var enabled = false
    var selectedCatalog: [String] = []
    var ownTopics: [OwnTopic] = []
    var feeds: [String] = []
    var sendTime = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    var push = true
    var sms = false
    var language = "en"

    init() {
        client = ServerConfig.client()
    }

    var isServerConfigured: Bool { client != nil }

    func refresh() async {
        guard let client else { return }
        await run {
            let settings = try await client.newsSettings()
            self.apply(settings)
            self.catalog = try await client.newsCatalog(language: settings.language)
            self.digests = (try? await client.newsDigests()) ?? []
        }
    }

    func toggleCatalog(_ id: String) {
        if let i = selectedCatalog.firstIndex(of: id) { selectedCatalog.remove(at: i) } else { selectedCatalog.append(id) }
    }

    /// Checks the address on the server (reachable, really a feed) before adding it to the draft.
    func addFeed(_ raw: String) async {
        guard let client else { return }
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !feeds.contains(url) else { return }
        await run {
            let check = try await client.checkFeed(url)
            self.feeds.append(url)
            self.message = "Added \(check.title) (\(check.items) stories right now). Tap Save to keep it."
        }
    }

    func save() async {
        guard let client else { return }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: sendTime)
        let topics = selectedCatalog.compactMap { id in catalog.first { $0.id == id }.map { NewsTopic(catalogId: $0.id, label: $0.label) } }
            + ownTopics.compactMap { t in
                let keywords = NewsTopic.keywords(from: t.keywordsText)
                let label = t.label.trimmingCharacters(in: .whitespacesAndNewlines)
                return keywords.isEmpty || label.isEmpty ? nil : NewsTopic(label: label, keywords: keywords)
            }
        let update = NewsSettingsUpdate(
            enabled: enabled,
            sendTime: String(format: "%02d:%02d", parts.hour ?? 8, parts.minute ?? 0),
            timezone: TimeZone.current.identifier,
            channels: (push ? [UpdateChannel.push] : []) + (sms ? [.sms] : []),
            language: language, topics: topics, feeds: feeds)
        await run {
            try await client.saveNewsSettings(update)
            self.apply(try await client.newsSettings())
            self.catalog = try await client.newsCatalog(language: self.language)
            // No channel chosen: the digest is kept here in the app and nothing is sent (ADR-174).
            let whereText = update.channels.isEmpty ? " It will be here in the app; nothing is sent to you." : ""
            self.message = self.enabled
                ? "Saved. Your next news is \(self.nextRunText ?? "scheduled").\(whereText)"
                : "Saved. Daily news is off."
        }
    }

    func sendNow() async {
        guard let client else { return }
        await run {
            let result = try await client.sendNewsNow()
            self.message = switch result.status {
            case "queued": "On its way\(result.aiWritten ? "" : " (headlines only)"). It appears below too."
            case "ready": result.errorCode == "no_channel"
                ? "It's below. Nothing was sent: notifications or texts aren't on for this iPhone."
                : "It's below\(result.aiWritten ? "" : " (headlines only)")."
            case "empty": NSLocalizedString("Nothing new for your topics right now.", comment: "")
            // The request may have reached the server, but no answer came back (DOD-08).
            case "unknown": NSLocalizedString("Couldn't confirm whether your news was built. It may still arrive, and Doddy won't send it again on its own. Wait a few minutes before trying again.", comment: "")
            default: "Couldn't build your news right now. Try again later."
            }
            self.digests = (try? await client.newsDigests()) ?? self.digests
        }
    }

    var nextRunText: String? {
        guard let raw = loaded?.nextRunAt, let date = ServerDates.parse(raw) else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func apply(_ s: NewsSettings) {
        loaded = s
        enabled = s.enabled
        selectedCatalog = s.topics.compactMap(\.catalogId)
        ownTopics = s.topics.filter { $0.catalogId == nil }.map { OwnTopic(label: $0.label, keywordsText: $0.keywords.joined(separator: ", ")) }
        feeds = s.feeds.map(\.url)
        push = s.channels.contains(.push)
        sms = s.channels.contains(.sms)
        language = s.language
        let hm = s.sendTime.split(separator: ":").compactMap { Int($0) }
        if hm.count == 2, let date = Calendar.current.date(from: DateComponents(hour: hm[0], minute: hm[1])) { sendTime = date }
    }

    private func run(_ work: @MainActor () async throws -> Void) async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch ServerError.notEnabled("push_not_enabled") {
            message = NSLocalizedString("Turn on notifications first, in Notifications and texts.", comment: "")
        } catch ServerError.notEnabled("sms_not_enabled") {
            message = NSLocalizedString("Turn on texts first, in Notifications and texts.", comment: "")
        } catch ServerError.notEnabled("no_topics") {
            message = NSLocalizedString("Pick at least one topic or feed.", comment: "")
        } catch {
            message = UpdatesModel.text(for: error)
        }
    }
}
