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
    /// The connect of a start that has handed back to the intent (see `start(mode:)`). Held here so
    /// nothing releases it; it ends the island itself if the connect fails.
    private static var connecting: Task<Void, Never>?
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
            await startOnHome()
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

    /// Doddy is on screen (owner, 9 Nov 2026: "only the small island"): start the conversation on
    /// Home, where its strip over the island is the screen, instead of opening the voice screen.
    /// Anything that needs a screen (voice screen already up, Face ID lock, no store, the account or
    /// voice-data gate) falls back to the voice screen as before.
    static func startOnHome() async {
        let router = ShortcutRouter.shared
        guard !router.isVoicePresented, AppLockGate.allows(.startConversation), let store = IntentStores.store else {
            router.talkButtonOpenedApp()
            return
        }
        let profiles = IntentStores.profiles
        if let profiles, !profiles.hasLoaded { await profiles.load() }
        let profile = profiles?.profile ?? .empty
        let started = await HomeConversation.shared.startFromShortcut(store: store, profile: profile, greeting: greeting(for: profile))
        if !started { router.talkButtonOpenedApp() }
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
        // How old this process is and how long iOS took to load Doddy before this press (the timeline below
        // begins here, so it can't show that): fixed words and seconds only.
        log.notice("talk start launch: \(LaunchWork.launchTiming().line(), privacy: .public)")
        // Where the seconds go between the press and a connected conversation (decision 2026-11-10-voice-start-timing):
        // fixed stage words and seconds only, on the "voice-audio" log, whatever way the start ends.
        let requestedAt = ProcessInfo.processInfo.systemUptime
        var timeline = VoiceStartTimeline(startedAt: requestedAt)
        // After a hand-back the connect task writes the line itself, when it ends.
        var handedBack = false
        defer {
            if !handedBack { log.notice("talk start timing: \(timeline.line(at: ProcessInfo.processInfo.systemUptime), privacy: .public)") }
        }

        // The checks that need nothing but this iPhone come first, so a press that can't start never flashes
        // an island. None of them waits.
        // The terms come first (ADR-581); the "Before we start" step needs the screen.
        guard !LegalAcceptanceStore.isNeeded else {
            throw refused("terms not accepted", needsApp: NSLocalizedString("Open Doddy to accept the terms first.", comment: ""))
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
        let auth = VoiceAuthSession.shared
        // A Doddy account needs no restore of the older voice login, which refreshed it over the network
        // on a press (`TalkStartAccount`). The token request refreshes the account's own token itself.
        let needsRestore = TalkStartAccount.needsRestore(
            accountSignedIn: DoddyAccountModel.shared.isSignedIn,
            voiceSessionSecondsLeft: auth.voiceSessionSecondsLeft)
        let voiceNotSetUp = NSLocalizedString("Open Doddy and start a conversation once to set up his voice. After that this works without opening him.", comment: "")
        // Without a restore the gate is read now, before the island; with one, after it (below).
        if !needsRestore, !(auth.hasVoiceAccess() && VoiceProviderConsent.isGranted()) {
            throw refused("voice not set up", needsApp: voiceNotSetUp)
        }

        // The island first (decision 2026-11-13-island-first): up now as "Connecting…", before anything below
        // waits. Every way out of this start from here on ends it, unless a conversation took it over.
        let shownByPress = showIslandFirst()
        timeline.mark(.islandShown, at: ProcessInfo.processInfo.systemUptime)
        defer { settleIslandFirst(shownByPress: shownByPress) }
        noteShortcutRan()

        // iOS can run the intent before `DoddyApp.init` has set the stores, on a cold launch: wait a moment
        // for them instead of refusing "voice input unavailable".
        await IntentStores.waitForStore()
        guard let store = IntentStores.store, store.environment.capabilities.isAvailable(.voiceInput) else {
            throw refused("voice input unavailable",
                          needsApp: NSLocalizedString("Doddy's voice isn't available right now. Open Doddy to see why.", comment: ""))
        }
        if needsRestore { await auth.restore() }
        timeline.mark(.account, at: ProcessInfo.processInfo.systemUptime)
        guard auth.hasVoiceAccess(), VoiceProviderConsent.isGranted() else {
            throw refused("voice not set up", needsApp: voiceNotSetUp)
        }

        // iOS may have started Doddy just for this, before any screen loaded the profile.
        let profiles = IntentStores.profiles
        if let profiles, !profiles.hasLoaded { await profiles.load() }
        let profile = profiles?.profile ?? .empty
        timeline.mark(.profile, at: ProcessInfo.processInfo.systemUptime)

        // Another conversation began while this press waited (a tap in the app): leave it.
        guard VoiceSessionController.runningConversation == nil else {
            log.notice("talk in the island: a conversation started meanwhile")
            return
        }
        try Task.checkCancellation()
        let controller = VoiceSessionController(store: store)
        started = controller
        // Home shows the conversation from here on (ADR-595), so opening Doddy during it leaves the
        // app usable (Messages, notes) with Doddy talking, instead of a sheet covering it.
        HomeConversation.shared.hold(controller)
        // The intent must not wait for the token request and the connect (up to 10 s): a background
        // intent has a short time budget, and iOS can end it before the island is seen. It returns once the
        // island and audio session are up (`backgroundStartReady`) and the connect carries on in a task
        // held here, under a background-task assertion. A late failure ends the island through the
        // controller's own `fail`, so no "connecting" island is left behind.
        let run = StartRun()
        let greetingLine = greeting(for: profile)
        let mode = VoiceConfig.connectionMode
        let startTask = Task { @MainActor in
            // A timeout can cancel this task before it gets its first turn. Never let that
            // abandoned press open the microphone later, after the foreground fallback.
            guard !Task.isCancelled else { run.finished = true; return }
            // The first sound of this conversation is timed from the press (decision 2026-11-14-first-audible-sound).
            AgentVoiceMeter.shared.beginStart(at: requestedAt)
            await controller.start(mode, profile: profile, wakeGreeting: greetingLine, withoutOpeningApp: true,
                                   requestedAt: requestedAt)
            run.finished = true
        }
        var waited: TimeInterval = 0
        let waitStart = ProcessInfo.processInfo.systemUptime
        while TalkStartHandoff.decide(islandReady: controller.backgroundStartReady, startEnded: run.finished || controller.phase.endedStart, waited: waited) == .keepWaiting {
            do {
                try await Task.sleep(for: .milliseconds(40))
            } catch {
                await cancelStart(startTask, controller: controller)
                throw error
            }
            waited = ProcessInfo.processInfo.systemUptime - waitStart
        }
        timeline.mark(.island, at: ProcessInfo.processInfo.systemUptime)
        if TalkStartHandoff.decide(islandReady: controller.backgroundStartReady,
                                   startEnded: run.finished || controller.phase.endedStart,
                                   waited: waited) == .timedOut {
            await cancelStart(startTask, controller: controller)
            throw refused("island start timed out", needsApp: TalkButton.openDoddyToTalk)
        }
        // A deliberate press asks for the popup immediately, still labelled Connecting.
        // Waiting for the first speaking event made an otherwise working start look inert.
        // iOS owns whether the expansion is shown; no claim that the agent can hear yet.
        // Only with Settings › "Expand when Doddy speaks" on, which is off unless the owner turned it
        // on (owner, 9 Nov 2026: only the small island; 12 Nov: "it switches from big to small"). The
        // conversation's own expansion (`IslandExpansion`) already follows the same switch.
        let expands = LaunchPreferencesMigration.islandExpands(
            UserDefaults.standard.object(forKey: LaunchPreferencesMigration.islandExpandsKey) as? Bool)
        if expands, controller.backgroundStartReady, controller.isLive {
            VoiceLiveActivity.shared.expand()
        }
        if !(run.finished || controller.phase.endedStart) {
            handedBack = true
            let handedTimeline = timeline
            let background = UIApplication.shared.beginBackgroundTask(withName: "doddy-talk-connect")
            connecting = Task { @MainActor in
                await startTask.value
                var done = handedTimeline
                done.mark(.connect, at: ProcessInfo.processInfo.systemUptime)
                log.notice("talk start timing: \(done.line(at: ProcessInfo.processInfo.systemUptime, token: controller.tokenSource), privacy: .public)")
                if case .failed = controller.phase { log.notice("talk in the island: the connection failed after the intent returned") }
                if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
                connecting = nil
            }
            return
        }
        timeline.mark(.connect, at: ProcessInfo.processInfo.systemUptime)
        log.notice("talk start timing: \(timeline.line(at: ProcessInfo.processInfo.systemUptime, token: controller.tokenSource), privacy: .public)")
        handedBack = true
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
        // Doddy came to the front while it started: iOS doesn't show his island over him, but Home
        // holds the conversation and shows it, so nothing is put over the app. The transcript sheet
        // comes up by itself only when a card needs the user (`HomeConversation.needsYou`).
    }

    /// Puts the island up now as "Connecting…" (decision 2026-11-13-island-first), with the greeting Doddy will
    /// open with, as the conversation shows it while it connects. True only when this press put it up: false when
    /// one was already up (not this press's) or iOS refused it, and then the conversation asks again itself and
    /// says so if it is refused. The conversation takes this island over at its own "Connecting…".
    private static func showIslandFirst() -> Bool {
        let island = VoiceLiveActivity.shared
        guard !island.isShowing else { return false }
        // The profile only if a screen already loaded it; the greeting gains the name when the conversation starts.
        let profile = IntentStores.profiles.flatMap { $0.hasLoaded ? $0.profile : nil } ?? .empty
        var state = DoddyVoiceAttributes.ContentState(status: .connecting, isMuted: false, greeting: greeting(for: profile))
        // ADR-617: the island speaks the language of Doddy's screens, as the conversation's own state does.
        state.language = Bundle.main.preferredLocalizations.first
        island.show(state, startedAt: .now)
        let shown = island.isShowing
        let word = shown ? "shown" : "refused by iOS"
        log.notice("talk in the island: island \(word, privacy: .public) before the set-up")
        return shown
    }

    /// The island the press put up stays only if a conversation is connecting or live; otherwise it goes at once.
    private static func settleIslandFirst(shownByPress: Bool) {
        let live = VoiceSessionController.current != nil
        guard TalkIslandFirst.afterwards(shownByPress: shownByPress, conversationLive: live) == .end else { return }
        log.notice("talk in the island: the press's island was ended, no conversation took it over")
        VoiceLiveActivity.shared.end()
    }

    /// Whether the start's `controller.start` has returned, read by the polling intent.
    @MainActor private final class StartRun { var finished = false }

    private static func cancelStart(_ task: Task<Void, Never>, controller: VoiceSessionController) async {
        task.cancel()
        // stop invalidates the controller's attempt before any await: a late token/context/SDK
        // answer cannot revive it. Do not await the uncooperative network operation itself.
        await controller.stop()
        await VoiceLiveActivity.shared.settle()
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

private extension VoiceSessionController.Phase {
    /// The start is over without a conversation: failed, microphone refused or ended. `.idle` is not,
    /// because the start task may not have begun yet.
    var endedStart: Bool {
        switch self {
        case .failed, .microphoneDenied, .ended: true
        default: false
        }
    }
}
