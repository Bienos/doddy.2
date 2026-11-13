import Foundation
import XCTest
@testable import DoddyCore

/// Before the first voice conversation the person is to agree that voice conversations are kept until they delete them
/// (owner, 13 Nov 2026, decision 2026-11-12-voice-conversations-per-account). The words are the owner's and a lawyer's
/// and don't exist yet, so only the mechanism is here, and it is off: with no version of the words there is nothing to
/// ask, and nothing is asked.
final class VoiceConsentTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "VoiceConsentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        // The teardown closure is Sendable: it carries only the suite's name (a String) and opens the suite itself.
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return defaults
    }

    // MARK: Off by default

    func testThereAreNoWordsYetSoNothingIsRequired() {
        XCTAssertNil(VoiceConsent.requiredVersion, "set only when the owner and a lawyer have written the words")
        for state in [VoiceConsent.State.notGiven, .given(version: 1), .given(version: 7)] {
            XCTAssertEqual(VoiceConsent.requirement(state: state), .notRequired, "\(state)")
        }
        XCTAssertFalse(VoiceConsent.requirement(state: .notGiven).blocksStart)
    }

    // MARK: The mechanism, for when there are words

    func testWithWordsItIsNeededUntilGiven() {
        XCTAssertEqual(VoiceConsent.requirement(state: .notGiven, requiredVersion: 1), .needed)
        XCTAssertTrue(VoiceConsent.requirement(state: .notGiven, requiredVersion: 1).blocksStart)
        XCTAssertEqual(VoiceConsent.requirement(state: .given(version: 1), requiredVersion: 1), .satisfied)
        XCTAssertFalse(VoiceConsent.requirement(state: .given(version: 1), requiredVersion: 1).blocksStart)
    }

    func testNewWordsAskAgainAndOlderOrNewerGivenVersionsAreCompared() {
        XCTAssertEqual(VoiceConsent.requirement(state: .given(version: 1), requiredVersion: 2), .needed, "the words changed")
        XCTAssertEqual(VoiceConsent.requirement(state: .given(version: 2), requiredVersion: 2), .satisfied)
        XCTAssertEqual(VoiceConsent.requirement(state: .given(version: 3), requiredVersion: 2), .satisfied, "a newer yes still counts")
    }

    func testAStoredVersionBecomesAState() {
        XCTAssertEqual(VoiceConsent.state(storedVersion: 0), .notGiven)
        XCTAssertEqual(VoiceConsent.state(storedVersion: -4), .notGiven)
        XCTAssertEqual(VoiceConsent.state(storedVersion: 1), .given(version: 1))
    }

    // MARK: Kept on this iPhone

    func testNothingIsStoredUntilItIsGiven() {
        XCTAssertEqual(VoiceConsent.stored(in: defaults()), .notGiven)
    }

    func testGivingIsKeptWithTheVersionAndWithdrawingRemovesIt() {
        let defaults = defaults()
        VoiceConsent.record(version: 2, in: defaults)
        XCTAssertEqual(VoiceConsent.stored(in: defaults), .given(version: 2))
        VoiceConsent.withdraw(in: defaults)
        XCTAssertEqual(VoiceConsent.stored(in: defaults), .notGiven)
        XCTAssertNil(defaults.object(forKey: VoiceConsent.preferenceKey), "nothing is left behind")
    }

    func testAVersionBelowOneIsNotRecordedAsAYes() {
        let defaults = defaults()
        VoiceConsent.record(version: 0, in: defaults)
        VoiceConsent.record(version: -1, in: defaults)
        XCTAssertEqual(VoiceConsent.stored(in: defaults), .notGiven)
    }

    func testAnOlderYesNeverReplacesANewerOne() {
        let defaults = defaults()
        VoiceConsent.record(version: 3, in: defaults)
        VoiceConsent.record(version: 2, in: defaults)
        XCTAssertEqual(VoiceConsent.stored(in: defaults), .given(version: 3))
    }

    func testTheKeyIsItsOwn() {
        XCTAssertEqual(VoiceConsent.preferenceKey, "voice.conversationsKeptConsentVersion")
        XCTAssertNotEqual(VoiceConsent.preferenceKey, "voice.providerConsent.elevenlabs.v1", "not the voice data notice's yes")
    }
}
