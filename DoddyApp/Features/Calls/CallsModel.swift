import DoddyCore
import Foundation
import Observation

/// State for Settings → Phone calls. Shows only what the server reported.
@MainActor
@Observable
final class CallsModel {
    private(set) var client: DoddyServerClient?
    private(set) var settings: CallSettings?
    /// Texts to Doddy (ADR-494); nil until the server answered.
    private(set) var textSettings: TextSettings?
    /// Why the texts settings couldn't be loaded, or nil. A failed load never reads as "not set up".
    private(set) var textsProblem: String?
    /// The exported history, ready to share, after Export phone and text history.
    private(set) var historyFile: URL?
    private(set) var notes: [CallNote] = []
    /// Notes the server holds but can't read any more; they can only be discarded.
    private(set) var unreadableNotes: [UnreadableCallNote] = []
    /// Why the notes from calls couldn't be loaded, or nil. A failed load is never shown as "no notes".
    private(set) var notesProblem: String?
    /// Notes already saved as memories whose removal from the inbox failed. Tapping Save again
    /// only retries the removal, so the memory isn't saved twice (DOD-06).
    private(set) var savedNoteIDs: Set<UUID> = []
    private(set) var recent: [CallRecord] = []
    /// Calls booked for later (ADR-495), newest first, as the server lists them.
    private(set) var scheduled: [ScheduledCall] = []
    /// Why the booked calls couldn't be loaded, or nil. A failed load is never shown as "none".
    private(set) var scheduledProblem: String?
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
            await self.loadScheduled(client, settings: settings)
            do {
                let texts = try await client.textSettings()
                self.textSettings = texts
                self.textsProblem = nil
                Self.mirror(texts)
            } catch {
                self.textsProblem = String(
                    format: NSLocalizedString("Couldn't load the settings for texts to Doddy. %@", comment: ""), Self.text(for: error))
            }
            // The inbox holds notes from calls and from texts (ADR-494).
            if settings.available.inbound || self.textSettings?.available.notes == true {
                do {
                    let inbox = try await client.callInbox()
                    self.notes = inbox.notes
                    self.unreadableNotes = inbox.unreadable
                    self.notesProblem = nil
                } catch {
                    self.notesProblem = String(
                        format: NSLocalizedString("Couldn't load your notes. %@", comment: ""), Self.text(for: error))
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

    // MARK: Texts to Doddy (ADR-494)

    func setTextsToDoddy(_ on: Bool) async { await changeTexts { try await $0.setTextsToDoddy(on, language: .current) } }
    func setTextReplies(_ on: Bool) async { await changeTexts { try await $0.setTextReplies(on, language: .current) } }
    func setTextRepliesUseMemories(_ on: Bool) async { await changeTexts { try await $0.setTextRepliesUseMemories(on) } }

    /// Writes, then reads back what the server now holds, as `change` does for calls.
    private func changeTexts(_ work: @escaping (DoddyServerClient) async throws -> Void) async {
        guard let client else { return }
        await run {
            var failure: (any Error)?
            do {
                try await work(client)
            } catch {
                failure = error
            }
            do {
                let texts = try await client.textSettings()
                self.textSettings = texts
                self.textsProblem = nil
                Self.mirror(texts)
            } catch {
                if failure == nil { self.message = UpdatesModel.savedButNotReadBack }
            }
            if let failure { throw failure }
        }
    }

    /// What leaves this iPhone reads these; the server's answer is the only source.
    private static func mirror(_ texts: TextSettings) {
        UserDefaults.standard.set(texts.inboundEnabled, forKey: PreferenceKey.textsToDoddyOn)
        UserDefaults.standard.set(texts.inboundEnabled && texts.repliesEnabled, forKey: PreferenceKey.textRepliesOn)
    }

    /// The server's JSON, saved to a file this iPhone shares from. Nothing else is added to it.
    func exportHistory() async {
        guard let client else { return }
        clearExport()
        await run {
            let data = try await client.phoneHistory()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Doddy phone and text history.json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            self.historyFile = url
        }
    }

    /// The export holds the phone number and the waiting notes: it isn't left behind.
    func clearExport() {
        if let file = historyFile { try? FileManager.default.removeItem(at: file) }
        historyFile = nil
    }

    func callMeNow() async {
        guard let client else { return }
        await run {
            let request: CallRequest
            do {
                request = try await client.callMeNow()
            } catch ServerError.providerUnavailable {
                // 502: the phone service turned the call down, so no call was placed.
                self.message = NSLocalizedString("The phone service couldn't place the call, so Doddy isn't calling. Try again in a few minutes.", comment: "")
                return
            }
            self.message = request.status == "requested"
                ? "Doddy is calling you now."
                : "Couldn't confirm the call was placed. Doddy won't redial on its own. Wait a minute before trying again."
            self.recent = (try? await client.recentCalls()) ?? self.recent
        }
    }

    // MARK: Calls booked for later (ADR-495)

    /// The list, and the iPhone's zone when a call is waiting and the server has another one, so
    /// quiet hours are checked where the user is now. The zone is sent only then.
    private func loadScheduled(_ client: DoddyServerClient, settings: CallSettings) async {
        guard settings.available.outbound else {
            scheduled = []
            scheduledProblem = nil
            return
        }
        do {
            scheduled = try await client.scheduledCalls()
            scheduledProblem = nil
        } catch {
            scheduledProblem = String(format: NSLocalizedString("Couldn't load your booked calls. %@", comment: ""), Self.text(for: error))
            return
        }
        let zone = TimeZone.current.identifier
        if scheduled.contains(where: \.canCancel), settings.timeZone != zone {
            try? await client.setCallTimeZone(zone)
        }
    }

    /// Only a call still waiting; the list is read back afterwards either way.
    func cancel(_ call: ScheduledCall) async {
        guard let client else { return }
        await run {
            var failure: (any Error)?
            do {
                try await client.cancelScheduledCall(call.id)
            } catch ServerError.notEnabled("already_placed_or_done") {
                self.message = NSLocalizedString("That call isn't waiting any more: it was placed, cancelled or skipped.", comment: "")
            } catch {
                failure = error
            }
            if let settings = self.settings { await self.loadScheduled(client, settings: settings) }
            if let failure { throw failure }
        }
    }

    /// Saves the note as a memory (as said on the call, at that time), then removes it from the inbox.
    func keep(_ note: CallNote, into store: MemoryStore) async {
        guard let client else { return }
        await run {
            if !self.savedNoteIDs.contains(note.id) {
                // The user's own text is a typed note; anything Doddy wrote, on a call or while
                // answering a text, is Doddy's note that the user saved (ADR-494).
                _ = try await store.save(
                    text: note.text, category: .other, source: note.fromText ? .explicitText : .notedByDoddy,
                    capturedAt: note.createdDate ?? Date())
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
        case .notEnabled("sms_not_enabled"): TextsBlocker.textsFromDoddyOff.localized
        case .notEnabled("memory_copy_off"): TextsBlocker.memoryCopyOff.localized
        case .notConfigured("replies_not_configured"): TextsBlocker.repliesNotSetUp.localized
        case .rateLimited: NSLocalizedString("That's the limit for now. Try again later.", comment: "")
        case .notConfigured: NSLocalizedString("Doddy's phone line isn't set up on the server yet.", comment: "")
        default: UpdatesModel.text(for: error)
        }
    }
}

extension TextsBlocker {
    /// `message` in the app's language; literal keys, so the strings catalog finds them.
    var localized: String {
        switch self {
        case .notSetUp: NSLocalizedString("Texts to Doddy aren't set up on Doddy's server yet.", comment: "")
        case .noVerifiedPhone: NSLocalizedString("Verify your phone number in Notifications and texts first.", comment: "")
        case .repliesNotSetUp: NSLocalizedString("Replies aren't set up on Doddy's server yet.", comment: "")
        case .textsToDoddyOff: NSLocalizedString("Turn on Texts to Doddy first.", comment: "")
        case .textsFromDoddyOff: NSLocalizedString("Replies are texts from Doddy: turn on texts in Notifications and texts first. If you sent STOP, text START to Doddy's number.", comment: "")
        case .repliesOff: NSLocalizedString("Turn on replies first.", comment: "")
        case .memoryCopyOff: NSLocalizedString("Turn on Memory on calls first: replies use the same copy of your notes.", comment: "")
        }
    }
}

extension TextsPause {
    /// `message` in the app's language; literal keys, so the strings catalog finds them.
    var localized: String {
        switch self {
        case .notReceiving: NSLocalizedString("Doddy's server can't receive texts right now, so nothing you text it is kept.", comment: "")
        case .repliesNotSetUp: NSLocalizedString("Replies are paused: they aren't set up on Doddy's server. Your texts wait as notes.", comment: "")
        case .repliesCantText: NSLocalizedString("Replies are paused: Doddy can't text you (texts are off in Notifications and texts, or you sent STOP). Your texts wait as notes.", comment: "")
        case .memoriesWithoutCopy: NSLocalizedString("Memory on calls is off, so replies can't use your notes.", comment: "")
        }
    }
}
