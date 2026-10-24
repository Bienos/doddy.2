import DoddyCore
import Foundation
import Observation
import UserNotifications

/// The focus timer (ADR-241): one session at a time, kept in UserDefaults so it survives the
/// app being closed, with a "time's up" notification and the Tiny Promise island. The timing
/// rules are `FocusSession` (DoddyCore, tested). The notification is checked in iOS's pending
/// list after it is added; the screen says so when it could not be confirmed.
@MainActor
@Observable
final class FocusController {
    static let shared = FocusController()

    private(set) var session: FocusSession?
    /// nil until a session asks: true when iOS lists the "time's up" notification as pending.
    private(set) var notificationConfirmed: Bool?

    @ObservationIgnored private let island = ToolLiveActivity(kind: .focus)
    @ObservationIgnored private var finishTimer: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "focusSession"
    /// How long "Time's up" stays on the Lock Screen after the app noticed.
    private static let finishedCardFor: TimeInterval = 300

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            session = try? JSONDecoder().decode(FocusSession.self, from: data)
        }
        // The island's buttons reach this object even when iOS launched the app just for them.
        ToolActivityActions.shared.togglePause[.focus] = { [weak self] in self?.togglePause() }
        ToolActivityActions.shared.stop[.focus] = { [weak self] in self?.stop() }
    }

    /// At launch and on every return to the foreground: pick up the island, notice a finished
    /// session, and wait for the end of a running one.
    func refresh(now: Date = Date()) {
        island.adoptExisting()
        guard var session else {
            island.end(final: nil)
            return
        }
        if session.finishIfDue(at: now) {
            self.session = session
            save()
        }
        sync()
    }

    func start(minutes: Int, label: String?) async {
        let now = Date()
        if session.map({ !$0.isOver }) == true { stop() }
        let new = FocusSession(minutes: minutes, label: label, now: now)
        session = new
        save()
        notificationConfirmed = await schedule(new)
        sync()
    }

    func togglePause() {
        guard var session else { return }
        let now = Date()
        if session.isRunning {
            session.pause(at: now)
            cancelNotification(session)
        } else if session.isPaused {
            session.resume(at: now)
            Task { [session] in self.notificationConfirmed = await self.schedule(session) }
        }
        self.session = session
        save()
        sync()
    }

    func stop() {
        guard var session else { return }
        session.stop(at: Date())
        cancelNotification(session)
        self.session = session
        save()
        sync()
    }

    /// Clears a finished or stopped session from the screen.
    func dismiss() {
        guard session?.isOver == true else { return }
        session = nil
        save()
        island.end(final: nil)
    }

    // MARK: Island and timer

    private func sync() {
        finishTimer?.cancel()
        guard let session else { return }
        switch session.state {
        case .running(let end):
            island.show(.init(isPaused: false, endsAt: end, label: session.label),
                        startedAt: session.startedAt, duration: session.duration)
            // While the app runs, notice the end at once; otherwise `refresh` does on return.
            finishTimer = Task { [weak self] in
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
        if let session, let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    // MARK: Notification

    private static func notificationID(_ session: FocusSession) -> String { "doddy.focus.\(session.id.uuidString)" }

    /// Adds the "time's up" notification and checks iOS lists it. Asks for permission only if
    /// it was never asked; denied means the timer runs without one.
    private func schedule(_ session: FocusSession) async -> Bool {
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
        content.title = TimerCopy.focusTitle(language)
        content.body = TimerCopy.focusBody(label: session.label, minutes: Int((session.duration / 60).rounded()), language)
        content.sound = .default
        // The end of a time the user chose: through a Focus where allowed (ADR-607).
        content.interruptionLevel = DoddyNotificationKind.focusDone.interruptionLevel
        let id = Self.notificationID(session)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        } catch {
            return false
        }
        return await center.pendingNotificationRequests().contains { $0.identifier == id }
    }

    private func cancelNotification(_ session: FocusSession) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID(session)])
    }
}
