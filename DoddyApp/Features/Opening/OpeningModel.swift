import DoddyCore
import Foundation
import Observation

/// Settings for the opening (ADR-207), read straight from UserDefaults so a UI-test launch
/// argument such as `-openingScene NO` works the same as the Settings switch.
enum OpeningPreferences {
    /// "Doddy's opening": on unless the user turned it off.
    static func sceneOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: PreferenceKey.openingScene) == nil ? true : defaults.bool(forKey: PreferenceKey.openingScene)
    }

    /// "Start listening when I open Doddy": on unless the user turned it off (owner decision,
    /// ADR-207). Must match the Settings toggle's default.
    static let listenOnOpenDefault = true

    static func listenOnOpen(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: PreferenceKey.listenOnOpen) == nil ? listenOnOpenDefault : defaults.bool(forKey: PreferenceKey.listenOnOpen)
    }
}

/// The four basketball drawings the opening sketches and animates, read once from the SVGs
/// bundled in `Resources/Character` (the supplied v1.3-r1 files, unchanged). The ball in each
/// is left out: the opening draws its own. Nil when a file is missing or can't be read, in
/// which case the opening doesn't play.
struct OpeningDrawings: Equatable, Sendable {
    let byPose: [OpeningPose: DoddyDrawing]

    subscript(pose: OpeningPose) -> DoddyDrawing? { byPose[pose] }

    static func load(from bundle: Bundle = .main) -> OpeningDrawings? {
        var byPose: [OpeningPose: DoddyDrawing] = [:]
        for pose in OpeningPose.allCases {
            guard let name = pose.svgResourceName else { continue }
            guard let url = bundle.url(forResource: name, withExtension: "svg"),
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  let drawing = try? SVGPoseReader.read(text)
            else { return nil }
            byPose[pose] = drawing.without(group: OpeningPose.ballGroup)
        }
        return OpeningDrawings(byPose: byPose)
    }
}

/// One showing of the opening.
struct OpeningPlay: Equatable, Sendable {
    let reducedMotion: Bool
    /// Open the conversation when the scene ends (Settings → "Start listening when I open Doddy").
    let thenListen: Bool
    let greeting: OpeningGreeting
    let drawings: OpeningDrawings
    let startedAt: Date
}

/// Home's state right after the opening: Doddy ready to talk, the hello as the heading, the
/// buttons sliding in. Over after `OpeningModel.readyFor` seconds.
struct OpeningReady: Equatable, Sendable {
    let greeting: OpeningGreeting
    let since: Date
}

/// Owns "is the opening on screen" and the two facts the policy needs about this process:
/// whether this is the launch, and how long the app was in the background. The rules are in
/// `OpeningPolicy` (DoddyCore, tested); the drawing is `OpeningSceneView`; Home shows `ready`.
@MainActor
@Observable
final class OpeningModel {
    /// How long Home keeps the ready pose and the hello after the opening.
    static let readyFor: TimeInterval = 8

    /// The opening on screen now; nil when nothing is showing.
    private(set) var play: OpeningPlay?
    /// Home's ready state: set as the opening starts (under it), kept for `readyFor` after it.
    private(set) var ready: OpeningReady?
    /// The opening's hand-over has begun: Home's buttons slide in.
    private(set) var handingOver = false
    /// Where Home draws Doddy, in global points, measured by Home. The opening lands him here.
    var homeArtBox: ScreenBox?
    private var consideredLaunch = false
    private var backgroundedAt: Date?
    private var drawings: OpeningDrawings?
    private var drawingsLoaded = false
    private var readyTimer: Task<Void, Never>?

    /// Call once Home is ready. The first time in this process, with the app on screen, counts
    /// as the launch; later calls (onboarding finished, the introduction reopened and closed)
    /// are not an opening. A launch in the background (a reminder's action) waits for
    /// `appBecameActive`, so nothing plays, and nothing listens, off screen.
    func homeReady(_ conditions: OpeningConditions, isActive: Bool, now: Date = .now) {
        guard isActive, !consideredLaunch else { return }
        consideredLaunch = true
        act(on: decide(conditions, trigger: .coldLaunch), now: now)
    }

    func appWentToBackground(now: Date = .now) {
        backgroundedAt = now
    }

    /// The first time the app is on screen is the launch if `homeReady` hasn't seen it yet. After
    /// that, a return from the background counts as an opening only after
    /// `OpeningPolicy.replayAfter`; a moment of inactivity (Control Centre, the app switcher) never.
    func appBecameActive(_ conditions: OpeningConditions, now: Date = .now) {
        if !consideredLaunch {
            consideredLaunch = true
            act(on: decide(conditions, trigger: .coldLaunch), now: now)
            return
        }
        guard let since = backgroundedAt else { return }
        backgroundedAt = nil
        guard play == nil else { return }
        act(on: decide(conditions, trigger: .returned(after: now.timeIntervalSince(since))), now: now)
    }

    /// The conversation came up on its own (Back Tap, Siri, the island) while the scene was
    /// playing: the scene stops, and nothing else opens.
    func conversationOpened() {
        guard play != nil else { return }
        play = nil
        handingOver = false
        keepReadyForAWhile()
    }

    /// The scene reached its hand-over (by itself or because the user tapped to skip).
    func handoverStarted() {
        handingOver = true
    }

    /// The scene reached its end: Doddy is in his place on Home. The conversation starts if that
    /// was decided.
    func finish() {
        guard let ended = play else { return }
        play = nil
        handingOver = false
        keepReadyForAWhile()
        if ended.thenListen { ShortcutRouter.shared.startListeningOnOpen() }
    }

    private func keepReadyForAWhile() {
        readyTimer?.cancel()
        readyTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.readyFor))
            guard !Task.isCancelled else { return }
            self?.ready = nil
        }
    }

    /// With nothing to draw (a missing or unreadable drawing) there is no scene to play.
    private func decide(_ conditions: OpeningConditions, trigger: OpeningTrigger) -> OpeningDecision {
        var conditions = conditions
        if conditions.sceneOn && loadedDrawings() == nil { conditions.characterArtHidden = true }
        return OpeningPolicy.decide(conditions, trigger: trigger)
    }

    private func loadedDrawings() -> OpeningDrawings? {
        if !drawingsLoaded {
            drawingsLoaded = true
            drawings = OpeningDrawings.load()
        }
        return drawings
    }

    private func act(on decision: OpeningDecision, now: Date) {
        switch decision {
        case .nothing:
            break
        case .scene(let reducedMotion, let thenListen):
            guard let drawings = loadedDrawings() else { return }
            let greeting = Self.greeting()
            // Home switches to Doddy ready to talk underneath, so it is right when it shows through.
            readyTimer?.cancel()
            ready = OpeningReady(greeting: greeting, since: now)
            handingOver = false
            play = OpeningPlay(
                reducedMotion: reducedMotion, thenListen: thenListen, greeting: greeting,
                drawings: drawings, startedAt: now)
        case .listenOnly:
            // Let Home appear first, so the conversation slides up over it as it does from the button.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                ShortcutRouter.shared.startListeningOnOpen()
            }
        }
    }

    /// The hello's words, from the same Settings as the voice: language, tone and nickname.
    static func greeting(defaults: UserDefaults = .standard, locale: Locale = .current) -> OpeningGreeting {
        OpeningGreetingCopy.render(
            language: ConversationLanguage.stored(in: defaults),
            deviceLanguageCode: locale.identifier,
            formality: PersonalitySettings.stored(in: defaults).formality,
            nickname: Nickname.stored(in: defaults))
    }
}
