import DoddyCore
import Foundation

/// Recaps of calls to and from Doddy's phone line (decision 2026-11-09-conversation-recaps, step 5). The
/// server writes them from the call (only while recaps are on here) and keeps only the three lists until this
/// iPhone has saved them as a note and read it back, then deletes its copy; the transcript is never stored
/// there. Like a call note, a recap is saved here without a tap only because the person turned on "Remember
/// what we talked about".
extension RecapKeeper {
    /// The ledger key of a call's recap: one note per call, even if the server's copy comes back.
    static func phoneKey(_ callId: UUID) -> String { "phone_line:\(callId.uuidString.lowercased())" }

    /// When the app last asked the server for recaps, so opening screens doesn't ask again and again.
    @MainActor private static var phoneAskedAt: Date?

    /// Tells the server whether to write recaps of this person's phone calls: on with the switch, off with
    /// it (which deletes every recap waiting there). Not claimed done: a failure is retried on the next fetch.
    @MainActor
    static func syncPhoneRecaps(_ on: Bool) async {
        phoneAskedAt = nil
        try? await PhoneRecapClient(server: ServerConfig.client()).setEnabled(on)
    }

    /// Saves the recaps waiting on the server as notes, then deletes the server's copies. At most once a minute
    /// unless `force`. Returns how many were saved.
    @MainActor
    @discardableResult
    static func rememberPhoneCalls(store: MemoryStore, force: Bool = false, defaults: UserDefaults = .standard,
                                   now: Date = Date()) async -> Int {
        guard isOn(defaults), let server = ServerConfig.client() else { return 0 }
        if !force, let asked = phoneAskedAt, now.timeIntervalSince(asked) < 60 { return 0 }
        phoneAskedAt = now
        let client = PhoneRecapClient(server: server)
        guard let listing = try? await client.list() else { return 0 }
        // The server forgot the switch (its data was deleted): tell it again, so later calls get a recap.
        if !listing.enabled { try? await client.setEnabled(true) }
        var saved = 0
        for recap in listing.recaps {
            let key = phoneKey(recap.callId)
            // Already a note here (the delete didn't reach the server last time): only delete it there.
            if ledger(defaults).contains(key) { try? await client.delete(recap.callId); continue }
            guard RecapPolicy.endedAfterSwitchOn(recap.endedAt, since: since(defaults)) else {
                // Not from after the switch was turned on: never saved.
                try? await client.delete(recap.callId)
                continue
            }
            guard let written = try? ConversationRecap(kind: .phoneLine, with: nil, endedAt: recap.endedAt, discussed: recap.discussed,
                                                       agreed: recap.agreed, toDo: recap.toDo, writtenBy: .server),
                  let text = try? RecapMemoryText.text(written, labels: phoneLabels(for: written)) else {
                // A recap that breaks the rules can never be saved: delete it rather than ask every time.
                try? await client.delete(recap.callId)
                continue
            }
            do {
                _ = try await store.save(text: text, category: .other, source: .conversationRecap, capturedAt: written.endedAt)
            } catch {
                continue // not saved, so not deleted there: tried again next time
            }
            defaults.set(ledger(defaults).adding(key).stored, forKey: RecapSettings.ledgerKey)
            saved += 1
            try? await client.delete(recap.callId)
        }
        // Recaps the server can't read can't be saved; delete them so they don't wait for 30 days.
        for id in listing.unreadable { try? await client.delete(id) }
        return saved
    }

    static func phoneLabels(for recap: ConversationRecap) -> RecapMemoryText.Labels {
        var labels = labels(for: recap)
        labels.title = String(format: NSLocalizedString("Phone call with Doddy, %@", comment: "Recap note title: when"),
                              recap.endedAt.formatted(date: .abbreviated, time: .shortened))
        return labels
    }
}
