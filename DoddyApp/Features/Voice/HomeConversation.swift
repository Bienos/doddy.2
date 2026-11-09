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
        case .failed:
            // A drop in the middle of a conversation is said on Home (ADR-687) and opens nothing
            // by itself, unless the "Worth keeping?" card waits: only the transcript shows it. The
            // draft of what Doddy last heard is on Home too (ADR-700).
            if !stays(onHome: controller) { return true }
        case .microphoneDenied: return true
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

    /// What Home says while the held conversation is a drop in the middle that needs nothing from
    /// the user (ADR-687). It stays until the next conversation starts.
    var droppedNotice: HomeDropNotice? {
        guard let controller, stays(onHome: controller) else { return nil }
        return controller.homeDropNotice
    }

    /// A drop in the middle that Home can tell completely: Home has the words and the draft of what
    /// Doddy last heard with its Save and Discard (ADR-700), but not the "Worth keeping?" card.
    private func stays(onHome controller: VoiceSessionController) -> Bool {
        controller.homeDropNotice != nil && controller.saveSuggestions == nil
    }

    /// For the transcript: the held conversation when there is something in it to show (live, or
    /// waiting for the user, or a drop Home is telling about), so opening the sheet never starts a
    /// second one.
    var forTranscript: VoiceSessionController? {
        guard let controller, controller.isLive || needsYou || droppedNotice != nil else { return nil }
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

    /// The same check the voice screen makes before it starts by itself (`VoiceView`).
    static func canStartInPlace() async -> Bool {
        let auth = VoiceAuthSession.shared
        await auth.restore()
        return auth.hasVoiceAccess() && VoiceProviderConsent.isGranted()
    }

    /// The Action Button, Back Tap or Siri with Doddy on screen: the conversation starts here, like a
    /// tap on Doddy, with the shortcut's greeting. False when it can't start in place (the account
    /// or voice-data gate isn't passed), so the caller opens the voice screen as before.
    func startFromShortcut(store: MemoryStore, profile: ApprovedProfile, greeting: String) async -> Bool {
        if live != nil { return true }
        guard await Self.canStartInPlace() else { return false }
        await start(store: store, profile: profile, wakeGreeting: greeting)
        return true
    }

    private func start(store: MemoryStore, profile: ApprovedProfile, wakeGreeting: String? = nil) async {
        // One conversation at a time (ADR-496): one starting or live elsewhere is the one Home shows.
        if let running = VoiceSessionController.runningConversation {
            controller = running
            return
        }
        let controller = VoiceSessionController(store: store)
        self.controller = controller
        await controller.start(VoiceConfig.connectionMode, profile: profile, wakeGreeting: wakeGreeting)
    }
}
