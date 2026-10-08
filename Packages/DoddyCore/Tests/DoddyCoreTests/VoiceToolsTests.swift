import XCTest
@testable import DoddyCore

final class VoiceToolsTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(VoiceToolRequest.parse(name: "search_memories", parametersJSON: Data(#"{"query":"klucze"}"#.utf8)), .searchMemories(query: "klucze"))
        XCTAssertEqual(VoiceToolRequest.parse(name: "save_memory", parametersJSON: Data(#"{"text":"Keys in the tin"}"#.utf8)), .saveMemory(text: "Keys in the tin"))
        XCTAssertEqual(VoiceToolRequest.parse(name: "save_memory", parametersJSON: Data(#"{"text":"  "}"#.utf8)), .invalid(name: "save_memory", reason: "missing text"))
        XCTAssertEqual(VoiceToolRequest.parse(name: "send_sms", parametersJSON: Data("{}".utf8)), .unsupported(name: "send_sms"))
        XCTAssertEqual(VoiceToolRequest.parse(name: "search_memories", parametersJSON: Data("not json".utf8)), .invalid(name: "search_memories", reason: "missing query"))
    }

    func testSearchReplyOnlyStatesStoredText() throws {
        XCTAssertTrue(VoiceToolReply.search(.noMatch).hasPrefix("No saved note matched"))
        let record = try MemoryRecord(id: UUID(), rawText: "Klucze są w niebieskiej puszce", source: .explicitText, capturedAt: Date(timeIntervalSince1970: 0))
        let reply = VoiceToolReply.search(.matches([MemoryCandidate(record: record, matchedTerms: ["klucze"])]))
        XCTAssertTrue(reply.contains("\"Klucze są w niebieskiej puszce\""))
        XCTAssertTrue(reply.hasPrefix("Found 1 saved note "))
    }
}
