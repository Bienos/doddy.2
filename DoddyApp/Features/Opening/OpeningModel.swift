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
        act(on: OpeningPolicy.decide(conditions, trigger: .coldLaunch))
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
            act(on: OpeningPolicy.decide(conditions, trigger: .coldLaunch))
            return
        }
        guard let since = backgroundedAt else { return }
        backgroundedAt = nil
        act(on: OpeningPolicy.decide(conditions, trigger: .returned(after: now.timeIntervalSince(since))))
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
