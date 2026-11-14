import XCTest
@testable import DoddyCore

final class VoiceStyleTests: XCTestCase {
    func testDefaultSendsNothing() {
        XCTAssertNil(VoiceStyle.doddyDefault.override)
        XCTAssertNil(VoiceStyle(speed: nil, expressiveness: nil).override)
    }

    func testOnlyChangedFieldsAreSentAndNeverAVoice() {
        XCTAssertEqual(
            VoiceStyle(speed: .faster, expressiveness: .steady).override,
            VoiceOverride(voiceID: nil, speed: 1.15, stability: 0.75))
        XCTAssertEqual(
            VoiceStyle(speed: .normal, expressiveness: .expressive).override,
            VoiceOverride(voiceID: nil, speed: nil, stability: 0.3))
        // Decision 2026-11-12-one-voice: Doddy speaks in the agent's own voice, whatever else is set.
        for speed in SpeakingSpeed.allCases {
            for level in Expressiveness.allCases {
                XCTAssertNil(VoiceStyle(speed: speed, expressiveness: level).override?.voiceID)
            }
        }
    }

    func testStoredValuesFallBackPerSetting() {
        XCTAssertEqual(
            VoiceStyle(speed: "warp", expressiveness: "expressive"),
            VoiceStyle(speed: .normal, expressiveness: .expressive))
    }

    func testTheVoiceSamplesAreGone() {
        let previews = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DoddyApp/Resources/VoicePreviews")
        XCTAssertFalse(FileManager.default.fileExists(atPath: previews.path), "decision 2026-11-12-one-voice removed the voice samples")
    }

    func testValuesStayInElevenLabsRanges() {
        for speed in SpeakingSpeed.allCases { XCTAssertTrue((0.7...1.2).contains(speed.elevenLabsSpeed)) }
        for level in Expressiveness.allCases { XCTAssertTrue((0...1).contains(level.elevenLabsStability)) }
    }
}
