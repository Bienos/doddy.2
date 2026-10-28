import XCTest

@testable import DoddyCore

final class MessagePhotoTests: XCTestCase {
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0x00, count: 32))

    func testOnlyAJpegWithinTheLimitCanBeSent() {
        XCTAssertNotNil(AssistantImage(jpeg: jpeg))
        XCTAssertNil(AssistantImage(jpeg: Data()))
        XCTAssertNil(AssistantImage(jpeg: Data([0x89, 0x50, 0x4E, 0x47] + Array(repeating: 0x00, count: 32))), "a PNG is not sent")
        XCTAssertNil(AssistantImage(jpeg: Data([0xFF, 0xD8, 0xFF] + Array(repeating: 0x00, count: AssistantImage.maxBytes))), "too large")
    }

    func testThePhotoIsOnTheWireOnlyWhenThereIsOne() throws {
        let image = try XCTUnwrap(AssistantImage(jpeg: jpeg))
        let with = WireCoding.wireRequest(from: AssistantRequest(sessionID: UUID(), userText: "Co to?", image: image))
        XCTAssertEqual(with.image?.mediaType, "image/jpeg")
        XCTAssertEqual(with.image?.data, jpeg.base64EncodedString())
        let without = WireCoding.wireRequest(from: AssistantRequest(sessionID: UUID(), userText: "Co to?"))
        let encoded = try XCTUnwrap(String(data: try WireCoding.encode(without), encoding: .utf8))
        XCTAssertFalse(encoded.contains("image"), "no photo, no field: the gateway refuses unknown fields")
    }

    func testAPhotoCanBeSentWithAnEmptyBoxAndGetsAQuestion() {
        XCTAssertTrue(ThreadRules.canSend(draft: "  ", isSending: false, hasPhoto: true))
        XCTAssertFalse(ThreadRules.canSend(draft: "  ", isSending: false, hasPhoto: false))
        XCTAssertFalse(ThreadRules.canSend(draft: "", isSending: true, hasPhoto: true))
        XCTAssertEqual(ThreadRules.photoQuestion(draft: "  ", fallback: "What's in this photo?"), "What's in this photo?")
        XCTAssertEqual(ThreadRules.photoQuestion(draft: " Ile to kosztuje? ", fallback: "x"), "Ile to kosztuje?")
    }

    func testAFailedPhotoMessageIsNotResentWithoutItsPhoto() {
        var failed = ThreadMessage.user("Co to?", hasPhoto: true)
        failed.delivery = .failed
        XCTAssertFalse(ThreadRules.canRetry(failed))
        XCTAssertEqual(ThreadRules.deliveryLine(for: failed), .notDeliveredPhoto)
        var plain = ThreadMessage.user("Co to?")
        plain.delivery = .failed
        XCTAssertTrue(ThreadRules.canRetry(plain))
        XCTAssertEqual(ThreadRules.deliveryLine(for: plain), .notDelivered)
    }

    func testAnExportFromBeforePhotosReadsAsNoPhoto() throws {
        let message = ThreadMessage.user("Cześć")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        XCTAssertEqual(object["hasPhoto"] as? Bool, false)
        object.removeValue(forKey: "hasPhoto")
        let old = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try JSONDecoder().decode(ThreadMessage.self, from: old).hasPhoto, false)
    }
}
