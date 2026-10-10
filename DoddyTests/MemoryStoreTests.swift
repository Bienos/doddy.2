import XCTest
import DoddyCore
@testable import Doddy

/// App-target tests. NOT RUN in the authoring environment (no Xcode); see BUILD_AND_TEST.md.
@MainActor
final class MemoryStoreTests: XCTestCase {
    func testSaveKeepsTheCallersSource() async throws {
        let store = MemoryStore(environment: .live(arguments: ["-inMemoryStore"]))
        let voice = try await store.save(text: "Car is on parking level 3.", category: .other, source: .explicitVoice)
        let typed = try await store.save(text: "Dentist on Friday.", category: .commitment, source: .explicitText)
        XCTAssertEqual(store.record(id: voice.id)?.source, .explicitVoice)
        XCTAssertEqual(store.record(id: typed.id)?.source, .explicitText)
    }
}
