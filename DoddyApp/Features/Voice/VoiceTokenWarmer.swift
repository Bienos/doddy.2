import AVFAudio
import DoddyCore
import Foundation
import Observation
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

    private let supply = VoiceTokenSupply()
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
            Task { @MainActor in
                if Self.paused { VoiceTokenWarmer.shared.clear() }
                else { VoiceTokenWarmer.shared.warmIfDue() }
            }
        })
        observeSignIn()
        warmIfDue()
    }

    /// Foreground can arrive before the account restore or first sign-in finishes. Reconsider
    /// readiness then, instead of waiting for a trip to the background and back.
    private func observeSignIn() {
        withObservationTracking {
            _ = DoddyAccountModel.shared.session
            _ = VoiceAuthSession.shared.isSignedIn
            _ = VoiceAuthSession.shared.isLoading
        } onChange: {
            Task { @MainActor in
                VoiceTokenWarmer.shared.observeSignIn()
                VoiceTokenWarmer.shared.warmIfDue()
            }
        }
    }

    private static var paused: Bool { UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) }

    /// A stable id for the signed-in account, used only to keep a token from another account out.
    /// Never logged or sent.
    private static var owner: String? {
        DoddyAccountModel.shared.session?.userID ?? VoiceAuthSession.shared.userID
    }

    /// Asks for a token now if the rules allow it.
    func warmIfDue() {
        guard UIApplication.shared.applicationState == .active,
              !Self.paused, VoiceProviderConsent.isGranted(),
              AVAudioApplication.shared.recordPermission == .granted,
              VoiceSessionController.runningConversation == nil,
              case .tokenServer(let endpoint) = VoiceConfig.connectionMode,
              VoiceAuthSession.shared.hasVoiceAccess(), let owner = Self.owner else { return }
        if supply.warm(endpoint: endpoint, owner: owner, fetch: Self.fetch) {
            Self.log.notice("token shelf: preparing one")
        }
    }

    /// The token for this start, if one is held and still good; gone from the shelf either way. A start
    /// whose token fails to connect asks again and gets a fresh one: nothing here is handed out twice.
    func token(endpoint: URL) async throws(VoiceTokenError) -> VoiceTokenSupply.Token {
        guard !Self.paused, VoiceProviderConsent.isGranted() else { clear(); throw .cancelled }
        guard let owner = Self.owner else { throw .sessionExpired }
        let token = try await supply.token(endpoint: endpoint, owner: owner, fetch: Self.fetch)
        guard !Self.paused, VoiceProviderConsent.isGranted(), owner == Self.owner else {
            clear()
            throw .cancelled
        }
        return token
    }

    private static func fetch(_ endpoint: URL) async -> Result<String, VoiceTokenError> {
        do throws(VoiceTokenError) {
            return .success(try await VoiceTokenClient(endpoint: endpoint).fetchToken())
        } catch {
            return .failure(error)
        }
    }

    /// Sign-out, account change, Pause all, consent withdrawn: nothing held survives.
    func clear() {
        supply.clear()
    }
}
