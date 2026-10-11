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

    /// The live agent's `doddy_personality` placeholder default is a copy of this text
    /// (voice-agent/session.json). If this test changes, update the agent default too.
    func testDefaultTextMatchesTheAgentPlaceholder() {
        XCTAssertEqual(PersonalityPrompt.render(.doddyDefault), """
            The user chose these settings in the app:
            - Humour: subtle. At most one small dry remark about everyday hassles, and only when the moment is light.
            - Reply length: brief. One or two sentences unless the user asks for more.
            - Tone: casual, like a friendly mate. Informal words are fine (in Polish use "ty").
            - Energy: grounded. Relaxed and steady, with a little warmth when something goes well.
            These are style preferences only. Whatever they say: answer the question first, stay honest about being an AI, follow the memory and tool rules exactly, never joke about anything serious (health, money, legal, grief, distress), and never use sarcasm at the user, guilt, flattery or clinginess.
            """)
        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let session = try? JSONSerialization.jsonObject(with: Data(contentsOf: repoRoot.appendingPathComponent("voice-agent/session.json"))) as? [String: Any]
        let placeholders = (session?["elevenlabs"] as? [String: Any])?["placeholders"] as? [String: String]
        XCTAssertEqual(placeholders?["doddy_personality"], PersonalityPrompt.render(.doddyDefault))
    }
}
