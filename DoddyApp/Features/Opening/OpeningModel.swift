import DoddyCore
import Foundation
import Observation

/// Settings for opening the app (ADR-225), read straight from UserDefaults so a UI-test launch
/// argument such as `-listenOnOpen NO` works the same as the Settings switch.
enum OpeningPreferences {
    /// Voice never starts just because the person installed or reopened the app. They can opt in
    /// separately in Settings → Voice.
    static let listenOnOpenDefault = false

    static func listenOnOpen(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: PreferenceKey.listenOnOpen) == nil ? listenOnOpenDefault : defaults.bool(forKey: PreferenceKey.listenOnOpen)
    }
}

/// Whether a link opened the app (`doddy://…`, a widget's link, the island's Show button): the scene delegate
/// notes it (`ShareAcceptSceneDelegate`) before the app becomes active, and the next opening decision uses it
/// up. The rule is `LinkOpenNote` in DoddyCore: a link goes where it points and never also starts listening.
@MainActor
enum OpeningLinks {
    private static var note = LinkOpenNote()

    static func linkOpened(now: Date = .now) { note.linkOpened(at: now) }

    static func take(for trigger: OpeningTrigger, now: Date = .now) -> Bool { note.take(for: trigger, now: now) }
}

/// Owns the two facts `OpeningPolicy` needs about this process: whether this is the launch, and
/// how long the app was in the background. The rules are in `OpeningPolicy` (DoddyCore, tested).
/// The first-launch basketball opening this model also played was removed with its v1.3 art
/// (decision 2026-11-09-remove-old-design-leftovers); only "Start listening when I open Doddy" is left.
@MainActor
@Observable
final class OpeningModel {
    private var consideredLaunch = false
    private var backgroundedAt: Date?

    /// Call once Home is ready. The first time in this process, with the app on screen, counts
    /// as the launch; later calls (onboarding finished, the introduction reopened and closed)
    /// are not an opening. A launch in the background (a reminder's action) waits for
    /// `appBecameActive`, so nothing listens off screen.
    func homeReady(_ conditions: OpeningConditions, isActive: Bool) {
        guard isActive, !consideredLaunch else { return }
        consideredLaunch = true
        act(on: decide(conditions, trigger: .coldLaunch))
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
            act(on: decide(conditions, trigger: .coldLaunch, now: now))
            return
        }
        guard let since = backgroundedAt else { return }
        backgroundedAt = nil
        act(on: decide(conditions, trigger: .returned(after: now.timeIntervalSince(since)), now: now))
    }

    /// `OpeningPolicy`'s answer, with "a link opened the app" filled in from the scene's note. The note is used up
    /// by every real decision, so it can't outlive the opening it belongs to.
    private func decide(_ conditions: OpeningConditions, trigger: OpeningTrigger, now: Date = .now) -> OpeningDecision {
        var conditions = conditions
        let byLink = OpeningLinks.take(for: trigger, now: now)
        conditions.openedByURL = conditions.openedByURL || byLink
        return OpeningPolicy.decide(conditions, trigger: trigger)
    }

    private func act(on decision: OpeningDecision) {
        guard decision.listens else { return }
        // Let Home appear first, so the conversation slides up over it as it does from the button.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            ShortcutRouter.shared.startListeningOnOpen()
        }
    }
}
