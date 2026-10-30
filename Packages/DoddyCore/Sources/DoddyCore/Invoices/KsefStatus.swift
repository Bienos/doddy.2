import Foundation

// Where an invoice stands in KSeF, Poland's national e-invoice system (ADR-667). inFakt sends an
// invoice to KSeF only when asked (`send_to_ksef`, or POST /api/v3/ksef2/documents/{uuid}/send.json)
// and answers asynchronously; its status endpoint says "pending", "sent", "success" (with
// `ksef_number`), "error" (with `status_description`) or "rejected". Read on docs.infakt.pl on
// 30 Oct 2026 (docs/research/2026-10-30/ksef_infakt_research.md, C9 and C10); no real answer has
// been seen yet.
//
// The rule as code: an invoice is in KSeF only with a KSeF number in the right shape. "success"
// without one is still pending (the number usually comes minutes later). Anything unreadable is
// unknown, which is never success and never a reason to send again: KSeF refuses a second invoice
// with the same number (error 440), and an accepted one can't be deleted, only corrected.
//
// Platforms: iPhone and iPad. Pure logic; tested on Linux.

/// A KSeF number: the seller's NIP, the day KSeF accepted the invoice, 12 hex characters and a
/// 2-character check, 35 characters in all, for example `5265877635-20250826-0100001AF629-AF`
/// (MF's KSeF 2.0 documentation, numer-ksef.md). Checked for shape only; the check characters are
/// KSeF's own CRC and are not recomputed here.
public struct KsefNumber: Equatable, Hashable, Sendable, Codable {
    public let value: String

    public init?(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        func digits(_ s: String) -> Bool { s.allSatisfy { ("0"..."9").contains($0) } }
        func hex(_ s: String) -> Bool { s.allSatisfy { ("0"..."9").contains($0) || ("A"..."F").contains($0) } }
        guard text.count == 35, parts.count == 4,
              parts[0].count == 10, digits(parts[0]), Nip(parts[0]) != nil,
              parts[1].count == 8, digits(parts[1]), CalendarDate(
                  year: Int(parts[1].prefix(4)) ?? 0, month: Int(parts[1].dropFirst(4).prefix(2)) ?? 0, day: Int(parts[1].suffix(2)) ?? 0) != nil,
              parts[2].count == 12, hex(parts[2]),
              parts[3].count == 2, hex(parts[3]) else { return nil }
        value = text
    }

    /// The seller's NIP the number starts with.
    public var sellerNip: String { String(value.prefix(10)) }
}

public enum KsefStatus: Equatable, Sendable, Codable {
    /// Not asked to go to KSeF.
    case notSent
    /// Asked; KSeF hasn't given a number yet ("pending", "sent", or "success" still without one).
    case pending
    /// In KSeF, with its number. Final.
    case accepted(KsefNumber)
    /// KSeF or inFakt refused it, in their words. A refused file is not an invoice: it can be fixed
    /// and sent again after the person's new yes.
    case rejected(String)
    /// The answer was lost or couldn't be read: not success, and not a reason to send again.
    case unknown

    /// From inFakt's KSeF status answer: `status`, and `ksef_number` / `status_description` when given.
    public static func fromInFakt(status: String?, ksefNumber: String?, description: String?) -> KsefStatus {
        switch status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pending", "sent":
            return .pending
        case "success":
            guard let raw = ksefNumber, !raw.isEmpty else { return .pending }
            return KsefNumber(raw).map { .accepted($0) } ?? .unknown
        case "error", "rejected":
            let words = (description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .rejected(words.isEmpty ? "No reason was given." : String(words.prefix(300)))
        default:
            return .unknown
        }
    }

    /// Issued in KSeF: only with a number.
    public var isInKsef: Bool {
        if case .accepted = self { return true }
        return false
    }
}
