import XCTest
@testable import DoddyCore

/// inFakt's wire format and the KSeF send (ADR-668). The answers below are inFakt's own examples
/// from the Postman collection behind docs.infakt.pl (read 30 Oct 2026); no real answer has been seen.
final class InFaktWireTests: XCTestCase {
    private func said<T: Equatable & Sendable & Codable>(_ value: T) -> Sourced<T> { Sourced(value, source: .saidByUser) }

    private func readyDraft() -> InvoiceDraft {
        InvoiceDraft(
            contractor: InvoiceContractor(
                kind: said(.company), name: said("ABC sp. z o.o."), nip: said("106-000-60-24"),
                address: said(InvoiceAddress(street: "Lipowa", buildingNumber: "3", flatNumber: "4", city: "Kraków", postCode: "31-004"))),
            lines: [
                InvoiceLine(name: said("Konsultacje"), quantityMilli: 2_500, unit: "godz.", netUnitPriceMinor: 50_000, vat: said(.percent(23))),
                InvoiceLine(name: said("Dojazd"), quantityMilli: 1_000, netUnitPriceMinor: 10_000, vat: said(.percent(23))),
            ],
            currency: said(.pln), issueDate: CalendarDate(iso: "2026-10-30"),
            paymentMethod: said(.transfer), paymentDueDate: CalendarDate(iso: "2026-11-13"))
    }

    private func confirmed(_ draft: InvoiceDraft) throws -> (InvoiceOperation, ConfirmedInvoice) {
        var operation = InvoiceOperation(draft: draft)
        try operation.confirm(shownDigest: try XCTUnwrap(operation.digest))
        let invoice = try operation.beginSend()
        return (operation, invoice)
    }

    // MARK: Create

    func testTheCreateBodyIsGroszeTheDocumentedFieldsAndNoKsef() throws {
        let (_, invoice) = try confirmed(readyDraft())
        let body = try InFaktWire.createBody(invoice).get()
        XCTAssertEqual(body, """
            {"invoice":{"client_business_activity_kind":"other_business","client_city":"Kraków","client_company_name":"ABC sp. z o.o.",\
            "client_country":"PL","client_flat_number":"4","client_post_code":"31-004","client_street":"Lipowa","client_street_number":"3",\
            "client_tax_code":"1060006024","currency":"PLN","invoice_date":"2026-10-30","payment_date":"2026-11-13","payment_method":"transfer",\
            "sale_date":"2026-10-30","services":[{"name":"Konsultacje","quantity":2.5,"tax_symbol":23,"unit":"godz.","unit_net_price":50000},\
            {"name":"Dojazd","quantity":1,"tax_symbol":23,"unit_net_price":10000}]},"send_to_ksef":false}
            """)
        let parsed = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(parsed["send_to_ksef"] as? Bool, false, "KSeF is its own tap")
    }

    func testSplitPaymentAndAnExemptionGoInTheBody() throws {
        var draft = readyDraft()
        draft.lines = [InvoiceLine(name: said("Korepetycje"), quantityMilli: 1_000, netUnitPriceMinor: 2_000_000, vat: said(.exempt))]
        draft.vatExemptionReason = "art. 43 ust. 1 pkt 27"
        draft.splitPayment = said(true)
        let (_, invoice) = try confirmed(draft)
        XCTAssertEqual(InFaktWire.createBody(invoice), .failure(.exemptionIdNeeded), "a free-text reason is not inFakt's id")
        let body = try InFaktWire.createBody(invoice, exemptionId: 4).get()
        XCTAssertTrue(body.contains(#""split_payment":true,"split_payment_type":"required""#))
        XCTAssertTrue(body.contains(#""vat_exemption_reason":4"#))
        XCTAssertTrue(body.contains(#""tax_symbol":"zw""#))
    }

    func testWhatIsNotConfirmedForInFaktIsRefusedNotGuessed() throws {
        var draft = readyDraft()
        draft.paymentMethod = said(.cod)
        XCTAssertEqual(InFaktWire.createBody(try confirmed(draft).1), .failure(.paymentMethod(.cod)))
        draft = readyDraft()
        draft.contractor.kind = said(.privatePerson)
        draft.contractor.nip = nil
        XCTAssertEqual(InFaktWire.createBody(try confirmed(draft).1), .failure(.privatePerson), "inFakt wants a first and a last name")
    }

    // MARK: Answers (inFakt's own examples)

    func testTheCreateAnswersAreRead() {
        let accepted = Data("""
            {"timestamps":{"task_created_at":"2023-03-13 10:21:25 +0100"},"invoice_task_reference_number":"34263ae5-4365-4ba1-a38d-c7952c5a5715",
             "processing_code":100,"processing_description":"Zlecenie przyjęte"}
            """.utf8)
        XCTAssertEqual(InFaktWire.createAccepted(accepted), "34263ae5-4365-4ba1-a38d-c7952c5a5715")
        XCTAssertNil(InFaktWire.createAccepted(Data(#"{"processing_code":100}"#.utf8)))

        let reference = "34263ae5-4365-4ba1-a38d-c7952c5a5715"
        let created = Data("""
            {"invoice_task_reference_number":"\(reference)","processing_code":201,"processing_description":"Faktura stworzona",
             "invoice_uuid":"1ba43eaf-4b29-41e5-a629-48e345e4c675"}
            """.utf8)
        XCTAssertEqual(InFaktWire.createStatus(created, reference: reference), .created(invoiceUUID: "1ba43eaf-4b29-41e5-a629-48e345e4c675"))
        XCTAssertEqual(InFaktWire.createStatus(created, reference: "another-task"), .unreadable, "an answer about another task is not ours")
        let failed = Data("""
            {"invoice_task_reference_number":"\(reference)","processing_code":422,"processing_description":"Nie udało się stworzyć faktury",
             "invoice_errors":{"payment_method":["Proszę wybrać odpowiedni sposób płatności."]}}
            """.utf8)
        XCTAssertEqual(InFaktWire.createStatus(failed, reference: reference),
                       .rejected(["payment_method: Proszę wybrać odpowiedni sposób płatności."]))
        let busy = Data(#"{"invoice_task_reference_number":"\#(reference)","processing_code":140}"#.utf8)
        XCTAssertEqual(InFaktWire.createStatus(busy, reference: reference), .processing)
        XCTAssertEqual(InFaktWire.createStatus(Data("<html>".utf8), reference: reference), .unreadable)
    }

    func testAnInvoiceAndItsKsefAnswerAreRead() throws {
        let invoice = try XCTUnwrap(InFaktWire.invoice(Data("""
            {"id":2310824,"uuid":"282ebe68-80aa-495e-aee4-66c5c0faa001","number":"16/03/2023","net_price":6623,"tax_price":1523,
             "gross_price":8146,"status":"draft"}
            """.utf8)))
        XCTAssertEqual(invoice.number, "16/03/2023")
        XCTAssertEqual(invoice.grossMinor, 8_146)
        XCTAssertNil(invoice.ksef)

        let uuid = "0be870f9-aa52-4d0f-a9ff-994e374ecff0"
        func answer(_ status: String, _ number: String?, _ text: String) -> Data {
            Data("""
                {"request_uuid":"d34279dc-b1a1-4852-b475-eb36c335992f","invoice_uuid":"\(uuid)","invoice_kind":"vat",
                 "ksef_number":\(number.map { "\"\($0)\"" } ?? "null"),"status":"\(status)","status_description":"\(text)"}
                """.utf8)
        }
        XCTAssertEqual(InFaktWire.ksefAnswer(answer("sent", nil, "Faktura została wysłana do przetworzenia w KSeF."), invoiceUUID: uuid), .pending)
        XCTAssertEqual(InFaktWire.ksefAnswer(answer("success", "7343521162-20231004-47A70D8BD670-57", "Faktura została przetworzona."), invoiceUUID: uuid),
                       .accepted(KsefNumber("7343521162-20231004-47A70D8BD670-57")!))
        XCTAssertEqual(InFaktWire.ksefAnswer(answer("error", nil, "21416:Wersja dokumentu niezgodna"), invoiceUUID: uuid),
                       .rejected("21416:Wersja dokumentu niezgodna"))
        XCTAssertEqual(InFaktWire.ksefAnswer(answer("success", "7343521162-20231004-47A70D8BD670-57", "x"), invoiceUUID: "someone-else"),
                       .unknown, "another invoice's success is not this one's")
    }

    // MARK: Exemptions

    func testTheExemptionListIsReadAndASaidArticleFindsItsEntry() throws {
        let page = try XCTUnwrap(InFaktWire.vatExemptions(Data("""
            {"metainfo":{"count":3,"total_count":112,"next":"https://api.infakt.pl/api/v3/vat_exemptions.json?offset=10&limit=10"},
             "entities":[
              {"id":1,"description":"zwolnienie podmiotowe","legal_basis_rule":"art. 113 ust. 1 i 9","legal_basis_source":"Ustawa o podatku od towarów i usług"},
              {"id":3,"description":"towary wykorzystywane w działalności zwolnionej","legal_basis_rule":"art. 43. ust. 1 pkt 2","legal_basis_source":"Ustawa"},
              {"id":4,"description":"korepetycje udzielane przez nauczycieli","legal_basis_rule":"art. 43 ust. 1 pkt 27","legal_basis_source":"Ustawa"}]}
            """.utf8)))
        XCTAssertEqual(page.entries.map(\.id), [1, 3, 4])
        XCTAssertTrue(page.hasNext)
        XCTAssertEqual(InFaktWire.matchExemption("art. 113 ust. 1 ustawy o VAT", in: page.entries)?.id, 1)
        XCTAssertEqual(InFaktWire.matchExemption("Art. 43 ust. 1 pkt 27", in: page.entries)?.id, 4)
        XCTAssertNil(InFaktWire.matchExemption("art. 43 ust. 1", in: page.entries), "two entries fit: the person picks")
        XCTAssertNil(InFaktWire.matchExemption("jestem zwolniony", in: page.entries))
    }

    // MARK: KSeF send

    func testKsefIsItsOwnYesSentOnceAndNeverResentWhenUnknown() async throws {
        var (operation, _) = try confirmed(readyDraft())
        operation.record(receipt: InvoiceReceipt(operationId: operation.operationId, externalId: "inv-1", number: "1/10/2026", verifiedAt: Date()))
        let provider = FakeKsefProvider([.failure(.outcomeUnknown), .success(.pending)])

        await KsefSender.send(&operation, using: provider)
        var calls = await provider.sendCalls
        XCTAssertEqual(calls, 0, "no send without its own yes")
        XCTAssertThrowsError(try operation.confirmKsefSend(shownExternalId: "inv-2"), "a yes for another invoice")

        try operation.confirmKsefSend(shownExternalId: "inv-1")
        var saved: [KsefStatus] = []
        await KsefSender.send(&operation, using: provider) { saved.append($0.ksef) }
        XCTAssertEqual(saved.first, .pending, "saved as on its way before the request")
        XCTAssertEqual(operation.ksef, .unknown)
        XCTAssertFalse(operation.mayAskToSendToKsef, "unknown is never offered again")
        await KsefSender.send(&operation, using: provider)
        calls = await provider.sendCalls
        XCTAssertEqual(calls, 1, "the yes was used up; unknown is not resent")

        await provider.setStatus(.success(.accepted(KsefNumber("5265877635-20251030-0100001AF629-AF")!)))
        await KsefSender.checkStatus(&operation, using: provider)
        XCTAssertTrue(operation.ksef.isInKsef)
        XCTAssertFalse(operation.mayAskToSendToKsef)
    }

    func testARefusedSendNeedsANewYesAndNothingLeftThePhoneGoesBack() async throws {
        var (operation, _) = try confirmed(readyDraft())
        operation.record(receipt: InvoiceReceipt(operationId: operation.operationId, externalId: "inv-1", number: nil, verifiedAt: Date()))
        let provider = FakeKsefProvider([.success(.rejected("Faktura nie może zostać wysłana do KSeF.")), .failure(.notVerified)])
        try operation.confirmKsefSend(shownExternalId: "inv-1")
        await KsefSender.send(&operation, using: provider)
        XCTAssertEqual(operation.ksef, .rejected("Faktura nie może zostać wysłana do KSeF."))
        XCTAssertTrue(operation.mayAskToSendToKsef, "a refused file isn't an invoice; it may be sent again")
        XCTAssertFalse(operation.ksefSendConfirmed, "but only after a new yes")

        try operation.confirmKsefSend(shownExternalId: "inv-1")
        await KsefSender.send(&operation, using: provider)
        XCTAssertEqual(operation.ksef, .notSent, "nothing left the iPhone")
        XCTAssertTrue(UnverifiedInFaktProvider() is any KsefProvider)
    }

    func testKsefIsOfferedOnlyWhenInFaktsSumsAreTheConfirmedOnes() throws {
        var (operation, _) = try confirmed(readyDraft())
        operation.record(receipt: InvoiceReceipt(operationId: operation.operationId, externalId: "inv-1", number: nil, verifiedAt: Date()))
        let totals = try XCTUnwrap(operation.draft.totals)
        func inFakt(_ uuid: String, gross: Int) -> InFaktWire.Invoice {
            InFaktWire.Invoice(uuid: uuid, number: nil, netMinor: totals.netMinor, taxMinor: gross - totals.netMinor, grossMinor: gross, ksef: nil)
        }
        XCTAssertNil(KsefSendGate.check(operation, against: inFakt("inv-1", gross: totals.grossMinor)))
        XCTAssertEqual(KsefSendGate.check(operation, against: inFakt("inv-1", gross: totals.grossMinor + 1)),
                       .totalsDiffer(confirmedGrossMinor: totals.grossMinor, inFaktGrossMinor: totals.grossMinor + 1))
        XCTAssertEqual(KsefSendGate.check(operation, against: inFakt("inv-9", gross: totals.grossMinor)), .otherInvoice)

        let card = InvoiceCard(operation, polish: true)
        XCTAssertFalse(card.canSendToKsef, "not offered while createVerified is false")
        XCTAssertEqual(card.ksefWarning?.hasPrefix("Wysłania do KSeF nie da się cofnąć"), true)
    }
}

/// A scripted inFakt for KSeF: each send takes the next answer.
actor FakeKsefProvider: KsefProvider {
    private var answers: [Result<KsefStatus, InvoiceProviderError>]
    private var status: Result<KsefStatus, InvoiceProviderError> = .failure(.outcomeUnknown)
    private(set) var sendCalls = 0

    init(_ answers: [Result<KsefStatus, InvoiceProviderError>]) { self.answers = answers }

    func setStatus(_ value: Result<KsefStatus, InvoiceProviderError>) { status = value }

    func sendToKsef(invoiceId: String) async throws -> KsefStatus {
        sendCalls += 1
        return try (answers.isEmpty ? .failure(.outcomeUnknown) : answers.removeFirst()).get()
    }

    func ksefStatus(invoiceId: String) async throws -> KsefStatus { try status.get() }
}

/// The draft kept between conversations (ADR-668), on real files.
final class InvoiceDraftFileTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("invoice-draft-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func session(heard: [String] = ["ABC NIP 1060006024, 23 procent"]) -> InvoiceVoiceSession {
        var session = InvoiceVoiceSession()
        let update: InvoiceVoiceUpdate = {
            guard case .draftInvoice(let u) = VoiceToolRequest.parse(
                name: VoiceToolName.draftInvoice,
                parametersJSON: Data(#"{"buyer_kind":"company","buyer_name":"ABC","buyer_nip":"1060006024","item":"Projekt","quantity":1,"net_price":500,"vat_rate":"23"}"#.utf8))
            else { return InvoiceVoiceUpdate() }
            return u
        }()
        _ = session.apply(update, userWords: heard, today: CalendarDate(iso: "2026-10-30")!)
        return session
    }

    func testADraftIsKeptReadBackAndRemoved() throws {
        let file = InvoiceDraftFile(url: directory.appendingPathComponent("invoice-draft.json"))
        XCTAssertEqual(file.load(), .none)
        let draft = session()
        XCTAssertTrue(file.save(draft))
        XCTAssertEqual(file.load(), .draft(draft), "the same draft, provenance and operation id included")
        guard case .draft(let back) = file.load() else { return XCTFail() }
        XCTAssertEqual(back.operation?.operationId, draft.operation?.operationId)
        XCTAssertEqual(back.operation?.draft.contractor.nip?.source, .saidByUser)
        XCTAssertTrue(file.remove())
        XCTAssertEqual(file.load(), .none)
        XCTAssertTrue(file.save(InvoiceVoiceSession()), "an empty draft is no file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }

    func testAnUnreadableFileIsSetAsideNotWrittenOver() throws {
        let file = InvoiceDraftFile(url: directory.appendingPathComponent("invoice-draft.json"))
        try Data("not json".utf8).write(to: file.url)
        XCTAssertEqual(file.load(), .setAside)
        XCTAssertEqual(try Data(contentsOf: file.asideURL), Data("not json".utf8))
        XCTAssertEqual(file.load(), .none)
        XCTAssertTrue(file.remove(), "Delete all takes the set-aside copy too")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.asideURL.path))
    }

    func testASaveThatCantBeWrittenSaysSo() {
        let file = InvoiceDraftFile(url: directory.appendingPathComponent("missing-folder/invoice-draft.json"))
        XCTAssertFalse(file.save(session()))
    }

    func testADefaultIssueDateMovesToTheNewDaySaidOneStays() throws {
        var kept = session()
        XCTAssertEqual(kept.operation?.draft.issueDate, CalendarDate(iso: "2026-10-30"))
        XCTAssertTrue(kept.refreshDefaults(today: CalendarDate(iso: "2026-11-02")!))
        XCTAssertEqual(kept.operation?.draft.issueDate, CalendarDate(iso: "2026-11-02"), "never a back-dated invoice by accident")

        var said = InvoiceVoiceSession()
        guard case .draftInvoice(let update) = VoiceToolRequest.parse(
            name: VoiceToolName.draftInvoice, parametersJSON: Data(#"{"issue_date":"2026-10-29","item":"x"}"#.utf8)) else { return XCTFail() }
        _ = said.apply(update, userWords: [], today: CalendarDate(iso: "2026-10-30")!)
        XCTAssertFalse(said.refreshDefaults(today: CalendarDate(iso: "2026-11-02")!))
        XCTAssertEqual(said.operation?.draft.issueDate, CalendarDate(iso: "2026-10-29"))
    }

    func testTheReplySaysWhetherTheDraftIsKept() throws {
        let operation = try XCTUnwrap(session().operation)
        XCTAssertTrue(VoiceToolReply.invoiceDraft(operation, notes: [], kept: true).contains("kept on this iPhone until the user closes the card"))
        XCTAssertTrue(VoiceToolReply.invoiceDraft(operation, notes: [], kept: false).contains("couldn't be kept on this iPhone"))
    }
}
