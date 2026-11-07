import Foundation
import XCTest
@testable import DoddyCore

/// "I lost my wallet" (ADR-692): the model says only what was lost; the steps, their order, their
/// links and numbers come from DoddyCore's fixed table, and nothing is ever marked done for the person.
final class LostWalletTests: XCTestCase {
    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: VoiceToolName.lostWallet, parametersJSON: Data(json.utf8))
    }

    private func situation(_ json: String, file: StaticString = #filePath, line: UInt = #line) throws -> LostWalletSituation {
        guard case .lostWallet(let situation) = parse(json) else {
            XCTFail("not a lost_wallet request: \(parse(json))", file: file, line: line)
            throw XCTSkip()
        }
        return situation
    }

    private func ids(_ s: LostWalletSituation, polish: Bool = false) -> [LostWalletStepID] {
        LostWalletPlan.steps(for: s, polish: polish).map(\.id)
    }

    /// Every combination of what was lost, stolen or not, abroad or not.
    private var everySituation: [LostWalletSituation] {
        var all: [LostWalletSituation] = []
        for mask in 1..<(1 << LostItem.allCases.count) {
            let items = LostItem.allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            for stolen in [false, true] {
                for abroad in [false, true] { all.append(LostWalletSituation(lost: items, stolen: stolen, abroad: abroad)) }
            }
        }
        return all
    }

    // MARK: What the model may send

    func testParsesTheItemsOnceInAFixedOrder() throws {
        let s = try situation(#"{"lost":["passport","bank_cards","ID_CARD","bank_cards"],"stolen":true}"#)
        XCTAssertEqual(s.lost, [.idCard, .bankCards, .passport])
        XCTAssertTrue(s.stolen)
        XCTAssertFalse(s.abroad)
    }

    func testOneItemAsAPlainStringCounts() throws {
        let s = try situation(#"{"lost":"bank_cards","abroad":true}"#)
        XCTAssertEqual(s.lost, [.bankCards])
        XCTAssertTrue(s.abroad)
        XCTAssertFalse(s.stolen)
    }

    func testRefusesWhatItCantUse() {
        for json in [#"{}"#, #"{"lost":[]}"#, #"{"lost":["wallet"]}"#, #"{"lost":["id_card", 3]}"#, #"{"lost":{"a":1}}"#] {
            guard case .invalid(let name, let reason) = parse(json) else { return XCTFail("accepted \(json)") }
            XCTAssertEqual(name, VoiceToolName.lostWallet)
            XCTAssertTrue(reason.contains("lost"), reason)
        }
    }

    func testAnUnknownItemIsRefusedNotDropped() {
        guard case .invalid(_, let reason) = parse(#"{"lost":["id_card","keys"]}"#) else { return XCTFail("keys were dropped") }
        XCTAssertTrue(reason.contains("keys"), reason)
    }

    // MARK: Which steps, in which order

    func testCardsOnly() {
        let s = LostWalletSituation(lost: [.bankCards], stolen: false, abroad: false)
        XCTAssertEqual(ids(s), [.blockCards])
        XCTAssertEqual(LostWalletPlan.steps(for: s, polish: false).first?.action, .call("+48828828828"))
    }

    func testIdCardLost() {
        let s = LostWalletSituation(lost: [.idCard], stolen: false, abroad: false)
        XCTAssertEqual(ids(s), [.cancelIdCard, .checkPesel, .blockDocuments, .newIdCard])
    }

    func testWholeWalletStolenAtHome() {
        let s = LostWalletSituation(lost: [.idCard, .bankCards, .drivingLicence], stolen: true, abroad: false)
        XCTAssertEqual(ids(s), [.blockCards, .cancelIdCard, .checkPesel, .blockDocuments, .reportTheft, .reportDrivingLicence, .newIdCard])
    }

    func testPassportStolenAbroad() {
        let s = LostWalletSituation(lost: [.passport, .bankCards], stolen: true, abroad: true)
        XCTAssertEqual(ids(s), [.blockCards, .blockDocuments, .reportTheft, .reportPassport, .consulAbroad])
    }

    func testCardsComeFirstWheneverTheyWereLost() {
        for s in everySituation where s.has(.bankCards) {
            XCTAssertEqual(ids(s).first, .blockCards, "\(s)")
        }
    }

    func testTheftIsReportedOnlyWhenStolen() {
        for s in everySituation {
            XCTAssertEqual(ids(s).contains(.reportTheft), s.stolen, "\(s)")
        }
    }

    func testDrivingLicenceAloneIsOneStep() {
        let s = LostWalletSituation(lost: [.drivingLicence], stolen: false, abroad: false)
        XCTAssertEqual(ids(s), [.reportDrivingLicence])
    }

    /// The PESEL check and the new-ID step belong to the ID card; the register of blocked documents
    /// to the ID card and the passport (the pages say so); nothing else adds them.
    func testWhichItemsBringWhichSteps() {
        for s in everySituation {
            XCTAssertEqual(ids(s).contains(.checkPesel), s.has(.idCard), "\(s)")
            XCTAssertEqual(ids(s).contains(.newIdCard), s.has(.idCard), "\(s)")
            XCTAssertEqual(ids(s).contains(.cancelIdCard), s.has(.idCard), "\(s)")
            XCTAssertEqual(ids(s).contains(.blockDocuments), s.has(.idCard) || s.has(.passport), "\(s)")
            XCTAssertEqual(ids(s).contains(.reportPassport), s.has(.passport), "\(s)")
            XCTAssertEqual(ids(s).contains(.reportDrivingLicence), s.has(.drivingLicence), "\(s)")
            XCTAssertEqual(ids(s).contains(.consulAbroad), s.abroad && (s.has(.idCard) || s.has(.passport)), "\(s)")
        }
    }

    func testTheNewIdCardComesLastAndTheCancellationBeforeIt() {
        for s in everySituation where s.has(.idCard) {
            let order = ids(s)
            XCTAssertEqual(order.last, .newIdCard, "\(s)")
            XCTAssertLessThan(order.firstIndex(of: .cancelIdCard)!, order.firstIndex(of: .newIdCard)!, "\(s)")
            XCTAssertLessThan(order.firstIndex(of: .cancelIdCard)!, order.firstIndex(of: .checkPesel)!, "\(s)")
        }
    }

    func testEveryStepAppearsOnce() {
        for s in everySituation {
            XCTAssertEqual(Set(ids(s)).count, ids(s).count, "\(s)")
            XCTAssertFalse(ids(s).isEmpty, "\(s)")
        }
    }

    // MARK: Links and numbers

    func testEveryButtonIsAnAllowedPageOrNumber() {
        for s in everySituation {
            for polish in [false, true] {
                for step in LostWalletPlan.steps(for: s, polish: polish) {
                    guard let action = step.action else {
                        XCTAssertNil(step.actionLabel, "\(step.id)")
                        continue
                    }
                    XCTAssertTrue(LostWalletPlan.isAllowed(action), "\(step.id): \(action)")
                    XCTAssertNotNil(action.url, "\(step.id)")
                    XCTAssertNotNil(step.actionLabel, "\(step.id)")
                }
            }
        }
        for url in LostWalletPlan.Links.all {
            XCTAssertTrue(LostWalletPlan.isAllowed(.open(url)), url.absoluteString)
        }
    }

    /// Each link was opened and read on the official page on 2 Nov 2026; a guessed or edited address
    /// would break this (docs/research/2026-11-02/lost_wallet_pl.md).
    func testLinksAreTheOnesReadOnTheOfficialPages() {
        XCTAssertEqual(LostWalletPlan.Links.all.map(\.absoluteString), [
            "https://www.gov.pl/web/gov/zglos-utrate-lub-uszkodzenie-swojego-dowodu-osobistego-uniewaznij-dowod",
            "https://www.gov.pl/web/gov/zastrzez-swoj-numer-pesel-lub-cofnij-zastrzezenie",
            "https://dokumentyzastrzezone.pl/zastrzeganie-dokumentow/",
            "https://www.gov.pl/web/gov/zglos-utrate-lub-zniszczenie-paszportu",
            "https://www.gov.pl/web/dyplomacja/polskie-przedstawicielstwa-na-swiecie",
            "https://www.gov.pl/web/gov/zglos-utrate-lub-uszkodzenie-prawa-jazdy",
            "https://www.gov.pl/web/gov/uzyskaj-dowod-osobisty",
        ])
        XCTAssertEqual(LostWalletPlan.allowedHosts, ["www.gov.pl", "dokumentyzastrzezone.pl"])
    }

    func testRefusesAnyOtherPageOrNumber() {
        let refused: [LostWalletAction] = [
            .open(URL(string: "http://dokumentyzastrzezone.pl/zastrzeganie-dokumentow/")!),
            .open(URL(string: "https://dokumentyzastrzezone.pl.example.com/")!),
            .open(URL(string: "https://www.dokumentyzastrzezone.pl/")!),
            .open(URL(string: "http://www.gov.pl/web/gov/zastrzez-swoj-numer-pesel")!),
            .open(URL(string: "https://gov.pl.example.com/web/gov")!),
            .open(URL(string: "https://example.com/zastrzez")!),
            .open(URL(string: "https://user@www.gov.pl/web/gov")!),
            .open(URL(string: "https://www.gov.pl:8443/web/gov")!),
            .open(URL(string: "tel:+48828828828")!),
            .call("+48123456789"),
            .call("828828828"),
        ]
        for action in refused { XCTAssertFalse(LostWalletPlan.isAllowed(action), "\(action)") }
    }

    func testTheCallButtonDialsTheNumberAsWritten() {
        XCTAssertEqual(LostWalletAction.call("+48828828828").url?.absoluteString, "tel:+48828828828")
    }

    // MARK: Words

    func testPolishAndEnglishHaveTheSameSteps() {
        for s in everySituation {
            let english = LostWalletPlan.steps(for: s, polish: false)
            let polish = LostWalletPlan.steps(for: s, polish: true)
            XCTAssertEqual(english.map(\.id), polish.map(\.id), "\(s)")
            XCTAssertEqual(english.map(\.action), polish.map(\.action), "\(s)")
            for (e, p) in zip(english, polish) {
                XCTAssertNotEqual(e.title, p.title, "\(e.id)")
                XCTAssertNotEqual(e.detail, p.detail, "\(e.id)")
            }
        }
    }

    func testTheReplyListsTheStepsAndWhatTheAgentMustNeverSay() {
        let s = LostWalletSituation(lost: [.idCard, .bankCards], stolen: true, abroad: false)
        let reply = VoiceToolReply.lostWalletShown(s)
        XCTAssertTrue(reply.hasPrefix("shown: a checklist with 6 steps"), reply)
        for step in LostWalletPlan.steps(for: s, polish: false) { XCTAssertTrue(reply.contains(step.title), step.title) }
        XCTAssertTrue(reply.contains("1. Block your bank cards"), reply)
        XCTAssertTrue(reply.contains("Never say a card is blocked"), reply)
        XCTAssertTrue(reply.contains("Never ask for or repeat a card number, PESEL"), reply)
        XCTAssertTrue(reply.contains("112"), reply)
    }

    // MARK: How it asks, in the car, under Pause all, in the log

    func testItIsItsOwnCardAndNeverRunsWithoutOne() {
        let request = VoiceToolRequest.lostWallet(LostWalletSituation(lost: [.idCard], stolen: false, abroad: false))
        XCTAssertEqual(AskFirst.need(for: request), .ownPayloadCard)
        XCTAssertEqual(CarProfile.decision(for: request), .run)
        XCTAssertFalse(ConnectionPause.applies(to: request))
        XCTAssertNil(ActivityRequest.describe(request, calendar: .current))
        XCTAssertEqual(ToolCatalog.descriptor(VoiceToolName.lostWallet)?.approval, .card)
        XCTAssertEqual(ToolCatalog.descriptor(VoiceToolName.lostWallet)?.effect, .handoff)
    }
}
