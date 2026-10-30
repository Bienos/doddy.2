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

/// Where a created invoice goes to KSeF (ADR-668): inFakt sends it on request and answers with
/// its KSeF status. Tests use a fake; the real one waits for the inFakt client.
public protocol KsefProvider: Sendable {
    /// Asks inFakt to send the invoice to KSeF; returns the status in its answer.
    func sendToKsef(invoiceId: String) async throws -> KsefStatus
    /// Reads where the invoice stands in KSeF. Never sends anything.
    func ksefStatus(invoiceId: String) async throws -> KsefStatus
}

/// Before Send to KSeF is offered (ADR-668): the invoice inFakt made must have exactly the sums the
/// person confirmed. KSeF does no arithmetic and an accepted invoice can only be corrected, so a
/// difference (inFakt may round per line) stops it here, not after.
public enum KsefSendGate {
    public enum Block: Equatable, Sendable {
        case totalsDiffer(confirmedGrossMinor: Int, inFaktGrossMinor: Int)
        case otherInvoice
    }

    public static func check(_ operation: InvoiceOperation, against invoice: InFaktWire.Invoice) -> Block? {
        guard invoice.uuid == operation.receipt?.externalId else { return .otherInvoice }
        guard let totals = operation.draft.totals else { return .otherInvoice }
        if totals.netMinor != invoice.netMinor || totals.vatMinor != invoice.taxMinor || totals.grossMinor != invoice.grossMinor {
            return .totalsDiffer(confirmedGrossMinor: totals.grossMinor, inFaktGrossMinor: invoice.grossMinor)
        }
        return nil
    }
}

/// Sends an invoice to KSeF once, after its own yes, saving first; never twice by itself.
public enum KsefSender {
    public static func send(
        _ operation: inout InvoiceOperation, using provider: any KsefProvider,
        persist: (InvoiceOperation) async -> Void = { _ in }
    ) async {
        let id: String
        do { id = try operation.beginKsefSend() } catch { return }
        await persist(operation)
        do {
            operation.recordKsef(try await provider.sendToKsef(invoiceId: id))
        } catch let error as InvoiceProviderError {
            switch error {
            case .notConfigured: operation.recordKsefNotSent("No inFakt key is saved, so nothing was sent to KSeF.")
            case .notVerified: operation.recordKsefNotSent("Sending to KSeF isn't switched on yet, so nothing was sent.")
            case .rejected(let reason): operation.recordKsef(.rejected(reason))
            case .outcomeUnknown: operation.recordKsef(.unknown)
            }
        } catch {
            operation.recordKsef(.unknown)
        }
        await persist(operation)
    }

    /// While on its way or unknown: asks inFakt where it stands. Sends nothing; if inFakt can't tell,
    /// nothing changes.
    public static func checkStatus(
        _ operation: inout InvoiceOperation, using provider: any KsefProvider,
        persist: (InvoiceOperation) async -> Void = { _ in }
    ) async {
        guard operation.ksef == .pending || operation.ksef == .unknown, let id = operation.receipt?.externalId else { return }
        guard let status = try? await provider.ksefStatus(invoiceId: id) else { return }
        operation.recordKsef(status)
        await persist(operation)
    }
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
public struct UnverifiedInFaktProvider: InvoiceProvider, KsefProvider {
    public init() {}

    public func createInvoice(_ invoice: ConfirmedInvoice) async throws -> InvoiceReceipt {
        throw InvoiceProviderError.notVerified
    }

    public func findInvoice(operationId: UUID) async throws -> InvoiceReceipt? {
        throw InvoiceProviderError.notVerified
    }

    public func sendToKsef(invoiceId: String) async throws -> KsefStatus {
        throw InvoiceProviderError.notVerified
    }

    public func ksefStatus(invoiceId: String) async throws -> KsefStatus {
        throw InvoiceProviderError.notVerified
    }
}
