import DoddyCore
import Foundation
import Observation
import WatchConnectivity
import WidgetKit

/// The watch's side (ADR-232). Holds only the last snapshot the iPhone sent (in memory, and in
/// the system's own application context); asks the iPhone to tick or save and shows its reply.
@MainActor
@Observable
final class WatchLink: NSObject {
    /// A WatchConnectivity request is interactive and must never leave a watch control spinning
    /// indefinitely if the iPhone process or reply path disappears.
    private static let replyTimeout: Duration = .seconds(15)

    private(set) var snapshot: WidgetSnapshot?
    private(set) var isSupported = true
    private(set) var isActivated = false
    private(set) var isReachable = false
    private(set) var activationFailed = false

    func activate() {
        isSupported = WCSession.isSupported()
        guard isSupported else {
            activationFailed = false
            return
        }
        isActivated = false
        isReachable = false
        activationFailed = false
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    enum Outcome: Equatable {
        case reply(WatchReply)
        /// Not sent: the iPhone isn't reachable. Nothing happened.
        case notSent
        /// Sent, but no answer: it may or may not have happened.
        case unanswered

        var message: String {
            switch self {
            case .reply(let reply): reply.message
            case .notSent: WatchNote.unreachable
            case .unanswered: WatchNote.unanswered
            }
        }
    }

    /// Sends one request and waits for the iPhone's read-back answer. Nothing is queued: when the
    /// iPhone can't be reached, the watch says so and nothing happens later.
    func send(_ request: WatchRequest) async -> Outcome {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable, let data = try? request.encoded() else { return .notSent }
        return await withCheckedContinuation { continuation in
            let once = OnceReply(continuation)
            let timeout = Task {
                do {
                    try await Task.sleep(for: Self.replyTimeout)
                    once.resume(.unanswered)
                } catch {
                    // The iPhone replied first; completing the request cancels this task.
                }
            }
            once.install(timeout: timeout)
            // WatchConnectivity calls these on its own queue: @Sendable so they aren't main-actor code.
            session.sendMessageData(data, replyHandler: { @Sendable reply in
                once.resume(.reply(WatchReply.decoded(reply) ?? .failed))
            }, errorHandler: { @Sendable _ in
                once.resume(.unanswered)
            })
        }
    }

    fileprivate func received(_ context: [String: Any]) {
        guard let data = context[WatchLinkVersion.snapshotKey] as? Data, let decoded = WidgetSnapshot.decoded(data) else { return }
        snapshot = decoded
        // The complications (ADR-262) read the same snapshot from the watch's App Group folder.
        // "Show notes and lists on Apple Watch" off arrives as an empty snapshot, so nothing of the
        // user's stays there.
        // Without the App Group the write fails and the complications say to open Doddy.
        // Reloaded after every write attempt (review I1), so a failed read-back never leaves the
        // complications showing what the iPhone has deleted or turned off.
        _ = try? WidgetSnapshotFile.write(decoded)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Resumes once, whichever handler WatchConnectivity calls.
private final class OnceReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<WatchLink.Outcome, Never>?
    private var timeout: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<WatchLink.Outcome, Never>) { self.continuation = continuation }

    func install(timeout: Task<Void, Never>) {
        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            timeout.cancel()
            return
        }
        self.timeout = timeout
        lock.unlock()
    }

    func resume(_ value: WatchLink.Outcome) {
        lock.lock()
        let continuation = self.continuation
        let timeout = self.timeout
        self.continuation = nil
        self.timeout = nil
        lock.unlock()
        timeout?.cancel()
        continuation?.resume(returning: value)
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        let context = session.receivedApplicationContext
        let data = context[WatchLinkVersion.snapshotKey] as? Data
        let activated = state == .activated
        let activationFailed = error != nil || !activated
        let reachable = session.isReachable
        Task { @MainActor in
            if let data { self.received([WatchLinkVersion.snapshotKey: data]) }
            self.isActivated = activated
            self.isReachable = activated && reachable
            self.activationFailed = activationFailed
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[WatchLinkVersion.snapshotKey] as? Data
        Task { @MainActor in
            if let data { self.received([WatchLinkVersion.snapshotKey: data]) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let activated = session.activationState == .activated
        let reachable = activated && session.isReachable
        Task { @MainActor in
            self.isActivated = activated
            self.isReachable = reachable
            if activated { self.activationFailed = false }
        }
    }
}
