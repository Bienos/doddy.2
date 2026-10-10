import XCTest
import DoddyCore
@testable import Doddy

/// App-target tests. NOT RUN in the authoring environment (no Xcode); see BUILD_AND_TEST.md.
final class AppEnvironmentTests: XCTestCase {
    func testUnavailableEnvironmentWiresOnlyUnavailableAdapters() {
        let env = AppEnvironment.unavailable
        XCTAssertTrue(env.memoryRepository is UnavailableMemoryRepository)
        XCTAssertTrue(env.recallService is UnavailableRecallService)
        XCTAssertTrue(env.assistantClient is UnavailableAssistantClient)
        XCTAssertTrue(env.actionAdapter is UnavailableActionAdapter)
    }

    func testEveryCapabilityHasHonestDisplayCopy() {
        for capability in Capability.allCases {
            XCTAssertFalse(capability.displayName.isEmpty)
            let text = StatusCopy.text(for: AppEnvironment.unavailable.capabilities.status(of: capability))
            XCTAssertTrue(text.hasPrefix("Not built"), "\(capability): \(text)")
        }
    }

    func testAvailableStatusCopy() {
        XCTAssertEqual(StatusCopy.text(for: .available), "Available")
        XCTAssertEqual(StatusCopy.text(for: .notImplemented(plannedMilestone: "M1")), "Not built yet · planned M1")
    }
}
