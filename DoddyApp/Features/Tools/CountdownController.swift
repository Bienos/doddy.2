import DoddyCore
import Foundation
import Observation
import UserNotifications

/// Countdown timers (ADR-337): the kitchen timer ("pasta, 10 minutes", by voice or from Home)
/// and the wind-down before bed. One countdown of each purpose at a time, kept in UserDefaults
/// so it survives the app being closed, with a "done" notification and the island. The timing
/// rules are `CountdownSession` (DoddyCore, tested). The notification is checked in iOS's
/// pending list after it is added; the screen says so when it could not be confirmed. Like the
/// focus timer, the island's buttons reach this object even when iOS started the app just for
/// them.
@MainActor
@Observable
final class CountdownController {
    static let shared = CountdownController()

    enum Outcome: Equatable {
        /// The countdown runs and iOS lists its "done" notification as pending.
        case verified
        /// The countdown runs, but iOS didn't confirm the notification (or notifications are off).
        case unconfirmed
    }

    private(set) var sessions: [CountdownSession.Purpose: CountdownSession] = [:]
    /// nil until a countdown asks: true when iOS lists its "done" notification as pending.
    private(set) var notificationConfirmed: [CountdownSession.Purpose: Bool] = [:]

    @ObservationIgnored private var islands: [CountdownSession.Purpose: ToolLiveActivity] = [
        .timer: ToolLiveActivity(kind: .timer),
        .windDown: ToolLiveActivity(kind: .windDown),
    ]
    @ObservationIgnored private var finishTimers: [CountdownSession.Purpose: Task<Void, Never>] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "countdownSessions"
    /// How long the done card stays on the Lock Screen after the app noticed.
    private static let finishedCardFor: TimeInterval = 300

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([CountdownSession].self, from: data) {
            for session in saved { sessions[session.purpose] = session }
        }
        for purpose in [CountdownSession.Purpose.timer, .windDown] {
            ToolActivityActions.shared.togglePause[Self.kind(purpose)] = { [weak self] in self?.togglePause(purpose) }
            ToolActivityActions.shared.stop[Self.kind(purpose)] = { [weak self] in self?.stop(purpose) }
        }
    }

    static func kind(_ purpose: CountdownSession.Purpose) -> DoddyToolAttributes.Kind {
        purpose == .windDown ? .windDown : .timer
    }

    func session(_ purpose: CountdownSession.Purpose) -> CountdownSession? { sessions[purpose] }

    /// At launch and on every return to the foreground: pick up the islands, notice a finished
    /// countdown, and wait for the end of a running one.
    func refresh(now: Date = Date()) {
        for (purpose, island) in islands {
            island.adoptExisting()
            guard var session = sessions[purpose] else {
                island.end(final: nil)
                continue
            }
            if session.finishIfDue(at: now) {
                sessions[purpose] = session
                save()
            }
            sync(purpose)
        }
    }

    /// Starts a countdown; a running one of the same purpose is stopped first (its
    /// notification is cancelled). Returns whether the "done" notification was confirmed.
    @discardableResult
    func start(seconds: Int, purpose: CountdownSession.Purpose, label: String?) async -> Outcome {
        let now = Date()
        if sessions[purpose].map({ !$0.isOver }) == true { stop(purpose) }
        let new = CountdownSession(seconds: seconds, purpose: purpose, label: label, now: now)
        sessions[purpose] = new
        save()
        let confirmed = await schedule(new)
        notificationConfirmed[purpose] = confirmed
        sync(purpose)
        return confirmed ? .verified : .unconfirmed
    }

    func togglePause(_ purpose: CountdownSession.Purpose) {
        guard var session = sessions[purpose] else { return }
        let now = Date()
        if session.isRunning {
            session.pause(at: now)
            cancelNotification(session)
        } else if session.isPaused {
            session.resume(at: now)
            Task { [session] in self.notificationConfirmed[purpose] = await self.schedule(session) }
        }
        sessions[purpose] = session
        save()
        sync(purpose)
    }

    func stop(_ purpose: CountdownSession.Purpose) {
        guard var session = sessions[purpose] else { return }
        session.stop(at: Date())
        cancelNotification(session)
        sessions[purpose] = session
        save()
        sync(purpose)
    }

    /// Clears a finished or stopped countdown from the screen.
    func dismiss(_ purpose: CountdownSession.Purpose) {
        guard sessions[purpose]?.isOver == true else { return }
        sessions[purpose] = nil
        save()
        islands[purpose]?.end(final: nil)
    }

    // MARK: Island and timer

    private func sync(_ purpose: CountdownSession.Purpose) {
        finishTimers[purpose]?.cancel()
        guard let session = sessions[purpose], let island = islands[purpose] else { return }
        switch session.state {
        case .running(let end):
            island.show(.init(isPaused: false, endsAt: end, label: session.label),
                        startedAt: session.startedAt, duration: session.duration)
            // While the app runs, notice the end at once; otherwise `refresh` does on return.
            finishTimers[purpose] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow) + 0.5))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        case .paused(let left):
            island.show(.init(isPaused: true, endsAt: nil, remaining: left, label: session.label),
                        startedAt: session.startedAt, duration: session.duration)
        case .finished:
            island.end(final: .init(isPaused: false, endsAt: nil, label: session.label, isFinished: true),
                       keepFor: Self.finishedCardFor)
        case .stopped:
            island.end(final: nil)
        }
    }

    private func save() {
        let kept = sessions.values.sorted { $0.startedAt < $1.startedAt }
        if !kept.isEmpty, let data = try? JSONEncoder().encode(kept) {
            defaults.set(data, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    // MARK: Notification

    /// Adds the "done" notification and checks iOS lists it. Asks for permission only if it
    /// was never asked; denied means the countdown runs without one. In the iPhone's language
    /// (ADR-213); the body is the user's own label when there is one.
    private func schedule(_ session: CountdownSession) async -> Bool {
        guard let end = session.endsAt else { return false }
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return false }
        let language = NotificationLanguage.current
        let content = UNMutableNotificationContent()
        content.title = CountdownSession.doneTitle(session.purpose, language)
        content.body = CountdownSession.doneBody(session.purpose, label: session.label, language)
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: session.notificationID, content: content, trigger: trigger))
        } catch {
            return false
        }
        return await center.pendingNotificationRequests().contains { $0.identifier == session.notificationID }
    }

    private func cancelNotification(_ session: CountdownSession) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [session.notificationID])
    }
}
