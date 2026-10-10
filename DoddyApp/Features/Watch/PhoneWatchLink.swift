import DoddyCore
import Foundation
import SwiftUI
import WatchConnectivity

/// The iPhone's side of the Apple Watch app (ADR-232). Sends the same snapshot the widgets get
/// (or an empty "off" one), and answers the watch's two requests from the store, read back. The
/// guard script keeps WatchConnectivity in this folder and the watch app.
@MainActor
final class PhoneWatchLink: NSObject {
    static let shared = PhoneWatchLink()

    weak var store: MemoryStore?
    private var lastSent: WidgetSnapshot?

    static var isOn: Bool {
        UserDefaults.standard.object(forKey: PreferenceKey.watchShowContent) as? Bool ?? true
    }

    /// True once a paired watch has Doddy installed.
    private(set) var isWatchAppInstalled = false

    private override init() {}

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Called whenever the widgets' snapshot is rebuilt. The watch only gets news, not time stamps.
    func send(_ snapshot: WidgetSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let content = Self.isOn ? snapshot : .off(at: snapshot.writtenAt)
        if let lastSent, lastSent.isOn == content.isOn, lastSent.pinned == content.pinned,
           lastSent.reminders == content.reminders, lastSent.lists == content.lists { return }
        guard let data = try? content.encoded() else { return }
        do {
            try session.updateApplicationContext([WatchLinkVersion.snapshotKey: data])
            lastSent = content
        } catch {
            // The watch keeps showing the previous snapshot with its time; nothing to repair here.
        }
    }

    fileprivate func handle(_ request: WatchRequest) async -> WatchReply {
        switch request {
        case .tick(let listID, let itemID, let shownDone):
            guard Self.isOn else { return .failed }
            return WatchReply(await WidgetSync.shared.tick(listID: listID, itemID: itemID, shownDone: shownDone))
        case .saveNote(let text):
            if let problem = WatchNote.problem(text) { return .notSaved(reason: problem) }
            guard let store, store.isStorageAvailable else {
                return .notSaved(reason: "Doddy's notes can't be opened on your iPhone, so nothing was saved.")
            }
            do {
                // Written or dictated on the watch and checked there before Save.
                let record = try await store.save(text: text, category: .other, source: .explicitText)
                return store.record(id: record.id) != nil ? .saved : .failed
            } catch {
                return .notSaved(reason: "Not saved: \(UserFacingError.message(for: error))")
            }
        }
    }
}

/// The watch's reply handler isn't marked Sendable; it is called once, from the main actor.
private struct ReplyBox: @unchecked Sendable {
    let reply: (Data) -> Void
}

extension PhoneWatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        let installed = session.isPaired && session.isWatchAppInstalled
        Task { @MainActor in
            self.isWatchAppInstalled = installed
            self.lastSent = nil
            WidgetSync.shared.refresh()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // A different watch was chosen: start a session with it.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let installed = session.isPaired && session.isWatchAppInstalled
        Task { @MainActor in
            self.isWatchAppInstalled = installed
            self.lastSent = nil
            WidgetSync.shared.refresh()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        let box = ReplyBox(reply: replyHandler)
        Task { @MainActor in
            let reply: WatchReply
            if let request = WatchRequest.decoded(messageData) {
                reply = await self.handle(request)
            } else {
                reply = .failed
            }
            box.reply((try? reply.encoded()) ?? Data())
        }
    }
}

/// Settings → Apple Watch.
struct WatchSettingsSection: View {
    @AppStorage(PreferenceKey.watchShowContent) private var watchOn = true

    var body: some View {
        if WCSession.isSupported(), WCSession.default.isPaired {
            Section("Apple Watch") {
                Toggle("Show notes and lists on Apple Watch", isOn: $watchOn)
                    .onChange(of: watchOn) { WidgetSync.shared.refresh() }
                    .accessibilityIdentifier("settings.watchOn")
                Text(watchOn
                     ? "The watch shows your pinned notes, next note reminders and lists, and can tick items and save new notes. It does that through your iPhone, which must be nearby; nothing is saved on the watch."
                     : "The watch shows nothing from your notes or lists.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
