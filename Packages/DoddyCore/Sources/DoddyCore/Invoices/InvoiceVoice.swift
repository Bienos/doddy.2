import Foundation

// Drafting an invoice by voice (ADR-667). The person dictates; the agent calls `draft_invoice` with
// what they said, one change at a time; the app keeps the draft on screen and tells the agent what is
// still missing and the sums code worked out. Nothing leaves the iPhone: issuing in inFakt stays a
// separate tap on the card, offered only once `InFaktAPI.createVerified` is true (ADR-640).
//
// What the model says is not trusted for the two figures a wrong guess hurts most:
//  - a NIP counts as said only if its ten digits are in the person's own transcribed words. An
//    invoice that reaches KSeF with the wrong buyer NIP is delivered to that other firm.
//  - a VAT rate counts as said only if the rate is in the person's words.
// Anything not heard is kept as the model's suggestion: shown with a question mark, counted as
// missing, and settled by the person's tap on the card or by saying it.
//
// The model never states an amount: net from a gross price, VAT, totals and a due date from "14 days"
// are worked out here, in integer grosze and calendar days.
//
// Platforms: iPhone and iPad. Pure logic; tested on Linux.

extension VoiceToolName {
    /// Builds or changes the invoice draft on the user's screen (ADR-667). Nothing is sent.
    public static let draftInvoice = "draft_invoice"
}

/// A price as the person said it, per unit, in grosze (or cents).
public enum InvoiceVoicePrice: Equatable, Sendable {
    case net(Int)
    case gross(Int)
}

/// One `draft_invoice` call as parsed: only what the agent sent. A field left out keeps what the
/// draft already has.
public struct InvoiceVoiceUpdate: Equatable, Sendable {
    /// Throw away the open draft and start a new one.
    public var startNew = false
    public var buyerKind: ContractorKind?
    public var buyerName: String?
    public var buyerNip: String?
    public var street: String?
    public var buildingNumber: String?
    public var flatNumber: String?
    public var city: String?
    public var postCode: String?
    /// Two letters, "PL" when left out.
    public var countryCode: String?
    /// The line the line fields go to, counted from 1. Nil when the call sends no line field.
    public var lineNumber: Int?
    public var removeLine = false
    public var item: String?
    public var quantityMilli: Int?
    public var unit: String?
    public var price: InvoiceVoicePrice?
    public var vat: VatRate?
    public var currency: InvoiceCurrency?
    public var issueDate: CalendarDate?
    public var saleDate: CalendarDate?
    public var paymentMethod: InvoicePayment?
    public var dueDate: CalendarDate?
    public var dueInDays: Int?
    public var exemptionReason: String?
    /// Whether split payment (MPP) applies, as the user answered.
    public var splitPayment: Bool?

    public init() {}

    var hasLineFields: Bool { item != nil || quantityMilli != nil || unit != nil || price != nil || vat != nil }
    var hasAddressFields: Bool {
        street != nil || buildingNumber != nil || flatNumber != nil || city != nil || postCode != nil || countryCode != nil
    }
}

/// Something the agent should know about this change, besides what is missing.
public enum InvoiceVoiceNote: Equatable, Sendable {
    /// The NIP's digits are not in the person's words: kept as a suggestion, waits for a tap or for them to say it.
    case nipNotHeard
    /// The VAT rate of this line (from 0) is not in the person's words.
    case vatNotHeard(line: Int)
    /// A gross price was turned into a net one.
    case netFromGross(line: Int, grossMinor: Int, netMinor: Int)
    /// A gross price waits for the line's VAT rate before its net price can be worked out.
    case grossNeedsVat(line: Int)
    /// No issue date was said, so it is today.
    case issueDateIsToday(CalendarDate)
    /// The due date was worked out from a number of days after the issue date.
    case dueFromDays(days: Int, date: CalendarDate)
    /// No sale date was said: the invoice has none, which means it is the issue date (art. 106e
    /// ust. 1 pkt 6 of the VAT act asks for it only when it differs).
    case saleDateIsIssueDate
    /// The issue date said is before today: KSeF treats such an invoice as made offline (offline24),
    /// so it must reach KSeF by the next business day after that date.
    case issueDateInPast(CalendarDate)
}

/// The invoice being drafted in one conversation: what the person said, field by field, and the
/// operation made from it. Held by the voice screen; not saved anywhere.
public struct InvoiceVoiceSession: Equatable, Sendable {
    struct LineInput: Equatable, Sendable {
        var name: Sourced<String>?
        var quantityMilli: Int?
        var unit: String?
        var price: InvoiceVoicePrice?
        var vat: Sourced<VatRate>?
    }

    private var kind: Sourced<ContractorKind>?
    private var name: Sourced<String>?
    private var nip: Sourced<String>?
    private var address: InvoiceAddress?
    private var lines: [LineInput] = []
    private var currency: Sourced<InvoiceCurrency>?
    private var issueDate: CalendarDate?
    private var saleDate: CalendarDate?
    private var payment: Sourced<InvoicePayment>?
    private var dueDate: CalendarDate?
    private var dueInDays: Int?
    private var exemptionReason: String?
    private var splitPayment: Sourced<Bool>?
    public private(set) var operation: InvoiceOperation?

    public init() {}

    public enum Outcome: Equatable, Sendable {
        case drafted(InvoiceOperation, notes: [InvoiceVoiceNote])
        /// Nothing was changed; the reason is for the agent.
        case refused(String)
    }

    /// Applies one call. `userWords` are the person's own transcribed turns in this conversation;
    /// `today` is the iPhone's local day.
    public mutating func apply(_ update: InvoiceVoiceUpdate, userWords: [String], today: CalendarDate) -> Outcome {
        if let operation, Self.isLocked(operation.state) {
            return .refused("this invoice is already being sent or was sent, so it can't be changed. To make another one, call "
                + "\(VoiceToolName.draftInvoice) with start_new.")
        }
        var next = update.startNew ? InvoiceVoiceSession() : self
        var notes: [InvoiceVoiceNote] = []

        // The buyer.
        if let value = update.buyerKind { next.kind = Sourced(value, source: .saidByUser) }
        if let value = update.buyerName { next.name = Sourced(Self.oneSpaced(value), source: .saidByUser) }
        if let raw = update.buyerNip {
            // A NIP that fails its check digit is kept as said, so the card can show what is wrong with it.
            let heard = Nip(raw).map { InvoiceHeard.saidNip($0, in: userWords) } ?? true
            next.nip = Sourced(raw, source: heard ? .saidByUser : .proposedByModel)
            if !heard { notes.append(.nipNotHeard) }
        }
        if update.hasAddressFields {
            var address = next.address ?? InvoiceAddress()
            if let v = update.street { address.street = v }
            if let v = update.buildingNumber { address.buildingNumber = v }
            if let v = update.flatNumber { address.flatNumber = v }
            if let v = update.city { address.city = v }
            if let v = update.postCode { address.postCode = v }
            if let v = update.countryCode { address.countryCode = v }
            next.address = address
        }

        // The line.
        if update.removeLine || update.hasLineFields {
            let number = update.lineNumber ?? 1
            let index = number - 1
            if update.removeLine {
                guard next.lines.indices.contains(index) else {
                    return .refused("the draft has no line \(number) (it has \(next.lines.count)); nothing was changed.")
                }
                next.lines.remove(at: index)
            } else {
                guard index >= 0, index <= next.lines.count else {
                    return .refused("the draft has \(next.lines.count) line\(next.lines.count == 1 ? "" : "s"), so the next new one is line "
                        + "\(next.lines.count + 1); nothing was changed.")
                }
                guard index < InvoiceDraft.maxLines else {
                    return .refused("an invoice from Doddy has at most \(InvoiceDraft.maxLines) lines; nothing was changed.")
                }
                if index == next.lines.count { next.lines.append(LineInput()) }
                var line = next.lines[index]
                // inFakt refuses double spaces in an item's name; one space says the same.
                if let v = update.item { line.name = Sourced(Self.oneSpaced(v), source: .saidByUser) }
                if let v = update.quantityMilli { line.quantityMilli = v }
                if let v = update.unit { line.unit = v }
                if let v = update.price { line.price = v }
                if let rate = update.vat {
                    let heard = InvoiceHeard.saidRate(rate, in: userWords)
                    line.vat = Sourced(rate, source: heard ? .saidByUser : .proposedByModel)
                    if !heard { notes.append(.vatNotHeard(line: index)) }
                }
                next.lines[index] = line
            }
        }

        // Currency, dates, payment.
        if let v = update.currency { next.currency = Sourced(v, source: .saidByUser) }
        if let v = update.issueDate {
            // KSeF refuses an invoice dated after the day it is sent, and inFakt lists it among its
            // rejections (research A14, C19).
            guard v <= today else {
                return .refused("an invoice can't be dated in the future: KSeF refuses an issue date after the day it is sent. "
                    + "Ask the user for today's date or an earlier one.")
            }
            next.issueDate = v
            if v < today { notes.append(.issueDateInPast(v)) }
        }
        if next.issueDate == nil {
            next.issueDate = today
            notes.append(.issueDateIsToday(today))
        }
        if let v = update.saleDate { next.saleDate = v }
        if let v = update.paymentMethod { next.payment = Sourced(v, source: .saidByUser) }
        if let v = update.dueDate {
            next.dueDate = v
            next.dueInDays = nil
        }
        if let days = update.dueInDays {
            next.dueInDays = days
            next.dueDate = nil
        }
        if let v = update.exemptionReason { next.exemptionReason = v }
        if let v = update.splitPayment { next.splitPayment = Sourced(v, source: .saidByUser) }

        // The draft, worked out from what was said.
        let (draft, derivedNotes) = next.makeDraft()
        notes += derivedNotes
        if next.saleDate == nil, !notes.contains(.saleDateIsIssueDate), update.startNew || operation == nil {
            notes.append(.saleDateIsIssueDate)
        }
        if var operation = update.startNew ? nil : next.operation {
            do { try operation.update(draft) } catch {
                return .refused("this invoice can't be changed now; nothing was changed.")
            }
            next.operation = operation
        } else {
            next.operation = InvoiceOperation(draft: draft)
        }
        self = next
        return .drafted(next.operation!, notes: notes)
    }

    /// The person tapped to confirm a value the model suggested, as the card showed it. False when
    /// that field holds no suggestion (nothing changes).
    @discardableResult
    public mutating func confirmSuggested(_ field: InvoiceField) -> Bool {
        guard let operation, !Self.isLocked(operation.state) else { return false }
        switch field {
        case .contractorNip:
            guard let value = nip, !value.isConfirmed else { return false }
            nip = Sourced(value.value, source: .saidByUser)
        case .lineVat(let i):
            guard lines.indices.contains(i), let value = lines[i].vat, !value.isConfirmed else { return false }
            lines[i].vat = Sourced(value.value, source: .saidByUser)
        default:
            return false
        }
        var updated = operation
        guard (try? updated.update(makeDraft().0)) != nil else { return false }
        self.operation = updated
        return true
    }

    /// The person closed the card: the draft is gone.
    public mutating func close() {
        self = InvoiceVoiceSession()
    }

    private static func isLocked(_ state: InvoiceState) -> Bool {
        switch state {
        case .pendingExternalWrite, .verifiedSucceeded, .verifiedFailed, .unknownOutcome: true
        case .drafted, .needsClarification, .readyForConfirmation, .userConfirmed: false
        }
    }

    private func makeDraft() -> (InvoiceDraft, [InvoiceVoiceNote]) {
        var notes: [InvoiceVoiceNote] = []
        let draftLines = lines.enumerated().map { index, input -> InvoiceLine in
            var net: Int?
            switch input.price {
            case .net(let value)?: net = value
            case .gross(let gross)?:
                if let rate = input.vat?.value {
                    let value = InvoiceVoiceMoney.netFromGross(gross, rate: rate)
                    net = value
                    if let value { notes.append(.netFromGross(line: index, grossMinor: gross, netMinor: value)) }
                } else {
                    notes.append(.grossNeedsVat(line: index))
                }
            case nil: net = nil
            }
            return InvoiceLine(name: input.name, quantityMilli: input.quantityMilli, unit: input.unit, netUnitPriceMinor: net, vat: input.vat)
        }
        var due = dueDate
        if let days = dueInDays, let issue = issueDate, let date = issue.adding(days: days) {
            due = date
            notes.append(.dueFromDays(days: days, date: date))
        }
        let draft = InvoiceDraft(
            contractor: InvoiceContractor(
                kind: kind, name: name, nip: nip, address: address.map { Sourced($0, source: .saidByUser) }),
            lines: draftLines, currency: currency, issueDate: issueDate, saleDate: saleDate,
            paymentMethod: payment, paymentDueDate: due, vatExemptionReason: exemptionReason, splitPayment: splitPayment)
        return (draft, notes)
    }

    /// Runs of spaces and line breaks become one space; the ends are trimmed.
    static func oneSpaced(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

/// Whether a figure is in what the person said. Their words are the speech-to-text of their own
/// turns, never the agent's or a tool's text.
public enum InvoiceHeard {
    /// Digits said one at a time as words, in Polish and English.
    static let digitWords: [String: Character] = [
        "zero": "0", "jeden": "1", "jedynka": "1", "dwa": "2", "dwójka": "2", "trzy": "3", "trójka": "3",
        "cztery": "4", "czwórka": "4", "pięć": "5", "piątka": "5", "sześć": "6", "szóstka": "6",
        "siedem": "7", "siódemka": "7", "osiem": "8", "ósemka": "8", "dziewięć": "9", "dziewiątka": "9",
        "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
    ]

    static func tokens(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// Every digit in the person's words, in order, across their turns: written digits and digit words.
    static func digits(in words: [String]) -> String {
        var out = ""
        for token in words.flatMap(tokens) {
            let written = token.filter { ("0"..."9").contains($0) }
            if !written.isEmpty {
                out += written
            } else if let digit = digitWords[token] {
                out.append(digit)
            }
        }
        return out
    }

    public static func saidNip(_ nip: Nip, in words: [String]) -> Bool {
        digits(in: words).contains(nip.digits)
    }

    /// The rate as a number ("23", "23%"), in words ("dwadzieścia trzy", "osiem"), or "zw" / "np" and
    /// their words.
    public static func saidRate(_ rate: VatRate, in words: [String]) -> Bool {
        let said = words.flatMap(tokens)
        func has(_ phrase: [String]) -> Bool {
            guard !phrase.isEmpty, said.count >= phrase.count else { return false }
            return (0...(said.count - phrase.count)).contains { Array(said[$0..<($0 + phrase.count)]) == phrase }
        }
        switch rate {
        case .percent(let value):
            let spoken: [[String]] = switch value {
            case 23: [["dwadzieścia", "trzy"], ["twenty", "three"]]
            case 8: [["osiem"], ["eight"]]
            case 5: [["pięć"], ["five"]]
            case 0: [["zero"], ["zerowa"], ["zerowy"], ["zerową"]]
            default: []
            }
            return said.contains(String(value)) || spoken.contains(where: has)
        case .exempt:
            return said.contains { $0 == "zw" || $0.hasPrefix("zwoln") || $0.hasPrefix("exempt") }
        case .notSubject:
            return said.contains("np") || has(["nie", "podlega"]) || has(["not", "subject"])
        }
    }
}

/// Amounts and quantities as the agent sends them: a JSON number or text such as "1 000,50 zł".
/// Never rounded: more decimals than a grosz (or a thousandth of a unit) is refused.
public enum InvoiceVoiceMoney {
    /// Net from a gross price per unit, rounded half up to a grosz. Exempt and not-subject lines carry
    /// no VAT, so net is gross. Nil if it would overflow.
    public static func netFromGross(_ gross: Int, rate: VatRate) -> Int? {
        let percent = rate.percent
        guard percent > 0 else { return gross }
        let (scaled, overflow) = gross.multipliedReportingOverflow(by: 100)
        guard !overflow else { return nil }
        let divisor = 100 + percent
        return (scaled + divisor / 2) / divisor
    }

    /// `scale` decimals (2 for money, 3 for a quantity); the result is in those units. Nil when it
    /// isn't a plain positive figure with at most `scale` decimals, or it is above `max`.
    static func scaled(_ value: Double, scale: Int, max: Int) -> Int? {
        guard value.isFinite, value > 0 else { return nil }
        let factor = scale == 3 ? 1000.0 : 100.0
        guard value <= Double(max) / factor else { return nil }
        let raw = value * factor
        let whole = raw.rounded()
        guard abs(raw - whole) < 0.000_001, whole >= 1 else { return nil }
        return Int(whole)
    }

    /// Text such as "1000", "1 000,50", "1000.50 zł" or "2,5". Read digit by digit.
    static func scaled(_ text: String, scale: Int, max: Int) -> Int? {
        var cleaned = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["pln", "zł", "zl", "eur", "€", "usd", "$", "gbp", "£", "godz.", "h"] where cleaned.hasSuffix(suffix) {
            cleaned = String(cleaned.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        cleaned = cleaned.filter { $0 != " " && $0 != "\u{00A0}" && $0 != "\u{202F}" }
        let parts = cleaned.split(whereSeparator: { $0 == "." || $0 == "," }).map(String.init)
        let separators = cleaned.filter { $0 == "." || $0 == "," }.count
        guard separators <= 1, parts.count == separators + 1, let whole = parts.first, !whole.isEmpty,
              whole.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        let fraction = parts.count == 2 ? parts[1] : ""
        guard fraction.count <= scale, fraction.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        let significant = String(whole.drop { $0 == "0" })
        guard significant.count <= 12, let units = Int(significant.isEmpty ? "0" : significant) else { return nil }
        let factor = scale == 3 ? 1000 : 100
        let minor = units * factor + (Int(fraction.padding(toLength: scale, withPad: "0", startingAt: 0)) ?? 0)
        guard minor >= 1, minor <= max else { return nil }
        return minor
    }
}

extension VoiceToolRequest {
    /// Every argument is optional; anything left out keeps what the draft has.
    static func parseDraftInvoice(_ args: Arguments, name: String) -> VoiceToolRequest {
        func invalid(_ reason: String) -> VoiceToolRequest { .invalid(name: name, reason: reason) }
        var update = InvoiceVoiceUpdate()
        update.startNew = args.flag("start_new")

        if let text = args.text("buyer_kind") {
            switch text.lowercased().trimmingCharacters(in: .whitespaces) {
            case "company", "firma", "business": update.buyerKind = .company
            case "private", "private_person", "person", "osoba prywatna", "osoba": update.buyerKind = .privatePerson
            default: return invalid("buyer_kind must be 'company' or 'private'")
            }
        }
        update.buyerName = args.text("buyer_name")
        update.buyerNip = args.text("buyer_nip")
        update.street = args.text("street")
        update.buildingNumber = args.text("building_number")
        update.flatNumber = args.text("flat_number")
        update.city = args.text("city")
        update.postCode = args.text("post_code")
        if let text = args.text("country") {
            let code = text.uppercased().trimmingCharacters(in: .whitespaces)
            guard code.count == 2, code.allSatisfy({ ("A"..."Z").contains($0) }) else {
                return invalid("country must be a two-letter code, for example PL or DE")
            }
            update.countryCode = code
        }

        if args.has("line") {
            guard let number = args.number("line"), number == number.rounded(), number >= 1, number <= Double(InvoiceDraft.maxLines) else {
                return invalid("line must be a whole number from 1 to \(InvoiceDraft.maxLines)")
            }
            update.lineNumber = Int(number)
        }
        update.removeLine = args.flag("remove_line")
        if update.removeLine, update.lineNumber == nil { return invalid("remove_line needs line, the number of the line to remove") }
        update.item = args.text("item")
        update.unit = args.text("unit")
        if args.has("quantity") {
            let quantity = args.number("quantity").flatMap { InvoiceVoiceMoney.scaled($0, scale: 3, max: InvoiceDraft.maxQuantityMilli) }
                ?? args.text("quantity").flatMap { InvoiceVoiceMoney.scaled($0, scale: 3, max: InvoiceDraft.maxQuantityMilli) }
            guard let quantity else {
                return invalid("quantity must be more than zero, at most \(InvoiceDraft.maxQuantityMilli / 1000), with at most three decimals")
            }
            update.quantityMilli = quantity
        }
        func money(_ key: String) -> Int?? {
            guard args.has(key) else { return .some(nil) }
            let value = args.number(key).flatMap { InvoiceVoiceMoney.scaled($0, scale: 2, max: InvoiceDraft.maxUnitPriceMinor) }
                ?? args.text(key).flatMap { InvoiceVoiceMoney.scaled($0, scale: 2, max: InvoiceDraft.maxUnitPriceMinor) }
            return value.map { .some($0) } ?? nil
        }
        let maxPrice = InvoiceDraft.maxUnitPriceMinor / 100
        guard let net = money("net_price"), let gross = money("gross_price") else {
            return invalid("a price must be more than zero and at most \(maxPrice), with at most two decimals, exactly as the user said it")
        }
        switch (net, gross) {
        case (let net?, nil): update.price = .net(net)
        case (nil, let gross?): update.price = .gross(gross)
        case (nil, nil): break
        case (_?, _?): return invalid("send net_price or gross_price, not both")
        }
        if args.has("vat_rate") {
            let text = args.text("vat_rate") ?? args.number("vat_rate").map { $0 == $0.rounded() ? String(Int($0)) : String($0) }
            guard let symbol = text?.replacingOccurrences(of: "%", with: ""), let rate = VatRate(symbol: symbol) else {
                return invalid("vat_rate must be one of 23, 8, 5, 0, zw (exempt) or np (not subject), as the user said it")
            }
            update.vat = rate
        }

        if let text = args.text("currency") {
            let code = text.uppercased().trimmingCharacters(in: .whitespaces)
            let mapped = ["ZŁ": "PLN", "ZL": "PLN", "ZŁOTY": "PLN", "€": "EUR", "$": "USD", "£": "GBP"][code] ?? code
            guard let currency = InvoiceCurrency(rawValue: mapped) else { return invalid("currency must be PLN, EUR, USD or GBP") }
            update.currency = currency
        }
        func day(_ key: String) -> CalendarDate?? {
            guard let text = args.text(key) else { return .some(nil) }
            return CalendarDate(iso: text.trimmingCharacters(in: .whitespaces)).map { .some($0) } ?? nil
        }
        guard let issue = day("issue_date"), let sale = day("sale_date"), let due = day("due_date") else {
            return invalid("dates must be written YYYY-MM-DD, for example 2026-10-30")
        }
        update.issueDate = issue
        update.saleDate = sale
        update.dueDate = due
        if args.has("due_in_days") {
            guard let days = args.number("due_in_days"), days == days.rounded(), (0...365).contains(days) else {
                return invalid("due_in_days must be a whole number of days from 0 to 365")
            }
            update.dueInDays = Int(days)
        }
        if update.dueDate != nil, update.dueInDays != nil { return invalid("send due_date or due_in_days, not both") }
        if let text = args.text("payment_method") {
            let methods: [String: InvoicePayment] = [
                "transfer": .transfer, "przelew": .transfer, "bank transfer": .transfer,
                "cash": .cash, "gotówka": .cash, "gotowka": .cash,
                "card": .card, "karta": .card, "paypal": .paypal, "barter": .barter,
                "cod": .cod, "za pobraniem": .cod, "pobranie": .cod,
            ]
            guard let method = methods[text.lowercased().trimmingCharacters(in: .whitespaces)] else {
                return invalid("payment_method must be transfer, cash, card, paypal, barter or cod")
            }
            update.paymentMethod = method
        }
        update.exemptionReason = args.text("exemption_reason")
        if args.has("split_payment") {
            guard let value = args.raw("split_payment") as? Bool else { return invalid("split_payment must be true or false") }
            update.splitPayment = value
        }

        if !update.startNew, !update.removeLine, !update.hasLineFields, !update.hasAddressFields, update.buyerKind == nil,
           update.buyerName == nil, update.buyerNip == nil, update.currency == nil, update.issueDate == nil, update.saleDate == nil,
           update.dueDate == nil, update.dueInDays == nil, update.paymentMethod == nil, update.exemptionReason == nil,
           update.splitPayment == nil {
            return invalid("nothing to put on the invoice: pass what the user said")
        }
        return .draftInvoice(update)
    }
}

extension VoiceToolReply {
    /// What the agent hears after a `draft_invoice` call. Sums and dates are Doddy's; names, the item
    /// text and the NIP are data (ToolData). Never says issued: sending is not built into this reply.
    public static func invoiceDraft(_ operation: InvoiceOperation, notes: [InvoiceVoiceNote]) -> String {
        let draft = operation.draft
        let currency = draft.currency?.value ?? .pln
        func money(_ minor: Int) -> String { MoneyText.format(minor, currency: currency, polish: false) }
        func field(_ f: InvoiceField) -> String { InvoiceCard.fieldName(f, polish: false) }

        var parts: [String] = []
        let ready = operation.state == .readyForConfirmation
        if ready {
            parts.append("ready: the invoice draft on the user's screen is complete. It is kept on this iPhone for this conversation only, "
                + "not saved. Nothing was sent to inFakt or KSeF and no invoice exists.")
        } else {
            parts.append("drafted: the invoice draft is on the user's screen, kept on this iPhone for this conversation only, not saved. "
                + "Nothing was sent to inFakt or KSeF and no invoice exists.")
        }
        if InFaktAPI.createVerified {
            parts.append(ready
                ? "The user issues it by tapping Issue in inFakt on the card; you can't issue it."
                : "Once it is complete the user can issue it with a tap on the card; you can't issue it.")
        } else {
            parts.append("Issuing through inFakt isn't switched on in this build, so it can't be issued from Doddy yet; if asked, say so.")
        }
        parts.append("Never say it was issued, sent, saved or is in KSeF.")

        var missing: [String] = []
        var unconfirmed: [String] = []
        var wrong: [String] = []
        for issue in draft.issues() {
            switch issue {
            case .missing(let f):
                // A gross price waiting for its rate is said below, with the rate.
                if case .lineUnitPrice(let i) = f, notes.contains(.grossNeedsVat(line: i)) { continue }
                missing.append(field(f))
            case .needsConfirmation(let f): unconfirmed.append(field(f))
            case .invalid(let f, let p): wrong.append("\(field(f)): \(InvoiceCard.problemText(p, polish: false))")
            }
        }
        if !wrong.isEmpty {
            parts.append("To fix (ask the user to say it again; never correct it yourself): " + wrong.joined(separator: "; ") + ".")
        }
        if !missing.isEmpty {
            parts.append("Still needed: " + missing.joined(separator: ", ") + ". Ask for one or two at a time, in the user's language; "
                + "never fill in a NIP, an address, a VAT rate or a date yourself.")
        }
        if !unconfirmed.isEmpty {
            parts.append("Waiting for the user: " + unconfirmed.joined(separator: ", ") + " "
                + "\(unconfirmed.count == 1 ? "is" : "are") not in what the user said, so the card shows "
                + "\(unconfirmed.count == 1 ? "it" : "them") with a question mark. Ask them to say it, or to tap Confirm on the card if it is right.")
        }
        for note in notes {
            switch note {
            case .netFromGross(let line, let gross, let net):
                parts.append("Line \(line + 1): the user gave a gross price of \(money(gross)) per unit; Doddy worked out \(money(net)) net.")
            case .grossNeedsVat(let line):
                parts.append("Line \(line + 1): the user gave a gross price; Doddy works out the net price once the VAT rate is known: ask for the rate.")
            case .issueDateIsToday(let date):
                parts.append("No issue date was said, so it is today, \(date.iso); the user can change it.")
            case .dueFromDays(let days, let date):
                parts.append("Due \(days) day\(days == 1 ? "" : "s") after the issue date: \(date.iso).")
            case .saleDateIsIssueDate:
                parts.append("No sale date was said: it is the same as the issue date. If the work was done or the goods delivered on another day, ask which.")
            case .issueDateInPast(let date):
                parts.append("The issue date \(date.iso) is before today: KSeF counts such an invoice as made offline, so it must reach KSeF by the "
                    + "next business day after that date. Tell the user in one sentence.")
            case .nipNotHeard, .vatNotHeard:
                break
            }
        }
        if let totals = draft.totals {
            parts.append("Sums worked out by Doddy (say only these, never your own): net \(money(totals.netMinor)), VAT \(money(totals.vatMinor)), "
                + "gross \(money(totals.grossMinor)).")
        }

        var data: [String] = []
        let buyer = draft.contractor
        if let name = buyer.name { data.append(quoted("Buyer", name.value)) }
        if let nip = buyer.nip { data.append(quoted("NIP", Nip(nip.value)?.display ?? nip.value)) }
        if let address = buyer.address { data.append(quoted("Address", InvoiceCard.oneLine(address.value))) }
        let nets = draft.totals?.lineNetMinor
        for (i, line) in draft.lines.enumerated() {
            let net = nets.map { money($0[i]) } ?? "not worked out yet"
            data.append(quoted("Line \(i + 1)", line.name?.value ?? "(no name yet)") + " · net \(net) · VAT \(line.vat?.value.symbol ?? "?")")
        }
        return parts.joined(separator: " ") + (data.isEmpty ? "" : "\n" + ToolData.block(data))
    }

    /// `draft_invoice` changed nothing.
    public static func invoiceRefused(_ reason: String) -> String {
        "failed: \(reason) Nothing was sent anywhere."
    }
}
