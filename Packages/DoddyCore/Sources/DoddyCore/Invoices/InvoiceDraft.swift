import Foundation

// An invoice as Doddy holds it before anything is sent (ADR-640). The person dictates the service,
// the buyer, the amount, the currency and the date (research, section 5.3 step 1); Doddy fills no
// gap by guessing. Every missing, unconfirmed or wrong field is reported by name, the sums are
// worked out by code (InvoiceTotals), and a draft with any issue cannot be confirmed.
//
// Platforms: iPhone and iPad. Pure logic; tested on Linux.

public enum ContractorKind: String, Codable, Sendable {
    /// A firm: its NIP and address are required on the invoice.
    case company
    /// A private person: no NIP needed.
    case privatePerson
}

public struct InvoiceAddress: Equatable, Sendable, Codable {
    public var street: String?
    public var buildingNumber: String?
    public var flatNumber: String?
    public var city: String?
    /// "XX-XXX".
    public var postCode: String?
    public var countryCode: String

    public init(street: String? = nil, buildingNumber: String? = nil, flatNumber: String? = nil,
                city: String? = nil, postCode: String? = nil, countryCode: String = "PL") {
        self.street = street
        self.buildingNumber = buildingNumber
        self.flatNumber = flatNumber
        self.city = city
        self.postCode = postCode
        self.countryCode = countryCode
    }

    static func isPostCode(_ text: String) -> Bool {
        let chars = Array(text)
        return chars.count == 6 && chars[2] == "-"
            && chars.enumerated().allSatisfy { $0.offset == 2 || ($0.element.isASCII && $0.element.isNumber) }
    }
}

public struct InvoiceContractor: Equatable, Sendable, Codable {
    public var kind: Sourced<ContractorKind>?
    public var name: Sourced<String>?
    /// As the person gave it; checked into a `Nip` only when the draft is validated.
    public var nip: Sourced<String>?
    public var address: Sourced<InvoiceAddress>?

    public init(kind: Sourced<ContractorKind>? = nil, name: Sourced<String>? = nil,
                nip: Sourced<String>? = nil, address: Sourced<InvoiceAddress>? = nil) {
        self.kind = kind
        self.name = name
        self.nip = nip
        self.address = address
    }
}

public struct InvoiceLine: Equatable, Sendable, Codable {
    public var name: Sourced<String>?
    /// Thousandths of a unit: 1,000 is one, 2,500 is two and a half. Never defaulted.
    public var quantityMilli: Int?
    public var unit: String?
    /// Net price of one unit in grosze (or cents).
    public var netUnitPriceMinor: Int?
    /// From the person or their own default, never from the model.
    public var vat: Sourced<VatRate>?

    public init(name: Sourced<String>? = nil, quantityMilli: Int? = nil, unit: String? = nil,
                netUnitPriceMinor: Int? = nil, vat: Sourced<VatRate>? = nil) {
        self.name = name
        self.quantityMilli = quantityMilli
        self.unit = unit
        self.netUnitPriceMinor = netUnitPriceMinor
        self.vat = vat
    }
}

/// A field of the draft, named so the reply can say exactly what is missing.
public enum InvoiceField: Equatable, Hashable, Sendable {
    case contractorKind, contractorName, contractorNip, contractorAddress
    case lines
    case lineName(Int), lineQuantity(Int), lineUnitPrice(Int), lineVat(Int)
    case currency, issueDate, saleDate, paymentMethod, paymentDueDate, vatExemptionReason
    /// Whether the split payment mechanism (MPP) applies: asked above 15,000 PLN gross (ADR-667).
    case splitPayment

    /// A stable key for `missing_data` in the result contract (lines are counted from 1).
    public var key: String {
        switch self {
        case .contractorKind: "contractor.kind"
        case .contractorName: "contractor.name"
        case .contractorNip: "contractor.nip"
        case .contractorAddress: "contractor.address"
        case .lines: "lines"
        case .lineName(let i): "lines.\(i + 1).name"
        case .lineQuantity(let i): "lines.\(i + 1).quantity"
        case .lineUnitPrice(let i): "lines.\(i + 1).net_unit_price"
        case .lineVat(let i): "lines.\(i + 1).vat_rate"
        case .currency: "currency"
        case .issueDate: "issue_date"
        case .saleDate: "sale_date"
        case .paymentMethod: "payment_method"
        case .paymentDueDate: "payment_due_date"
        case .vatExemptionReason: "vat_exemption_reason"
        case .splitPayment: "split_payment"
        }
    }
}

public enum InvoiceProblem: Equatable, Sendable {
    case nipChecksum
    case postCodeFormat
    case notAPositiveAmount
    case amountTooLarge
    case quantityOutOfRange
    case tooManyLines
    case textTooLong
    case dueBeforeIssue
    /// inFakt refuses `&`, `<` and `>` in an item's name before it reaches KSeF (ADR-667).
    case characterNotAllowed
    /// KSeF needs the VAT in PLN and an exchange rate for an invoice in another currency; Doddy
    /// doesn't draft those yet (ADR-667).
    case foreignCurrencyNotReady
    /// A buyer abroad needs an EU VAT number or another tax id and 0 WDT, 0 EX or np rates; Doddy
    /// doesn't draft those yet (ADR-667).
    case foreignBuyerNotReady
}

public enum InvoiceIssue: Equatable, Sendable {
    /// Not given at all.
    case missing(InvoiceField)
    /// Only the model suggested it: the person has to say or confirm it.
    case needsConfirmation(InvoiceField)
    /// Given, and wrong.
    case invalid(InvoiceField, InvoiceProblem)

    public var field: InvoiceField {
        switch self {
        case .missing(let f), .needsConfirmation(let f), .invalid(let f, _): f
        }
    }
}

public struct InvoiceDraft: Equatable, Sendable, Codable {
    public static let maxLines = 50
    public static let maxText = 200
    public static let maxQuantityMilli = 10_000_000
    public static let maxUnitPriceMinor = 100_000_000
    /// Above this gross total in PLN the invoice must say whether the split payment mechanism applies
    /// (art. 106e ust. 1 pkt 18a of the VAT act, FA(3) P_18A): 15,000.00 PLN (ADR-667).
    public static let splitPaymentThresholdMinor = 1_500_000
    /// Characters inFakt refuses in an item's name (its list of KSeF rejections, ADR-667).
    public static let refusedNameCharacters: Set<Character> = ["&", "<", ">"]

    public var contractor: InvoiceContractor
    public var lines: [InvoiceLine]
    public var currency: Sourced<InvoiceCurrency>?
    public var issueDate: CalendarDate?
    /// Nil means the same day as the issue date (ADR-667).
    public var saleDate: CalendarDate?
    public var paymentMethod: Sourced<InvoicePayment>?
    public var paymentDueDate: CalendarDate?
    /// Why VAT does not apply, in the person's words, when a line is exempt ("zw").
    public var vatExemptionReason: String?
    /// The split payment mechanism (MPP) applies: goods or services from annex 15 of the VAT act on
    /// an invoice above 15,000 PLN gross. Asked only above that amount; nil below it (ADR-667).
    public var splitPayment: Sourced<Bool>?

    public init(contractor: InvoiceContractor = InvoiceContractor(), lines: [InvoiceLine] = [],
                currency: Sourced<InvoiceCurrency>? = nil, issueDate: CalendarDate? = nil,
                saleDate: CalendarDate? = nil, paymentMethod: Sourced<InvoicePayment>? = nil,
                paymentDueDate: CalendarDate? = nil, vatExemptionReason: String? = nil, splitPayment: Sourced<Bool>? = nil) {
        self.contractor = contractor
        self.lines = lines
        self.currency = currency
        self.issueDate = issueDate
        self.saleDate = saleDate
        self.paymentMethod = paymentMethod
        self.paymentDueDate = paymentDueDate
        self.vatExemptionReason = vatExemptionReason
        self.splitPayment = splitPayment
    }

    /// Everything wrong with the draft, in the order the person was asked for things. Empty means
    /// the draft can be shown for confirmation.
    public func issues() -> [InvoiceIssue] {
        var found: [InvoiceIssue] = []

        func check<T>(_ value: Sourced<T>?, _ field: InvoiceField) -> T? {
            guard let value else { found.append(.missing(field)); return nil }
            guard value.isConfirmed else { found.append(.needsConfirmation(field)); return nil }
            return value.value
        }
        func text(_ value: Sourced<String>?, _ field: InvoiceField) {
            guard let confirmed = check(value, field) else { return }
            let clean = confirmed.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty { found.append(.missing(field)) }
            else if clean.count > Self.maxText { found.append(.invalid(field, .textTooLong)) }
        }

        // The buyer.
        let kind = check(contractor.kind, .contractorKind)
        // Only a person confirmed as a private person may go without a NIP: until the kind is settled,
        // a firm's NIP is required. Every buyer's address is required: the VAT act (art. 106e ust. 1
        // pkt 3) asks for it on every invoice but a simplified one, which Doddy doesn't draft (ADR-667).
        let mayOmitFirmData = kind == .privatePerson
        text(contractor.name, .contractorName)
        if let nip = contractor.nip {
            if let raw = check(nip, .contractorNip), Nip(raw) == nil { found.append(.invalid(.contractorNip, .nipChecksum)) }
        } else if !mayOmitFirmData {
            found.append(.missing(.contractorNip))
        }
        if let address = check(contractor.address, .contractorAddress) {
            func empty(_ s: String?) -> Bool { (s ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
            if address.countryCode != "PL" {
                found.append(.invalid(.contractorAddress, .foreignBuyerNotReady))
            } else if empty(address.street) || empty(address.city) || empty(address.postCode) {
                found.append(.missing(.contractorAddress))
            } else if !InvoiceAddress.isPostCode(address.postCode ?? "") {
                found.append(.invalid(.contractorAddress, .postCodeFormat))
            }
        }

        // The lines.
        if lines.isEmpty {
            found.append(.missing(.lines))
        } else if lines.count > Self.maxLines {
            found.append(.invalid(.lines, .tooManyLines))
        }
        for (i, line) in lines.enumerated().prefix(Self.maxLines) {
            text(line.name, .lineName(i))
            if let name = line.name?.value, name.contains(where: { Self.refusedNameCharacters.contains($0) }) {
                found.append(.invalid(.lineName(i), .characterNotAllowed))
            }
            if let q = line.quantityMilli {
                if q < 1 || q > Self.maxQuantityMilli { found.append(.invalid(.lineQuantity(i), .quantityOutOfRange)) }
            } else {
                found.append(.missing(.lineQuantity(i)))
            }
            if let p = line.netUnitPriceMinor {
                if p <= 0 { found.append(.invalid(.lineUnitPrice(i), .notAPositiveAmount)) }
                else if p > Self.maxUnitPriceMinor { found.append(.invalid(.lineUnitPrice(i), .amountTooLarge)) }
            } else {
                found.append(.missing(.lineUnitPrice(i)))
            }
            _ = check(line.vat, .lineVat(i))
        }
        if lines.contains(where: { $0.vat?.value == .exempt && $0.vat?.isConfirmed == true }),
           (vatExemptionReason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            found.append(.missing(.vatExemptionReason))
        }

        // Currency, dates, payment.
        if let code = check(currency, .currency), code != .pln {
            found.append(.invalid(.currency, .foreignCurrencyNotReady))
        }
        if currency?.value == .pln, let gross = totals?.grossMinor, gross > Self.splitPaymentThresholdMinor {
            _ = check(splitPayment, .splitPayment)
        }
        if issueDate == nil { found.append(.missing(.issueDate)) }
        // No sale date means it is the issue date: the VAT act (art. 106e ust. 1 pkt 6) and KSeF's
        // FA(3) (P_6) ask for it only when it differs (ADR-667). A sale date after the issue date is
        // allowed (an advance invoice is a different kind, not drafted here), so it is not checked.
        let method = check(paymentMethod, .paymentMethod)
        if let due = paymentDueDate {
            if let issue = issueDate, due < issue { found.append(.invalid(.paymentDueDate, .dueBeforeIssue)) }
        } else if method?.needsDueDate == true {
            found.append(.missing(.paymentDueDate))
        }
        return found
    }

    /// `missing_data` of the result contract: the keys of everything not given or not yet confirmed.
    public var missingData: [String] {
        var seen = Set<String>()
        return issues().compactMap { issue -> String? in
            switch issue {
            case .missing(let f), .needsConfirmation(let f): seen.insert(f.key).inserted ? f.key : nil
            case .invalid: nil
            }
        }
    }

    /// The draft can be shown for confirmation: nothing missing, unconfirmed or wrong.
    public var isReadyForConfirmation: Bool { issues().isEmpty }

    /// The sums, when the lines have what they need.
    public var totals: InvoiceTotals? { InvoiceTotals.compute(lines) }
}
