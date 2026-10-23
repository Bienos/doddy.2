import DoddyCore
import Foundation
import Observation

/// Talking on Home (owner, 22 Oct 2026, ADR-595): a tap on Doddy starts the conversation right on
/// Home instead of opening the voice screen over it. Home shows what he is doing and his last
/// line; the voice screen is now the transcript, a sheet the user opens with Transcript, and it
/// comes up by itself when a card needs the user (a yes, an access question, a sign-in) or the
/// conversation failed.
///
/// This holds the conversation Home started, and one the transcript started, so it keeps going
/// while the sheet is closed: `VoiceSessionController`'s one-at-a-time gate holds conversations
/// only weakly. Replaced at the next start; an ended one holds no microphone.
@MainActor
@Observable
final class HomeConversation {
    static let shared = HomeConversation()

    private(set) var controller: VoiceSessionController?

    /// The conversation Home shows while it is connecting or live.
    var live: VoiceSessionController? {
        guard let controller, controller.isLive else { return nil }
        return controller
    }

    /// Something in the conversation waits for the user, and only the transcript can show it:
    /// a card to say yes or no to, the access or sign-in card, the permission sheet, or a failure
    /// with its way out.
    var needsYou: Bool {
        guard let controller else { return false }
        switch controller.phase {
        case .failed, .microphoneDenied: return true
        default: break
        }
        // Every pending action is a card waiting for the user's tap; results are `reminderStatus`
        // and the like, not pending actions.
        return controller.pendingAction != nil || controller.accessRequest != nil || controller.accountNeeded != nil
            || controller.permissionRequest != nil
    }

    func hold(_ controller: VoiceSessionController) {
        self.controller = controller
    }

    /// For the transcript: the held conversation when there is something in it to show (live, or
    /// waiting for the user), so opening the sheet never starts a second one.
    var forTranscript: VoiceSessionController? {
        guard let controller, controller.isLive || needsYou else { return nil }
        return controller
    }

    /// Home's Talk button and a tap on the persistent Doddy. While he talks, a tap ends the
    /// conversation. Otherwise it starts here when the account and voice-data gate is already
    /// passed; when it isn't, the transcript opens on that gate, which starts the conversation.
    func talk(store: MemoryStore, profile: ApprovedProfile) {
        if let live {
            Task { await live.stop() }
            return
        }
        Task {
            if await Self.canStartInPlace() {
                await start(store: store, profile: profile)
            } else {
                ShortcutRouter.shared.isVoicePresented = true
            }
        }
    }

    /// The Action Button, Back Tap, Siri or "Start listening when I open Doddy" (owner, 23 Oct
    /// 2026): the conversation starts here on Home, as a tap on Doddy does, never in the transcript
    /// sheet. One already going is left as it is. When the sign-in or voice-data step isn't done,
    /// the voice screen opens on it, as for a tap.
    func startFromShortcut(store: MemoryStore, profile: ApprovedProfile, greeted: Bool) {
        guard live == nil else { return }
        Task {
            if await Self.canStartInPlace() {
                await start(store: store, profile: profile, greeting: greeted ? TalkInIsland.greeting(for: profile) : nil)
            } else {
                ShortcutRouter.shared.openVoiceForGate(greeted: greeted)
            }
        }
    }

    /// The same check the voice screen makes before it starts by itself (`VoiceView`).
    static func canStartInPlace() async -> Bool {
        let provider = VoiceProvider.effective(
            stored: UserDefaults.standard.string(forKey: VoiceProvider.preferenceKey), tokenServerSet: true)
        let auth = VoiceAuthSession.shared
        await auth.restore()
        return (auth.isSignedIn || VoiceConfig.directVoiceEnabled) && VoiceProviderConsent.isGranted(for: provider)
    }

    private func start(store: MemoryStore, profile: ApprovedProfile, greeting: String? = nil) async {
        // One conversation at a time (ADR-496): one starting or live elsewhere is the one Home shows.
        if let running = VoiceSessionController.runningConversation {
            controller = running
            return
        }
        let controller = VoiceSessionController(store: store)
        self.controller = controller
        await controller.start(VoiceConfig.connectionMode, profile: profile, wakeGreeting: greeting)
    }
}
