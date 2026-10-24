import XCTest
@testable import DoddyCore

/// A scripted accounting program. It counts how often an invoice was created.
actor FakeInvoiceProvider: InvoiceProvider {
    enum Script {
        case succeed
        case reject(String)
        /// Created, but the answer is lost: the caller sees a timeout.
        case createThenLoseAnswer
        /// The request never arrived: nothing is created, the caller sees a timeout.
        case timeoutBeforeCreate
        case answerWithAnotherOperation
    }

    private var script: Script
    private(set) var createCalls = 0
    private(set) var findCalls = 0
    private var created: [UUID: InvoiceReceipt] = [:]
    private var findFails = false

    init(_ script: Script) { self.script = script }

    func setScript(_ script: Script) { self.script = script }
    func setFindFails(_ value: Bool) { findFails = value }

    func createInvoice(_ invoice: ConfirmedInvoice) async throws -> InvoiceReceipt {
        createCalls += 1
        let receipt = InvoiceReceipt(operationId: invoice.operationId, externalId: "inv-\(createCalls)", number: "1/10/2026",
                                     verifiedAt: Date(timeIntervalSince1970: 1_000))
        switch script {
        case .succeed:
            created[invoice.operationId] = receipt
            return receipt
        case .reject(let why):
            throw InvoiceProviderError.rejected(why)
        case .createThenLoseAnswer:
            created[invoice.operationId] = receipt
            throw InvoiceProviderError.outcomeUnknown
        case .timeoutBeforeCreate:
            throw InvoiceProviderError.outcomeUnknown
        case .answerWithAnotherOperation:
            return InvoiceReceipt(operationId: UUID(), externalId: "someone-else", number: nil, verifiedAt: Date())
        }
    }

    func findInvoice(operationId: UUID) async throws -> InvoiceReceipt? {
        findCalls += 1
        if findFails { throw InvoiceProviderError.outcomeUnknown }
        return created[operationId]
    }
}

/// Invoices (ADR-640): the draft, the sums, the confirmation and the "never twice" rule.
final class InvoiceTests: XCTestCase {
    // MARK: Helpers

    private func said<T: Equatable & Sendable & Codable>(_ value: T) -> Sourced<T> { Sourced(value, source: .saidByUser) }

    private func readyDraft() -> InvoiceDraft {
        InvoiceDraft(
            contractor: InvoiceContractor(
                kind: said(.company), name: said("Urząd Miejski Krakowa"), nip: said("1060006024"),
                address: said(InvoiceAddress(street: "Plac Wszystkich Świętych", buildingNumber: "3-4", city: "Kraków", postCode: "31-004"))),
            lines: [InvoiceLine(name: said("Konsultacje"), quantityMilli: 2_000, unit: "godz.", netUnitPriceMinor: 50_000, vat: said(.percent(23)))],
            currency: said(.pln), issueDate: CalendarDate(iso: "2026-10-24"), saleDate: CalendarDate(iso: "2026-10-24"),
            paymentMethod: said(.transfer), paymentDueDate: CalendarDate(iso: "2026-11-07"))
    }

    private func confirmed(_ draft: InvoiceDraft) throws -> InvoiceOperation {
        var operation = InvoiceOperation(draft: draft)
        XCTAssertEqual(operation.state, .readyForConfirmation)
        try operation.confirm(shownDigest: try XCTUnwrap(operation.digest))
        return operation
    }

    // MARK: NIP, dates, money

    func testNipChecksum() {
        XCTAssertEqual(Nip("1060006024")?.digits, "1060006024")
        XCTAssertEqual(Nip("106-000-60-24")?.display, "106-000-60-24")
        XCTAssertEqual(Nip("PL 106 000 60 24")?.digits, "1060006024")
        XCTAssertNil(Nip("1060006025"))      // wrong check digit
        XCTAssertNil(Nip("106000602"))       // nine digits
        XCTAssertNil(Nip("10600060244"))     // eleven digits
        XCTAssertNil(Nip("106000602a"))
        XCTAssertNil(Nip("1234567890"))      // a guessed one
        XCTAssertNil(Nip(""))
    }

    func testCalendarDates() throws {
        XCTAssertEqual(CalendarDate(iso: "2026-10-24")?.iso, "2026-10-24")
        XCTAssertNil(CalendarDate(iso: "2026-02-29"))
        XCTAssertNotNil(CalendarDate(iso: "2028-02-29"))
        XCTAssertNil(CalendarDate(iso: "2026-13-01"))
        XCTAssertNil(CalendarDate(iso: "26-10-24"))
        XCTAssertNil(CalendarDate(iso: "2026-1-5"))
        let day = try XCTUnwrap(CalendarDate(iso: "2026-10-24"))
        XCTAssertEqual(day.adding(days: 14)?.iso, "2026-11-07")
        XCTAssertEqual(day.adding(days: -24)?.iso, "2026-09-30")
        XCTAssertEqual(try XCTUnwrap(CalendarDate(iso: "2026-12-31")).adding(days: 1)?.iso, "2027-01-01")
        XCTAssertEqual(try XCTUnwrap(CalendarDate(iso: "2028-02-28")).adding(days: 1)?.iso, "2028-02-29")
        XCTAssertLessThan(try XCTUnwrap(CalendarDate(iso: "2026-10-23")), day)
    }

    func testVatSymbolsAndMoneyText() {
        XCTAssertEqual(VatRate(symbol: "23"), .percent(23))
        XCTAssertEqual(VatRate(symbol: "ZW"), .exempt)
        XCTAssertEqual(VatRate(symbol: "np"), .notSubject)
        XCTAssertNil(VatRate(symbol: "22"))
        XCTAssertNil(VatRate(symbol: "7"))
        XCTAssertEqual(VatRate.exempt.percent, 0)
        XCTAssertEqual(MoneyText.format(123_000, currency: .pln, polish: true), "1\u{00A0}230,00 PLN")
        XCTAssertEqual(MoneyText.format(123_000, currency: .eur, polish: false), "1,230.00 EUR")
        XCTAssertEqual(MoneyText.format(5, currency: .pln, polish: true), "0,05 PLN")
        XCTAssertEqual(MoneyText.format(-250, currency: .usd, polish: false), "-2.50 USD")
        XCTAssertEqual(MoneyText.format(123_456_789, currency: .pln, polish: true), "1\u{00A0}234\u{00A0}567,89 PLN")
    }

    // MARK: Sums

    func testTotalsInGrosze() throws {
        let totals = try XCTUnwrap(readyDraft().totals)
        XCTAssertEqual(totals.lineNetMinor, [100_000])
        XCTAssertEqual(totals.netMinor, 100_000)
        XCTAssertEqual(totals.vatMinor, 23_000)
        XCTAssertEqual(totals.grossMinor, 123_000)
    }

    func testRoundingRules() throws {
        func totals(_ lines: [(qty: Int, price: Int, vat: VatRate)]) -> InvoiceTotals? {
            InvoiceTotals.compute(lines.map {
                InvoiceLine(name: said("x"), quantityMilli: $0.qty, unit: nil, netUnitPriceMinor: $0.price, vat: said($0.vat))
            })
        }
        // A line's net value is rounded half up to a grosz: 0.5 × 0.05 zł = 0.025 zł → 0.03 zł.
        XCTAssertEqual(totals([(500, 5, .percent(0))])?.lineNetMinor, [3])
        XCTAssertEqual(totals([(499, 5, .percent(0))])?.lineNetMinor, [2])
        XCTAssertEqual(totals([(3_000, 333, .percent(0))])?.lineNetMinor, [999])
        // VAT is worked out on the SUM of a rate's nets (10.05 + 10.05 at 8%: 20.10 × 0.08 = 1.608 → 1.61),
        // not line by line (0.804 → 0.80, twice = 1.60).
        let two = try XCTUnwrap(totals([(1_000, 1_005, .percent(8)), (1_000, 1_005, .percent(8))]))
        XCTAssertEqual(two.groups.map(\.vatMinor), [161])
        XCTAssertEqual(two.grossMinor, 2_010 + 161)
        // Half a grosz of VAT rounds up: 0.50 zł × 0.23 = 0.115 → 0.12 zł.
        XCTAssertEqual(totals([(1_000, 50, .percent(23))])?.groups.first?.vatMinor, 12)
        // Several rates are kept apart, in the order 23, 8, 5, 0, zw, np; zw and np carry no VAT.
        let mixed = try XCTUnwrap(totals([(1_000, 10_000, .exempt), (1_000, 10_000, .percent(5)),
                                          (1_000, 10_000, .percent(23)), (1_000, 10_000, .notSubject), (1_000, 10_000, .percent(0))]))
        XCTAssertEqual(mixed.groups.map(\.rate), [.percent(23), .percent(5), .percent(0), .exempt, .notSubject])
        XCTAssertEqual(mixed.vatMinor, 2_300 + 500)
        XCTAssertEqual(mixed.netMinor, 50_000)
    }

    func testTotalsRefuseWhatItCannotWorkOut() {
        func one(_ line: InvoiceLine) -> InvoiceTotals? { InvoiceTotals.compute([line]) }
        let ok = InvoiceLine(name: said("x"), quantityMilli: 1_000, unit: nil, netUnitPriceMinor: 100, vat: said(.percent(23)))
        XCTAssertNotNil(one(ok))
        var noVat = ok; noVat.vat = nil
        XCTAssertNil(one(noVat))
        var guessedVat = ok; guessedVat.vat = Sourced(.percent(23), source: .proposedByModel)
        XCTAssertNil(one(guessedVat))
        var noQty = ok; noQty.quantityMilli = nil
        XCTAssertNil(one(noQty))
        var zero = ok; zero.netUnitPriceMinor = 0
        XCTAssertNil(one(zero))
        var huge = ok; huge.netUnitPriceMinor = InvoiceDraft.maxUnitPriceMinor + 1
        XCTAssertNil(one(huge))
        XCTAssertNil(InvoiceTotals.compute([]))
        XCTAssertNil(InvoiceTotals.compute(Array(repeating: ok, count: InvoiceDraft.maxLines + 1)))
    }

    // MARK: Missing data and never guessing (acceptance test 8)

    func testAReadyDraftHasNoIssues() {
        XCTAssertEqual(readyDraft().issues(), [])
        XCTAssertTrue(readyDraft().isReadyForConfirmation)
        XCTAssertEqual(readyDraft().missingData, [])
    }

    /// "Wystaw fakturę dla ABC na 1000 zł": a preview and the missing data; never a guessed NIP or VAT rate.
    func testABareRequestListsWhatIsMissingAndGuessesNothing() throws {
        let draft = InvoiceDraft(
            contractor: InvoiceContractor(name: said("ABC")),
            lines: [InvoiceLine(name: said("Usługa"), netUnitPriceMinor: 100_000)])
        XCTAssertFalse(draft.isReadyForConfirmation)
        let missing = Set(draft.missingData)
        for key in ["contractor.kind", "contractor.nip", "contractor.address", "lines.1.quantity", "lines.1.vat_rate",
                    "currency", "issue_date", "sale_date", "payment_method"] {
            XCTAssertTrue(missing.contains(key), "\(key) should be missing: \(missing)")
        }
        XCTAssertNil(draft.totals, "no VAT rate was given, so no sum is shown")
        let operation = InvoiceOperation(draft: draft)
        XCTAssertEqual(operation.state, .needsClarification)
        XCTAssertNil(operation.digest)
    }

    func testAValueTheModelProposedIsNotEnough() {
        var draft = readyDraft()
        draft.contractor.nip = Sourced("1060006024", source: .proposedByModel)
        draft.lines[0].vat = Sourced(.percent(23), source: .proposedByModel)
        draft.contractor.kind = Sourced(.company, source: .proposedByModel)
        let issues = draft.issues()
        XCTAssertTrue(issues.contains(.needsConfirmation(.contractorNip)))
        XCTAssertTrue(issues.contains(.needsConfirmation(.lineVat(0))))
        XCTAssertTrue(issues.contains(.needsConfirmation(.contractorKind)))
        XCTAssertEqual(Set(draft.missingData), ["contractor.nip", "lines.1.vat_rate", "contractor.kind"])
        XCTAssertNil(draft.totals)
        // The person's own default counts, and says where it came from.
        draft.lines[0].vat = Sourced(.percent(23), source: .userDefault)
        draft.contractor.nip = said("1060006024")
        draft.contractor.kind = said(.company)
        XCTAssertEqual(draft.issues(), [])
    }

    func testWrongValuesAreNamed() {
        var draft = readyDraft()
        draft.contractor.nip = said("1234567890")
        draft.contractor.address = said(InvoiceAddress(street: "A", city: "B", postCode: "31004"))
        draft.lines[0].netUnitPriceMinor = -5
        draft.lines[0].quantityMilli = 0
        draft.paymentDueDate = CalendarDate(iso: "2026-10-01")
        let issues = draft.issues()
        XCTAssertTrue(issues.contains(.invalid(.contractorNip, .nipChecksum)))
        XCTAssertTrue(issues.contains(.invalid(.contractorAddress, .postCodeFormat)))
        XCTAssertTrue(issues.contains(.invalid(.lineUnitPrice(0), .notAPositiveAmount)))
        XCTAssertTrue(issues.contains(.invalid(.lineQuantity(0), .quantityOutOfRange)))
        XCTAssertTrue(issues.contains(.invalid(.paymentDueDate, .dueBeforeIssue)))
        XCTAssertEqual(draft.missingData, [], "wrong values are not 'missing'")
    }

    func testAPrivatePersonNeedsNoNipButAFirmDoes() {
        var draft = readyDraft()
        draft.contractor = InvoiceContractor(kind: said(.privatePerson), name: said("Jan Kowalski"))
        XCTAssertEqual(draft.issues(), [])
        draft.contractor.kind = said(.company)
        XCTAssertTrue(draft.issues().contains(.missing(.contractorNip)))
        XCTAssertTrue(draft.issues().contains(.missing(.contractorAddress)))
    }

    func testAnExemptLineNeedsItsReason() {
        var draft = readyDraft()
        draft.lines[0].vat = said(.exempt)
        XCTAssertTrue(draft.issues().contains(.missing(.vatExemptionReason)))
        draft.vatExemptionReason = "art. 43 ust. 1 pkt 37 ustawy o VAT"
        XCTAssertEqual(draft.issues(), [])
    }

    func testPaymentDueDateIsNeededOnlyWhenPaidLater() {
        var draft = readyDraft()
        draft.paymentDueDate = nil
        XCTAssertTrue(draft.issues().contains(.missing(.paymentDueDate)))
        draft.paymentMethod = said(.cash)
        XCTAssertEqual(draft.issues(), [])
    }

    // MARK: Confirmation is bound to what was shown

    func testConfirmationBindsToTheShownDigest() throws {
        var operation = InvoiceOperation(draft: readyDraft())
        let shown = try XCTUnwrap(operation.digest)
        XCTAssertEqual(shown.count, 64)
        XCTAssertThrowsError(try operation.confirm(shownDigest: "00")) { XCTAssertEqual($0 as? InvoiceOperationError, .stale) }
        XCTAssertEqual(operation.state, .readyForConfirmation)
        try operation.confirm(shownDigest: shown)
        XCTAssertEqual(operation.state, .userConfirmed)
        // Changing anything afterwards is a different invoice: the yes is gone.
        var edited = readyDraft()
        edited.lines[0].netUnitPriceMinor = 50_001
        try operation.update(edited)
        XCTAssertEqual(operation.state, .readyForConfirmation)
        XCTAssertNil(operation.confirmedDigest)
        XCTAssertNotEqual(operation.digest, shown)
        XCTAssertThrowsError(try operation.beginSend())
    }

    func testTheDigestSeesEveryField() throws {
        let base = try XCTUnwrap(InvoiceOperation(draft: readyDraft()).digest)
        func digest(_ change: (inout InvoiceDraft) -> Void) -> String? {
            var d = readyDraft(); change(&d); return InvoiceOperation(draft: d).digest
        }
        XCTAssertEqual(digest { _ in }, base)
        XCTAssertNotEqual(digest { $0.contractor.name = said("Inny") }, base)
        XCTAssertNotEqual(digest { $0.contractor.nip = said("5260250995") }, base)
        XCTAssertNotEqual(digest { $0.lines[0].quantityMilli = 2_001 }, base)
        XCTAssertNotEqual(digest { $0.lines[0].unit = "szt." }, base)
        XCTAssertNotEqual(digest { $0.lines[0].vat = said(.percent(8)) }, base)
        XCTAssertNotEqual(digest { $0.currency = said(.eur) }, base)
        XCTAssertNotEqual(digest { $0.saleDate = CalendarDate(iso: "2026-10-23") }, base)
        XCTAssertNotEqual(digest { $0.paymentMethod = said(.card) }, base)
        XCTAssertNotEqual(digest { $0.paymentDueDate = CalendarDate(iso: "2026-11-08") }, base)
    }

    func testCanonicalTextHasSortedKeysAndEscapes() throws {
        var draft = readyDraft()
        draft.lines[0].name = said("Usługa \"A\"\n")
        let totals = try XCTUnwrap(draft.totals)
        let text = InvoiceOperation.canonicalJSON(draft, totals)
        XCTAssertTrue(text.hasPrefix("{\"buyer\":{\"address\":{\"buildingNumber\":\"3-4\""), text)
        XCTAssertTrue(text.contains("\"name\":\"Usługa \\\"A\\\"\\n\""), text)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(text.utf8)))
    }

    // MARK: Sending: once, saved first, never twice by itself (acceptance tests 9 and 15)

    func testASuccessfulSendIsOnlyDoneWithAReceiptForThisOperation() async throws {
        var operation = try confirmed(readyDraft())
        let provider = FakeInvoiceProvider(.succeed)
        var saved: [InvoiceState] = []
        await InvoiceSender.send(&operation, using: provider) { saved.append($0.state) }
        XCTAssertEqual(saved, [.pendingExternalWrite, .verifiedSucceeded], "saved BEFORE the call, and after")
        XCTAssertEqual(operation.state, .verifiedSucceeded)
        XCTAssertEqual(operation.receipt?.number, "1/10/2026")
        let calls = await provider.createCalls
        XCTAssertEqual(calls, 1)
    }

    func testAReceiptForAnotherOperationIsNotASuccess() async throws {
        var operation = try confirmed(readyDraft())
        await InvoiceSender.send(&operation, using: FakeInvoiceProvider(.answerWithAnotherOperation))
        XCTAssertEqual(operation.state, .unknownOutcome)
        XCTAssertNil(operation.receipt)
    }

    func testARefusalIsADefiniteFailureAndAFreshYesIsNeededToTryAgain() async throws {
        var operation = try confirmed(readyDraft())
        let provider = FakeInvoiceProvider(.reject("Invalid NIP"))
        await InvoiceSender.send(&operation, using: provider)
        XCTAssertEqual(operation.state, .verifiedFailed)
        XCTAssertEqual(operation.note, "Invalid NIP")
        // Sending again without a new confirmation does nothing.
        await InvoiceSender.send(&operation, using: provider)
        let calls = await provider.createCalls
        XCTAssertEqual(calls, 1)
        operation.reopenAfterFailure()
        XCTAssertEqual(operation.state, .readyForConfirmation)
        XCTAssertNil(operation.confirmedDigest)
    }

    /// "Timeout while sending → unknown, then check the status; do not send a second time by itself."
    func testATimeoutIsUnknownAndNothingIsResentByItself() async throws {
        var operation = try confirmed(readyDraft())
        let provider = FakeInvoiceProvider(.createThenLoseAnswer)
        await InvoiceSender.send(&operation, using: provider)
        XCTAssertEqual(operation.state, .unknownOutcome)
        // Whatever is called next, a second create never happens.
        await InvoiceSender.send(&operation, using: provider)
        await InvoiceSender.send(&operation, using: provider)
        var calls = await provider.createCalls
        XCTAssertEqual(calls, 1)
        XCTAssertThrowsError(try operation.beginSend()) { XCTAssertEqual($0 as? InvoiceOperationError, .wrongState(.unknownOutcome)) }
        // The status check finds the invoice that was created: issued, still one create call.
        await InvoiceSender.checkStatus(&operation, using: provider)
        XCTAssertEqual(operation.state, .verifiedSucceeded)
        XCTAssertEqual(operation.receipt?.externalId, "inv-1")
        calls = await provider.createCalls
        XCTAssertEqual(calls, 1)
    }

    func testWhenTheProviderHasNoSuchInvoiceANewYesIsNeeded() async throws {
        var operation = try confirmed(readyDraft())
        let provider = FakeInvoiceProvider(.timeoutBeforeCreate)
        await InvoiceSender.send(&operation, using: provider)
        XCTAssertEqual(operation.state, .unknownOutcome)
        await InvoiceSender.checkStatus(&operation, using: provider)
        XCTAssertEqual(operation.state, .readyForConfirmation, "the provider confirms none exists: back to the card")
        XCTAssertNil(operation.confirmedDigest)
        XCTAssertNil(operation.receipt)
        await InvoiceSender.send(&operation, using: provider)
        let calls = await provider.createCalls
        XCTAssertEqual(calls, 1, "no send without the new tap")
        try operation.confirm(shownDigest: try XCTUnwrap(operation.digest))
        await provider.setScript(.succeed)
        await InvoiceSender.send(&operation, using: provider)
        XCTAssertEqual(operation.state, .verifiedSucceeded)
    }

    func testAStatusCheckThatCannotTellLeavesItUnknown() async throws {
        var operation = try confirmed(readyDraft())
        let provider = FakeInvoiceProvider(.createThenLoseAnswer)
        await InvoiceSender.send(&operation, using: provider)
        await provider.setFindFails(true)
        await InvoiceSender.checkStatus(&operation, using: provider)
        XCTAssertEqual(operation.state, .unknownOutcome)
    }

    func testAnUnconfirmedOperationSendsNothing() async throws {
        var operation = InvoiceOperation(draft: readyDraft())
        let provider = FakeInvoiceProvider(.succeed)
        await InvoiceSender.send(&operation, using: provider)
        XCTAssertEqual(operation.state, .readyForConfirmation)
        let calls = await provider.createCalls
        XCTAssertEqual(calls, 0)
    }

    func testTheUnverifiedInFaktProviderMakesNoRequestAndSaysSo() async throws {
        XCTAssertFalse(InFaktAPI.createVerified)
        var operation = try confirmed(readyDraft())
        await InvoiceSender.send(&operation, using: UnverifiedInFaktProvider())
        XCTAssertEqual(operation.state, .verifiedFailed)
        XCTAssertTrue(operation.note?.contains("nothing was sent") == true)
        XCTAssertEqual(InFaktAPI.apiKeyHeader, "X-inFakt-ApiKey")
        XCTAssertEqual(InFaktAPI.productionBase, "https://api.infakt.pl/api/v3")
    }

    func testAnOperationSurvivesBeingSavedAndRead() throws {
        let operation = try confirmed(readyDraft())
        let data = try JSONEncoder().encode(operation)
        let back = try JSONDecoder().decode(InvoiceOperation.self, from: data)
        XCTAssertEqual(back, operation)
        XCTAssertEqual(back.digest, operation.digest)
    }
}
