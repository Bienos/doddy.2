import XCTest
@testable import DoddyCore

/// The invoice card (ADR-640): the one look at the exact invoice before a yes. Its wording and sums
/// come from code, it names every gap, and it says "issued" only with a receipt.
final class InvoiceCardTests: XCTestCase {
    private func said<T: Equatable & Sendable & Codable>(_ value: T) -> Sourced<T> { Sourced(value, source: .saidByUser) }
    private func proposed<T: Equatable & Sendable & Codable>(_ value: T) -> Sourced<T> { Sourced(value, source: .proposedByModel) }

    private func readyDraft() -> InvoiceDraft {
        InvoiceDraft(
            contractor: InvoiceContractor(
                kind: said(.company), name: said("Przykładowa Firma Sp. z o.o."), nip: said("1234563218"),
                address: said(InvoiceAddress(street: "Lipowa", buildingNumber: "3", flatNumber: "4", city: "Kraków", postCode: "31-004"))),
            lines: [InvoiceLine(name: said("Konsultacje"), quantityMilli: 2_000, unit: "godz.", netUnitPriceMinor: 50_000, vat: said(.percent(23)))],
            currency: said(.pln), issueDate: CalendarDate(iso: "2026-10-24"), saleDate: CalendarDate(iso: "2026-10-23"),
            paymentMethod: said(.transfer), paymentDueDate: CalendarDate(iso: "2026-11-07"))
    }

    func testACompleteInvoiceShowsTheExactSumsFromCode() throws {
        let card = InvoiceCard(InvoiceOperation(draft: readyDraft()), polish: true)
        XCTAssertEqual(card.problems, [])
        XCTAssertEqual(card.stateLine, "Gotowa do potwierdzenia")
        XCTAssertNotNil(card.digest)
        XCTAssertEqual(card.buyer.map(\.value), ["firma", "Przykładowa Firma Sp. z o.o.", "123-456-32-18", "Lipowa 3/4, 31-004 Kraków"])
        XCTAssertEqual(card.lines.count, 1)
        XCTAssertEqual(card.lines[0].detail, "2 godz. × 500,00 PLN netto · VAT 23%")
        XCTAssertEqual(card.lines[0].net, "1\u{00A0}000,00 PLN")
        XCTAssertEqual(card.totals.map(\.label), ["Netto 23%", "VAT 23%", "Razem netto", "Razem VAT", "Razem brutto"])
        XCTAssertEqual(card.totals.map(\.value), ["1\u{00A0}000,00 PLN", "230,00 PLN", "1\u{00A0}000,00 PLN", "230,00 PLN", "1\u{00A0}230,00 PLN"])
        XCTAssertEqual(card.facts.map(\.value), ["PLN", "24.10.2026", "23.10.2026", "przelew", "07.11.2026"])
    }

    func testConfirmIsNotOfferedWhileSendingIsNotVerified() throws {
        XCTAssertFalse(InFaktAPI.createVerified)
        let card = InvoiceCard(InvoiceOperation(draft: readyDraft()), polish: true)
        XCTAssertFalse(card.canConfirm, "a complete card still can't be confirmed into a send that can't happen")
        XCTAssertTrue(card.sendingNote?.contains("nie jest jeszcze włączona") ?? false)
        XCTAssertTrue(card.sendingNote?.contains("Nic nie zostało wystawione") ?? false)
        let english = InvoiceCard(InvoiceOperation(draft: readyDraft()), polish: false)
        XCTAssertTrue(english.sendingNote?.contains("Nothing was issued") ?? false)
    }

    func testEveryGapIsNamedAndAModelSuggestionIsNotTakenForSaid() throws {
        var draft = readyDraft()
        draft.lines[0].vat = proposed(.percent(23))
        draft.contractor.nip = proposed("1234563218")
        draft.paymentDueDate = nil
        let card = InvoiceCard(InvoiceOperation(draft: draft), polish: true)
        XCTAssertEqual(card.problems, [
            "Do potwierdzenia przez Ciebie: NIP nabywcy. Zaproponował to model, nie Ty.",
            "Do potwierdzenia przez Ciebie: stawka VAT w pozycji 1. Zaproponował to model, nie Ty.",
            "Brakuje: termin płatności.",
        ])
        XCTAssertEqual(card.stateLine, "Brakuje danych")
        XCTAssertNil(card.digest, "no yes can be bound to an incomplete invoice")
        XCTAssertFalse(card.canConfirm)
        XCTAssertTrue(card.buyer.first { $0.label == "NIP" }?.proposed ?? false, "shown, and marked as a suggestion")
        XCTAssertTrue(card.lines[0].proposed)
        XCTAssertEqual(card.totals, [], "no sums while a rate is only suggested")
        XCTAssertEqual(card.lines[0].net, "")
    }

    func testAWrongNipIsToFixAndNeverShownAsValid() throws {
        var draft = readyDraft()
        draft.contractor.nip = said("1234563219")
        let card = InvoiceCard(InvoiceOperation(draft: draft), polish: true)
        XCTAssertEqual(card.problems, ["Do poprawy: NIP nabywcy: numer NIP ma błędną cyfrę kontrolną."])
        XCTAssertEqual(card.buyer.first { $0.label == "NIP" }?.value, "1234563219", "shown as given, not reformatted as if it were valid")
    }

    func testEnglishCard() throws {
        var draft = readyDraft()
        draft.saleDate = nil
        let card = InvoiceCard(InvoiceOperation(draft: draft), polish: false)
        XCTAssertEqual(card.problems, ["Missing: sale date."])
        XCTAssertEqual(card.lines[0].detail, "2 godz. × 500.00 PLN net · VAT 23%")
        XCTAssertEqual(card.totals.last?.label, "Total gross")
        XCTAssertEqual(card.totals.last?.value, "1,230.00 PLN")
        XCTAssertEqual(card.facts.map(\.value).prefix(3), ["PLN", "2026-10-24", "bank transfer"])
    }

    func testQuantitiesKeepTheirFractions() {
        XCTAssertEqual(InvoiceCard.quantity(1_000, polish: true), "1")
        XCTAssertEqual(InvoiceCard.quantity(2_500, polish: true), "2,5")
        XCTAssertEqual(InvoiceCard.quantity(2_250, polish: true), "2,25")
        XCTAssertEqual(InvoiceCard.quantity(2_001, polish: true), "2,001")
        XCTAssertEqual(InvoiceCard.quantity(500, polish: false), "0.5")
    }

    func testExemptAndNotSubjectGroupsKeepTheirSymbols() throws {
        var draft = readyDraft()
        draft.lines[0].vat = said(.exempt)
        draft.vatExemptionReason = "art. 43 ust. 1 pkt 37 ustawy o VAT"
        let card = InvoiceCard(InvoiceOperation(draft: draft), polish: true)
        XCTAssertEqual(card.problems, [])
        XCTAssertEqual(card.lines[0].detail, "2 godz. × 500,00 PLN netto · VAT zw")
        XCTAssertEqual(card.totals.map(\.label).prefix(2), ["Netto zw", "VAT zw"])
        XCTAssertTrue(card.facts.contains { $0.label == "Podstawa zwolnienia z VAT" })
    }

    // MARK: "Issued" only with a receipt

    private func sent(_ draft: InvoiceDraft) throws -> InvoiceOperation {
        var operation = InvoiceOperation(draft: draft)
        try operation.confirm(shownDigest: try XCTUnwrap(operation.digest))
        _ = try operation.beginSend()
        return operation
    }

    func testStateLineSaysIssuedOnlyWithAReceiptThatNamesTheOperation() throws {
        var operation = try sent(readyDraft())
        XCTAssertEqual(InvoiceCard(operation, polish: true).stateLine, "Wysyłanie do inFakt, czekam na odpowiedź")

        operation.recordUnknown()
        let unknown = InvoiceCard(operation, polish: true).stateLine
        XCTAssertTrue(unknown.hasPrefix("Nie wiadomo, czy faktura powstała"))
        XCTAssertFalse(unknown.contains("Wystawiona"))

        operation.record(receipt: InvoiceReceipt(operationId: UUID(), externalId: "someone-else", number: "9/9", verifiedAt: Date()))
        XCTAssertFalse(InvoiceCard(operation, polish: true).stateLine.contains("Wystawiona"), "another operation's receipt is not ours")

        operation.record(receipt: InvoiceReceipt(operationId: operation.operationId, externalId: "inv-1", number: "FV 1/10/2026", verifiedAt: Date()))
        XCTAssertEqual(InvoiceCard(operation, polish: true).stateLine, "Wystawiona w inFakt FV 1/10/2026")
        XCTAssertEqual(InvoiceCard(operation, polish: false).stateLine, "Issued in inFakt FV 1/10/2026")
    }

    func testAFailureSaysNotIssuedAndGivesTheReason() throws {
        var operation = try sent(readyDraft())
        operation.recordFailure("inFakt odrzucił fakturę: błędny NIP")
        XCTAssertEqual(InvoiceCard(operation, polish: true).stateLine, "Nie wystawiona: inFakt odrzucił fakturę: błędny NIP")
    }

    func testTheDigestOnTheCardIsTheOneAYesIsBoundTo() throws {
        var operation = InvoiceOperation(draft: readyDraft())
        let shown = try XCTUnwrap(InvoiceCard(operation, polish: true).digest)
        try operation.confirm(shownDigest: shown)
        XCTAssertEqual(operation.state, .userConfirmed)
    }
}
