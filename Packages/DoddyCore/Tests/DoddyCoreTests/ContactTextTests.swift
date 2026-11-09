import Foundation
import XCTest
@testable import DoddyCore

/// Texts from Doddy's number to the user's contacts (decision 2026-11-09-texts-to-contacts).
final class ContactTextTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private let poland = ["48"]

    private func ania(_ raw: String = "600 123 456") -> ContactText.ContactNumber {
        ContactText.ContactNumber(contactName: "Ania", raw: raw)!
    }

    func testNumbersAsContactsWriteThem() {
        XCTAssertEqual(ania("600 123 456").e164, "+48600123456")
        XCTAssertEqual(ania("+48 600-123-456").e164, "+48600123456")
        XCTAssertEqual(ania("0048 (600) 123 456").e164, "+48600123456")
        XCTAssertEqual(ania("+49 151 23456789").e164, "+4915123456789")
    }

    func testWhatIsNotANumberIsRefused() {
        for raw in ["", "Ania", "112", "600 123 456 wew. 12", "*100#", "0600123456", "+0 600", "+48600123456789012"] {
            XCTAssertNil(ContactText.ContactNumber(contactName: "Ania", raw: raw), raw)
        }
        XCTAssertNil(ContactText.ContactNumber(contactName: "  ", raw: "600123456"), "a contact needs a name for the card")
    }

    func testAGoodTextMayGoToTheCard() {
        XCTAssertNil(ContactText.problem(body: "Spóźnię się 10 minut", to: ania(), sentToday: 0, allowedCallingCodes: poland))
    }

    func testFiftyADayAndNoMore() {
        XCTAssertEqual(ContactText.maxPerDay, 50)
        XCTAssertNil(ContactText.problem(body: "Hej", to: ania(), sentToday: 49, allowedCallingCodes: poland))
        XCTAssertEqual(ContactText.problem(body: "Hej", to: ania(), sentToday: 50, allowedCallingCodes: poland), .dailyLimit)
    }

    func testEmptyLongAndHiddenTextsAreRefused() {
        XCTAssertEqual(ContactText.problem(body: " \n", to: ania(), sentToday: 0, allowedCallingCodes: poland), .empty)
        let long = String(repeating: "a", count: ApprovedTextLimits.maxLength + 1)
        XCTAssertEqual(ContactText.problem(body: long, to: ania(), sentToday: 0, allowedCallingCodes: poland), .tooLong)
        XCTAssertEqual(ContactText.problem(body: "Hej\u{202E}", to: ania(), sentToday: 0, allowedCallingCodes: poland), .hiddenCharacter)
    }

    func testOnlyAllowedCountries() {
        let german = ania("+49 151 23456789")
        XCTAssertEqual(ContactText.problem(body: "Hallo", to: german, sentToday: 0, allowedCallingCodes: poland), .numberNotAllowed)
        XCTAssertNil(ContactText.problem(body: "Hallo", to: german, sentToday: 0, allowedCallingCodes: poland + ["49"]))
    }

    func testTheTapApprovesExactlyThisNumberAndText() {
        let hash = ContactText.approvalHash(to: ania(), body: "Spóźnię się")
        XCTAssertEqual(hash, ApprovalHash.text(to: "+48600123456", body: "Spóźnię się"))
        XCTAssertNotEqual(hash, ContactText.approvalHash(to: ania(), body: "Spóźnię się!"), "a changed text needs a new tap")
        XCTAssertNotEqual(hash, ContactText.approvalHash(to: ania("600 123 457"), body: "Spóźnię się"), "another number needs a new tap")
    }

    func testNoSignatureIsAdded() {
        // The hash covers the text as written: nothing is appended before it is sent.
        XCTAssertEqual(ContactText.approvalHash(to: ania(), body: "Hej"), ApprovalHash.hex([ApprovalHash.version, "text", "+48600123456", "Hej"]))
    }

    func testTheRulesFileSaysTheSame() throws {
        let rules = try String(contentsOf: repoRoot.appendingPathComponent("docs/trust/config/doddy_rules.yaml"), encoding: .utf8)
        XCTAssertTrue(rules.contains("contact_texts_per_account_day: \(ContactText.maxPerDay)"))
        XCTAssertTrue(rules.contains("contact_text_recipients: iphone_contacts_number_read_by_app"))
    }
}
