import AVFAudio
import DoddyCore
import Foundation
import LiveKit
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
    private var networkPolicy = VoiceNetworkPreparationPolicy()
    private var networkRoom: Room?
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
        let conditions = Self.conditions
        guard conditions.mayPrepare else { return }
        // Independent of the token's age/cool-down, and never awaited by a tap. Even a held
        // token doesn't prepare the provider's network route for the SDK's room connection.
        if networkPolicy.request(if: conditions, at: ProcessInfo.processInfo.systemUptime) {
            prepareNetwork()
        }
        guard case .tokenServer(let endpoint) = VoiceConfig.connectionMode, let owner = Self.owner else { return }
        if supply.warm(endpoint: endpoint, owner: owner, fetch: Self.fetch) {
            Self.log.notice("token shelf: preparing one")
        }
    }

    private static var conditions: VoicePreparationConditions {
        let configured: Bool
        if case .notSetUp = VoiceConfig.connectionMode { configured = false } else { configured = true }
        return VoicePreparationConditions(
            foreground: UIApplication.shared.applicationState == .active,
            hasVoiceAccess: VoiceAuthSession.shared.hasVoiceAccess(),
            // The Debug developer connection alone isn't a signed-in owner. It may be used
            // on a press, but never authorises provider requests while signed out.
            hasSignedInOwner: owner != nil,
            consentGranted: VoiceProviderConsent.isGranted(),
            microphoneAllowed: AVAudioApplication.shared.recordPermission == .granted,
            paused: paused, conversationRunning: VoiceSessionController.runningConversation != nil,
            configured: configured)
    }

    private func prepareNetwork() {
        Task { @MainActor in
            // A sign-out, Pause all, a background transition or a start can win the queue.
            guard Self.conditions.mayPrepare else { return }
            let room = networkRoom ?? Room()
            networkRoom = room
            // LiveKit 2.19.0 Room+Region.prepareConnection: for this non-LiveKit-Cloud host,
            // schedules a credential-free HTTPS HEAD through HTTP.prewarmConnection. It
            // never calls connect or touches an audio track. The SDK owns that HEAD task,
            // swallows its network errors and returns before it finishes; log the request,
            // never "connected" or a preparation duration. This isn't the SDK's live Room.
            Self.log.notice("voice network preparation requested")
            try? await room.prepareConnection(url: VoiceConfig.mediaEndpointAddress, token: nil)
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

    /// A translator conversation talks to its own agent (decision 2026-11-12-translator-agent), so a token held
    /// ahead for the main agent is no use to it: this fetches one now, with the same checks as `token(endpoint:)`
    /// (Pause all, the voice data notice, the same account), and leaves the shelf as it is.
    func translatorToken(endpoint: URL) async throws(VoiceTokenError) -> String {
        guard !Self.paused, VoiceProviderConsent.isGranted() else { clear(); throw .cancelled }
        guard let owner = Self.owner else { throw .sessionExpired }
        let token = try await VoiceTokenClient(endpoint: endpoint).fetchToken(agent: .translator)
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
