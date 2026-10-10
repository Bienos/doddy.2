import Foundation

/// SIMULATION. A stand-in "message provider" for the approval and receipt flow. It sends
/// nothing, opens no connection and is marked `isSimulation`, so every receipt says so.
public actor SimulatedActionAdapter: ActionAdapter {
    /// What the pretend provider does with the next send, and what a later status check finds.
    public enum Outcome: String, CaseIterable, Sendable {
        case delivers
        case fails
        case noAnswerThenDelivered
        case noAnswerThenNotDelivered
        case noAnswerStaysUnknown
        /// The provider says "ok" but gives no reference; the ledger must not call that confirmed.
        case okWithoutReference
    }

    public nonisolated let connectorID = "simulation"
    public nonisolated let isSimulation = true

    private var outcome: Outcome
    private var known: [UUID: ActionProviderResult] = [:]
    /// Every payload this adapter was asked to send. Tests use it to prove nothing is sent twice.
    public private(set) var executedPayloads: [ActionPayload] = []
    public var executeCount: Int { executedPayloads.count }
    public private(set) var statusCheckCount = 0

    public init(outcome: Outcome = .delivers) {
        self.outcome = outcome
    }

    public func setOutcome(_ outcome: Outcome) {
        self.outcome = outcome
    }

    public nonisolated func supports(_ type: ActionType) -> Bool {
        type == .sendMessage
    }

    public func execute(_ request: ActionExecutionRequest) async throws -> ActionProviderResult {
        executedPayloads.append(request.payload)
        let reference = "SIM-" + request.idempotencyKey.uuidString.prefix(8)
        switch outcome {
        case .delivers:
            known[request.idempotencyKey] = .confirmed(providerReference: reference)
            return .confirmed(providerReference: reference)
        case .fails:
            known[request.idempotencyKey] = .failed(reason: "Simulated: the test provider rejected the message")
            return .failed(reason: "Simulated: the test provider rejected the message")
        case .noAnswerThenDelivered:
            known[request.idempotencyKey] = .confirmed(providerReference: reference)
            throw SimulatedTimeout()
        case .noAnswerThenNotDelivered:
            known[request.idempotencyKey] = .failed(reason: "Simulated: the test provider never received it")
            throw SimulatedTimeout()
        case .noAnswerStaysUnknown:
            throw SimulatedTimeout()
        case .okWithoutReference:
            return .confirmed(providerReference: "")
        }
    }

    public func status(idempotencyKey: UUID) async throws -> ActionProviderResult {
        statusCheckCount += 1
        return known[idempotencyKey] ?? .unknown(reason: "Simulated: the test provider has no record yet")
    }

    struct SimulatedTimeout: Error {}
}
