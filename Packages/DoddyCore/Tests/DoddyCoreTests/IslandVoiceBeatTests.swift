import XCTest
@testable import DoddyCore

/// ADR-670: the beat the Dynamic Island swells with while Doddy talks outside the app.
final class IslandVoiceBeatTests: XCTestCase {
    func testAPauseIsZeroAndHisLoudestIsTheTopStep() {
        XCTAssertEqual(IslandVoiceBeat.step(peak: 0), 0)
        XCTAssertEqual(IslandVoiceBeat.step(peak: 0.05), 0)
        XCTAssertEqual(IslandVoiceBeat.step(peak: 1), IslandVoiceBeat.maxStep)
        XCTAssertEqual(IslandVoiceBeat.step(peak: 2), IslandVoiceBeat.maxStep, "clamped")
    }

    func testANonsenseLevelIsAPause() {
        XCTAssertEqual(IslandVoiceBeat.step(peak: .nan), 0)
        XCTAssertEqual(IslandVoiceBeat.step(peak: -.infinity), 0)
        XCTAssertEqual(IslandVoiceBeat.step(peak: -0.5), 0)
    }

    func testLouderIsNeverASmallerStep() {
        var previous = 0
        for peak in stride(from: 0.0, through: 1.0, by: 0.01) {
            let step = IslandVoiceBeat.step(peak: peak)
            XCTAssertGreaterThanOrEqual(step, previous, "\(peak)")
            XCTAssertLessThanOrEqual(step, IslandVoiceBeat.maxStep)
            previous = step
        }
        XCTAssertEqual(previous, IslandVoiceBeat.maxStep)
    }

    func testEveryStepCanHappen() {
        let steps = Set(stride(from: 0.0, through: 1.0, by: 0.01).map { IslandVoiceBeat.step(peak: $0) })
        XCTAssertEqual(steps, Set(0...IslandVoiceBeat.maxStep))
    }

    func testAnEvenlyLoudSentenceStillMoves() {
        var beat = IslandVoiceBeat()
        let loud = (0..<10).map { _ in beat.next(peak: 1) }
        for (a, b) in zip(loud, loud.dropFirst()) {
            XCTAssertNotEqual(a, b, "two beats in a row are never the same while he is audible")
        }
        XCTAssertEqual(Set(loud), [IslandVoiceBeat.maxStep, IslandVoiceBeat.maxStep - 1])

        var middle = IslandVoiceBeat()
        let steady = (0..<6).map { _ in middle.next(peak: 0.4) }
        XCTAssertEqual(steady, [2, 3, 2, 3, 2, 3])
    }

    func testAPauseStaysStill() {
        var beat = IslandVoiceBeat()
        XCTAssertEqual((0..<4).map { _ in beat.next(peak: 0) }, [0, 0, 0, 0],
                       "between his words the island rests instead of flickering")
    }

    func testResetForgetsTheLastStep() {
        var beat = IslandVoiceBeat()
        XCTAssertEqual(beat.next(peak: 1), IslandVoiceBeat.maxStep)
        XCTAssertEqual(beat.last, IslandVoiceBeat.maxStep)
        beat.reset()
        XCTAssertNil(beat.last)
        XCTAssertEqual(beat.next(peak: 1), IslandVoiceBeat.maxStep, "a new sentence starts from his real level")
    }

    func testTheBeatIsNoFasterThanTheIslandsUpdatesMayGo() {
        // Each beat is one Live Activity update; `VoiceLiveActivity` keeps updates 0.5 s apart.
        XCTAssertGreaterThanOrEqual(IslandVoiceBeat.interval, 0.5)
        XCTAssertLessThanOrEqual(IslandVoiceBeat.interval, 1, "slower stops looking like a pulse")
    }

    // MARK: The made-up pulse's peak, for a voice with no audio track to measure

    func testThePeakOfAStretchIsItsLoudestMoment() {
        let start = 0.0, end = 0.6
        let peak = SpeechPulse.peak(from: start, to: end)
        for t in stride(from: start, through: end, by: 0.01) {
            XCTAssertGreaterThanOrEqual(peak + 0.03, SpeechPulse.level(at: t), "\(t)")
        }
        XCTAssertGreaterThan(peak, 0.5, "a stretch of 0.6 s holds at least one burst")
    }

    func testTheBreathGivesAQuietBeat() {
        // Burst 7 is the breath: nothing sounds between the end of burst 6 and the start of 8.
        XCTAssertEqual(SpeechPulse.peak(from: 3.0, to: 3.2), 0, accuracy: 1e-9)
    }

    func testTheMadeUpPulseGivesDifferentSteps() {
        var steps: Set<Int> = []
        var t = 0.0
        while t < 12 {
            steps.insert(IslandVoiceBeat.step(peak: SpeechPulse.peak(from: t, to: t + IslandVoiceBeat.interval)))
            t += IslandVoiceBeat.interval
        }
        XCTAssertGreaterThanOrEqual(steps.count, 2, "the island moves without an audio track too")
    }

    func testNoPeakForANonsenseStretch() {
        XCTAssertEqual(SpeechPulse.peak(from: 1, to: 0.5), 0)
        XCTAssertEqual(SpeechPulse.peak(from: .nan, to: 1), 0)
        XCTAssertEqual(SpeechPulse.peak(from: 0, to: .infinity), 0)
        XCTAssertEqual(SpeechPulse.peak(from: -5, to: -1), 0)
    }
}
