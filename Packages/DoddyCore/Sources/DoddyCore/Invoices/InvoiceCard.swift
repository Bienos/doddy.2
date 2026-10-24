import Foundation

// What the invoice card says (ADR-633). The card is the person's one look at the exact invoice before
// they say yes, so its wording is made here, in code that is tested, and the SwiftUI view only lays it
// out. Everything shown comes from the operation: the sums are InvoiceTotals', the problems are the
// draft's own issues, and the card says "issued" only when a receipt exists.
//
// Two languages, as ParcelTracking: Polish for the person's screens, English otherwise.
//
// Platforms: iPhone and iPad.

public struct InvoiceCard: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let label: String
        public let value: String
        /// Only the model suggested this value: shown so it can be confirmed, marked so it is not mistaken for said.
        public let proposed: Bool

        init(_ label: String, _ value: String, proposed: Bool = false) {
            self.label = label
            self.value = value
            self.proposed = proposed
        }
    }

    public struct LineRow: Equatable, Sendable {
        public let name: String
        /// "2,5 godz. × 500,00 PLN netto · VAT 23%".
        public let detail: String
        public let net: String
        public let proposed: Bool
    }

    public let buyer: [Row]
    public let lines: [LineRow]
    public let facts: [Row]
    public let totals: [Row]
    /// Every missing, unconfirmed or wrong field as a sentence. Empty means the card is complete.
    public let problems: [String]
    public let stateLine: String
    /// The digest the person's yes is bound to (nil while the card is incomplete).
    public let digest: String?
    /// The Confirm button is offered: nothing missing, and sending is switched on in this build.
    public let canConfirm: Bool
    /// Why Confirm is not offered although the card is complete: sending is not switched on.
    public let sendingNote: String?

    public init(_ operation: InvoiceOperation, polish: Bool) {
        let text = Words(polish: polish)
        let draft = operation.draft
        let currency = draft.currency?.value ?? .pln
        let sums = draft.totals

        var buyer: [Row] = []
        let c = draft.contractor
        if let kind = c.kind { buyer.append(Row(text.kind, text.kindName(kind.value), proposed: !kind.isConfirmed)) }
        if let name = c.name { buyer.append(Row(text.name, name.value, proposed: !name.isConfirmed)) }
        if let nip = c.nip { buyer.append(Row("NIP", Nip(nip.value)?.display ?? nip.value, proposed: !nip.isConfirmed)) }
        if let address = c.address {
            buyer.append(Row(text.address, Self.oneLine(address.value), proposed: !address.isConfirmed))
        }
        self.buyer = buyer

        self.lines = draft.lines.enumerated().map { index, line in
            let net = sums.flatMap { $0.lineNetMinor.indices.contains(index) ? $0.lineNetMinor[index] : nil }
            let quantity = line.quantityMilli.map { Self.quantity($0, polish: polish) } ?? "?"
            let unit = (line.unit ?? "").trimmingCharacters(in: .whitespaces)
            let price = line.netUnitPriceMinor.map { MoneyText.format($0, currency: currency, polish: polish) } ?? "?"
            let vat = line.vat.map { "VAT \($0.value.symbol)\(Self.isPercent($0.value) ? "%" : "")" } ?? "VAT ?"
            return LineRow(
                name: line.name?.value ?? "?",
                detail: "\(quantity)\(unit.isEmpty ? "" : " " + unit) × \(price) \(text.netWord) · \(vat)",
                net: net.map { MoneyText.format($0, currency: currency, polish: polish) } ?? "",
                proposed: !(line.name?.isConfirmed ?? true) || !(line.vat?.isConfirmed ?? true))
        }

        var facts: [Row] = []
        if let value = draft.currency { facts.append(Row(text.currency, value.value.rawValue, proposed: !value.isConfirmed)) }
        if let date = draft.issueDate { facts.append(Row(text.issueDate, Self.date(date, polish: polish))) }
        if let date = draft.saleDate { facts.append(Row(text.saleDate, Self.date(date, polish: polish))) }
        if let payment = draft.paymentMethod {
            facts.append(Row(text.payment, text.paymentName(payment.value), proposed: !payment.isConfirmed))
        }
        if let date = draft.paymentDueDate { facts.append(Row(text.dueDate, Self.date(date, polish: polish))) }
        if let reason = draft.vatExemptionReason, !reason.trimmingCharacters(in: .whitespaces).isEmpty {
            facts.append(Row(text.exemptionReason, reason))
        }
        self.facts = facts

        var totals: [Row] = []
        if let sums {
            for group in sums.groups {
                let rate = Self.isPercent(group.rate) ? group.rate.symbol + "%" : group.rate.symbol
                totals.append(Row("\(text.net) \(rate)", MoneyText.format(group.netMinor, currency: currency, polish: polish)))
                totals.append(Row("VAT \(rate)", MoneyText.format(group.vatMinor, currency: currency, polish: polish)))
            }
            totals.append(Row(text.totalNet, MoneyText.format(sums.netMinor, currency: currency, polish: polish)))
            totals.append(Row(text.totalVat, MoneyText.format(sums.vatMinor, currency: currency, polish: polish)))
            totals.append(Row(text.totalGross, MoneyText.format(sums.grossMinor, currency: currency, polish: polish)))
        }
        self.totals = totals

        self.problems = draft.issues().map { text.sentence($0) }
        self.stateLine = text.state(operation)
        self.digest = operation.digest

        if InFaktAPI.createVerified {
            self.sendingNote = nil
            self.canConfirm = operation.state == .readyForConfirmation
        } else {
            self.sendingNote = text.notSwitchedOn
            self.canConfirm = false
        }
    }

    // MARK: Formatting

    private static func isPercent(_ rate: VatRate) -> Bool {
        if case .percent = rate { return true }
        return false
    }

    /// 1,000 thousandths is "1", 2,500 is "2,5" (Polish) or "2.5".
    static func quantity(_ milli: Int, polish: Bool) -> String {
        let whole = milli / 1000
        let fraction = milli % 1000
        guard fraction != 0 else { return String(whole) }
        var digits = String(format: "%03d", fraction)
        while digits.hasSuffix("0") { digits.removeLast() }
        return "\(whole)\(polish ? "," : ".")\(digits)"
    }

    /// 24.10.2026 in Polish, 2026-10-24 otherwise.
    static func date(_ date: CalendarDate, polish: Bool) -> String {
        polish ? String(format: "%02d.%02d.%04d", date.day, date.month, date.year) : date.iso
    }

    static func oneLine(_ a: InvoiceAddress) -> String {
        func part(_ s: String?) -> String? {
            let t = (s ?? "").trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        let number = [part(a.buildingNumber), part(a.flatNumber)].compactMap { $0 }.joined(separator: "/")
        let street = [part(a.street), number.isEmpty ? nil : number].compactMap { $0 }.joined(separator: " ")
        let town = [part(a.postCode), part(a.city)].compactMap { $0 }.joined(separator: " ")
        let country = a.countryCode == "PL" ? nil : a.countryCode
        return [street.isEmpty ? nil : street, town.isEmpty ? nil : town, country].compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: Words

    private struct Words {
        let polish: Bool

        func pick(_ pl: String, _ en: String) -> String { polish ? pl : en }

        var kind: String { pick("Nabywca", "Buyer") }
        var name: String { pick("Nazwa", "Name") }
        var address: String { pick("Adres", "Address") }
        var currency: String { pick("Waluta", "Currency") }
        var issueDate: String { pick("Data wystawienia", "Issue date") }
        var saleDate: String { pick("Data sprzedaży", "Sale date") }
        var payment: String { pick("Płatność", "Payment") }
        var dueDate: String { pick("Termin płatności", "Due date") }
        var exemptionReason: String { pick("Podstawa zwolnienia z VAT", "VAT exemption reason") }
        var net: String { pick("Netto", "Net") }
        var netWord: String { pick("netto", "net") }
        var totalNet: String { pick("Razem netto", "Total net") }
        var totalVat: String { pick("Razem VAT", "Total VAT") }
        var totalGross: String { pick("Razem brutto", "Total gross") }
        var notSwitchedOn: String {
            pick("Wysyłka do inFakt nie jest jeszcze włączona w tej wersji, więc to tylko podgląd. Nic nie zostało wystawione.",
                 "Sending to inFakt isn't switched on in this build, so this is a preview only. Nothing was issued.")
        }

        func kindName(_ kind: ContractorKind) -> String {
            switch kind {
            case .company: pick("firma", "company")
            case .privatePerson: pick("osoba prywatna", "private person")
            }
        }

        func paymentName(_ payment: InvoicePayment) -> String {
            switch payment {
            case .transfer: pick("przelew", "bank transfer")
            case .cash: pick("gotówka", "cash")
            case .card: pick("karta", "card")
            case .paypal: "PayPal"
            case .barter: "barter"
            case .cod: pick("za pobraniem", "cash on delivery")
            }
        }

        func field(_ field: InvoiceField) -> String {
            switch field {
            case .contractorKind: pick("rodzaj nabywcy (firma czy osoba prywatna)", "buyer type (company or private person)")
            case .contractorName: pick("nazwa nabywcy", "buyer's name")
            case .contractorNip: pick("NIP nabywcy", "buyer's NIP")
            case .contractorAddress: pick("adres nabywcy", "buyer's address")
            case .lines: pick("pozycje faktury", "invoice lines")
            case .lineName(let i): pick("nazwa pozycji \(i + 1)", "name of line \(i + 1)")
            case .lineQuantity(let i): pick("ilość w pozycji \(i + 1)", "quantity in line \(i + 1)")
            case .lineUnitPrice(let i): pick("cena netto w pozycji \(i + 1)", "net price in line \(i + 1)")
            case .lineVat(let i): pick("stawka VAT w pozycji \(i + 1)", "VAT rate in line \(i + 1)")
            case .currency: pick("waluta", "currency")
            case .issueDate: pick("data wystawienia", "issue date")
            case .saleDate: pick("data sprzedaży", "sale date")
            case .paymentMethod: pick("sposób płatności", "payment method")
            case .paymentDueDate: pick("termin płatności", "payment due date")
            case .vatExemptionReason: pick("podstawa zwolnienia z VAT", "VAT exemption reason")
            }
        }

        func problem(_ problem: InvoiceProblem) -> String {
            switch problem {
            case .nipChecksum: pick("numer NIP ma błędną cyfrę kontrolną", "the NIP's check digit is wrong")
            case .postCodeFormat: pick("kod pocztowy powinien mieć postać 00-000", "a Polish postal code looks like 00-000")
            case .notAPositiveAmount: pick("kwota musi być większa od zera", "the amount must be more than zero")
            case .amountTooLarge: pick("kwota jest zbyt duża", "the amount is too large")
            case .quantityOutOfRange: pick("ilość jest poza dozwolonym zakresem", "the quantity is out of range")
            case .tooManyLines: pick("pozycji jest za dużo (najwyżej \(InvoiceDraft.maxLines))", "too many lines (at most \(InvoiceDraft.maxLines))")
            case .textTooLong: pick("tekst jest za długi (najwyżej \(InvoiceDraft.maxText) znaków)", "the text is too long (at most \(InvoiceDraft.maxText) characters)")
            case .dueBeforeIssue: pick("termin płatności jest przed datą wystawienia", "the due date is before the issue date")
            }
        }

        func sentence(_ issue: InvoiceIssue) -> String {
            switch issue {
            case .missing(let f): pick("Brakuje: \(field(f)).", "Missing: \(field(f)).")
            case .needsConfirmation(let f):
                pick("Do potwierdzenia przez Ciebie: \(field(f)). Zaproponował to model, nie Ty.",
                     "You need to confirm: \(field(f)). The model suggested it; you didn't say it.")
            case .invalid(let f, let p): pick("Do poprawy: \(field(f)): \(problem(p)).", "To fix: \(field(f)): \(problem(p)).")
            }
        }

        /// "Issued" only with a receipt in hand.
        func state(_ operation: InvoiceOperation) -> String {
            switch operation.state {
            case .drafted: return pick("Szkic", "Draft")
            case .needsClarification: return pick("Brakuje danych", "Details missing")
            case .readyForConfirmation: return pick("Gotowa do potwierdzenia", "Ready for you to confirm")
            case .userConfirmed: return pick("Potwierdzona przez Ciebie, jeszcze nie wysłana", "You confirmed it; not sent yet")
            case .pendingExternalWrite: return pick("Wysyłanie do inFakt, czekam na odpowiedź", "Sending to inFakt, waiting for its answer")
            case .verifiedSucceeded:
                guard let receipt = operation.receipt else { return pick("Nie wiadomo, czy faktura powstała", "Not known whether the invoice was created") }
                let number = receipt.number.map { " " + $0 } ?? ""
                return pick("Wystawiona w inFakt\(number)", "Issued in inFakt\(number)")
            case .verifiedFailed: return pick("Nie wystawiona: \(operation.note ?? "inFakt odmówił")", "Not issued: \(operation.note ?? "inFakt refused it")")
            case .unknownOutcome: return pick("Nie wiadomo, czy faktura powstała. Sprawdź w inFakt, zanim wyślesz ponownie.", "Not known whether the invoice was created. Check inFakt before sending again.")
            }
        }
    }
}
