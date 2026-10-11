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
    /// Notes the server holds but can't read any more; they can only be discarded.
    private(set) var unreadableNotes: [UnreadableCallNote] = []
    /// Why the notes from calls couldn't be loaded, or nil. A failed load is never shown as "no notes".
    private(set) var notesProblem: String?
    /// Notes already saved as memories whose removal from the inbox failed. Tapping Save again
    /// only retries the removal, so the memory isn't saved twice (DOD-06).
    private(set) var savedNoteIDs: Set<UUID> = []
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
            if settings.available.inbound {
                do {
                    let inbox = try await client.callInbox()
                    self.notes = inbox.notes
                    self.unreadableNotes = inbox.unreadable
                    self.notesProblem = nil
                } catch {
                    self.notesProblem = String(
                        format: NSLocalizedString("Couldn't load the notes from your calls. %@", comment: ""), Self.text(for: error))
                }
            } else {
                self.notes = []
                self.unreadableNotes = []
                self.notesProblem = nil
            }
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
    /// If the upload fails after the server switched the copy on, the switch shows on (as the
    /// server reports), the message says the memories aren't copied yet, and the upload is tried
    /// again when Doddy next comes to the front (DOD-08/11).
    func setMemoryCopy(_ on: Bool, records: [MemoryRecord]) async {
        await change { client in
            try await client.setMemoryCopy(enabled: on)
            UserDefaults.standard.set(on, forKey: PreferenceKey.memoryCopyOn)
            if on {
                do {
                    try await MemoryCopySync.shared.uploadNow(records)
                } catch {
                    self.message = String(
                        format: NSLocalizedString("Memory on calls is on, but your memories aren't copied yet: %@ Doddy tries again the next time you open it, or turn this off to delete the copy.", comment: ""),
                        Self.text(for: error))
                }
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
            if !self.savedNoteIDs.contains(note.id) {
                _ = try await store.save(
                    text: note.text, category: .other, source: .explicitVoice, capturedAt: note.createdDate ?? Date())
                self.savedNoteIDs.insert(note.id)
            }
            do {
                try await client.deleteCallNote(note.id)
                self.notes.removeAll { $0.id == note.id }
                self.savedNoteIDs.remove(note.id)
            } catch {
                self.message = NSLocalizedString("Saved to your memories, but it couldn't be removed from this list. Tap Discard to remove it.", comment: "")
            }
        }
    }

    /// Removes a note from the inbox, readable or not.
    func discard(_ id: UUID) async {
        guard let client else { return }
        await run {
            try await client.deleteCallNote(id)
            self.notes.removeAll { $0.id == id }
            self.unreadableNotes.removeAll { $0.id == id }
            self.savedNoteIDs.remove(id)
        }
    }

    /// Writes, then shows what the server now holds. The settings are read back even when the
    /// write failed, since it may have half happened (the copy switched on, then the upload
    /// failed), and a failed read-back after a good write never reads as "nothing changed" (DOD-08).
    private func change(_ work: @escaping (DoddyServerClient) async throws -> Void) async {
        guard let client else { return }
        await run {
            var failure: (any Error)?
            do {
                try await work(client)
            } catch {
                failure = error
            }
            do {
                let settings = try await client.callSettings()
                self.settings = settings
                UserDefaults.standard.set(settings.memoryCopy.enabled, forKey: PreferenceKey.memoryCopyOn)
            } catch {
                if failure == nil { self.message = UpdatesModel.savedButNotReadBack }
            }
            if let failure { throw failure }
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
        case .notEnabled("no_verified_phone"): NSLocalizedString("Verify your phone number first, in Settings → Notifications and texts.", comment: "")
        case .notEnabled("outbound_not_enabled"): NSLocalizedString("Turn on \"Doddy may call me\" first.", comment: "")
        case .rateLimited: NSLocalizedString("That's the limit for calls for now. Try again later.", comment: "")
        case .notConfigured: NSLocalizedString("Doddy's phone line isn't set up on the server yet.", comment: "")
        default: UpdatesModel.text(for: error)
        }
    }
}
