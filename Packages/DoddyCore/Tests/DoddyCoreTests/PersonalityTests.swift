import XCTest
@testable import DoddyCore

final class PersonalityTests: XCTestCase {
    func testDefaultsMatchPersonaDraft() {
        // doddy_persona_v1.yaml: humor_level subtle, verbosity brief, formality casual; energy grounded.
        XCTAssertEqual(PersonalitySettings.doddyDefault, PersonalitySettings(humour: .subtle, length: .brief, formality: .casual, mood: .grounded))
    }

    func testStoredValuesFallBackPerSetting() {
        let parsed = PersonalitySettings(humour: "off", length: "nonsense", formality: nil, mood: "lively")
        XCTAssertEqual(parsed, PersonalitySettings(humour: .off, length: .brief, formality: .casual, mood: .lively))
        XCTAssertEqual(PersonalitySettings(humour: nil, length: nil, formality: nil, mood: nil), .doddyDefault)
    }

    func testRenderNamesEveryChoiceAndKeepsRules() {
        for humour in HumourLevel.allCases {
            for length in ReplyLength.allCases {
                for formality in Formality.allCases {
                    for mood in Mood.allCases {
                        let text = PersonalityPrompt.render(PersonalitySettings(humour: humour, length: length, formality: formality, mood: mood))
                        XCTAssertTrue(text.contains("- Humour: " + PersonalityPrompt.humour(humour)))
                        XCTAssertTrue(text.contains("- Reply length: " + PersonalityPrompt.length(length)))
                        XCTAssertTrue(text.contains("- Tone: " + PersonalityPrompt.formality(formality)))
                        XCTAssertTrue(text.contains("- Energy: " + PersonalityPrompt.mood(mood)))
                        XCTAssertTrue(text.hasSuffix(PersonalityPrompt.unchangedRules))
                    }
                }
            }
        }
    }

    func testHumourOffSaysNoJokes() {
        let text = PersonalityPrompt.render(.focused)
        XCTAssertTrue(text.contains("No jokes"))
        XCTAssertFalse(text.contains("playful."))
    }

    func testOptionsAreDistinct() {
        XCTAssertEqual(Set(HumourLevel.allCases.map(PersonalityPrompt.humour)).count, HumourLevel.allCases.count)
        XCTAssertEqual(Set(ReplyLength.allCases.map(PersonalityPrompt.length)).count, ReplyLength.allCases.count)
        XCTAssertEqual(Set(Formality.allCases.map(PersonalityPrompt.formality)).count, Formality.allCases.count)
        XCTAssertEqual(Set(Mood.allCases.map(PersonalityPrompt.mood)).count, Mood.allCases.count)
    }
}
