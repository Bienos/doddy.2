import XCTest
@testable import DoddyCore

/// ADR-655: the loudness number behind Home's island extension.
final class VoiceLevelTests: XCTestCase {
    func testSilenceAndNonsenseAreZero() {
        XCTAssertEqual(VoiceLevel.level(rms: 0), 0)
        XCTAssertEqual(VoiceLevel.level(rms: -0.5), 0)
        XCTAssertEqual(VoiceLevel.level(rms: .nan), 0)
        XCTAssertEqual(VoiceLevel.level(rms: .infinity), 0)
    }

    func testQuietRoomIsZeroAndLoudSpeechIsOne() {
        // -60 dB, a very quiet room, and -50 dB, the bottom of the scale.
        XCTAssertEqual(VoiceLevel.level(rms: 0.001), 0)
        XCTAssertEqual(VoiceLevel.level(rms: pow(10, -50.0 / 20)), 0, accuracy: 1e-9)
        // -12 dB and anything louder.
        XCTAssertEqual(VoiceLevel.level(rms: pow(10, -12.0 / 20)), 1, accuracy: 1e-9)
        XCTAssertEqual(VoiceLevel.level(rms: 1), 1)
    }

    func testLouderIsNeverLess() {
        var previous = 0.0
        var rms = 0.0005
        while rms < 1 {
            let level = VoiceLevel.level(rms: rms)
            XCTAssertGreaterThanOrEqual(level, previous)
            XCTAssertLessThanOrEqual(level, 1)
            previous = level
            rms *= 1.07
        }
    }

    func testTheSmootherRisesFasterThanItFalls() {
        var rising = VoiceLevelSmoother()
        rising.push(1, seconds: 0.02)
        var falling = VoiceLevelSmoother()
        for _ in 0..<20 { falling.push(1, seconds: 0.02) }
        let peak = falling.value
        falling.push(0, seconds: 0.02)
        XCTAssertGreaterThan(rising.value, 0.5, "one 20 ms buffer of speech already lifts it")
        XCTAssertGreaterThan(falling.value, peak * 0.8, "one 20 ms buffer of silence barely lowers it")
    }

    func testTheSmootherStaysInRangeAndSurvivesBadInput() {
        var smoother = VoiceLevelSmoother()
        for raw in [0.0, 2.0, -3.0, .nan, 0.5, .infinity] {
            for seconds in [0.0, -1.0, .nan, 0.01, 10.0] {
                let value = smoother.push(raw, seconds: seconds)
                XCTAssertTrue(value.isFinite)
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, 1)
            }
        }
        smoother.reset()
        XCTAssertEqual(smoother.value, 0)
    }

    func testItSettlesOnASteadyLevel() {
        var smoother = VoiceLevelSmoother()
        for _ in 0..<100 { smoother.push(0.6, seconds: 0.02) }
        XCTAssertEqual(smoother.value, 0.6, accuracy: 0.001)
    }
}
