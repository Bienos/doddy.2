import XCTest
@testable import DoddyCore

/// ElevenLabs is the only voice (9 Nov 2026). Conversations kept before then may name OpenAI; they must load.
final class ConversationLogProviderTests: XCTestCase {
    func testOldConversationLogsStillLoad() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","startedAt":0,"endedAt":1,"lines":[{"fromUser":true,"text":"hi"}]}"#
        let log = try JSONDecoder().decode(ConversationLog.self, from: Data(old.utf8))
        XCTAssertNil(log.voiceProvider)
        let tagged = ConversationLog(startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 1), lines: [], voiceProvider: "openai")
        XCTAssertEqual(try JSONDecoder().decode(ConversationLog.self, from: JSONEncoder().encode(tagged)).voiceProvider, "openai")
    }

    func testTheHistoryNamesTheVoiceThatRanTheConversation() {
        func log(_ voice: String?) -> ConversationLog {
            ConversationLog(startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 1), lines: [], voiceProvider: voice)
        }
        XCTAssertNil(log(nil).voiceName)
        XCTAssertEqual(log("elevenlabs").voiceName, "ElevenLabs")
        XCTAssertEqual(log("openai").voiceName, "OpenAI", "a conversation kept from before 9 Nov 2026 is still named truthfully")
    }
}
