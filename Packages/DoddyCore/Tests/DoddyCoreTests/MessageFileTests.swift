import XCTest

@testable import DoddyCore

final class MessageFileTests: XCTestCase {
    private let pdf = Data("%PDF-1.7\n%fake".utf8)
    private let text = Data("Lista zakupów: mleko, chleb".utf8)

    func testOnlyAPdfOrUtf8TextWithinTheLimitsCanBeSent() {
        XCTAssertNotNil(AssistantFile(name: "umowa.pdf", kind: .pdf, data: pdf))
        XCTAssertNotNil(AssistantFile(name: "lista.txt", kind: .text, data: text))
        XCTAssertNil(AssistantFile(name: "x.pdf", kind: .pdf, data: Data()), "empty")
        XCTAssertNil(AssistantFile(name: "x.pdf", kind: .pdf, data: text), "a PDF must start like one")
        XCTAssertNil(AssistantFile(name: "x.txt", kind: .text, data: Data([0xFF, 0xFE, 0x00])), "text must be UTF-8")
        XCTAssertNil(AssistantFile(name: "x.txt", kind: .text, data: Data("  \n ".utf8)), "not blank")
        XCTAssertNil(AssistantFile(name: "x.txt", kind: .text, data: Data(String(repeating: "a", count: AssistantFile.maxTextScalars + 1).utf8)))
        XCTAssertNil(AssistantFile(name: "x.pdf", kind: .pdf, data: pdf + Data(count: AssistantFile.maxBytes)), "too large")
        XCTAssertNil(AssistantFile(name: " \n ", kind: .pdf, data: pdf), "a name is needed")
    }

    func testTheNameLosesControlCharactersAndStaysWithinTheLimit() throws {
        XCTAssertEqual(try XCTUnwrap(AssistantFile(name: " umo\nwa\u{0}.pdf ", kind: .pdf, data: pdf)).name, "umowa.pdf")
        let long = try XCTUnwrap(AssistantFile(name: String(repeating: "ą", count: 300), kind: .pdf, data: pdf))
        XCTAssertEqual(long.name.unicodeScalars.count, AssistantFile.maxNameScalars)
    }

    func testTheFileIsOnTheWireOnlyWhenThereIsOne() throws {
        let file = try XCTUnwrap(AssistantFile(name: "umowa.pdf", kind: .pdf, data: pdf))
        let with = WireCoding.wireRequest(from: AssistantRequest(sessionID: UUID(), userText: "Co to?", file: file))
        XCTAssertEqual(with.file?.name, "umowa.pdf")
        XCTAssertEqual(with.file?.mediaType, "application/pdf")
        XCTAssertEqual(with.file?.data, pdf.base64EncodedString())
        XCTAssertNil(with.image)
        let textFile = try XCTUnwrap(AssistantFile(name: "lista.txt", kind: .text, data: text))
        XCTAssertEqual(WireCoding.wireRequest(from: AssistantRequest(sessionID: UUID(), userText: "?", file: textFile)).file?.mediaType, "text/plain")
        let without = WireCoding.wireRequest(from: AssistantRequest(sessionID: UUID(), userText: "Co to?"))
        let encoded = try XCTUnwrap(String(data: try WireCoding.encode(without), encoding: .utf8))
        XCTAssertFalse(encoded.contains("\"file\""), "no file, no field: the gateway refuses unknown fields")
    }

    func testAFailedFileMessageIsNotResentWithoutItsFile() {
        var failed = ThreadMessage.user("Co to?", attachedFileName: "umowa.pdf")
        failed.delivery = .failed
        XCTAssertFalse(ThreadRules.canRetry(failed))
        XCTAssertEqual(ThreadRules.deliveryLine(for: failed), .notDeliveredFile)
    }

    func testAnExportFromBeforeFilesReadsAsNoFile() throws {
        let message = ThreadMessage.user("Cześć", attachedFileName: "lista.txt")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        XCTAssertEqual(object["attachedFileName"] as? String, "lista.txt")
        object.removeValue(forKey: "attachedFileName")
        let old = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(try JSONDecoder().decode(ThreadMessage.self, from: old).attachedFileName)
    }
}
