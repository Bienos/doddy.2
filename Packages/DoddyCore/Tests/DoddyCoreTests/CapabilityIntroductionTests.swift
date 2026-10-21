import XCTest
@testable import DoddyCore

/// The onboarding "What I can do" paragraph must match the build it describes.
final class CapabilityIntroductionTests: XCTestCase {
    func testShippingBuildMentionsRemindersAndConfirmationNotTheOldDenial() {
        for serverConfigured in [true, false] {
            let text = CapabilityIntroduction.text(for: .shipping(serverConfigured: serverConfigured))
            XCTAssertTrue(text.hasPrefix("I'm an AI assistant, not a person."))
            XCTAssertTrue(text.contains("I can add a reminder"))
            XCTAssertTrue(text.contains("only after you confirm each one on screen"))
            // ADR-577: apps are allowed from the conversation, the first time one is needed.
            XCTAssertTrue(text.contains("I ask you on screen to allow it"))
            XCTAssertFalse(text.contains("Settings › Connections"))
            XCTAssertTrue(text.contains("ElevenLabs"))
            XCTAssertFalse(text.contains("can't add reminders"))
            XCTAssertFalse(text.contains("can't set reminders"))
        }
    }

    func testBuildWithoutRemindersOrVoiceSaysSo() {
        let text = CapabilityIntroduction.text(for: .m0)
        XCTAssertTrue(text.contains("I can't add reminders or use other apps in this build."))
        XCTAssertFalse(text.contains("ElevenLabs"))
        XCTAssertFalse(text.contains("I can add a reminder"))
    }

    func testAlwaysPointsToTheDataFlowScreen() {
        for catalog in [CapabilityCatalog.m0, .v1Voice, .shipping(serverConfigured: true)] {
            XCTAssertTrue(CapabilityIntroduction.text(for: catalog).hasSuffix("Settings › What leaves this iPhone shows everything that is sent, and where."))
        }
    }
}
