import XCTest
@testable import DoddyCore

final class VoiceStyleTests: XCTestCase {
    func testDefaultSendsNothing() {
        XCTAssertNil(VoiceStyle.doddyDefault.override)
        XCTAssertNil(VoiceStyle(voice: nil, speed: nil, expressiveness: nil).override)
    }

    func testOnlyChangedFieldsAreSent() {
        XCTAssertEqual(
            VoiceStyle(voice: .josh, speed: .normal, expressiveness: .natural).override,
            VoiceOverride(voiceID: "ZoiZ8fuDWInAcwPXaVeq", speed: nil, stability: nil))
        XCTAssertEqual(
            VoiceStyle(voice: .doddy, speed: .faster, expressiveness: .steady).override,
            VoiceOverride(voiceID: nil, speed: 1.15, stability: 0.75))
    }

    func testStoredValuesFallBackPerSetting() {
        XCTAssertEqual(
            VoiceStyle(voice: "wiktor", speed: "warp", expressiveness: nil),
            VoiceStyle(voice: .wiktor, speed: .normal, expressiveness: .natural))
    }

    func testValuesStayInElevenLabsRanges() {
        for speed in SpeakingSpeed.allCases { XCTAssertTrue((0.7...1.2).contains(speed.elevenLabsSpeed)) }
        for level in Expressiveness.allCases { XCTAssertTrue((0...1).contains(level.elevenLabsStability)) }
        let ids = VoiceChoice.allCases.compactMap(\.elevenLabsVoiceID)
        XCTAssertEqual(Set(ids).count, VoiceChoice.allCases.count - 1)
    }
}
