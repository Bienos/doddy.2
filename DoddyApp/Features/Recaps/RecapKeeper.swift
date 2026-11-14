import DoddyCore
import Foundation

/// Saves recaps as notes while "Remember what we talked about" is on (decision
/// 2026-11-09-conversation-recaps):
/// - calls Doddy made for the person, recapped by the rules from the brief and the answer card
///   (`CallCaseRecap`), never the transcript (step 2);
/// - conversations with Doddy, written by Apple's model on this iPhone (`OnDeviceRecapWriter`, step 3a), or,
///   when it can't and the person said yes, by Doddy's server (`ServerRecapClient`, step 3b).
///
/// A recap is saved once: its key goes into `RecapLedger` only after `MemoryStore.save` read the note
/// back, so a failed save is tried again next time and a note the person deleted never comes back.
/// Calls answered before the switch was turned on are left alone.
@MainActor
enum RecapKeeper {
    private static var conversationsInFlight: Set<String> = []
    /// Turning the switch on or off. On records when, so only conversations after it are recapped.
    static func setRemember(_ on: Bool, defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(UUID().uuidString, forKey: RecapSettings.rememberEpochKey)
        defaults.set(on, forKey: RecapSettings.rememberKey)
        if on {
            defaults.set(now.timeIntervalSince1970, forKey: RecapSettings.rememberSinceKey)
        } else {
            defaults.removeObject(forKey: RecapSettings.rememberSinceKey)
        }
    }

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: RecapSettings.rememberKey) as? Bool ?? RecapSettings.rememberDefault
    }

    /// The person's yes to Doddy's server writing a recap this iPhone can't (off until given).
    static func serverYes(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: RecapSettings.serverWriterKey) as? Bool ?? RecapSettings.serverWriterDefault
    }

    static func since(_ defaults: UserDefaults = .standard) -> Date? {
        guard let seconds = defaults.object(forKey: RecapSettings.rememberSinceKey) as? Double else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Which recap note belongs to which conversation, and which conversations were deleted.
    static func links(_ defaults: UserDefaults = .standard) -> RecapLinks {
        RecapLinks(stored: defaults.string(forKey: RecapLinks.key))
    }

    /// Reads, changes and writes the links in one step. Everything here runs on the main actor with no
    /// suspension in between, so two changes cannot overwrite each other.
    static func updateLinks(_ defaults: UserDefaults = .standard, _ change: (RecapLinks) -> RecapLinks) {
        defaults.set(change(links(defaults)).stored, forKey: RecapLinks.key)
    }

    static func ledger(_ defaults: UserDefaults = .standard) -> RecapLedger {
        RecapLedger(stored: defaults.string(forKey: RecapSettings.ledgerKey))
    }

    /// Whether this call's recap is in the notes (saved and read back on this iPhone).
    static func hasRecap(_ record: StoredCallCase, defaults: UserDefaults = .standard) -> Bool {
        ledger(defaults).contains(RecapLedger.key(callCase: record.id, attempt: record.resultAttemptId))
    }

    /// Saves a recap for each answered call that has none yet. Returns how many were saved.
    @discardableResult
    static func rememberCalls(_ cases: [StoredCallCase], store: MemoryStore,
                              defaults: UserDefaults = .standard) async -> Int {
        guard isOn(defaults) else { return 0 }
        var saved = 0
        for record in cases {
            let key = RecapLedger.key(callCase: record.id, attempt: record.resultAttemptId)
            guard !ledger(defaults).contains(key),
                  RecapPolicy.decide(kind: .callForYou, rememberOn: true, isPrivate: false, wordsFromPerson: 0,
                                     onDeviceAvailable: false, serverYes: false) == .recap(.rules),
                  let recap = CallCaseRecap.make(record),
                  RecapPolicy.endedAfterSwitchOn(recap.endedAt, since: since(defaults)),
                  let text = try? RecapMemoryText.text(recap, labels: labels(for: recap))
            else { continue }
            do {
                _ = try await store.save(text: text, category: .other, source: .conversationRecap,
                                         capturedAt: recap.endedAt)
                defaults.set(ledger(defaults).adding(key).stored, forKey: RecapSettings.ledgerKey)
                saved += 1
            } catch {
                // Not marked: tried again the next time the calls are loaded.
                continue
            }
        }
        return saved
    }

    /// The language a recap is written in: the iPhone's, as the conversation usually is (Polish when unknown).
    static var languageCode: String { Locale.current.language.languageCode?.identifier ?? "pl" }

    enum ConversationOutcome: Equatable {
        case saved
        case skipped(RecapPolicy.Skip)
        /// This conversation already has its recap, or ended before the switch was turned on.
        case notNew
        /// The model's answer broke a recap rule, or the model failed: nothing saved.
        case refused
        /// The note couldn't be saved and read back: nothing claimed, nothing marked.
        case notSaved
        /// The person deleted the conversation while its recap was being written: no recap was kept.
        case sourceDeleted
    }

    /// After a conversation with Doddy ends: a recap note, written on this iPhone, if the switch is on, the
    /// conversation isn't Private and the person said enough. `startedAt` identifies the conversation, so
    /// it is recapped once. `conversationID` is the kept conversation's id: the saved note is linked to it, so
    /// deleting the conversation can offer to delete the note, and a deleted conversation gets no recap.
    @discardableResult
    static func recapConversation(lines: [RecapModelIO.Line], startedAt: Date, endedAt: Date, isPrivate: Bool,
                                  conversationID: UUID? = nil,
                                  store: MemoryStore, defaults: UserDefaults = .standard,
                                  onDeviceAvailable: Bool? = nil,
                                  write: @MainActor (RecapWriter, [RecapModelIO.Line], String) async throws -> Data = writeConversation) async -> ConversationOutcome {
        let personWords = lines.filter { $0.speaker == .person }.map(\.text).joined(separator: " ")
        let language = languageCode
        let decision = RecapPolicy.decide(kind: .voiceConversation, rememberOn: isOn(defaults), isPrivate: isPrivate,
                                          wordsFromPerson: RecapPolicy.wordCount(personWords),
                                          onDeviceAvailable: onDeviceAvailable ?? OnDeviceRecapWriter.isAvailable(languageCode: language),
                                          serverYes: serverYes(defaults))
        guard case .recap(let writer) = decision else {
            if case .skip(let why) = decision { return .skipped(why) }
            return .refused
        }
        let key = "voice_conversation:\(Int64((startedAt.timeIntervalSince1970 * 1000).rounded()))"
        guard writer == .onDevice || writer == .server, !ledger(defaults).contains(key), !conversationsInFlight.contains(key),
              RecapPolicy.endedAfterSwitchOn(endedAt, since: since(defaults)) else { return .notNew }
        if let conversationID, links(defaults).isDeleted(conversationID) { return .sourceDeleted }
        let consentSince = since(defaults)
        let consentEpoch = defaults.string(forKey: RecapSettings.rememberEpochKey)
        conversationsInFlight.insert(key)
        defer { conversationsInFlight.remove(key) }
        let recap: ConversationRecap
        let text: String
        do {
            let answer = try await write(writer, lines, language)
            recap = try RecapModelIO.read(answer, kind: .voiceConversation, with: nil, endedAt: endedAt,
                                          writtenBy: writer, conversation: RecapModelIO.plainText(lines))
            text = try RecapMemoryText.text(recap, labels: labels(for: recap))
        } catch {
            return .refused
        }
        // A model can outlive the person's consent. An off/on cycle is a new permission epoch,
        // not permission to complete an older extraction. Never mark it in the ledger on refusal.
        guard !Task.isCancelled, isOn(defaults), since(defaults) == consentSince,
              defaults.string(forKey: RecapSettings.rememberEpochKey) == consentEpoch else {
            return .skipped(.switchedOff)
        }
        guard writer != .server || serverYes(defaults) else { return .skipped(.noWriter) }
        guard !ledger(defaults).contains(key) else { return .notNew }
        if let conversationID, links(defaults).isDeleted(conversationID) { return .sourceDeleted }
        do {
            let saved = try await store.save(text: text, category: .other, source: .conversationRecap,
                                             capturedAt: recap.endedAt)
            defaults.set(ledger(defaults).adding(key).stored, forKey: RecapSettings.ledgerKey)
            if let conversationID {
                // The conversation may have been deleted while the note was being saved. Then the note
                // goes too; if it can't be removed it stays linked, so it is still found and reported.
                if links(defaults).isDeleted(conversationID) {
                    if (try? await store.delete(id: saved.id)) != nil { return .sourceDeleted }
                    updateLinks(defaults) { $0.linking(conversation: conversationID, memory: saved.id, evenIfDeleted: true) }
                } else {
                    updateLinks(defaults) { $0.linking(conversation: conversationID, memory: saved.id) }
                }
            }
            return .saved
        } catch {
            return .notSaved
        }
    }

    private static func writeConversation(_ writer: RecapWriter, _ lines: [RecapModelIO.Line], _ language: String) async throws -> Data {
        if writer == .onDevice {
            return try await OnDeviceRecapWriter.write(kind: .voiceConversation, lines: lines, languageCode: language)
        }
        return try await ServerRecapClient(server: ServerConfig.client())
            .write(kind: .voiceConversation, lines: lines, languageCode: language)
    }

    static func labels(for recap: ConversationRecap) -> RecapMemoryText.Labels {
        let date = recap.endedAt.formatted(date: .abbreviated, time: .shortened)
        let title: String = switch (recap.kind, recap.with) {
        case (.voiceConversation, _):
            String(format: NSLocalizedString("Conversation with Doddy, %@", comment: "Recap note title: when"), date)
        case (.recording, _):
            String(format: NSLocalizedString("Recording, %@", comment: "Recap note title: when"), date)
        case (_, let with?):
            String(format: NSLocalizedString("Call with %@, %@", comment: "Recap note title: who, when"), with, date)
        case (_, nil):
            String(format: NSLocalizedString("Call, %@", comment: "Recap note title: when"), date)
        }
        let writtenBy: String = switch recap.writtenBy {
        case .rules: NSLocalizedString("Recap made by Doddy from the call's card and answer, not from the transcript.", comment: "")
        case .onDevice: NSLocalizedString("Recap written on this iPhone.", comment: "")
        case .server: NSLocalizedString("Recap written by Claude on Doddy's server.", comment: "")
        }
        return RecapMemoryText.Labels(
            title: title,
            discussed: NSLocalizedString("Discussed", comment: "Recap section"),
            agreed: NSLocalizedString("Agreed", comment: "Recap section"),
            toDo: NSLocalizedString("To do", comment: "Recap section"),
            writtenBy: writtenBy)
    }
}
