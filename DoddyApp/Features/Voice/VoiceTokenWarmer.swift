import AVFAudio
import DoddyCore
import Foundation
import UIKit
import os

/// Fetches the voice token before the person asks to talk, so a press only has to connect (owner,
/// 10 Nov 2026; decision `2026-11-10-action-button-start`). The rules (one use, same account and
/// server, 4 minutes, a 15-minute cool-down after an unused one) are `VoiceTokenShelf`, tested in
/// DoddyCore. This file only decides when asking is allowed and keeps the shelf.
///
/// Never before the person has agreed to the voice data notice, has the microphone allowed and is
/// signed in; never while Pause all is on or a conversation is running. It starts no conversation and
/// no microphone: a token alone connects nothing. Nothing about a token is logged.
@MainActor
final class VoiceTokenWarmer {
    static let shared = VoiceTokenWarmer()

    private var shelf = VoiceTokenShelf()
    /// Bumped by every `clear()`, so a fetch that was running when the shelf was cleared keeps nothing.
    private var epoch = 0
    private var warming: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "voice-audio")

    private init() {}

    /// Once, at launch: warms whenever Doddy comes to the front, and clears when Pause all goes on.
    func install() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in VoiceTokenWarmer.shared.warmIfDue() }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in if Self.paused { VoiceTokenWarmer.shared.clear() } }
        })
    }

    private static var paused: Bool { UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) }

    /// A stable id for the signed-in account, used only to keep a token from another account out.
    /// Never logged or sent.
    private static var owner: String? {
        DoddyAccountModel.shared.session?.userID ?? VoiceAuthSession.shared.userID
    }

    /// Asks for a token now if the rules allow it.
    func warmIfDue(now: Date = .now) {
        guard warming == nil, !Self.paused, VoiceProviderConsent.isGranted(),
              AVAudioApplication.shared.recordPermission == .granted,
              VoiceSessionController.runningConversation == nil,
              case .tokenServer(let endpoint) = VoiceConfig.connectionMode,
              VoiceAuthSession.shared.hasVoiceAccess(), let owner = Self.owner,
              shelf.shouldWarm(endpoint: endpoint, owner: owner, now: now) else { return }
        shelf.warmStarted(now: now)
        let started = epoch
        warming = Task { @MainActor in
            defer { warming = nil }
            let token = try? await VoiceTokenClient(endpoint: endpoint).fetchToken()
            // Cleared (sign-out, Pause all, consent withdrawn) or another account while it was fetched.
            guard started == epoch, owner == Self.owner, let token else {
                Self.log.notice("token shelf: nothing kept")
                return
            }
            shelf.store(token, endpoint: endpoint, owner: owner, fetchedAt: .now)
            Self.log.notice("token shelf: one kept")
        }
    }

    /// The token for this start, if one is held and still good; gone from the shelf either way. A start
    /// whose token fails to connect asks again and gets a fresh one: nothing here is handed out twice.
    func take(endpoint: URL, now: Date = .now) -> String? {
        guard !Self.paused, VoiceProviderConsent.isGranted() else { clear(); return nil }
        return shelf.take(endpoint: endpoint, owner: Self.owner, now: now)
    }

    /// Sign-out, account change, Pause all, consent withdrawn: nothing held survives.
    func clear() {
        epoch += 1
        shelf.clear()
        warming?.cancel()
        warming = nil
    }
}
