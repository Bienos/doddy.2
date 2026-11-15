import DoddyCore
import Foundation
import Observation

/// State for Settings → Phone calls. Shows only what the server reported.
@MainActor
@Observable
final class CallsModel {
    private(set) var client: DoddyServerClient?
    private(set) var settings: CallSettings?
    /// Texts to Doddy (ADR-753); nil until the server answered.
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
    /// Calls booked for later (ADR-754), newest first, as the server lists them.
    private(set) var scheduled: [ScheduledCall] = []
    /// Why the booked calls couldn't be loaded, or nil. A failed load is never shown as "none".
    private(set) var scheduledProblem: String?
    /// The morning call (decision 2026-11-14-morning-call) as the server reported it; nil until it answered.
    private(set) var morning: MorningCallStatus?
    /// Why the morning call couldn't be loaded, or nil. A failed load is never shown as "none".
    private(set) var morningProblem: String?
    /// What the server said about the last change to the morning call, shown next to its switch.
    private(set) var morningMessage: String?
    /// Approval identities of morning calls booked from Settings whose outcome was unknown, so the card can say so.
    private(set) static var unconfirmedMorning: Set<String> = []
    private(set) var isWorking = false
    private(set) var message: String?

    init() {
        client = ServerConfig.client()
    }

    var isServerConfigured: Bool { client != nil }

    func refresh() async {
        guard let client else { return }
        morningMessage = nil
        await run {
            let settings = try await client.callSettings()
            self.settings = settings
            self.recent = (try? await client.recentCalls()) ?? []
            await self.loadScheduled(client, settings: settings)
            await self.loadMorning(client)
            do {
                let texts = try await client.textSettings()
                self.textSettings = texts
                self.textsProblem = nil
                Self.mirror(texts)
            } catch {
                self.textsProblem = String(
                    format: NSLocalizedString("Couldn't load the settings for texts to Doddy. %@", comment: ""), Self.text(for: error))
            }
            // The inbox holds notes from calls and from texts (ADR-753).
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
    /// again when Doddy next comes to the front (DOD-08/11). `records` may be every note:
    /// `MemoryCopySync` leaves private notes out of every upload (ADR-310).
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

    // MARK: Texts to Doddy (ADR-753)

    func setTextsToDoddy(_ on: Bool) async { await changeTexts { try await $0.setTextsToDoddy(on, language: .current) } }

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
    }

    /// The server's JSON, saved to a file this iPhone shares from. Nothing else is added to it.
    func exportHistory() async {
        guard let client else { return }
        clearExport()
        await run {
            let data = try await client.phoneHistory()
            // In the share folder (readable only while the iPhone is unlocked), where a launch also sweeps it.
            self.historyFile = try TemporaryShareFiles.write(
                data, title: "Doddy phone and text history", fileExtension: "json", fallback: "Doddy history")
        }
    }

    /// The export holds the phone number and the waiting notes: it isn't left behind.
    func clearExport() {
        if let file = historyFile { TemporaryShareFiles.remove(file) }
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
                ? NSLocalizedString("Doddy is calling you now.", comment: "")
                : NSLocalizedString("Couldn't confirm the call was placed. Doddy won't redial on its own. Wait a minute before trying again.", comment: "")
            self.recent = (try? await client.recentCalls()) ?? self.recent
        }
    }

    // MARK: Calls booked for later (ADR-754)

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
        let defaults = UserDefaults.standard
        defaults.set(CallZoneSync.waitingUntil(scheduled), forKey: CallZoneSync.waitingUntilKey)
        let zone = TimeZone.current.identifier
        if scheduled.contains(where: \.canCancel), settings.timeZone != zone {
            if (try? await client.setCallTimeZone(zone)) != nil { defaults.set(zone, forKey: CallZoneSync.lastSentKey) }
        } else if let held = settings.timeZone {
            defaults.set(held, forKey: CallZoneSync.lastSentKey)
        }
    }

    // MARK: The morning call (decision 2026-11-14-morning-call)

    private func loadMorning(_ client: DoddyServerClient) async {
        do {
            morning = try await client.morningCall()
            morningProblem = nil
        } catch {
            morning = nil
            morningProblem = String(format: NSLocalizedString("Couldn't load your morning call. %@", comment: ""), Self.text(for: error))
        }
    }

    /// One tap (the switch turned off, or Stop) stops it at once; the server's answer is read back either way, and only
    /// what it said is shown (DOD-05, DOD-08).
    func stopMorningCalls() async {
        guard let client else { return }
        await runMorning {
            do {
                switch try await client.stopMorningCalls() {
                case .stopped(let calling):
                    self.morningMessage = calling
                        ? NSLocalizedString("Morning calls stopped. Today's call was already being placed, so it may still ring this once.", comment: "")
                        : NSLocalizedString("Morning calls stopped. Doddy won't call you in the morning any more.", comment: "")
                case .noneActive:
                    self.morningMessage = NSLocalizedString("There was no morning call to stop.", comment: "")
                case .unknown:
                    self.morningMessage = NSLocalizedString("Couldn't confirm the stop reached Doddy's server. Tap Stop again: stopping twice is safe.", comment: "")
                }
            } catch {
                self.morningMessage = String(
                    format: NSLocalizedString("Couldn't stop the morning calls. %@", comment: "Morning call: the stop failed"), Self.text(for: error))
            }
            await self.loadMorning(client)
        }
    }

    /// Before the card in Settings: the number, quiet hours, the server's switch and the morning call it would replace,
    /// read from the server now, as the voice card does before it shows. Nothing is set up here.
    func prepareMorningCall(_ draft: MorningCallDraft) async -> MorningCallPreparation {
        guard let client else {
            return .notReady(NSLocalizedString("Phone calls aren't available in this version of Doddy yet.", comment: ""))
        }
        isWorking = true
        defer { isWorking = false }
        do {
            async let settings = client.callSettings()
            async let phone = client.phoneStatus()
            async let morning = client.morningCall()
            let (s, p, m) = try await (settings, phone, morning)
            self.settings = s
            self.morning = m
            self.morningProblem = nil
            switch MorningCallProposal.check(draft, settings: s, phone: p, status: m) {
            case .ready(let proposal): return .ready(proposal)
            case .blocked(let blocker): return .notReady(blocker.localized)
            }
        } catch {
            return .notReady(String(
                format: NSLocalizedString("Couldn't check with Doddy's server before showing the card. %@", comment: "Morning call"), Self.text(for: error)))
        }
    }

    /// After a tap on the card's own button, never on the switch alone (DOD-07): exactly what the card showed goes to the
    /// server with its approval, through the voice card's call (`bookMorningCall`, `POST /v1/calls/morning`). A booking
    /// while one is active replaces the one the card named. The switch then shows what the server reads back, whatever
    /// the answer was (DOD-08); an unknown outcome is never retried on its own (DOD-09).
    func bookMorningCall(_ proposal: MorningCallProposal, allowQuietHours: Bool) async {
        guard let client else { return }
        let language = NotificationLanguage.current
        let identity = proposal.draft.identity(to: proposal.to, language: language)
        await runMorning {
            do {
                switch try await client.bookMorningCall(
                    proposal.draft, to: proposal.to, allowQuietHours: allowQuietHours, language: language, replaces: proposal.replaces?.id) {
                case .booked:
                    Self.unconfirmedMorning.remove(identity)
                    self.morningMessage = String(
                        format: NSLocalizedString("Morning call set up: %@. Each day is checked again before it rings.", comment: "Morning call"),
                        proposal.draft.scheduleText(language))
                case .refused("already_booked"):
                    self.morningMessage = MorningCallRefusal.alreadySetUp.localized
                case .refused(let code):
                    self.morningMessage = String(
                        format: NSLocalizedString("The morning call wasn't set up. %@", comment: "Morning call: the server refused it"),
                        MorningCallRefusal(code: code).localized)
                case .unknown:
                    Self.unconfirmedMorning.insert(identity)
                    self.morningMessage = NSLocalizedString("Couldn't confirm Doddy's server set up the morning call. The switch shows what the server says now. If it's off, setting up the same time and days again is safe: the server sets it up at most once.", comment: "Morning call")
                }
            } catch {
                // Certainly not set up: it never left this iPhone, or the server's answer means it never ran.
                self.morningMessage = String(
                    format: NSLocalizedString("The morning call wasn't set up. %@", comment: "Morning call: the server refused it"), Self.text(for: error))
            }
            await self.loadMorning(client)
        }
    }

    /// Whether an earlier try of this exact schedule, here or in a conversation, had an unclear outcome.
    static func isUnconfirmed(_ proposal: MorningCallProposal) -> Bool {
        let identity = proposal.draft.identity(to: proposal.to, language: .current)
        return unconfirmedMorning.contains(identity) || VoiceSessionController.unconfirmedCalls.contains(identity)
    }

    /// Like `run`, but the answer is shown next to the morning call's switch; each step handles its own errors.
    private func runMorning(_ work: @MainActor () async -> Void) async {
        isWorking = true
        message = nil
        morningMessage = nil
        defer { isWorking = false }
        await work()
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
                // The user's own text is a typed note; a note Doddy took on a call is Doddy's note
                // that the user saved (ADR-753).
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
        case .notEnabled("sms_not_enabled"): NSLocalizedString("Texts from Doddy are off: turn on texts in Notifications and texts first. If you sent STOP, text START to Doddy's number.", comment: "")
        case .notEnabled("phone_not_allowed"): NSLocalizedString("Doddy doesn't text or call numbers in that country.", comment: "")
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
        }
    }
}

extension TextsPause {
    /// `message` in the app's language; literal keys, so the strings catalog finds them.
    var localized: String {
        switch self {
        case .notReceiving: NSLocalizedString("Doddy's server can't receive texts right now, so nothing you text it is kept.", comment: "")
        }
    }
}

/// Tells Doddy's server the iPhone's time zone when Doddy comes to the front while a call it
/// booked may still be waiting (ADR-754), so quiet hours are checked where the user is. Sends
/// nothing otherwise, and never creates a server account to do it.
@MainActor
enum CallZoneSender {
    private static var sending = false

    static func sendIfNeeded(now: Date = Date()) {
        let defaults = UserDefaults.standard
        let current = TimeZone.current.identifier
        guard !sending,
              CallZoneSync.shouldSend(
                now: now, waitingUntil: defaults.object(forKey: CallZoneSync.waitingUntilKey) as? Date,
                lastSent: defaults.string(forKey: CallZoneSync.lastSentKey), current: current),
              let client = ServerConfig.client()
        else { return }
        sending = true
        Task { @MainActor in
            defer { sending = false }
            guard await client.hasAccount() else { return }
            if (try? await client.setCallTimeZone(current)) != nil {
                UserDefaults.standard.set(current, forKey: CallZoneSync.lastSentKey)
            }
        }
    }
}
