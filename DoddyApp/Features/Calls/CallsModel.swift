import DoddyCore
import Foundation
import Observation

/// State for Settings → Phone calls. Shows only what the server reported.
@MainActor
@Observable
final class CallsModel {
    private(set) var client: DoddyServerClient?
    private(set) var settings: CallSettings?
    private(set) var notes: [CallNote] = []
    private(set) var recent: [CallRecord] = []
    private(set) var isWorking = false
    private(set) var message: String?

    init() {
        client = ServerConfig.client()
    }

    var isServerConfigured: Bool { client != nil }

    func refresh() async {
        guard let client else { return }
        await run {
            let settings = try await client.callSettings()
            self.settings = settings
            self.recent = (try? await client.recentCalls()) ?? []
            self.notes = settings.available.inbound ? ((try? await client.callNotes()) ?? []) : []
            // The server is the source of truth for whether a copy exists.
            UserDefaults.standard.set(settings.memoryCopy.enabled, forKey: PreferenceKey.memoryCopyOn)
        }
    }

    func setPIN(_ pin: String) async {
        guard CallPIN.isAcceptable(pin) else {
            message = UpdatesModel.text(for: ServerError.weakPIN)
            return
        }
        await change { try await $0.setCallPIN(pin) }
    }

    func removePIN() async { await change { try await $0.removeCallPIN() } }
    func setInbound(_ on: Bool) async { await change { try await $0.setInboundCalls(on) } }
    func setOutbound(_ on: Bool) async { await change { try await $0.setOutboundConsent(on) } }

    /// On: switch the copy on, then upload what is on the phone now. Off: the server deletes it.
    func setMemoryCopy(_ on: Bool, records: [MemoryRecord]) async {
        await change { client in
            try await client.setMemoryCopy(enabled: on)
            UserDefaults.standard.set(on, forKey: PreferenceKey.memoryCopyOn)
            if on {
                try await client.replaceMemoryCopy(MemoryCopyItem.from(records))
            } else {
                MemoryCopySync.shared.stop()
            }
        }
    }

    func callMeNow() async {
        guard let client else { return }
        await run {
            let request = try await client.callMeNow()
            self.message = request.status == "requested"
                ? "Doddy is calling you now."
                : "Couldn't confirm the call was placed. Doddy won't redial on its own. Wait a minute before trying again."
            self.recent = (try? await client.recentCalls()) ?? self.recent
        }
    }

    /// Saves the note as a memory (as said on the call, at that time), then removes it from the inbox.
    func keep(_ note: CallNote, into store: MemoryStore) async {
        guard let client else { return }
        await run {
            _ = try await store.save(
                text: note.text, category: .other, source: .explicitVoice, capturedAt: note.createdDate ?? Date())
            do {
                try await client.deleteCallNote(note.id)
                self.notes.removeAll { $0.id == note.id }
            } catch {
                self.message = "Saved to your memories, but it couldn't be removed from this list. Tap Discard to remove it."
            }
        }
    }

    func discard(_ note: CallNote) async {
        guard let client else { return }
        await run {
            try await client.deleteCallNote(note.id)
            self.notes.removeAll { $0.id == note.id }
        }
    }

    private func change(_ work: @escaping (DoddyServerClient) async throws -> Void) async {
        guard let client else { return }
        await run {
            try await work(client)
            self.settings = try await client.callSettings()
        }
    }

    private func run(_ work: @MainActor () async throws -> Void) async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            message = Self.text(for: error)
        }
    }

    static func text(for error: any Error) -> String {
        switch error as? ServerError {
        case .notEnabled("no_verified_phone"): "Verify your phone number first, in Settings → Notifications and texts."
        case .notEnabled("outbound_not_enabled"): "Turn on \"Doddy may call me\" first."
        case .rateLimited: "That's the limit for calls for now. Try again later."
        case .notConfigured: "Doddy's phone line isn't set up on the server yet."
        default: UpdatesModel.text(for: error)
        }
    }
}
