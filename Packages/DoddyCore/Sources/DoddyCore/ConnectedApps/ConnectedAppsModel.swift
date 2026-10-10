import Foundation
import Observation

/// Opens the system authentication browser and returns the callback URL. The app implements it
/// with ASWebAuthenticationSession; there is no embedded login form.
public protocol WebAuthenticator: Sendable {
    func authenticate(url: URL, callbackScheme: String) async throws(WebAuthenticationError) -> URL
}

public enum WebAuthenticationError: Error, Equatable, Sendable {
    case canceled
    case failed
}

/// What the Google Calendar card shows. Derived from server state, never guessed.
public enum GoogleCalendarCardState: Equatable, Sendable {
    case notConfigured
    case loading
    case disconnected
    case connecting
    /// Mock mode only: the demo asks for a tap instead of showing a fake Google sign-in.
    case awaitingDemoApproval
    case connected
    case permissionInsufficient(ConnectionReason?)
    case expired
    case error(String)
    case disconnecting
}

@MainActor
@Observable
public final class ConnectedAppsModel {
    public private(set) var connection: ConnectionView?
    /// Transient calendar context; cleared on disconnect, on any non-connected state and after expiry.
    public private(set) var events: EventsResult?
    public private(set) var lastReceipt: ConnectedAppReceipt?
    public private(set) var receipts: [ConnectedAppReceipt] = []
    public private(set) var message: String?
    public private(set) var isWorking = false
    public private(set) var isReadingEvents = false
    /// An in-flight or local state that overrides the server's; nil means "show the server state".
    private var phase: GoogleCalendarCardState? = .loading
    private var pendingAttempt: ConnectResponse?

    private let client: any ConnectedAppsClient
    private let authenticator: any WebAuthenticator
    private let isConfigured: Bool

    public init(client: (any ConnectedAppsClient)?, authenticator: any WebAuthenticator) {
        self.client = client ?? UnconfiguredConnectedAppsClient()
        self.authenticator = authenticator
        self.isConfigured = client != nil
        phase = isConfigured ? .loading : .notConfigured
    }

    /// Mock data is labelled everywhere it appears.
    public var isDemo: Bool { connection?.mode == .mock || events?.mode == .mock }

    public var cardState: GoogleCalendarCardState {
        if let phase { return phase }
        guard let connection else { return .disconnected }
        switch connection.status {
        case .disconnected: return .disconnected
        case .connecting: return .connecting
        case .connected: return .connected
        case .permissionInsufficient: return .permissionInsufficient(connection.reason)
        case .expired: return .expired
        case .error: return .error("Doddy couldn't check the connection right now.")
        }
    }

    public func load() async {
        guard isConfigured, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            apply(try await client.status())
            phase = nil
            receipts = (try? await client.receipts()) ?? receipts
        } catch {
            fail(error)
        }
    }

    /// Deliberate user action. Duplicate taps are ignored while work is in flight.
    public func connect() async {
        // A second tap can land after a demo attempt already returned and is waiting for
        // approval; that must not start another attempt.
        guard isConfigured, !isWorking, phase != .awaitingDemoApproval else { return }
        isWorking = true
        message = nil
        phase = .connecting
        do {
            let attempt = try await client.connect()
            pendingAttempt = attempt
            if attempt.mode == .mock || attempt.authorizationUrl == nil {
                phase = .awaitingDemoApproval
                isWorking = false
                return
            }
            let result: CompletionResult
            do {
                let url = try await authenticator.authenticate(url: attempt.authorizationUrl!, callbackScheme: attempt.callbackScheme)
                result = ConnectionCallback.result(from: url, expectedScheme: attempt.callbackScheme, attemptId: attempt.attemptId) ?? .canceled
            } catch {
                result = .canceled
            }
            try await finish(attempt, result)
        } catch {
            fail(error)
        }
        pendingAttempt = nil
        isWorking = false
    }

    /// Mock mode: the user confirms a demo connection (no Google account involved).
    public func completeDemo(approve: Bool) async {
        guard let attempt = pendingAttempt, phase == .awaitingDemoApproval, !isWorking else { return }
        isWorking = true
        phase = .connecting
        do {
            try await finish(attempt, .mock(approve: approve))
        } catch {
            fail(error)
        }
        pendingAttempt = nil
        isWorking = false
    }

    public func cancelDemo() async {
        guard let attempt = pendingAttempt, phase == .awaitingDemoApproval else { return }
        isWorking = true
        do { try await finish(attempt, .canceled) } catch { fail(error) }
        pendingAttempt = nil
        isWorking = false
    }

    public func loadTomorrow(now: Date = Date(), timeZone: TimeZone = .current) async {
        guard isConfigured, !isWorking, cardState == .connected else { return }
        isWorking = true
        isReadingEvents = true
        message = nil
        defer {
            isWorking = false
            isReadingEvents = false
        }
        let request = EventsRequest(date: LocalDay.tomorrow(from: now, in: timeZone), timeZone: timeZone.identifier)
        do {
            let result = try await client.tomorrowEvents(request)
            events = result
            record(result.receipt)
        } catch {
            // An error is never shown as an empty day: the previous list is dropped too.
            events = nil
            fail(error)
            if case .server(let code, _, _, _) = error, ["connection_expired", "permission_insufficient", "not_connected"].contains(code) {
                if let view = try? await client.status() { apply(view) }
                phase = nil
            }
        }
    }

    /// Deliberate user action. Transient calendar data is cleared before the server is asked.
    public func disconnect() async {
        guard isConfigured, !isWorking else { return }
        isWorking = true
        events = nil
        message = nil
        phase = .disconnecting
        do {
            let result = try await client.disconnect()
            apply(result.connection)
            record(result.receipt)
            phase = nil
            if result.connection.remoteCleanup == .failed { message = result.receipt.summary }
        } catch {
            fail(error)
        }
        isWorking = false
    }

    /// Call when the screen appears or time passes; drops results past their expiry.
    public func discardExpiredEvents(now: Date = Date()) {
        guard let events, let expiry = ConnectedAppsDates.instant(events.expiresAt) else { return }
        if now >= expiry { self.events = nil }
    }

    private func finish(_ attempt: ConnectResponse, _ result: CompletionResult) async throws(ConnectedAppsError) {
        let done = try await client.complete(CompleteRequest(attemptId: attempt.attemptId, nonce: attempt.nonce, result: result))
        apply(done.connection)
        record(done.receipt)
        phase = nil
        if done.receipt.status != .succeeded { message = done.receipt.summary }
    }

    private func apply(_ view: ConnectionView) {
        connection = view
        if view.status != .connected { events = nil }
    }

    private func record(_ receipt: ConnectedAppReceipt) {
        lastReceipt = receipt
        receipts.insert(receipt, at: 0)
        if receipts.count > 20 { receipts.removeLast(receipts.count - 20) }
    }

    private func fail(_ error: ConnectedAppsError) {
        if let receipt = error.receipt { record(receipt) }
        message = error.userMessage
        switch error {
        case .notConfigured: phase = .notConfigured
        case .server: phase = nil
        default: phase = connection == nil ? .error(error.userMessage) : nil
        }
    }
}
