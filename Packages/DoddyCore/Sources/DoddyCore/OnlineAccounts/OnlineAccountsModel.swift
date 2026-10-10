import Foundation
import Observation

/// State behind Settings → Online accounts. Everything shown comes from the server's answer:
/// a switch changes only after the server says so, and a failure never looks like success.
@MainActor
@Observable
public final class OnlineAccountsModel {
    public enum Load: Equatable, Sendable {
        case notConfigured
        case loading
        case ready
        case failed(String)
    }

    /// A mock-mode connection waiting for the user's tap (the demo shows no fake sign-in page).
    public struct DemoAttempt: Equatable, Sendable {
        public let toolkit: String
        public let attempt: ConnectResponse
    }

    public private(set) var catalog: ToolsCatalog?
    public private(set) var load: Load
    public private(set) var message: String?
    public private(set) var lastReceipt: OnlineToolReceipt?
    public private(set) var receipts: [OnlineToolReceipt] = []
    /// The account being connected or disconnected right now.
    public private(set) var busyToolkit: String?
    /// Switches waiting for the server's answer.
    public private(set) var switching: Set<String> = []
    public private(set) var demoAttempt: DemoAttempt?

    private let client: any OnlineAccountsClient
    private let authenticator: any WebAuthenticator
    private let isConfigured: Bool

    public init(client: (any OnlineAccountsClient)?, authenticator: any WebAuthenticator) {
        self.client = client ?? UnconfiguredOnlineAccountsClient()
        self.authenticator = authenticator
        self.isConfigured = client != nil
        load = client == nil ? .notConfigured : .loading
    }

    /// Mock data is labelled everywhere it appears.
    public var isDemo: Bool { catalog?.mode == .mock }

    public func toolkit(_ id: String) -> ToolkitView? { catalog?.toolkits.first { $0.id == id } }

    public func isEnabled(_ tool: String) -> Bool {
        catalog?.toolkits.flatMap(\.tools).first { $0.name == tool }?.enabled ?? false
    }

    public func refresh() async {
        guard isConfigured else { return }
        do {
            catalog = try await client.catalog()
            load = .ready
            receipts = (try? await client.receipts()) ?? receipts
        } catch {
            // Keep what was shown before, but say it may be out of date.
            load = catalog == nil ? .failed(error.userMessage) : .ready
            message = error.userMessage
        }
    }

    /// Deliberate user action: opens the provider's own sign-in page in the system browser.
    public func connect(_ toolkit: String) async {
        guard isConfigured, busyToolkit == nil else { return }
        busyToolkit = toolkit
        message = nil
        defer { busyToolkit = nil }
        do {
            let attempt = try await client.connect(toolkit: toolkit)
            if attempt.mode == .mock || attempt.authorizationUrl == nil {
                demoAttempt = DemoAttempt(toolkit: toolkit, attempt: attempt)
                return
            }
            let result: CompletionResult
            do {
                let url = try await authenticator.authenticate(url: attempt.authorizationUrl!, callbackScheme: attempt.callbackScheme)
                result = ConnectionCallback.result(from: url, expectedScheme: attempt.callbackScheme, attemptId: attempt.attemptId) ?? .canceled
            } catch {
                result = .canceled
            }
            try await finish(toolkit, attempt, result)
        } catch {
            fail(error)
        }
    }

    public func completeDemo(approve: Bool) async {
        guard let demo = demoAttempt, busyToolkit == nil else { return }
        demoAttempt = nil
        busyToolkit = demo.toolkit
        defer { busyToolkit = nil }
        do {
            try await finish(demo.toolkit, demo.attempt, .mock(approve: approve))
        } catch {
            fail(error)
        }
    }

    public func cancelDemo() async {
        guard let demo = demoAttempt, busyToolkit == nil else { return }
        demoAttempt = nil
        busyToolkit = demo.toolkit
        defer { busyToolkit = nil }
        do { try await finish(demo.toolkit, demo.attempt, .canceled) } catch { fail(error) }
    }

    /// Deliberate user action. The server switches the account's tools off first.
    public func disconnect(_ toolkit: String) async {
        guard isConfigured, busyToolkit == nil else { return }
        busyToolkit = toolkit
        message = nil
        defer { busyToolkit = nil }
        do {
            let result = try await client.disconnect(toolkit: toolkit)
            apply(result)
            if result.toolkit.remoteCleanup == .failed || result.receipt.status != .succeeded { message = result.receipt.summary }
        } catch {
            fail(error)
            await refresh()
        }
    }

    /// The switch moves only if the server accepts it; otherwise it stays where it was and the
    /// reason is shown.
    public func setSwitch(_ tool: String, enabled: Bool) async {
        guard isConfigured, !switching.contains(tool) else { return }
        switching.insert(tool)
        message = nil
        defer { switching.remove(tool) }
        do {
            apply(try await client.setSwitch(tool: tool, enabled: enabled))
        } catch {
            fail(error)
        }
    }

    private func finish(_ toolkit: String, _ attempt: ConnectResponse, _ result: CompletionResult) async throws(OnlineAccountsError) {
        let done = try await client.complete(toolkit: toolkit, CompleteRequest(attemptId: attempt.attemptId, nonce: attempt.nonce, result: result))
        apply(done)
        if done.receipt.status != .succeeded { message = done.receipt.summary }
    }

    private func apply(_ result: ToolkitResult) {
        if let current = catalog {
            let toolkits = current.toolkits.map { $0.id == result.toolkit.id ? result.toolkit : $0 }
            catalog = ToolsCatalog(mode: current.mode, toolkits: toolkits)
        }
        record(result.receipt)
    }

    private func record(_ receipt: OnlineToolReceipt) {
        lastReceipt = receipt
        receipts.insert(receipt, at: 0)
        if receipts.count > 30 { receipts.removeLast(receipts.count - 30) }
    }

    private func fail(_ error: OnlineAccountsError) {
        if let receipt = error.receipt { record(receipt) }
        message = error.userMessage
        if case .notConfigured = error { load = .notConfigured }
    }
}
