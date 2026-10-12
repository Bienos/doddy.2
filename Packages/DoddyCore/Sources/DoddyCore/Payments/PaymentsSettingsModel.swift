import Foundation
import Observation

/// State behind Settings → Payments. Everything shown comes from the server's answer: the switch
/// changes only after the server accepts it, and a failure never looks like success.
@MainActor
@Observable
public final class PaymentsSettingsModel {
    public enum Load: Equatable, Sendable {
        case notConfigured
        case loading
        case ready
        case failed(String)
    }

    public private(set) var status: PaymentStatus?
    public private(set) var load: Load
    public private(set) var message: String?
    public private(set) var receipts: [PaymentReceipt] = []
    /// The switch is waiting for the server's answer.
    public private(set) var switching = false

    private let client: any PaymentsClient
    private let isConfigured: Bool

    public init(client: (any PaymentsClient)?) {
        self.client = client ?? UnconfiguredPaymentsClient()
        self.isConfigured = client != nil
        load = client == nil ? .notConfigured : .loading
    }

    /// Mock data is labelled everywhere it appears.
    public var isDemo: Bool { status?.mode == .mock }

    /// The server has a wallet and the person's switch is on.
    public var isEnabled: Bool { status?.enabled ?? false }

    /// A payment can be started: a wallet exists on the server and the person's switch is on.
    public var canPay: Bool { (status?.wallet.configured ?? false) && isEnabled }

    /// Payments sent but never confirmed. Shown at the top until the person has checked their wallet.
    public var unresolved: Int { status?.unresolved ?? 0 }

    public func refresh() async {
        guard isConfigured else { return }
        do {
            status = try await client.status()
            load = .ready
            receipts = (try? await client.receipts()) ?? receipts
        } catch {
            // Keep what was shown before, but say it may be out of date.
            load = status == nil ? .failed(error.userMessage) : .ready
            message = error.userMessage
        }
    }

    /// The switch moves only if the server accepts it; otherwise it stays where it was and the reason is shown.
    public func setEnabled(_ enabled: Bool) async {
        guard isConfigured, !switching else { return }
        switching = true
        message = nil
        defer { switching = false }
        do {
            let result = try await client.setSwitch(enabled: enabled)
            status = result.status
            receipts.insert(result.receipt, at: 0)
            if receipts.count > 30 { receipts.removeLast(receipts.count - 30) }
        } catch {
            if let receipt = error.receipt { receipts.insert(receipt, at: 0) }
            message = error.userMessage
            if case .notConfigured = error { load = .notConfigured }
        }
    }
}
