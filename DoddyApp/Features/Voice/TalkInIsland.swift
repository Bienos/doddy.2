import ActivityKit
import AVFAudio
import DoddyCore
import Foundation
import UIKit
import os

/// "Talk in the Island" (ADR-569): one press of the Action Button (set to Doddy's control) or a
/// tap on the control starts a conversation without bringing Doddy to the front. Doddy greets
/// ("Hey Pat, what's up?"), the island opens up while he talks, and the conversation stays in the
/// Dynamic Island and on the Lock Screen with Mute and Stop. Tapping the island opens the voice
/// screen on the same conversation (`ShortcutRouter.showConversationStartedElsewhere`).
///
/// App target only: `TalkInIslandIntent` is a `LiveActivityIntent`, which iOS runs in the app's
/// process, starting it in the background if needed. Only what can be finished without a screen
/// starts here. Anything that needs one (signing in, the voice data notice, the microphone
/// question, the Face ID lock, Live Activities switched off) is refused with a sentence saying
/// what to open, and nothing starts. Whether iOS lets the microphone start with Doddy in the
/// background is checked by the conversation itself before it connects (`VoiceSessionController`,
/// `withoutOpeningApp`), and a refusal comes back here as its message.
@MainActor
enum TalkInIsland {
    /// What the intent shows when it can't start (Shortcuts or the control shows the sentence).
    struct Problem: Error, CustomLocalizedStringResourceConvertible {
        let message: String
        var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
    }

    /// The conversation started here. The one-at-a-time gate holds a conversation weakly and the
    /// voice screen only while it is open, so with no screen this keeps it alive. Replaced at the
    /// next start; an ended one holds no microphone.
    private static var started: VoiceSessionController?
    /// Which check stopped a start, never anything said. Console: subsystem `com.bienos.doddy2.dev`,
    /// category `voice-audio`, like the conversation's own start lines.
    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "voice-audio")

    /// "Hey Pat, what's up?": what Doddy says first when a shortcut starts the conversation, with
    /// the name he may use (Settings nickname, else the reviewed profile's name).
    static func greeting(for profile: ApprovedProfile) -> String {
        WakeGreeting.line(
            name: WakeGreeting.name(nickname: Nickname.stored(), profileName: profile.value(.name)),
            polish: ConversationLanguage.stored() == .polish)
    }

    /// Starts the conversation and returns once it is connecting or live. Throws `Problem` with
    /// the sentence to show when it can't.
    static func start() async throws {
        // One conversation at a time (ADR-496): a second press leaves the running one alone.
        if VoiceSessionController.runningConversation != nil {
            log.notice("talk in the island: a conversation is already running")
            return
        }
        // The shortcut ran, so the "Open Doddy faster" card and its reminder are done (ADR-559).
        let setup = ShortcutRouter.shared.setup
        setup.noteShortcutRan()
        Task { await OpenWaysReminderScheduler.refresh(setup) }

        guard let store = IntentStores.store, store.environment.capabilities.isAvailable(.voiceInput) else {
            throw refused("voice input unavailable",
                          NSLocalizedString("Doddy's voice isn't available right now. Open Doddy to see why.", comment: ""))
        }
        // The conversation hands the agent the saved notes, so it never starts past the Face ID lock.
        guard !AppLock.shared.isLocked else {
            throw refused("app lock", NSLocalizedString("Doddy is locked. Open Doddy and unlock him to talk.", comment: ""))
        }
        // iOS stops a recording started this way unless its Live Activity is up.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw refused("live activities off", NSLocalizedString("Doddy talks without opening only in the Dynamic Island. Turn on Live Activities for Doddy in iPhone Settings, then try again.", comment: ""))
        }
        // iOS can only ask about the microphone with Doddy on screen.
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw refused("microphone not allowed", NSLocalizedString("Doddy needs the microphone. Open Doddy and start a conversation once to allow it.", comment: ""))
        }
        // The same account and voice-data gate as the voice screen (`VoiceView`).
        let provider = VoiceProvider.effective(
            stored: UserDefaults.standard.string(forKey: VoiceProvider.preferenceKey), tokenServerSet: true)
        let auth = VoiceAuthSession.shared
        await auth.restore()
        guard auth.isSignedIn || VoiceConfig.directVoiceEnabled, VoiceProviderConsent.isGranted(for: provider) else {
            throw refused("voice not set up", NSLocalizedString("Open Doddy and start a conversation once to set up his voice. After that this works without opening him.", comment: ""))
        }

        // iOS may have started Doddy just for this, before any screen loaded the profile.
        let profiles = IntentStores.profiles
        if let profiles, !profiles.hasLoaded { await profiles.load() }
        let profile = profiles?.profile ?? .empty

        let controller = VoiceSessionController(store: store)
        started = controller
        await controller.start(VoiceConfig.connectionMode, profile: profile,
                               wakeGreeting: greeting(for: profile), withoutOpeningApp: true)
        switch controller.phase {
        case .failed(let message):
            throw refused("conversation failed", message)
        case .microphoneDenied:
            throw refused("microphone denied", NSLocalizedString("Doddy needs the microphone. Open Doddy and start a conversation once to allow it.", comment: ""))
        default:
            break
        }
        // Pressed with Doddy already on screen: iOS doesn't show his island over him, so show the
        // conversation instead of leaving it without a screen.
        if UIApplication.shared.applicationState == .active, VoiceSessionController.runningConversation != nil {
            ShortcutRouter.shared.showConversationStartedElsewhere()
        }
    }

    private static func refused(_ check: String, _ message: String) -> Problem {
        log.notice("talk in the island not started: \(check, privacy: .public)")
        return Problem(message: message)
    }
}
