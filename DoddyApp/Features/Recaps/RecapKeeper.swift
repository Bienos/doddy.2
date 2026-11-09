import DoddyCore
import Foundation

/// Saves recaps as notes while "Remember what we talked about" is on (decision
/// 2026-11-09-conversation-recaps). Step 2: calls Doddy made for the person, recapped by the rules from
/// the brief and the answer card (`CallCaseRecap`), never the transcript.
///
/// A recap is saved once: its key goes into `RecapLedger` only after `MemoryStore.save` read the note
/// back, so a failed save is tried again next time and a note the person deleted never comes back.
/// Calls answered before the switch was turned on are left alone.
@MainActor
enum RecapKeeper {
    /// Turning the switch on or off. On records when, so only conversations after it are recapped.
    static func setRemember(_ on: Bool, defaults: UserDefaults = .standard, now: Date = Date()) {
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

    static func since(_ defaults: UserDefaults = .standard) -> Date? {
        guard let seconds = defaults.object(forKey: RecapSettings.rememberSinceKey) as? Double else { return nil }
        return Date(timeIntervalSince1970: seconds)
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

    static func labels(for recap: ConversationRecap) -> RecapMemoryText.Labels {
        let date = recap.endedAt.formatted(date: .abbreviated, time: .shortened)
        let title: String = if let with = recap.with {
            String(format: NSLocalizedString("Call with %@, %@", comment: "Recap note title: who, when"), with, date)
        } else {
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
