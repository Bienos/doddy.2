import XCTest
@testable import DoddyCore

/// Doddy on a Mac running the iPad app (ADR-349).
final class HostDeviceTests: XCTestCase {
    func testWhatEachDeviceCanDo() {
        XCTAssertTrue(HostDevice.phone.supports(.backTap))
        XCTAssertFalse(HostDevice.pad.supports(.backTap))
        XCTAssertFalse(HostDevice.mac.supports(.backTap))
        XCTAssertTrue(HostDevice.pad.supports(.liveActivities))
        XCTAssertFalse(HostDevice.mac.supports(.liveActivities))
        XCTAssertTrue(HostDevice.pad.supports(.alarms))
        XCTAssertFalse(HostDevice.mac.supports(.alarms))
        // Reminders and renewals notify everywhere.
        for host in HostDevice.allCases { XCTAssertTrue(host.supports(.notifications), host.rawValue) }
    }

    func testTheMacGetsAnHonestAlarmReply() {
        let reply = VoiceToolReply.alarmNotOnThisDevice(.mac)
        XCTAssertTrue(reply.hasPrefix("failed: alarms can't be set on this Mac."))
        XCTAssertTrue(reply.contains("Nothing was set"))
        XCTAssertTrue(reply.contains("timer"))
    }
}
