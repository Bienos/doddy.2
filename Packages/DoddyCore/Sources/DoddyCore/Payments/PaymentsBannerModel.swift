import Foundation
import Observation

/// Where the Home banner keeps its small facts on this iPhone (the app backs it with UserDefaults; tests with a fake).
public protocol PaymentsBannerStorage: Sendable {
    /// Payments were switched on at some point. Until then Home never asks the server about payments.
    func everEnabled() -> Bool
    func markEverEnabled()
    /// How many unconfirmed payments the person has said they checked.
    func acknowledged() -> Int
    func setAcknowledged(_ count: Int)
    /// The server's last count, so the banner shows at once and stays when offline.
    func lastUnresolved() -> Int
    func setLastUnresolved(_ count: Int)
}

/// The banner on Home for a payment that was sent and never confirmed (ADR-452). The server keeps counting such
/// a payment until its record is pruned (90 days) because only the person can learn what happened, from their wallet's
/// history. So the banner shows while the server's count is above the number the person said they had checked.
@MainActor
@Observable
public final class PaymentsBannerModel {
    public private(set) var unresolved: Int
    public private(set) var acknowledgedCount: Int

    private let client: any PaymentsClient
    private let isConfigured: Bool
    @ObservationIgnored private let storage: any PaymentsBannerStorage

    public init(client: (any PaymentsClient)?, storage: any PaymentsBannerStorage) {
        self.client = client ?? UnconfiguredPaymentsClient()
        self.isConfigured = client != nil
        self.storage = storage
        unresolved = storage.lastUnresolved()
        acknowledgedCount = storage.acknowledged()
    }

    public var isVisible: Bool { isConfigured && unresolved > acknowledgedCount }

    /// Asks the server for its count, only once payments have been switched on. A failed ask keeps what was shown.
    public func refresh() async {
        guard isConfigured, storage.everEnabled() else { return }
        do {
            let status = try await client.status()
            unresolved = status.unresolved
            storage.setLastUnresolved(unresolved)
            if storage.acknowledged() > unresolved { storage.setAcknowledged(unresolved) }
            acknowledgedCount = storage.acknowledged()
        } catch {
            return
        }
    }

    /// "I've checked my wallet": hides the banner until another payment is left unconfirmed.
    public func acknowledge() {
        storage.setAcknowledged(unresolved)
        acknowledgedCount = unresolved
    }

    /// Payments have been switched on: from now on Home keeps the count current.
    public func noteEnabled() { storage.markEverEnabled() }
}
