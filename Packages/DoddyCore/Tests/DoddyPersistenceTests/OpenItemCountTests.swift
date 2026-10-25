import DoddyCore
@testable import DoddyPersistence
import Foundation
import XCTest

/// ADR-652: the count on a list's place reminder is read from the real list items: only the ones
/// not ticked, only that list.
final class OpenItemCountTests: XCTestCase {
    func testOnlyOpenItemsOfThatListAreCounted() async throws {
        let database = try DoddyDatabase.inMemory()
        let lists = SQLiteListRepository(database: database)
        let reminders = SQLiteNoteReminderRepository(database: database)

        let shopping = try await lists.create(name: "Zakupy", items: ["mleko", "jajka", "chleb", "masło"], source: .voice)
        let other = try await lists.create(name: "Praca", items: ["raport"], source: .voice)
        let startCount = await reminders.openItemCount(listID: shopping.id)
        XCTAssertEqual(startCount, 4)

        _ = try await lists.setDone(shopping.items.prefix(3).map(\.id), done: true)
        let afterTicking = await reminders.openItemCount(listID: shopping.id)
        XCTAssertEqual(afterTicking, 1)
        let otherCount = await reminders.openItemCount(listID: other.id)
        XCTAssertEqual(otherCount, 1, "another list is not counted")

        _ = try await lists.setDone(shopping.items.map(\.id), done: true)
        let allDone = await reminders.openItemCount(listID: shopping.id)
        XCTAssertEqual(allDone, 0, "an empty count is 0, not unknown")
        let unknownList = await reminders.openItemCount(listID: UUID())
        XCTAssertEqual(unknownList, 0)
    }
}
