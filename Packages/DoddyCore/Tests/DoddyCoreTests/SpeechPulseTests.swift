import XCTest
@testable import DoddyCore

/// ADR-654: the clock-made speech rhythm and the spring behind Home's island extension.
final class SpeechPulseTests: XCTestCase {
    func testTheLevelStaysBetweenZeroAndOne() {
        var time = 0.0
        while time < 60 {
            let level = SpeechPulse.level(at: time)
            XCTAssertGreaterThanOrEqual(level, 0)
            XCTAssertLessThanOrEqual(level, 1)
            time += 0.013
        }
    }

    func testNothingBeforeItStartsOrForANonsenseTime() {
        XCTAssertEqual(SpeechPulse.level(at: -1), 0)
        XCTAssertEqual(SpeechPulse.level(at: .nan), 0)
        XCTAssertEqual(SpeechPulse.level(at: .infinity), 0)
    }

    func testItIsTheSameEveryTime() {
        for time in stride(from: 0.0, to: 10.0, by: 0.37) {
            XCTAssertEqual(SpeechPulse.level(at: time), SpeechPulse.level(at: time))
        }
    }

    func testItActuallyPulses() {
        let samples = stride(from: 0.0, to: 3.0, by: 0.01).map { SpeechPulse.level(at: $0) }
        XCTAssertGreaterThan(samples.max() ?? 0, 0.6, "a burst gets loud")
        XCTAssertLessThan(samples.min() ?? 1, 0.05, "and drops back between bursts")
    }

    func testEveryEighthBurstIsABreath() {
        XCTAssertNil(SpeechPulse.burst(7))
        XCTAssertNil(SpeechPulse.burst(15))
        XCTAssertNotNil(SpeechPulse.burst(6))
        // Burst 6 ends before 2.9 s and burst 8 starts after 3.3 s: a pause of about half a second.
        for time in [3.0, 3.1, 3.2] {
            XCTAssertEqual(SpeechPulse.level(at: time), 0, accuracy: 1e-9, "\(time)")
        }
    }

    func testBurstsAreNeverCloserThanAThirdOfASecond() {
        var previous: TimeInterval?
        for k in 0..<500 {
            guard let burst = SpeechPulse.burst(k) else { continue }
            if let previous {
                XCTAssertGreaterThanOrEqual(burst.onset - previous, 0.33, "burst \(k)")
            }
            previous = burst.onset
        }
    }

    // MARK: The spring

    func testTheSpringStartsAtFromAndEndsAtTo() {
        XCTAssertEqual(IslandSpring.value(from: 0, to: 1, elapsed: 0), 0)
        XCTAssertEqual(IslandSpring.value(from: 0, to: 1, elapsed: -1), 0)
        XCTAssertEqual(IslandSpring.value(from: 0, to: 1, elapsed: 5), 1, accuracy: 0.001)
        XCTAssertEqual(IslandSpring.value(from: 1, to: 0, elapsed: 5), 0, accuracy: 0.001)
    }

    func testTheDefaultSpringOvershootsABitThenSettles() {
        let peak = stride(from: 0.0, to: 1.5, by: 0.01).map { IslandSpring.value(from: 0, to: 1, elapsed: $0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 1.0, "it pops past the target")
        XCTAssertLessThan(peak, 1.25, "but only a little")
    }

    func testACriticallyDampedSpringNeverOvershoots() {
        for time in stride(from: 0.0, to: 3.0, by: 0.02) {
            let value = IslandSpring.value(from: 0, to: 1, elapsed: time, damping: 1)
            XCTAssertLessThanOrEqual(value, 1.0000001)
            XCTAssertGreaterThanOrEqual(value, 0)
        }
    }
}
