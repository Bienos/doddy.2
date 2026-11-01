import XCTest
@testable import DoddyCore

/// A buyer's name and address from the registers by NIP (ADR-671). The VAT register answer is a real
/// one (NIP 5260250995, 1 Nov 2026, bank accounts cut); the CEIDG one is the official documentation's.
final class CompanyRegisterTests: XCTestCase {
    private let day = CalendarDate(iso: "2026-11-01")!
    private let orange = Nip("5260250995")!

    private let vatFound = Data("""
        {"result":{"subject":{"name":"ORANGE POLSKA SPÓŁKA AKCYJNA","nip":"5260250995","statusVat":"Czynny","regon":"012100784",
         "pesel":null,"krs":"0000010681","residenceAddress":"ALEJE JEROZOLIMSKIE 160, 02-326 WARSZAWA","workingAddress":null,
         "representatives":[],"authorizedClerks":[],"partners":[],"registrationLegalDate":"1996-01-01",
         "accountNumbers":["58103015080000000503131332"],"hasVirtualAccounts":true},
         "requestDateTime":"01-11-2026 15:39:49","requestId":"jPEOY-995l7fd"}}
        """.utf8)

    // MARK: The VAT register

    func testTheVatRegisterAddressIsBuiltFromACheckedNipOnly() {
        XCTAssertEqual(VatRegister.url(for: orange, on: day).absoluteString,
                       "https://wl-api.mf.gov.pl/api/search/nip/5260250995?date=2026-11-01")
    }

    func testAFoundTaxpayerGivesNameAddressAndStatus() throws {
        guard case .found(let company) = VatRegister.read(vatFound, statusCode: 200, nip: orange, on: day) else {
            return XCTFail("should be found")
        }
        XCTAssertEqual(company.name, "ORANGE POLSKA SPÓŁKA AKCYJNA")
        XCTAssertEqual(company.address, InvoiceAddress(street: "ALEJE JEROZOLIMSKIE", buildingNumber: "160", city: "WARSZAWA", postCode: "02-326"))
        XCTAssertEqual(company.status, "Czynny")
        XCTAssertTrue(company.isActive)
        XCTAssertEqual(company.requestId, "jPEOY-995l7fd", "the register's proof of the check is kept")
        XCTAssertEqual(company.source, .vatRegister)
    }

    func testNotFoundInvalidAndUnreadableAreToldApart() {
        let none = Data(#"{"result":{"subject":null,"requestDateTime":"01-11-2026 15:40:00","requestId":"abc"}}"#.utf8)
        XCTAssertEqual(VatRegister.read(none, statusCode: 200, nip: orange, on: day), .notFound)
        let invalid = Data(#"{"message":"Nieprawidłowy NIP.","code":"WL-115"}"#.utf8)
        XCTAssertEqual(VatRegister.read(invalid, statusCode: 400, nip: orange, on: day), .invalidNip)
        // The register's bot check answers 200 with a web page (seen on 1 Nov 2026): not "not found".
        let botCheck = Data(#"<html style="height:100%"><head><META NAME="ROBOTS" CONTENT="NOINDEX, NOFOLLOW"></head></html>"#.utf8)
        XCTAssertEqual(VatRegister.read(botCheck, statusCode: 200, nip: orange, on: day), .couldNotCheck)
        XCTAssertEqual(VatRegister.read(vatFound, statusCode: 429, nip: orange, on: day), .couldNotCheck)
        XCTAssertEqual(VatRegister.read(Data(#"{"result":{}}"#.utf8), statusCode: 200, nip: orange, on: day), .couldNotCheck)
        XCTAssertEqual(VatRegister.read(vatFound, statusCode: 200, nip: Nip("1060006024")!, on: day), .couldNotCheck,
                       "an answer about another NIP is never used")
    }

    func testOneLineAddressesAreSplitOrRefused() {
        XCTAssertEqual(AddressLine.parse("UL. LIPOWA 3/4, 31-004 KRAKÓW"),
                       InvoiceAddress(street: "UL. LIPOWA", buildingNumber: "3", flatNumber: "4", city: "KRAKÓW", postCode: "31-004"))
        XCTAssertEqual(AddressLine.parse("ALEJA JANA PAWŁA II 12A LOK. 5, 00-001 WARSZAWA"),
                       InvoiceAddress(street: "ALEJA JANA PAWŁA II", buildingNumber: "12A", flatNumber: "5", city: "WARSZAWA", postCode: "00-001"))
        XCTAssertEqual(AddressLine.parse("WĘGRZCE 15, 32-086 WĘGRZCE"),
                       InvoiceAddress(street: "WĘGRZCE", buildingNumber: "15", city: "WĘGRZCE", postCode: "32-086"))
        XCTAssertEqual(AddressLine.parse("UL. 3 MAJA 7, 30-062 KRAKÓW")?.street, "UL. 3 MAJA", "a number inside a street's name stays")
        XCTAssertEqual(AddressLine.parse("UL. 3 MAJA 7, 30-062 KRAKÓW")?.buildingNumber, "7")
        XCTAssertEqual(AddressLine.parse("NOWA WIEŚ, 05-500 PIASECZNO")?.street, "NOWA WIEŚ", "no number: the whole place is the street line")
        XCTAssertNil(AddressLine.parse("LIPOWA 3 KRAKÓW"), "no postcode: not used")
        XCTAssertNil(AddressLine.parse("LIPOWA 3, KRAKÓW"))
    }

    // MARK: CEIDG through Doddy's server

    private let ceidgEntry = Data("""
        {"firma":[{"id":"31F87519-9395-4FCF-8E19-6D5C0522FA7A","nazwa":"Adam IntegracjaMGMF - Zmiana",
          "adresDzialalnosci":{"ulica":"ul. Zwierzyniecka","budynek":"1","miasto":"Białystok","kraj":"PL","kod":"15-333"},
          "wlasciciel":{"imie":"Adam","nazwisko":"IntegracjaMGMF - Zmiana","nip":"2367852376","regon":"29883786011481"},
          "dataRozpoczecia":"2014-07-28","status":"AKTYWNY"}]}
        """.utf8)

    func testACeidgEntryGivesItsStructuredAddress() throws {
        let nip = try XCTUnwrap(Nip("2367852376"))
        guard case .found(let company) = CeidgRegister.read(ceidgEntry, statusCode: 200, nip: nip, on: day) else { return XCTFail() }
        XCTAssertEqual(company.name, "Adam IntegracjaMGMF - Zmiana")
        XCTAssertEqual(company.address, InvoiceAddress(street: "ul. Zwierzyniecka", buildingNumber: "1", city: "Białystok", postCode: "15-333"))
        XCTAssertEqual(company.source, .ceidg)
        XCTAssertTrue(company.isActive)

        XCTAssertEqual(CeidgRegister.read(Data(), statusCode: 404, nip: nip, on: day), .notFound)
        XCTAssertEqual(CeidgRegister.read(Data(#"{"error":"registry_disabled"}"#.utf8), statusCode: 503, nip: nip, on: day), .unavailable)
        XCTAssertEqual(CeidgRegister.read(ceidgEntry, statusCode: 502, nip: nip, on: day), .couldNotCheck)
        XCTAssertEqual(CeidgRegister.read(ceidgEntry, statusCode: 200, nip: orange, on: day), .couldNotCheck, "another owner's entry")
    }

    func testAnActiveCeidgEntryIsPreferredOverARemovedOne() throws {
        let nip = try XCTUnwrap(Nip("2367852376"))
        let two = Data("""
            {"firma":[
              {"nazwa":"Stara firma","adresDzialalnosci":{"ulica":"Polna","budynek":"1","miasto":"Gdańsk","kod":"80-001"},
               "wlasciciel":{"nip":"2367852376"},"status":"WYKRESLONY"},
              {"nazwa":"Nowa firma","adresDzialalnosci":{"miasto":"Węgrzce","kod":"32-086","budynek":"15"},
               "wlasciciel":{"nip":"2367852376"},"status":"AKTYWNY"}]}
            """.utf8)
        guard case .found(let company) = CeidgRegister.read(two, statusCode: 200, nip: nip, on: day) else { return XCTFail() }
        XCTAssertEqual(company.name, "Nowa firma")
        XCTAssertEqual(company.address.street, "Węgrzce", "a village without streets: its name stands for the street")
    }

    func testTheTwoRegistersAnswerAsOne() {
        let entry = RegisteredCompany(nip: "2367852376", name: "Adam", address: InvoiceAddress(street: "A", city: "B", postCode: "15-333"),
                                      addressLine: nil, status: "AKTYWNY", source: .ceidg, checkedOn: day, requestId: nil)
        XCTAssertEqual(CompanyLookup.combined(vat: .notFound, ceidg: .found(entry)), .found(entry), "a sole trader outside VAT")
        XCTAssertEqual(CompanyLookup.combined(vat: .notFound, ceidg: .notFound), .notFound)
        XCTAssertEqual(CompanyLookup.combined(vat: .notFound, ceidg: .unavailable), .notFound, "the VAT register said so itself")
        XCTAssertEqual(CompanyLookup.combined(vat: .couldNotCheck, ceidg: .notFound), .couldNotCheck, "could still be a firm")
        XCTAssertEqual(CompanyLookup.combined(vat: .couldNotCheck, ceidg: nil), .couldNotCheck)
        XCTAssertEqual(CompanyLookup.combined(vat: .invalidNip, ceidg: .found(entry)), .invalidNip, "CEIDG isn't asked then")
        XCTAssertFalse(CompanyLookup.invalidNip.asksCeidgToo)
    }

    func testWhatLeavesThisIPhoneNamesBothRegisters() throws {
        func rows(server: Bool, paused: Bool) -> [String: DataFlowRow] {
            let state = DataFlowState(rememberConversations: true, shareProfileWithVoice: false, tokenServerSet: true, connectionsOn: [],
                                      pauseAll: paused, doddyServerSet: false, askDoddyOn: false, askDoddyUsesNotes: false,
                                      messagingServerSet: server)
            return Dictionary(uniqueKeysWithValues: DataFlow.rows(state).map { ($0.id, $0) })
        }
        let on = rows(server: true, paused: false)
        let vat = try XCTUnwrap(on["vatRegister"])
        XCTAssertTrue(vat.isActive)
        XCTAssertTrue(vat.what.hasPrefix("Only a buyer's NIP"))
        XCTAssertTrue(vat.note?.contains("bank accounts it lists aren't read or kept") ?? false)
        XCTAssertTrue(try XCTUnwrap(on["ceidg"]).isActive)
        XCTAssertFalse(try XCTUnwrap(rows(server: false, paused: false)["ceidg"]).isActive, "no server, no CEIDG")
        let paused = rows(server: true, paused: true)
        XCTAssertFalse(try XCTUnwrap(paused["vatRegister"]).isActive)
        XCTAssertFalse(try XCTUnwrap(paused["ceidg"]).isActive)
    }

    // MARK: The draft

    private func session(nip: String = "5260250995", heard: [String]) -> InvoiceVoiceSession {
        var session = InvoiceVoiceSession()
        guard case .draftInvoice(let update) = VoiceToolRequest.parse(
            name: VoiceToolName.draftInvoice,
            parametersJSON: Data(#"{"buyer_kind":"company","buyer_name":"Orange","buyer_nip":"\#(nip)"}"#.utf8)) else { return session }
        _ = session.apply(update, userWords: heard, today: day)
        return session
    }

    func testOnlyANipThePersonSaidIsLookedUp() {
        XCTAssertEqual(session(heard: ["Faktura dla Orange, NIP 526 025 09 95"]).registerLookupNip, orange)
        XCTAssertNil(session(heard: ["Faktura dla Orange"]).registerLookupNip, "a NIP only the model suggested isn't sent anywhere")
        XCTAssertNil(session(nip: "1234567890", heard: ["NIP 1234567890"]).registerLookupNip, "a NIP that fails its check digit")
    }

    func testAFoundEntryFillsTheBuyerAndTheCardSaysWhere() throws {
        var draft = session(heard: ["Faktura dla Orange, NIP 5260250995"])
        guard case .found(let company) = VatRegister.read(vatFound, statusCode: 200, nip: orange, on: day) else { return XCTFail() }
        let notes = draft.applyRegister(.found(company), for: orange)
        XCTAssertEqual(notes, [.fromRegister(company)])
        let operation = try XCTUnwrap(draft.operation)
        XCTAssertEqual(operation.draft.contractor.name, Sourced("ORANGE POLSKA SPÓŁKA AKCYJNA", source: .officialRegister))
        XCTAssertEqual(operation.draft.contractor.address?.source, .officialRegister)
        XCTAssertFalse(operation.draft.missingData.contains("contractor.address"))
        XCTAssertNil(draft.registerLookupNip, "asked once")

        let card = InvoiceCard(operation, polish: true, register: draft.register)
        XCTAssertEqual(card.registerLine, "Dane nabywcy z wykazu podatników VAT (Ministerstwo Finansów), sprawdzone 01.11.2026. Status VAT: Czynny.")
        XCTAssertEqual(card.buyer.first { $0.label == "Nazwa" }?.fromRegister, true)
        let reply = VoiceToolReply.invoiceDraft(operation, notes: notes, kept: true)
        XCTAssertTrue(reply.contains("VAT register today"))
        XCTAssertTrue(reply.contains("ORANGE POLSKA SPÓŁKA AKCYJNA"), "the name goes to the agent as data")

        // The person's own words still win.
        guard case .draftInvoice(let update) = VoiceToolRequest.parse(
            name: VoiceToolName.draftInvoice, parametersJSON: Data(#"{"city":"Kraków","post_code":"31-004","street":"Lipowa"}"#.utf8))
        else { return XCTFail() }
        guard case .drafted(let changed, _) = draft.apply(update, userWords: [], today: day) else { return XCTFail() }
        XCTAssertEqual(changed.draft.contractor.address?.source, .saidByUser)
        XCTAssertEqual(changed.draft.contractor.address?.value.city, "Kraków")
    }

    func testAnInactiveTaxpayerIsTold() throws {
        var draft = session(heard: ["NIP 5260250995"])
        let exempt = RegisteredCompany(nip: "5260250995", name: "X", address: InvoiceAddress(street: "A", buildingNumber: "1", city: "B", postCode: "00-001"),
                                       addressLine: nil, status: "Zwolniony", source: .vatRegister, checkedOn: day, requestId: nil)
        let notes = draft.applyRegister(.found(exempt), for: orange)
        let reply = VoiceToolReply.invoiceDraft(try XCTUnwrap(draft.operation), notes: notes)
        XCTAssertTrue(reply.contains("not an active VAT payer"))
    }

    func testNoEntryIsRememberedButCouldNotCheckIsAskedAgain() throws {
        var draft = session(heard: ["NIP 5260250995"])
        XCTAssertEqual(draft.applyRegister(.couldNotCheck, for: orange), [.registerNotChecked])
        XCTAssertEqual(draft.registerLookupNip, orange, "nothing is known yet: may be asked again")
        XCTAssertEqual(draft.applyRegister(.notFound, for: orange), [.notInRegister])
        XCTAssertNil(draft.registerLookupNip, "not asked twice about a NIP no register has")
        XCTAssertTrue(VoiceToolReply.invoiceDraft(try XCTUnwrap(draft.operation), notes: [.notInRegister]).contains("didn't find this NIP"))
    }

    func testAnAnswerForAnOldNipIsIgnored() throws {
        var draft = session(heard: ["NIP 5260250995 a nie, 1060006024"])
        guard case .draftInvoice(let update) = VoiceToolRequest.parse(
            name: VoiceToolName.draftInvoice, parametersJSON: Data(#"{"buyer_nip":"1060006024"}"#.utf8)) else { return XCTFail() }
        _ = draft.apply(update, userWords: ["NIP 5260250995 a nie, 1060006024"], today: day)
        guard case .found(let company) = VatRegister.read(vatFound, statusCode: 200, nip: orange, on: day) else { return XCTFail() }
        XCTAssertEqual(draft.applyRegister(.found(company), for: orange), [], "the NIP changed while the register answered")
        XCTAssertEqual(draft.operation?.draft.contractor.name?.value, "Orange")
    }

    func testAKeptDraftKeepsItsRegisterEntry() throws {
        var draft = session(heard: ["NIP 5260250995"])
        guard case .found(let company) = VatRegister.read(vatFound, statusCode: 200, nip: orange, on: day) else { return XCTFail() }
        _ = draft.applyRegister(.found(company), for: orange)
        let data = try JSONEncoder().encode(draft)
        let back = try JSONDecoder().decode(InvoiceVoiceSession.self, from: data)
        XCTAssertEqual(back, draft)
        XCTAssertEqual(back.register?.requestId, "jPEOY-995l7fd")
    }
}
