import DoddyCore
import Foundation
import Observation

/// Single owner of "what the app shows because a shortcut ran". The Talk to Doddy intent and
/// the UI both go through it, so a second invocation focuses the open conversation instead of
/// starting a second one, and a tap test can claim the invocation as its receipt.
@MainActor
@Observable
final class ShortcutRouter {
    static let shared = ShortcutRouter()

    /// Bound to the full-screen voice conversation in `RootView`.
    var isVoicePresented = false
    /// Bound to the guided Back Tap setup sheet in `RootView`.
    var isSetupPresented = false
    let setup: BackTapSetupModel

    init(setup: BackTapSetupModel = BackTapSetupModel()) {
        self.setup = setup
    }

    /// Called from `TalkToDoddyIntent.perform()`. If a tap test is active the invocation is its
    /// receipt and the setup sheet takes over; otherwise the voice conversation opens.
    func talkToDoddyInvoked(at now: Date = .now) {
        if setup.deliver(ShortcutReceipt(receivedAt: now)) {
            isVoicePresented = false
            isSetupPresented = true
        } else {
            isSetupPresented = false
            isVoicePresented = true
        }
    }
}

/// Main-actor state over the deterministic `BackTapSetupCoordinator`. Persists only the
/// outcome (not started / deferred / tested by the user) and an active test window, as JSON in
/// UserDefaults next to the other UI preferences. Never any transcript or reported page.
@MainActor
@Observable
final class BackTapSetupModel {
    private(set) var coordinator: BackTapSetupCoordinator
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults
        coordinator = BackTapSetupCoordinator(summary: Self.load(from: defaults), now: now)
    }

    var phase: BackTapSetupPhase { coordinator.phase }

    @discardableResult
    func send(_ event: BackTapSetupEvent) -> BackTapSetupOutcome {
        let outcome = coordinator.handle(event)
        persist()
        return outcome
    }

    /// True when the receipt matched an active test (the coordinator decides; stale, early or
    /// duplicate receipts and receipts outside a test are refused).
    func deliver(_ receipt: ShortcutReceipt) -> Bool {
        send(.receipt(receipt)) == .accepted
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(coordinator.summary) {
            defaults.set(data, forKey: PreferenceKey.backTapSetup)
        }
    }

    private static func load(from defaults: UserDefaults) -> BackTapSetupSummary {
        // UI tests preset the outcome with e.g. "-backTapSetupStatus deferred".
        if let raw = defaults.string(forKey: PreferenceKey.backTapSetupStatus),
           let status = BackTapSetupSummary.Status(rawValue: raw) {
            return BackTapSetupSummary(status: status, testedAt: status == .userReportedTested ? .now : nil)
        }
        guard let data = defaults.data(forKey: PreferenceKey.backTapSetup),
              let summary = try? JSONDecoder().decode(BackTapSetupSummary.self, from: data)
        else { return BackTapSetupSummary() }
        return summary
    }
}
