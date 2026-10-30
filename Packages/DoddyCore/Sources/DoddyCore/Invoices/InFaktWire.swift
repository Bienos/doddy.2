import Foundation

// inFakt's wire format (ADR-668): the body Doddy would send to create an invoice, and how inFakt's
// answers are read. Written from the Postman collection behind docs.infakt.pl as read on
// 30 Oct 2026 (docs/research/2026-10-30/ksef_infakt_research.md, C1 to C3, C9, C10, C16, C17), with
// inFakt's own examples as test fixtures. **No request is made here, and no real answer has been
// seen**: until one create call in the sandbox shows the same shapes, `InFaktAPI.createVerified`
// stays false and nothing uses this to send.
//
// What it refuses rather than guesses: a private person (inFakt wants a first and a last name, the
// draft has one name), a buyer abroad or another currency (not drafted yet), an exempt line without
// an exemption id from inFakt's own list, and cash on delivery (inFakt's list says "delivery"; not
// confirmed to be the same).
//
// Platforms: iPhone and iPad. Pure logic; tested on Linux.

public enum InFaktWire {
    public enum Unsupported: Error, Equatable, Sendable {
        case privatePerson
        case foreignBuyer
        case currency
        case exemptionIdNeeded
        case paymentMethod(InvoicePayment)
    }

    // MARK: Create

    /// The body of `POST /api/v3/async/invoices.json` for a confirmed invoice: prices in grosze,
    /// `invoice_date` / `sale_date` / `payment_date`, the buyer as `client_*` fields, and
    /// `send_to_ksef` false (KSeF is its own tap). Keys sorted, so the same invoice is always the same text.
    public static func createBody(_ invoice: ConfirmedInvoice, exemptionId: Int? = nil) -> Result<String, Unsupported> {
        let draft = invoice.draft
        let buyer = draft.contractor
        guard buyer.kind?.value == .company else { return .failure(.privatePerson) }
        guard let address = buyer.address?.value, address.countryCode == "PL" else { return .failure(.foreignBuyer) }
        guard draft.currency?.value == .pln else { return .failure(.currency) }
        guard let method = draft.paymentMethod?.value else { return .failure(.paymentMethod(.cod)) }
        if method == .cod { return .failure(.paymentMethod(.cod)) }
        let exempt = draft.lines.contains { $0.vat?.value == .exempt }
        if exempt, exemptionId == nil { return .failure(.exemptionIdNeeded) }
        guard let issue = draft.issueDate, let nip = buyer.nip.flatMap({ Nip($0.value) }) else { return .failure(.foreignBuyer) }

        var fields: [(String, JSON)] = [
            ("client_business_activity_kind", .string("other_business")),
            ("client_company_name", .string(buyer.name?.value ?? "")),
            ("client_tax_code", .string(nip.digits)),
            ("client_street", .string(address.street ?? "")),
            ("client_city", .string(address.city ?? "")),
            ("client_post_code", .string(address.postCode ?? "")),
            ("client_country", .string("PL")),
            ("currency", .string("PLN")),
            ("invoice_date", .string(issue.iso)),
            // No sale date on the draft means the issue date (ADR-667); said outright, so inFakt's own
            // default for a missing one (not documented) never decides it.
            ("sale_date", .string((draft.saleDate ?? issue).iso)),
            ("payment_method", .string(method.rawValue)),
        ]
        if let number = address.buildingNumber, !number.isEmpty { fields.append(("client_street_number", .string(number))) }
        if let flat = address.flatNumber, !flat.isEmpty { fields.append(("client_flat_number", .string(flat))) }
        if let due = draft.paymentDueDate { fields.append(("payment_date", .string(due.iso))) }
        if draft.splitPayment?.value == true {
            fields.append(("split_payment", .bool(true)))
            fields.append(("split_payment_type", .string("required")))
        }
        if exempt, let exemptionId { fields.append(("vat_exemption_reason", .int(exemptionId))) }
        let services: [JSON] = draft.lines.map { line in
            var service: [(String, JSON)] = [
                ("name", .string(line.name?.value ?? "")),
                ("quantity", .raw(InvoiceCard.quantity(line.quantityMilli ?? 0, polish: false))),
                ("unit_net_price", .int(line.netUnitPriceMinor ?? 0)),
                // A number in requests (inFakt's example sends 23); "zw" and "np" are words.
                ("tax_symbol", line.vat.map { rate -> JSON in
                    if case .percent(let value) = rate.value { return .int(value) }
                    return .string(rate.value.symbol)
                } ?? .null),
            ]
            if let unit = line.unit?.trimmingCharacters(in: .whitespaces), !unit.isEmpty { service.append(("unit", .string(unit))) }
            return .object(service)
        }
        fields.append(("services", .array(services)))
        return .success(JSON.object([("invoice", .object(fields)), ("send_to_ksef", .bool(false))]).text)
    }

    // MARK: Answers

    /// The reference of an accepted create (201: `invoice_task_reference_number`, `processing_code` 100).
    public static func createAccepted(_ data: Data) -> String? {
        guard let object = Self.object(data), let reference = object["invoice_task_reference_number"] as? String,
              !reference.isEmpty else { return nil }
        return reference
    }

    public enum CreateStatus: Equatable, Sendable {
        /// 100, 120, 140: accepted, waiting, being processed.
        case processing
        /// 201, with the invoice's id.
        case created(invoiceUUID: String)
        /// 422: not created, with inFakt's reasons ("field: message").
        case rejected([String])
        /// Not an answer this code understands, or one about another task: not a success.
        case unreadable
    }

    /// `GET /async/invoices/status/{reference}.json`. An answer for another task is unreadable.
    public static func createStatus(_ data: Data, reference: String) -> CreateStatus {
        guard let object = Self.object(data), object["invoice_task_reference_number"] as? String == reference,
              let code = object["processing_code"] as? Int else { return .unreadable }
        switch code {
        case 100, 120, 140: return .processing
        case 201:
            guard let uuid = object["invoice_uuid"] as? String, !uuid.isEmpty else { return .unreadable }
            return .created(invoiceUUID: uuid)
        case 422:
            let errors = (object["invoice_errors"] as? [String: Any]) ?? [:]
            let reasons = errors.keys.sorted().flatMap { key -> [String] in
                let messages = (errors[key] as? [Any])?.compactMap { $0 as? String } ?? []
                return messages.isEmpty ? [key] : messages.map { "\(key): \($0)" }
            }
            return .rejected(reasons.isEmpty ? [object["processing_description"] as? String ?? "inFakt gave no reason."] : reasons)
        default: return .unreadable
        }
    }

    /// An invoice as `GET /invoices/{uuid}.json` describes it: what is needed to check it against
    /// what the person confirmed, and where it stands in KSeF.
    public struct Invoice: Equatable, Sendable {
        public let uuid: String
        public let number: String?
        public let netMinor: Int
        public let taxMinor: Int
        public let grossMinor: Int
        /// From `ksef_data`, when inFakt has sent it there.
        public let ksef: KsefStatus?
    }

    public static func invoice(_ data: Data) -> Invoice? {
        guard let object = Self.object(data), let uuid = object["uuid"] as? String, !uuid.isEmpty,
              let net = object["net_price"] as? Int, let tax = object["tax_price"] as? Int,
              let gross = object["gross_price"] as? Int else { return nil }
        var ksef: KsefStatus?
        if let data = object["ksef_data"] as? [String: Any], data["status"] != nil {
            ksef = Self.ksef(data)
        }
        return Invoice(uuid: uuid, number: object["number"] as? String, netMinor: net, taxMinor: tax, grossMinor: gross, ksef: ksef)
    }

    /// The answer of `POST /ksef2/documents/{uuid}/send.json` or `GET …/status.json`. An answer about
    /// another invoice is unknown, never this one's success.
    public static func ksefAnswer(_ data: Data, invoiceUUID: String) -> KsefStatus {
        guard let object = Self.object(data), object["invoice_uuid"] as? String == invoiceUUID else { return .unknown }
        return ksef(object)
    }

    private static func ksef(_ object: [String: Any]) -> KsefStatus {
        KsefStatus.fromInFakt(status: object["status"] as? String, ksefNumber: object["ksef_number"] as? String,
                              description: object["status_description"] as? String)
    }

    // MARK: VAT exemptions

    /// One entry of inFakt's list of exemption grounds (`GET /vat_exemptions.json`, 112 entries).
    public struct VatExemption: Equatable, Sendable, Codable {
        public let id: Int
        public let description: String
        /// "art. 113 ust. 1 i 9".
        public let rule: String
        public let source: String
    }

    /// One page of the list, and whether inFakt says there is another.
    public static func vatExemptions(_ data: Data) -> (entries: [VatExemption], hasNext: Bool)? {
        guard let object = Self.object(data), let entities = object["entities"] as? [[String: Any]] else { return nil }
        let entries = entities.compactMap { entry -> VatExemption? in
            guard let id = entry["id"] as? Int, let rule = entry["legal_basis_rule"] as? String else { return nil }
            return VatExemption(id: id, description: entry["description"] as? String ?? "", rule: rule,
                                source: entry["legal_basis_source"] as? String ?? "")
        }
        let meta = object["metainfo"] as? [String: Any]
        let count = meta?["count"] as? Int ?? entries.count
        let total = meta?["total_count"] as? Int ?? 0
        return (entries, (meta?["next"] as? String) != nil && count > 0 && total > 0 && entries.count == count && count < total)
    }

    /// The one entry whose article, ust., pkt and lit. are the ones the person said ("art. 113 ust. 1"
    /// matches "art. 113 ust. 1 i 9"). Nil when none or more than one matches: then the person picks.
    public static func matchExemption(_ said: String, in list: [VatExemption]) -> VatExemption? {
        guard let wanted = ArticleRef(said) else { return nil }
        let found = list.filter { ArticleRef($0.rule).map(wanted.isSatisfied(by:)) ?? false }
        return found.count == 1 ? found[0] : nil
    }

    struct ArticleRef: Equatable {
        var article: String
        var ust: String?
        var pkt: String?
        var lit: String?

        init?(_ text: String) {
            let words = text.lowercased().replacingOccurrences(of: ".", with: " ")
                .split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
            func after(_ marker: String) -> String? {
                guard let i = words.firstIndex(of: marker), i + 1 < words.count else { return nil }
                return words[i + 1]
            }
            guard let article = after("art") else { return nil }
            self.article = article
            ust = after("ust")
            pkt = after("pkt")
            lit = after("lit")
        }

        /// Every part the person said is in the rule, and the rule has nothing narrower they left out.
        func isSatisfied(by rule: ArticleRef) -> Bool {
            article == rule.article && ust == rule.ust && pkt == rule.pkt && lit == rule.lit
        }
    }

    // MARK: JSON

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// A small writer with sorted keys and no floating point: a quantity is written as its decimal text.
    indirect enum JSON {
        case string(String), int(Int), bool(Bool), raw(String), null
        case array([JSON])
        case object([(String, JSON)])

        var text: String {
            switch self {
            case .string(let s): ErrandDraft.jsonString(s)
            case .int(let i): String(i)
            case .bool(let b): b ? "true" : "false"
            case .raw(let r): r
            case .null: "null"
            case .array(let items): "[" + items.map(\.text).joined(separator: ",") + "]"
            case .object(let pairs):
                "{" + pairs.sorted { $0.0 < $1.0 }.map { ErrandDraft.jsonString($0.0) + ":" + $0.1.text }.joined(separator: ",") + "}"
            }
        }
    }
}
