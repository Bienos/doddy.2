import XCTest
@testable import DoddyCore

/// ADR-581: the email card takes the server's preview lines apart without changing any of them.
final class EmailPreviewLayoutTests: XCTestCase {
    func testDraftPreviewBecomesToSubjectAndText() {
        let layout = EmailPreviewLayout.parse(["To: ania@example.com", "Subject: Spóźnię się 10 minut", "Cześć Aniu,\nbędę o 9:10."])
        XCTAssertEqual(layout, EmailPreviewLayout(to: "ania@example.com", subject: "Spóźnię się 10 minut",
                                                  body: "Cześć Aniu,\nbędę o 9:10.", notes: []))
    }

    func testSendKeepsItsWarningAsANote() {
        let layout = EmailPreviewLayout.parse(["To: a@b.pl", "Subject: Hi", "Body", "It is sent at once from your Gmail and can't be taken back."])
        XCTAssertEqual(layout?.notes, ["It is sent at once from your Gmail and can't be taken back."])
    }

    func testReplyKeepsItsWholeReLine() {
        let layout = EmailPreviewLayout.parse(["To: Ania Kowalska <ania@example.com>", "Re: Kawa", "OK"])
        XCTAssertEqual(layout?.to, "Ania Kowalska <ania@example.com>")
        XCTAssertEqual(layout?.subject, "Re: Kawa")
    }

    func testAnythingElseStaysAList() {
        XCTAssertNil(EmailPreviewLayout.parse(["Buy milk", "Due: tomorrow"]))
        XCTAssertNil(EmailPreviewLayout.parse(["To: a@b.pl", "Subject: Hi"]))
        XCTAssertNil(EmailPreviewLayout.parse(["To: a@b.pl", "Due: tomorrow", "Body"]))
        XCTAssertNil(EmailPreviewLayout.parse(["To: ", "Subject: Hi", "Body"]))
    }
}
