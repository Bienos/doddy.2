import AVFAudio
import DoddyCore
import Foundation
import Observation
import UIKit
import os

/// "Hey Doddy" (ADR-254, ADR-472). Off unless the user turns it on in Settings. While on, Apple's
/// on-device speech recognition (`SpeechWakeEngine`) listens on this iPhone for the wake word;
/// nothing it hears is kept or sent. Hearing it starts an ordinary voice
/// conversation (the same `VoiceSessionController` a tap starts) and the Dynamic Island greets
/// the user: "Hey Pat, what's up?".
///
/// What iOS allows, and so what this does:
/// - The microphone starts only while Doddy is open. It keeps running in the background (the
///   app's audio background mode), with the island saying "Say “Hey Doddy”" and iOS's own
///   microphone indicator on, until iOS ends the app or something below stops it.
/// - One Live Activity carries both the listening and the conversation it starts, because iOS
///   doesn't let an app start a Live Activity from the background.
/// - It stops for a conversation (which needs the microphone), while Doddy plays sound, in Low
///   Power Mode, when a call or another app takes the microphone, and when the user taps Stop
///   listening on the island (that turns the switch off). After a conversation it tries to start
///   again at once; if iOS refuses in the background, it waits until Doddy is opened and the
///   island goes away rather than claim to listen.
///
/// The only file that runs the wake-word engine (scripts/check_forbidden_capabilities.sh). Not
/// verified on a device: see docs/implementation/HEY_DODDY_STATUS.md.
@MainActor
@Observable
final class WakeWordListener {
    static let shared = WakeWordListener()

    /// What Settings shows. Worked out by `WakeListenerPolicy` from the current conditions.
    private(set) var state: WakeListenerState = .off
    /// The conversation the wake word started, until the voice screen takes it.
    private(set) var wakeConversation: VoiceSessionController?

    /// Set at launch by `DoddyApp`.
    @ObservationIgnored var store: MemoryStore?
    @ObservationIgnored var profiles: ProfileStore?

    @ObservationIgnored private var engine: SpeechWakeEngine?
    @ObservationIgnored private var running = false
    /// The engine's recorder is running (Stop listening reads it, ADR-361).
    var isEngineRunning: Bool { running }
    @ObservationIgnored private var gate = WakeGate()
    @ObservationIgnored private var inForeground = false
    @ObservationIgnored private var interrupted = false
    /// What in Doddy is playing or recording sound right now (read aloud, voice memos, voice samples).
    @ObservationIgnored private var appSounds: Set<ObjectIdentifier> = []
    @ObservationIgnored private var startFailure: String?
    /// From the wake word until the conversation has started (or failed to).
    @ObservationIgnored private var handingOver = false
    /// Right after a conversation gives the microphone back: the one moment a restart in the
    /// background may still work, because the app's audio session is active.
    @ObservationIgnored private var mayRestartInBackground = false
    /// After a conversation, until its audio has been shut down: starting the recorder earlier
    /// could be stopped by that shutdown without anyone noticing.
    @ObservationIgnored private var waitingForConversationAudio = false
    @ObservationIgnored private var audioReleaseFallback: Task<Void, Never>?
    /// True while the island shows "Hey Doddy" listening or paused for this listener.
    @ObservationIgnored private var ownsIsland = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var restEnds: Task<Void, Never>?
    private let island = VoiceLiveActivity.shared
    /// UI-test launches never listen, whatever an earlier run left in the settings.
    private let isAllowedThisLaunch = !ProcessInfo.processInfo.arguments.contains("-inMemoryStore")
    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "hey-doddy")
    /// When a conversation ended without `stop()` (the agent hung up, the connection dropped),
    /// nobody says when its audio is gone; listening restarts after this instead.
    private static let audioReleaseFallbackDelay: TimeInterval = 1.5

    private init() {}

    // MARK: Called by the app

    func appBecameActive() {
        inForeground = true
        watchSystem()
        refresh()
    }

    func appWentToBackground() {
        inForeground = false
        refresh()
    }

    /// The switch or a permission changed: start over with the new setup.
    func setupChanged() {
        startFailure = nil
        dropEngine()
        refresh()
    }

    /// Settings → Hey Doddy switch, or the Home card. Asks iOS for the microphone and for speech
    /// recognition here, where the user can answer.
    func turnOn() async {
        UserDefaults.standard.set(true, forKey: PreferenceKey.heyDoddyOn)
        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }
        await SpeechWakeEngine.requestAuthorization()
        setupChanged()
    }

    /// Settings, or Stop listening on the island.
    func turnOff() {
        UserDefaults.standard.set(false, forKey: PreferenceKey.heyDoddyOn)
        setupChanged()
    }

    /// Read aloud, voice memos and voice samples need the audio set up their way: listening
    /// steps aside while any of them plays or records. Each passes `ObjectIdentifier(self)`, so
    /// one finishing doesn't restart listening while another is still going.
    func appSound(_ source: ObjectIdentifier, playing: Bool) {
        let wasPlaying = !appSounds.isEmpty
        if playing { appSounds.insert(source) } else { appSounds.remove(source) }
        guard wasPlaying != !appSounds.isEmpty else { return }
        refresh()
    }

    /// Whether the voice screen should open for the wake word's conversation when the app comes
    /// to the front: it is running, or it ended with notes to look at.
    var hasConversationToShow: Bool {
        guard let conversation = wakeConversation else { return false }
        return handingOver || conversation.isLive || conversation.pendingAction != nil || conversation.saveSuggestions != nil
    }

    /// The voice screen takes the wake word's conversation instead of starting its own.
    func takeConversation() -> VoiceSessionController? {
        defer { wakeConversation = nil }
        return wakeConversation
    }

    /// A finished conversation with nothing to look at isn't kept for the voice screen.
    func forgetFinishedConversation() {
        if !hasConversationToShow { wakeConversation = nil }
    }

    /// The voice screen picked up this conversation as the one already running (ADR-496), so it
    /// is no longer waiting to be shown; a later screen must not get it again once it has ended.
    func conversationShown(_ conversation: VoiceSessionController) {
        if wakeConversation === conversation { wakeConversation = nil }
    }

    /// Called by `VoiceSessionController` when its conversation is over and it would end the
    /// island. Returns true when "Hey Doddy" takes the island back (it shows "paused" until the
    /// conversation's audio is gone, then listening, or ends it if iOS refuses the microphone);
    /// false when the conversation should end the island as usual.
    func takeIslandBack() -> Bool {
        handingOver = false
        guard WakeListenerPolicy.state(conditions(mayStartMicrophone: true)) == .listening else {
            refresh()
            return false
        }
        waitingForConversationAudio = true
        ownsIsland = true
        island.show(Self.styled(.wakePaused), startedAt: .now)
        audioReleaseFallback?.cancel()
        audioReleaseFallback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.audioReleaseFallbackDelay))
            guard !Task.isCancelled else { return }
            self?.conversationAudioReleased()
        }
        return true
    }

    /// The conversation's audio has been shut down (`VoiceSessionController.stop()` after the
    /// SDK ended it, or the fallback delay): listening may start again.
    func conversationAudioReleased() {
        guard waitingForConversationAudio else { return }
        audioReleaseFallback?.cancel()
        audioReleaseFallback = nil
        waitingForConversationAudio = false
        mayRestartInBackground = true
        refresh()
    }

    // MARK: State

    private func conditions(mayStartMicrophone: Bool) -> WakeConditions {
        WakeConditions(
            // A Focus with Doddy's filter can pause listening (ADR-312); the switch itself stays on.
            switchedOn: isAllowedThisLaunch && UserDefaults.standard.bool(forKey: PreferenceKey.heyDoddyOn)
                && !FocusFilterState.shared.settings.pausesHeyDoddy,
            speech: SpeechWakeEngine.availability,
            microphone: Self.microphone,
            conversationOrVoiceScreen: handingOver || waitingForConversationAudio
                || VoiceSessionController.conversationInProgress || ShortcutRouter.shared.isVoicePresented,
            appSoundPlaying: !appSounds.isEmpty,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            interrupted: interrupted,
            overWakeLimit: gate.isOverLimit(at: .now),
            mayStartMicrophone: mayStartMicrophone,
            running: running,
            startFailure: startFailure)
    }

    func refresh() {
        var current = conditions(mayStartMicrophone: inForeground || mayRestartInBackground)
        mayRestartInBackground = false
        var target = WakeListenerPolicy.state(current)
        switch target {
        case .listening:
            if !running {
                startEngine(inBackground: !inForeground)
                current.running = running
                current.startFailure = startFailure
                current.mayStartMicrophone = false
                target = WakeListenerPolicy.state(current)
            }
        case .paused(.interrupted):
            // The engine's audio stopped itself; it starts again when iOS says it may.
            break
        case .off, .speechNotAllowed, .speechUnavailable, .microphoneDenied:
            dropEngine()
        default:
            stopEngine()
        }
        state = target
        syncIsland()
        scheduleRestEnd()
        ListeningIndicatorModel.shared.refresh()
    }

    private static var microphone: WakeConditions.Microphone {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .allowed
        case .denied: .denied
        default: .notAsked
        }
    }

    // MARK: Engine

    private func startEngine(inBackground: Bool) {
        do {
            if engine == nil {
                engine = SpeechWakeEngine(onDetection: Self.detectionHandler(), onFailure: Self.errorHandler())
            }
            try engine?.start()
            running = true
            startFailure = nil
            gate.listeningStarted(at: .now)
            Self.log.notice("listening for the wake word (background: \(inBackground, privacy: .public))")
        } catch {
            running = false
            Self.log.error("couldn't start listening: \(error.localizedDescription, privacy: .public)")
            // In the background iOS may simply refuse the microphone; that's "open Doddy", not a fault.
            if !inBackground || Self.isSetupError(error) { startFailure = Self.message(for: error) }
        }
    }

    private func stopEngine() {
        guard running else { return }
        engine?.stop()
        running = false
        gate.listeningStopped()
    }

    private func dropEngine() {
        stopEngine()
        engine = nil
    }

    /// The engine calls these on audio and recognition threads, so they are made outside the main actor.
    nonisolated private static func detectionHandler() -> @Sendable () -> Void {
        { Task { @MainActor in WakeWordListener.shared.heard() } }
    }

    nonisolated private static func errorHandler() -> @Sendable (String) -> Void {
        { text in Task { @MainActor in WakeWordListener.shared.engineFailed(text) } }
    }

    private func engineFailed(_ description: String) {
        Self.log.error("listening failed: \(description, privacy: .public)")
        stopEngine()
        startFailure = description
        refresh()
    }

    private static func isSetupError(_ error: Error) -> Bool {
        guard let error = error as? SpeechWakeEngine.StartError else { return false }
        switch error {
        case .speechNotAllowed, .unavailable: return true
        case .audio: return false
        }
    }

    private static func message(for error: Error) -> String {
        switch error as? SpeechWakeEngine.StartError {
        case .speechNotAllowed?:
            "Doddy isn't allowed to use speech recognition. Allow it in iOS Settings, Doddy."
        case .unavailable?:
            "This iPhone can't recognize English on the device, so “Hey Doddy” can't listen without sending sound to Apple. It stays off."
        case .audio(let reason)?:
            "The microphone couldn't start (\(reason))."
        case nil:
            "The microphone couldn't start (\(error.localizedDescription))."
        }
    }

    // MARK: The wake word

    private func heard() {
        guard running, state == .listening else { return }
        // One conversation at a time (ADR-496): one is already starting or live (the voice screen
        // opened a moment ago), so the wake word starts nothing and doesn't count towards the
        // hourly limit; refresh pauses the listener for that conversation.
        if VoiceSessionController.runningConversation != nil {
            Self.log.notice("wake word ignored: a conversation is already starting or live")
            refresh()
            return
        }
        guard gate.accept(at: .now) else {
            // Too soon after starting, or too many this hour (refresh rests the listener).
            refresh()
            return
        }
        guard let store else { return }
        // Whether Doddy was on screen: a start from the background is the leading suspect for the
        // silent 30-second sessions (docs/implementation/VOICE_SESSION_STARTS.md).
        let heardNote = "wake word heard (Doddy in foreground: \(inForeground))"
        Self.log.notice("\(heardNote, privacy: .public)")
        // The conversation needs the microphone: give it up first.
        stopEngine()
        handingOver = true
        ownsIsland = false

        let profile = profiles?.profile ?? .empty
        let name = WakeGreeting.name(nickname: Nickname.stored(), profileName: profile.value(.name))
        let greeting = WakeGreeting.line(name: name, polish: ConversationLanguage.stored() == .polish)
        // Answer on the island at once, before connecting.
        let now = Date()
        island.show(Self.styled(.init(status: .connecting, isMuted: false, greeting: greeting, conversationStartedAt: now)), startedAt: now)

        let conversation = VoiceSessionController(store: store)
        wakeConversation = conversation
        state = .paused(.conversation)
        // On screen: open the voice screen now, unless another sheet is up (it would be pushed
        // aside); then it opens when Doddy next comes to the front.
        if inForeground { _ = ShortcutRouter.shared.showWakeConversation() }

        // Keeps the app running in the background between letting go of the microphone and the
        // conversation taking it.
        let background = UIApplication.shared.beginBackgroundTask(withName: "Hey Doddy")
        Task {
            await conversation.start(Self.connectionMode(), profile: profile, wakeGreeting: greeting)
            if !conversation.isLive, conversation.phase != .ended {
                // It never got going (not set up, microphone refused, no connection): the island
                // still shows the greeting, so this listener deals with it.
                ownsIsland = true
            }
            handingOver = false
            // Doddy may be in the background: this is the moment a restart can still work.
            mayRestartInBackground = true
            refresh()
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }
    }

    /// Voice sessions always use DODDY's authenticated server; the app never falls back to a public agent.
    private static func connectionMode() -> VoiceConnectionMode {
        VoiceConnectionMode.resolve(serverAddress: VoiceConfig.tokenEndpointAddress)
    }

    // MARK: Island

    private func syncIsland() {
        // The wake word's conversation is starting, or the last one's audio is still shutting
        // down: the island is in someone's hands already.
        if handingOver || waitingForConversationAudio { return }
        // Listening, or paused by a call or another app (listening starts again when iOS allows):
        // the island says which.
        let shown: DoddyVoiceAttributes.ContentState? = switch state {
        case .listening: .wakeListening
        case .paused(.interrupted) where ownsIsland: .wakePaused
        default: nil
        }
        if let shown {
            guard !VoiceSessionController.conversationInProgress else { return }
            island.show(Self.styled(shown), startedAt: .now)
            ownsIsland = true
            // Stop listening on the island turns "Hey Doddy" off. Nothing to mute.
            let actions = VoiceActivityActions.shared
            actions.endConversation = { WakeWordListener.shared.turnOff() }
            actions.toggleMute = nil
        } else if ownsIsland {
            ownsIsland = false
            // A conversation that is running has taken the island over.
            if !VoiceSessionController.conversationInProgress { island.end() }
        }
    }

    /// The island looks the way the user picked in Settings (ADR-239), like a conversation's.
    private static func styled(_ state: DoddyVoiceAttributes.ContentState) -> DoddyVoiceAttributes.ContentState {
        var state = state
        state.islandStyle = IslandStyle.stored(UserDefaults.standard.string(forKey: PreferenceKey.islandStyle))
        return state
    }

    // MARK: System events

    private func watchSystem() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in WakeWordListener.shared.refresh() }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { note in
            let info = note.userInfo
            let began = (info?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            let options = AVAudioSession.InterruptionOptions(rawValue: info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            let shouldResume = options.contains(.shouldResume)
            Task { @MainActor in WakeWordListener.shared.interruption(began: began, shouldResume: shouldResume) }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { _ in
            // iOS restarted its audio system: the recorder is gone. Start over.
            Task { @MainActor in WakeWordListener.shared.setupChanged() }
        })
    }

    private func interruption(began: Bool, shouldResume: Bool) {
        // Interruptions during a conversation are the conversation's business.
        guard running || interrupted else { return }
        if began {
            interrupted = true
        } else {
            interrupted = false
            // Without "should resume" the recorder stays stopped: start it again ourselves.
            if !shouldResume { stopEngine() }
        }
        refresh()
    }

    /// Listening rests after too many wake-ups; this comes back when the hour has passed.
    private func scheduleRestEnd() {
        restEnds?.cancel()
        restEnds = nil
        guard state == .paused(.tooManyWakeUps), let end = gate.limitEnds(at: .now) else { return }
        restEnds = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, end.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
