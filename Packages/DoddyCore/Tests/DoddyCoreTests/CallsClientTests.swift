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
        let items = MemoryCopyItem.from([mine, sample])
        XCTAssertEqual(items, [MemoryCopyItem(id: mine.id, text: "Dentist Tuesday", capturedAt: ServerDates.format(date))])
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
