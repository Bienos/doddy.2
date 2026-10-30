import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// The life of one invoice (ADR-640), after docs/architecture/TOOLS_AND_ACTIONS.md's reminder
// machine and the constitution's rules for external writes:
//
//   drafted → needsClarification → readyForConfirmation → userConfirmed
//           → pendingExternalWrite → verifiedSucceeded | verifiedFailed | unknownOutcome
//
//  - The person's yes is bound to the SHA-256 digest of the exact payload they saw. Change the draft
//    afterwards and it is a different invoice that needs its own yes.
//  - `pendingExternalWrite` is saved BEFORE the call goes out.
//  - "Issued" means a receipt the provider returned and that names this operation. Nothing else, and
//    never the model's word, counts as done.
//  - After an unknown outcome (the connection died, the answer was lost) nothing is sent again by
//    itself: the provider is asked whether the invoice exists, and a new send needs a new yes.
//
// Platforms: iPhone and iPad. Pure logic; tested on Linux.

public enum InvoiceState: String, Codable, Sendable {
    case drafted, needsClarification, readyForConfirmation, userConfirmed
    case pendingExternalWrite, verifiedSucceeded, verifiedFailed, unknownOutcome
}

/// What a provider returned for a created invoice, naming the operation it belongs to.
public struct InvoiceReceipt: Equatable, Sendable, Codable {
    public let operationId: UUID
    /// The provider's own identifier for the invoice.
    public let externalId: String
    /// The invoice number the provider gave it, when it did.
    public let number: String?
    public let verifiedAt: Date

    public init(operationId: UUID, externalId: String, number: String?, verifiedAt: Date) {
        self.operationId = operationId
        self.externalId = externalId
        self.number = number
        self.verifiedAt = verifiedAt
    }
}

public enum InvoiceOperationError: Error, Equatable, Sendable {
    /// The draft changed since the person saw it.
    case stale
    case notReady
    case wrongState(InvoiceState)
}

/// An invoice the person confirmed, exactly as shown. Only an `InvoiceOperation` can make one, so a
/// provider can never be handed a draft that was not confirmed.
public struct ConfirmedInvoice: Equatable, Sendable {
    public let operationId: UUID
    public let digest: String
    public let draft: InvoiceDraft
    public let totals: InvoiceTotals
}

public struct InvoiceOperation: Equatable, Sendable, Codable {
    public let operationId: UUID
    public private(set) var draft: InvoiceDraft
    public private(set) var state: InvoiceState
    /// The digest the person confirmed.
    public private(set) var confirmedDigest: String?
    public private(set) var receipt: InvoiceReceipt?
    /// Why it failed or was set aside, in words for the person.
    public private(set) var note: String?
    /// Where the invoice stands in KSeF once inFakt has it (ADR-667). Only `.accepted`, with a KSeF
    /// number, means it is issued in KSeF; it is never set before a receipt exists.
    public private(set) var ksef: KsefStatus = .notSent

    public init(draft: InvoiceDraft, operationId: UUID = UUID()) {
        self.operationId = operationId
        self.draft = draft
        self.state = .drafted
        evaluate()
    }

    /// The digest of the exact payload the person is shown (nil while sums can't be worked out).
    public var digest: String? {
        guard let totals = draft.totals, draft.isReadyForConfirmation else { return nil }
        return Self.digest(of: Self.canonicalJSON(draft, totals))
    }

    /// Replaces the draft (the person changed or added something). Allowed until the send starts.
    public mutating func update(_ newDraft: InvoiceDraft) throws {
        switch state {
        case .drafted, .needsClarification, .readyForConfirmation, .userConfirmed: break
        default: throw InvoiceOperationError.wrongState(state)
        }
        draft = newDraft
        confirmedDigest = nil
        evaluate()
    }

    /// The person tapped Confirm on a card that showed `shownDigest`.
    public mutating func confirm(shownDigest: String) throws {
        guard state == .readyForConfirmation else { throw InvoiceOperationError.wrongState(state) }
        guard let current = digest else { throw InvoiceOperationError.notReady }
        guard shownDigest == current else { throw InvoiceOperationError.stale }
        confirmedDigest = current
        state = .userConfirmed
    }

    /// Takes the confirmed invoice out and moves to `pendingExternalWrite`. The caller saves the
    /// operation before it calls the provider. Only from `userConfirmed`, and only while the draft is
    /// still the one that was confirmed.
    public mutating func beginSend() throws -> ConfirmedInvoice {
        guard state == .userConfirmed else { throw InvoiceOperationError.wrongState(state) }
        guard let current = digest, current == confirmedDigest, let totals = draft.totals else {
            throw InvoiceOperationError.stale
        }
        state = .pendingExternalWrite
        return ConfirmedInvoice(operationId: operationId, digest: current, draft: draft, totals: totals)
    }

    /// The provider returned a receipt. It counts only if it names this operation and carries an
    /// identifier; otherwise the outcome is unknown, not a success.
    public mutating func record(receipt: InvoiceReceipt) {
        guard state == .pendingExternalWrite || state == .unknownOutcome else { return }
        guard receipt.operationId == operationId, !receipt.externalId.isEmpty else {
            state = .unknownOutcome
            note = "The reply could not be matched to this invoice."
            return
        }
        self.receipt = receipt
        state = .verifiedSucceeded
        note = nil
    }

    /// The provider said no, or nothing left the phone: a definite failure.
    public mutating func recordFailure(_ reason: String) {
        guard state == .pendingExternalWrite else { return }
        state = .verifiedFailed
        note = reason
    }

    /// The connection died or the answer was lost: the invoice may or may not exist.
    public mutating func recordUnknown() {
        guard state == .pendingExternalWrite else { return }
        state = .unknownOutcome
        note = "It is not known whether the invoice was created."
    }

    /// The provider was asked about this operation after an unknown outcome. A receipt settles it as
    /// issued. "None exists" returns to the confirmation step: a new send needs a new yes.
    public mutating func resolveUnknown(found: InvoiceReceipt?) {
        guard state == .unknownOutcome else { return }
        if let found {
            record(receipt: found)
        } else {
            confirmedDigest = nil
            state = .readyForConfirmation
            note = "The provider has no such invoice. It was not created; confirm again to send."
            evaluate(keepNote: true)
        }
    }

    /// inFakt's answer about sending this invoice to KSeF (ADR-667). Only after a receipt: an invoice
    /// that isn't known to exist can't be in KSeF. An accepted invoice stays accepted: KSeF never
    /// deletes or changes one (only a correction invoice can), so a later answer can't take it back.
    public mutating func recordKsef(_ status: KsefStatus) {
        guard state == .verifiedSucceeded, receipt != nil else { return }
        if case .accepted = ksef { return }
        ksef = status
    }

    /// After a definite failure the person may confirm again (a fresh yes).
    public mutating func reopenAfterFailure() {
        guard state == .verifiedFailed else { return }
        confirmedDigest = nil
        evaluate(keepNote: true)
    }

    private mutating func evaluate(keepNote: Bool = false) {
        if !keepNote { note = nil }
        if draft.lines.isEmpty && draft.contractor.name == nil && draft.currency == nil {
            state = .drafted
        } else {
            state = draft.isReadyForConfirmation ? .readyForConfirmation : .needsClarification
        }
    }

    // MARK: Digest

    /// The exact text the digest is taken over: keys sorted, no spaces, strings escaped as
    /// JavaScript's `JSON.stringify` does, so a server could compute the same.
    static func canonicalJSON(_ draft: InvoiceDraft, _ totals: InvoiceTotals) -> String {
        func s(_ text: String?) -> String { text.map { ErrandDraft.jsonString($0) } ?? "null" }
        let c = draft.contractor
        let a = c.address?.value ?? InvoiceAddress()
        let nip = c.nip.flatMap { Nip($0.value)?.digits }
        let buyer = "{\"address\":{\"buildingNumber\":\(s(a.buildingNumber)),\"city\":\(s(a.city)),"
            + "\"countryCode\":\(s(a.countryCode)),\"flatNumber\":\(s(a.flatNumber)),\"postCode\":\(s(a.postCode)),"
            + "\"street\":\(s(a.street))},\"kind\":\(s(c.kind?.value.rawValue)),\"name\":\(s(c.name?.value)),\"nip\":\(s(nip))}"
        let lines = zip(draft.lines, totals.lineNetMinor).map { line, net in
            "{\"lineNetMinor\":\(net),\"name\":\(s(line.name?.value)),\"netUnitPriceMinor\":\(line.netUnitPriceMinor ?? 0),"
                + "\"quantityMilli\":\(line.quantityMilli ?? 0),\"unit\":\(s(line.unit)),\"vat\":\(s(line.vat?.value.symbol))}"
        }
        let groups = totals.groups.map {
            "{\"netMinor\":\($0.netMinor),\"rate\":\(s($0.rate.symbol)),\"vatMinor\":\($0.vatMinor)}"
        }
        return "{\"buyer\":\(buyer),\"currency\":\(s(draft.currency?.value.rawValue)),\"dueDate\":\(s(draft.paymentDueDate?.iso)),"
            + "\"exemptionReason\":\(s(draft.vatExemptionReason)),\"issueDate\":\(s(draft.issueDate?.iso)),"
            + "\"lines\":[\(lines.joined(separator: ","))],\"payment\":\(s(draft.paymentMethod?.value.rawValue)),"
            + "\"saleDate\":\(s(draft.saleDate?.iso)),\"splitPayment\":\(draft.splitPayment.map { $0.value ? "true" : "false" } ?? "null"),"
            + "\"totals\":{\"grossMinor\":\(totals.grossMinor),"
            + "\"groups\":[\(groups.joined(separator: ","))],\"netMinor\":\(totals.netMinor),\"vatMinor\":\(totals.vatMinor)}}"
    }

    static func digest(of canonical: String) -> String {
        SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
