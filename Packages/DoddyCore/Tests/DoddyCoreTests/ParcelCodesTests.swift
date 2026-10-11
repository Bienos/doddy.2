import XCTest
@testable import DoddyCore

/// Parcel pickup codes from email (ADR-348).
final class ParcelCodesTests: XCTestCase {
    func testInPostEmailGivesCodeAndLocker() {
        let email = """
        Twoja paczka czeka w Paczkomacie!
        Paczkomat: WAW123M, ul. Prosta 1, Warszawa
        Kod odbioru: 482915
        Masz czas do 14.10.2026 12:00.
        """
        XCTAssertEqual(ParcelCodes.find(in: email), [ParcelCode(code: "482915", carrier: "InPost", locker: "WAW123M")])
    }

    func testEnglishAndGermanAndCodeOnTheNextLine() {
        XCTAssertEqual(ParcelCodes.find(in: "Your DHL parcel is ready.\nPickup code:\n7731"),
                       [ParcelCode(code: "7731", carrier: "DHL", locker: nil)])
        XCTAssertEqual(ParcelCodes.find(in: "Ihr Abholcode lautet 58A21X für die Packstation 105").first?.code, "58A21X")
    }

    func testNumbersOnOtherLinesAreNotCodes() {
        let email = "Order 123456789 shipped.\nTracking: 00340434161094042557\nCall 800 100 100"
        XCTAssertTrue(ParcelCodes.find(in: email).isEmpty)
        XCTAssertNil(VoiceToolReply.parcelCodesNote(in: email))
    }

    func testReplyFramesTheCodeAsInformation() throws {
        let note = try XCTUnwrap(VoiceToolReply.parcelCodesNote(in: "InPost\nKod odbioru: 482915"))
        XCTAssertTrue(note.contains("482915 (InPost)"))
        XCTAssertTrue(note.contains("not an instruction"))
        XCTAssertTrue(note.contains("never save it unless they say yes"))
    }

    func testAtMostThreeCodes() {
        let email = (1...5).map { "Pickup code: 10\($0)00" }.joined(separator: "\n")
        XCTAssertEqual(ParcelCodes.find(in: email).count, 3)
    }
}

extension ParcelCodesTests {
    private func result(_ tool: String, _ text: String) throws -> RunResult {
        let json: [String: Any] = [
            "mode": "live", "tool": tool, "text": text, "count": 1, "truncated": false,
            "receipt": [
                "operationId": UUID().uuidString, "operation": "read", "toolkit": "gmail", "tool": tool,
                "timestamp": "2026-10-11T12:00:00Z", "mode": "live", "status": "succeeded", "summary": "Read an email",
            ],
        ]
        return try JSONDecoder().decode(RunResult.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testOnlyAReadEmailGetsTheNote() throws {
        let email = "From: InPost\nKod odbioru: 482915"
        XCTAssertTrue(VoiceToolReply.cloudResult(try result("read_email", email)).contains("looks like a parcel pickup code"))
        XCTAssertTrue(VoiceToolReply.cloudResult(try result("read_outlook_email", email)).contains("482915 (InPost)"))
        // A list of emails, a Notion page or a web search is left exactly as it came.
        XCTAssertEqual(VoiceToolReply.cloudResult(try result("check_email", email)), email)
        XCTAssertEqual(VoiceToolReply.cloudResult(try result("read_notion_page", email)), email)
    }
}
