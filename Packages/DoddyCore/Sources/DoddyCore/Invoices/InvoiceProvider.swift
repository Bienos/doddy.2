import Foundation

// Where an invoice goes (ADR-640). A provider is the accounting program: it creates the invoice and,
// asked afterwards, says whether an invoice for an operation exists. Doddy talks to it only through
// this protocol, so the rules in `InvoiceOperation` and `InvoiceSender` hold whichever program it is,
// and tests use a fake. The real inFakt provider is a stub until its API facts are confirmed
// (`InFaktAPI`, docs/implementation/INFAKT_STATUS.md).
//
// Platforms: iPhone and iPad. No networking in DoddyCore: a real provider lives in the app.

public enum InvoiceProviderError: Error, Equatable, Sendable {
    /// No key is saved. Nothing was sent.
    case notConfigured
    /// The provider's request format is not confirmed yet. Nothing was sent.
    case notVerified
    /// The provider answered with a definite no (a refused request). Nothing was created.
    case rejected(String)
    /// The connection died, timed out, or the provider answered in a way that does not say whether
    /// the invoice was created.
    case outcomeUnknown
}

public protocol InvoiceProvider: Sendable {
    /// Creates the invoice and returns a receipt that names `invoice.operationId`.
    func createInvoice(_ invoice: ConfirmedInvoice) async throws -> InvoiceReceipt
    /// The receipt of the invoice made for this operation, or nil when the provider confirms that
    /// none exists. Throws when it cannot tell.
    func findInvoice(operationId: UUID) async throws -> InvoiceReceipt?
}

/// Sends a confirmed invoice once, saving first, and never twice by itself.
public enum InvoiceSender {
    /// `persist` is called with the operation in `pendingExternalWrite` BEFORE the provider is
    /// called, and again with the result. Does nothing unless the operation is confirmed and unchanged.
    public static func send(
        _ operation: inout InvoiceOperation, using provider: any InvoiceProvider,
        persist: (InvoiceOperation) async -> Void = { _ in }
    ) async {
        let confirmed: ConfirmedInvoice
        do { confirmed = try operation.beginSend() } catch { return }
        await persist(operation)
        do {
            operation.record(receipt: try await provider.createInvoice(confirmed))
        } catch let error as InvoiceProviderError {
            switch error {
            case .notConfigured: operation.recordFailure("No inFakt key is saved, so nothing was sent.")
            case .notVerified: operation.recordFailure("This connection is not switched on yet, so nothing was sent.")
            case .rejected(let reason): operation.recordFailure(reason)
            case .outcomeUnknown: operation.recordUnknown()
            }
        } catch {
            // Anything else (a cancelled task, an unexpected error) does not say whether it was created.
            operation.recordUnknown()
        }
        await persist(operation)
    }

    /// After an unknown outcome: asks the provider whether the invoice exists. If it cannot tell,
    /// the operation stays unknown.
    public static func checkStatus(
        _ operation: inout InvoiceOperation, using provider: any InvoiceProvider,
        persist: (InvoiceOperation) async -> Void = { _ in }
    ) async {
        guard operation.state == .unknownOutcome else { return }
        do {
            operation.resolveUnknown(found: try await provider.findInvoice(operationId: operation.operationId))
            await persist(operation)
        } catch {
            // Cannot tell: still unknown. Nothing is resent.
        }
    }
}

/// What is confirmed about inFakt's API, from inFakt's own documentation on 24 Oct 2026
/// (docs/implementation/INFAKT_STATUS.md). Since 30 Oct 2026 its field tables also say prices are
/// grosze and the create dates are `invoice_date`, `sale_date` and `payment_date`
/// (docs/research/2026-10-30/ksef_infakt_research.md, C1 and C2), but no real answer has been seen:
/// `createVerified` stays false until one create call in the sandbox, and the provider below refuses to run.
public enum InFaktAPI {
    public static let productionBase = "https://api.infakt.pl/api/v3"
    public static let sandboxBase = "https://api.sandbox-infakt.pl/api/v3"
    /// Where a free test account and test key are made.
    public static let sandboxSignUp = "https://konto.sandbox-infakt.pl/rejestracja"
    public static let apiKeyHeader = "X-inFakt-ApiKey"
    /// The narrowest scopes that cover creating invoices and reading them back.
    public static let neededScopes = ["api:invoices:read", "api:invoices:write"]
    /// inFakt's published limits per IP address: 300 GET and 150 other requests per 60 seconds.
    public static let getPerMinute = 300
    public static let writePerMinute = 150
    /// Flipped to true only after one real create call in the sandbox settles the open facts.
    public static let createVerified = false
}

/// The inFakt provider while its request format is unconfirmed: it makes no request and says so.
public struct UnverifiedInFaktProvider: InvoiceProvider {
    public init() {}

    public func createInvoice(_ invoice: ConfirmedInvoice) async throws -> InvoiceReceipt {
        throw InvoiceProviderError.notVerified
    }

    public func findInvoice(operationId: UUID) async throws -> InvoiceReceipt? {
        throw InvoiceProviderError.notVerified
    }
}
