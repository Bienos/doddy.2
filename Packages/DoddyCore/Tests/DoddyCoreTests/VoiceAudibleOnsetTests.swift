import XCTest
@testable import DoddyCore

/// The first sound of Doddy's voice after a press (decision `2026-11-14-first-audible-sound`). Buffers here
/// are 10 ms long, like the ones the voice track hands the meter; every time is a reading of one monotonic
/// clock in seconds.
final class VoiceAudibleOnsetTests: XCTestCase {
    private let buffer = 0.01
    private let silence = 0.0
    private let speech = 0.8

    /// Feeds `count` buffers of the same level, one after another from `start`, and returns the first result found.
    @discardableResult
    private func feed(_ onset: inout VoiceAudibleOnset, level: Double, count: Int, from start: Double) -> VoiceAudibleOnset.Result? {
        var found: VoiceAudibleOnset.Result?
        for index in 0..<count {
            if let result = onset.push(level: level, seconds: buffer, at: start + Double(index) * buffer) { found = found ?? result }
        }
        return found
    }

    func testSilenceThenSpeechGivesTheDelayToTheFirstBufferOfSound() {
        var onset = VoiceAudibleOnset()
        onset.begin(at: 100)
        XCTAssertNil(feed(&onset, level: silence, count: 70, from: 100.5))
        let found = feed(&onset, level: speech, count: 10, from: 101.2)
        XCTAssertEqual(found?.sound ?? -1, 1.2, accuracy: 0.0001, "timed to where the sound began, not to where it was confirmed")
        XCTAssertEqual(found?.listeningFrom ?? -1, 0.5, accuracy: 0.0001, "the first buffer the meter saw")
        XCTAssertEqual(onset.result, found)
    }

    func testTheResultComesOnceAndLaterBuffersChangeNothing() {
        var onset = VoiceAudibleOnset()
        onset.begin(at: 0)
        let first = feed(&onset, level: speech, count: 10, from: 2)
        XCTAssertNotNil(first)
        XCTAssertNil(onset.push(level: speech, seconds: buffer, at: 3))
        XCTAssertNil(onset.push(level: silence, seconds: buffer, at: 3.01))
        XCTAssertEqual(onset.result, first)
    }

    func testAClickShorterThanTheSustainIsNotSound() {
        var onset = VoiceAudibleOnset()
        onset.begin(at: 0)
        XCTAssertNil(feed(&onset, level: speech, count: 3, from: 0.5), "30 ms of sound is under the 40 ms it must last")
        XCTAssertNil(feed(&onset, level: silence, count: 5, from: 0.53))
        XCTAssertNil(onset.result)
        let found = feed(&onset, level: speech, count: 4, from: 1.0)
        XCTAssertEqual(found?.sound ?? -1, 1.0, accuracy: 0.0001, "the run that lasted is timed from its own first buffer")
    }

    func testAQuietBufferBreaksTheRunSoTheLoudTimeIsNotAddedUp() {
        var onset = VoiceAudibleOnset()
        onset.begin(at: 0)
        XCTAssertNil(feed(&onset, level: speech, count: 2, from: 1.00))
        XCTAssertNil(feed(&onset, level: silence, count: 1, from: 1.02))
        XCTAssertNil(feed(&onset, level: speech, count: 2, from: 1.03))
        XCTAssertNil(onset.result, "two buffers, a gap, two buffers: never 40 ms in a row")
    }

    func testTheThresholdItselfCountsAsSound() {
        var onset = VoiceAudibleOnset()
        onset.begin(at: 0)
        XCTAssertNotNil(feed(&onset, level: VoiceAudibleOnset.defaultThreshold, count: 4, from: 1))
        var below = VoiceAudibleOnset()
        below.begin(at: 0)
        XCTAssertNil(feed(&below, level: VoiceAudibleOnset.defaultThreshold - 0.001, count: 50, from: 1))
    }

    func testTenMillisecondBuffersAddUpToTheSustainDespiteRounding() {
        // Ten buffers of 0.01 add up to 0.09999999999999999 in floating point, not 0.1.
        var onset = VoiceAudibleOnset(sustain: 0.1)
        onset.begin(at: 0)
        XCTAssertNotNil(feed(&onset, level: speech, count: 10, from: 1), "ten buffers of 10 ms are 100 ms")
        var short = VoiceAudibleOnset(sustain: 0.1)
        short.begin(at: 0)
        XCTAssertNil(feed(&short, level: speech, count: 9, from: 1), "nine are not")
    }

    func testTheThresholdSitsBetweenTheNoiseFloorAndSpeech() {
        // RMS of samples scaled to -1...1: conversational speech is about -25 dB, a decoded line's hiss -65 dB.
        let speechLevel = VoiceLevel.level(rms: pow(10, -25.0 / 20))
        let noiseLevel = VoiceLevel.level(rms: pow(10, -65.0 / 20))
        XCTAssertGreaterThan(speechLevel, VoiceAudibleOnset.defaultThreshold)
        XCTAssertLessThan(noiseLevel, VoiceAudibleOnset.defaultThreshold)
    }

    func testNothingIsMeasuredWithoutAPress() {
        var onset = VoiceAudibleOnset()
        XCTAssertNil(feed(&onset, level: speech, count: 20, from: 5))
        XCTAssertNil(onset.result)
        XCTAssertFalse(onset.isWatching)
    }

    func testAPressStartsOverAndForgetsTheLastResult() {
        var onset = VoiceAudibleOnset()
        onset.begin(at: 0)
        XCTAssertNotNil(feed(&onset, level: speech, count: 5, from: 2))
        XCTAssertFalse(onset.isWatching, "found: nothing more to watch for")
        onset.begin(at: 50)
        XCTAssertNil(onset.result)
        XCTAssertTrue(onset.isWatching)
        let found = feed(&onset, level: speech, count: 5, from: 53)
        XCTAssertEqual(found?.sound ?? -1, 3, accuracy: 0.0001)
        XCTAssertEqual(found?.listeningFrom ?? -1, 3, accuracy: 0.0001, "the first buffer was already sound: no earlier than this")
    }

    func testAPressThatNeverGotAConversationExpiresInsteadOfTimingTheNextOne() {
        var onset = VoiceAudibleOnset()
        onset.begin(at: 0)
        XCTAssertNil(feed(&onset, level: speech, count: 10, from: VoiceAudibleOnset.maxWait + 5), "a minute after the press is not that press's sound")
        XCTAssertNil(onset.result)
        XCTAssertFalse(onset.isWatching, "the old mark is dropped, so a later start with no press of its own isn't timed from it")
        XCTAssertNil(feed(&onset, level: speech, count: 10, from: VoiceAudibleOnset.maxWait + 6))
    }

    func testResetStopsWatching() {
        var onset = VoiceAudibleOnset()
        onset.begin(at: 0)
        onset.reset()
        XCTAssertFalse(onset.isWatching)
        XCTAssertNil(feed(&onset, level: speech, count: 10, from: 1))
    }

    func testBrokenInputIsIgnoredAndNeverGivesANegativeOrNaNDelay() {
        var onset = VoiceAudibleOnset()
        onset.begin(at: 10)
        XCTAssertNil(onset.push(level: speech, seconds: 0, at: 11), "a buffer with no length")
        XCTAssertNil(onset.push(level: speech, seconds: -1, at: 11))
        XCTAssertNil(onset.push(level: speech, seconds: .nan, at: 11))
        XCTAssertNil(onset.push(level: speech, seconds: buffer, at: .infinity))
        XCTAssertNil(onset.push(level: .nan, seconds: buffer, at: 11), "a level that isn't a number is not sound")
        XCTAssertNil(onset.result)
        // A clock that reads before the press: the delay is 0, never negative.
        var early = VoiceAudibleOnset()
        early.begin(at: 10)
        let found = feed(&early, level: speech, count: 5, from: 9)
        XCTAssertEqual(found?.sound, 0)
        XCTAssertEqual(found?.listeningFrom, 0)
        var broken = VoiceAudibleOnset()
        broken.begin(at: .nan)
        XCTAssertFalse(broken.isWatching, "a press with no readable time isn't timed")
    }

    func testTheLineHasOnlyFixedWordsAndSeconds() {
        let result = VoiceAudibleOnset.Result(sound: 2.84, listeningFrom: 2.79)
        XCTAssertEqual(result.line(), "first sound 2.84 s · listening from 2.79 s")
        XCTAssertEqual(result.line(outputLatency: 0.052), "first sound 2.84 s · listening from 2.79 s · output latency 0.05 s")
        XCTAssertEqual(result.line(outputLatency: .nan), "first sound 2.84 s · listening from 2.79 s", "an unreadable latency is left out, not written as 0")
        XCTAssertEqual(result.line(outputLatency: -0.2), "first sound 2.84 s · listening from 2.79 s · output latency 0.00 s")
    }
}
