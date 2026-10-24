import DoddyCore
import Foundation
import Observation

/// The stopwatch (ADR-614): one at a time, kept in UserDefaults so it survives the app being
/// closed, with a Lock Screen and Dynamic Island clock that counts up by itself. The timing rules
/// are `Stopwatch` (DoddyCore, tested). It sends no notification: nothing ends. It measures time
/// and claims nothing else.
@MainActor
@Observable
final class StopwatchController {
    static let shared = StopwatchController()

    private(set) var watch: Stopwatch?

    @ObservationIgnored private let island = ToolLiveActivity(kind: .stopwatch)
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "stopwatch"
    /// How long "Stopped at 12:07" stays on the Lock Screen after a stop.
    private static let stoppedCardFor: TimeInterval = 300

    enum StartOutcome: Equatable {
        case started(Stopwatch)
        /// One is already running or paused: it was not replaced.
        case alreadyThere(Stopwatch)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            watch = try? JSONDecoder().decode(Stopwatch.self, from: data)
        }
        // The island's buttons reach this object even when iOS launched the app just for them.
        ToolActivityActions.shared.togglePause[.stopwatch] = { [weak self] in self?.togglePause() }
        ToolActivityActions.shared.stop[.stopwatch] = { [weak self] in self?.stop() }
    }

    /// At launch and on every return to the foreground: pick up the island and stop a stopwatch
    /// left running to its limit.
    func refresh(now: Date = Date()) {
        island.adoptExisting()
        guard var watch else {
            island.end(final: nil)
            return
        }
        if watch.stopIfAtLimit(at: now) {
            self.watch = watch
            save()
        }
        sync(now: now)
    }

    /// Starts one, unless one is already running or paused (the user's reading is never replaced).
    @discardableResult
    func start(label: String?, now: Date = Date()) -> StartOutcome {
        if let watch, !watch.isOver { return .alreadyThere(watch) }
        let new = Stopwatch(label: label, now: now)
        watch = new
        save()
        sync(now: now)
        return .started(new)
    }

    func togglePause(now: Date = Date()) {
        guard var watch else { return }
        if watch.isRunning { watch.pause(at: now) } else if watch.isPaused { watch.resume(at: now) }
        self.watch = watch
        save()
        sync(now: now)
    }

    /// Stops it and returns the reading it stopped at; nil when there is none or it was over already.
    @discardableResult
    func stop(now: Date = Date()) -> TimeInterval? {
        guard var watch, !watch.isOver else { return nil }
        watch.stop(at: now)
        self.watch = watch
        save()
        sync(now: now)
        return watch.elapsed(at: now)
    }

    /// Clears a stopped stopwatch from the screen.
    func dismiss() {
        guard watch?.isOver == true else { return }
        watch = nil
        save()
        island.end(final: nil)
    }

    private func sync(now: Date) {
        guard let watch else { return }
        switch watch.state {
        case .running:
            island.show(.init(isPaused: false, endsAt: nil, label: watch.label, countsFrom: watch.countsFrom),
                        startedAt: watch.startedAt, duration: 0)
        case .paused:
            island.show(.init(isPaused: true, endsAt: nil, label: watch.label, elapsed: watch.elapsed(at: now)),
                        startedAt: watch.startedAt, duration: 0)
        case .stopped:
            island.end(final: .init(isPaused: false, endsAt: nil, label: watch.label, isFinished: true,
                                    elapsed: watch.elapsed(at: watch.stoppedAt ?? now)),
                       keepFor: Self.stoppedCardFor)
        }
    }

    private func save() {
        if let watch, let data = try? JSONEncoder().encode(watch) {
            defaults.set(data, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}
