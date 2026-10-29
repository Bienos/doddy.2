import ActivityKit
import AVFAudio
import DoddyCore
import Foundation
import UIKit
import os

/// "Talk to Doddy" from the Action Button or a control (ADR-579, wired again by ADR-632 after
/// ADR-593 had the controls open the app). One press decides with `TalkLaunchPlanner`: start in
/// the Dynamic Island without opening Doddy, or end the conversation that is running (press again
/// to stop). `TalkInIslandIntent` does the same from the Shortcuts app.
@MainActor
enum TalkButton {
    /// What the intent does next.
    enum Outcome: Equatable {
        /// Started, ended, shown in the app, or ignored as a repeat press.
        case done
        /// Bring Doddy forward on the conversation screen without asking.
        case openApp
        /// Bring Doddy forward after iOS asks, with the reason.
        case askToOpenApp(String)
        /// Say this; nothing opens.
        case tell(String)
    }

    static let openDoddyToTalk = NSLocalizedString("Open Doddy to talk.", comment: "")

    /// Always the island (ADR-632). Settings has had no Action Button choice since ADR-593, so a
    /// choice stored by the ADR-579 build isn't read: the user could no longer see or change it.
    static func press(now: Date = .now) async -> Outcome {
        await TalkInIsland.press(mode: .dynamicIsland, now: now)
    }
}

/// Starting a conversation without bringing Doddy to the front (ADR-577). Doddy greets ("Hey Pat,
/// what's up?"), the island opens up while he talks, and the conversation stays in the Dynamic
/// Island and on the Lock Screen with Mute and Stop. Tapping the island opens the voice screen on
/// the same conversation (`ShortcutRouter.showConversationStartedElsewhere`).
///
/// App target only: the intents are `LiveActivityIntent`s, which iOS runs in the app's process,
/// starting it in the background if needed. Only what can be finished without a screen starts
/// here. Anything that needs one (signing in, the voice data notice, the microphone question, the
/// Face ID lock, Live Activities switched off, the terms) is refused as `needsApp`, and nothing
/// starts. Whether iOS lets the microphone start with Doddy in the background is checked by the
/// conversation itself before it connects (`VoiceSessionController`, `withoutOpeningApp`), and a
/// refusal comes back here as `needsApp` too: opening Doddy is what fixes it.
@MainActor
enum TalkInIsland {
    /// What the intent shows when it can't start (Shortcuts or the control shows the sentence).
    struct Problem: Error, CustomLocalizedStringResourceConvertible {
        let message: String
        var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
    }

    /// The conversation started here. The one-at-a-time gate holds a conversation weakly and the
    /// voice screen only while it is open, so with no screen this keeps it alive. Replaced only
    /// by a later start; an ended one holds no microphone.
    private static var started: VoiceSessionController?
    /// A press is between its first check and a conversation that the gate can see. Set before
    /// the first `await`, so a second press in that time is ignored instead of making a second
    /// controller (which used to replace `started` and let the first conversation go).
    private static var isStarting = false
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

    /// The running conversation as a press sees it.
    private static var pressState: TalkPressState {
        if isStarting { return .starting }
        guard let running = VoiceSessionController.runningConversation else { return .none }
        // Still connecting counts as starting: a second press then is a bounce.
        guard let since = running.startedAt else { return .starting }
        return .running(since: since)
    }

    /// One press (ADR-579).
    static func press(mode: TalkLaunchMode, now: Date) async -> TalkButton.Outcome {
        let onScreen = UIApplication.shared.applicationState == .active
        let step = TalkLaunchPlanner.step(mode: mode, conversation: pressState, appOnScreen: onScreen, now: now)
        log.notice("talk button: \(String(describing: step), privacy: .public), mode \(mode.rawValue, privacy: .public)")
        switch step {
        case .ignore:
            return .done
        case .endRunning:
            await VoiceSessionController.runningConversation?.stop()
            await VoiceLiveActivity.shared.settle()
            return .done
        case .showInApp:
            noteShortcutRan()
            ShortcutRouter.shared.talkButtonOpenedApp()
            return .done
        case .openApp:
            noteShortcutRan()
            return .openApp
        case .startInIsland:
            do {
                try await start(mode: mode)
                return .done
            } catch let problem as StartProblem {
                switch TalkLaunchPlanner.fallback(mode: mode, problem: problem.kind, canOpenApp: true) {
                case .openApp: return .openApp
                case .askToOpenApp(let reason): return .askToOpenApp(reason)
                case .tell(let message): return .tell(message)
                }
            } catch {
                return .tell(error.localizedDescription)
            }
        }
    }

    /// The older "Talk in the Island" control: always the island; a problem is only said.
    static func start() async throws {
        switch await press(mode: .dynamicIsland, now: .now) {
        case .done: return
        case .openApp: throw Problem(message: TalkButton.openDoddyToTalk)
        case .askToOpenApp(let message), .tell(let message): throw Problem(message: message)
        }
    }

    private struct StartProblem: Error {
        let kind: TalkStartProblem
    }

    /// The shortcut ran, so the "Open Doddy faster" card and its reminder are done (ADR-559).
    private static func noteShortcutRan() {
        let setup = ShortcutRouter.shared.setup
        setup.noteShortcutRan()
        Task { await OpenWaysReminderScheduler.refresh(setup) }
    }

    /// Starts the conversation and returns once it is connecting or live. Throws `StartProblem`.
    private static func start(mode: TalkLaunchMode) async throws {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        noteShortcutRan()

        // The terms come first (ADR-581); the "Before we start" step needs the screen.
        guard !LegalAcceptanceStore.isNeeded else {
            throw refused("terms not accepted", needsApp: NSLocalizedString("Open Doddy to accept the terms first.", comment: ""))
        }
        guard let store = IntentStores.store, store.environment.capabilities.isAvailable(.voiceInput) else {
            throw refused("voice input unavailable",
                          needsApp: NSLocalizedString("Doddy's voice isn't available right now. Open Doddy to see why.", comment: ""))
        }
        // The conversation hands the agent the saved notes, so it never starts past the Face ID lock.
        guard !AppLock.shared.isLocked else {
            throw refused("app lock", needsApp: NSLocalizedString("Doddy is locked. Open Doddy and unlock him to talk.", comment: ""))
        }
        // iOS stops a recording started this way unless its Live Activity is up.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw refused("live activities off", needsApp: NSLocalizedString("Doddy talks without opening only in the Dynamic Island. Turn on Live Activities for Doddy in iPhone Settings, or open Doddy to talk.", comment: ""))
        }
        // iOS can only ask about the microphone with Doddy on screen.
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw refused("microphone not allowed", needsApp: NSLocalizedString("Doddy needs the microphone. Open Doddy and start a conversation once to allow it.", comment: ""))
        }
        // The same account and voice-data gate as the voice screen (`VoiceView`).
        let provider = VoiceProvider.effective(
            stored: UserDefaults.standard.string(forKey: VoiceProvider.preferenceKey), tokenServerSet: true)
        let auth = VoiceAuthSession.shared
        await auth.restore()
        guard auth.isSignedIn || VoiceConfig.usesDirectAgent(for: provider), VoiceProviderConsent.isGranted(for: provider) else {
            throw refused("voice not set up", needsApp: NSLocalizedString("Open Doddy and start a conversation once to set up his voice. After that this works without opening him.", comment: ""))
        }

        // iOS may have started Doddy just for this, before any screen loaded the profile.
        let profiles = IntentStores.profiles
        if let profiles, !profiles.hasLoaded { await profiles.load() }
        let profile = profiles?.profile ?? .empty

        // Another conversation began while this press waited (a tap in the app): leave it.
        guard VoiceSessionController.runningConversation == nil else {
            log.notice("talk in the island: a conversation started meanwhile")
            return
        }
        let controller = VoiceSessionController(store: store)
        started = controller
        await controller.start(VoiceConfig.connectionMode, profile: profile,
                               wakeGreeting: greeting(for: profile), withoutOpeningApp: true)
        switch controller.phase {
        case .failed(let message):
            // The island or the microphone was refused in the background: opening Doddy fixes it.
            if controller.backgroundStartRefused { throw refused("refused in the background", needsApp: message) }
            throw refused("conversation failed", failed: message)
        case .microphoneDenied:
            throw refused("microphone denied", needsApp: NSLocalizedString("Doddy needs the microphone. Open Doddy and start a conversation once to allow it.", comment: ""))
        default:
            break
        }
        // Doddy came to the front while it started: iOS doesn't show his island over him, so show
        // the conversation instead of leaving it without a screen.
        if UIApplication.shared.applicationState == .active, VoiceSessionController.runningConversation != nil {
            ShortcutRouter.shared.showConversationStartedElsewhere()
        }
    }

    private static func refused(_ check: String, needsApp message: String) -> StartProblem {
        log.notice("talk in the island not started: \(check, privacy: .public)")
        return StartProblem(kind: .needsApp(message))
    }

    private static func refused(_ check: String, failed message: String) -> StartProblem {
        log.notice("talk in the island not started: \(check, privacy: .public)")
        return StartProblem(kind: .failed(message))
    }
}
