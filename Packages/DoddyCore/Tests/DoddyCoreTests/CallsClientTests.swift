import XCTest
@testable import DoddyCore

final class CallsClientTests: XCTestCase {
    func testPINRulesMatchTheServer() {
        for bad in ["123", "2580", "11111", "111111", "123456", "987654", "012345", "12a456", "123456789", "１２３４５６"] {
            XCTAssertFalse(CallPIN.isAcceptable(bad), bad)
        }
        for ok in ["258025", "135792", "904216", "90421688"] { XCTAssertTrue(CallPIN.isAcceptable(ok), ok) }
    }

    func testMemoryCopyUsesCorrectedTextAndSkipsSamples() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let mine = try MemoryRecord(id: UUID(), rawText: "Dentist Tuesdy", source: .explicitText, capturedAt: date)
            .correcting(to: "Dentist Tuesday", at: date)
        let sample = try MemoryRecord(id: UUID(), rawText: "Sample", source: .sampleFixture, capturedAt: date)
        let items = MemoryCopyItem.from([mine, sample], excluding: PrivateNotes())
        XCTAssertEqual(items, [MemoryCopyItem(id: mine.id, text: "Dentist Tuesday", capturedAt: ServerDates.format(date))])
    }

    /// ADR-310: a private note is never in the server copy for calls, whoever builds the upload.
    func testMemoryCopyNeverIncludesPrivateNotes() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let pin = try MemoryRecord(id: UUID(), rawText: "Bank PIN 4417", source: .explicitText, capturedAt: date)
        let keys = try MemoryRecord(id: UUID(), rawText: "Keys in the blue tin", source: .explicitText, capturedAt: date)
        // Privacy follows the note's id, so a corrected private note stays out too.
        let door = try MemoryRecord(id: UUID(), rawText: "Door code 1234", source: .explicitText, capturedAt: date)
            .correcting(to: "Door code 5678", at: date)
        let items = MemoryCopyItem.from([pin, keys, door], excluding: PrivateNotes(ids: [pin.id, door.id]))
        XCTAssertEqual(items, [MemoryCopyItem(id: keys.id, text: "Keys in the blue tin", capturedAt: ServerDates.format(date))])
        // When every note is private the upload is empty, and the server copy is replaced with nothing.
        XCTAssertEqual(MemoryCopyItem.from([pin], excluding: PrivateNotes(ids: [pin.id])), [])
    }

    /// The bytes that go to the server for the snapshot carry no trace of a private note.
    func testSnapshotRequestHasNoPrivateNote() async throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let pin = try MemoryRecord(id: UUID(), rawText: "Bank PIN 4417", source: .explicitText, capturedAt: date)
        let keys = try MemoryRecord(id: UUID(), rawText: "Keys in the blue tin", source: .explicitText, capturedAt: date)
        let transport = StepTransport([.success(ServerResponse(status: 200, body: Data(#"{"count":1}"#.utf8)))])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        let count = try await client.replaceMemoryCopy(MemoryCopyItem.from([pin, keys], excluding: PrivateNotes(ids: [pin.id])))
        XCTAssertEqual(count, 1)
        let sent = await transport.sent
        XCTAssertEqual(sent.map(\.path), ["/v1/memory-copy/snapshot"])
        let body = String(decoding: try XCTUnwrap(sent.first?.body), as: UTF8.self).lowercased()
        XCTAssertFalse(body.contains("4417"))
        XCTAssertFalse(body.contains(pin.id.uuidString.lowercased()))
        XCTAssertTrue(body.contains(keys.id.uuidString.lowercased()))
    }

    func testSettingsDecodeAndWeakPINMaps() throws {
        let json = #"{"available":{"inbound":true,"outbound":false},"doddyNumber":"+48221234567","phoneVerified":true,"inboundEnabled":false,"pinSet":true,"pinLocked":false,"outboundConsent":false,"memoryCopy":{"enabled":true,"count":3}}"#
        let s = try JSONDecoder().decode(CallSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.memoryCopy.count, 3)
        XCTAssertFalse(s.available.outbound)
        XCTAssertEqual(DoddyServerClient.error(from: ServerResponse(status: 400, body: Data(#"{"error":"weak_pin"}"#.utf8))), .weakPIN)
    }

    func testServerDatesAcceptMilliseconds() {
        XCTAssertNotNil(ServerDates.parse("2026-10-10T09:02:18.197Z"))
        XCTAssertNotNil(ServerDates.parse("2026-10-10T09:02:18Z"))
    }

    func testPhoneCallsAreNeverClaimedAvailableByTheCatalog() {
        XCTAssertFalse(CapabilityCatalog.withMessaging(serverConfigured: true).isAvailable(.phoneCalls))
        XCTAssertEqual(CapabilityCatalog.m0.status(of: .phoneCalls), .notImplemented(plannedMilestone: "S2"))
    }
}
