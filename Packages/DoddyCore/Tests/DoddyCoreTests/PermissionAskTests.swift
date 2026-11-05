import Foundation
import XCTest
@testable import DoddyCore

/// "Let Doddy use Calendar?" (ADR-566): which sheet, when it may show, and what the agent hears.
final class PermissionAskTests: XCTestCase {
    func testKind() {
        XCTAssertEqual(PermissionAsk.kind(iosRefused: false), .turnOn)
        XCTAssertEqual(PermissionAsk.kind(iosRefused: true), .openSettings, "a tap in Doddy can't undo iOS's no")
    }

    func testOneSheetAtATimeAndNoNagging() {
        XCTAssertTrue(PermissionAsk.mayAsk(.calendar, declined: [], sheetShowing: false))
        XCTAssertFalse(PermissionAsk.mayAsk(.calendar, declined: [], sheetShowing: true))
        XCTAssertFalse(PermissionAsk.mayAsk(.calendar, declined: [.calendar], sheetShowing: false))
        XCTAssertTrue(PermissionAsk.mayAsk(.contacts, declined: [.calendar], sheetShowing: false), "only the one the user said no to")
    }

    func testTheReasonIsWhatDoddyWasAskedToDo() {
        XCTAssertEqual(PermissionAsk.reason(.lookupContact(name: "Marta")), "Looked for a contact: “Marta”")
        XCTAssertEqual(PermissionAsk.reason(.readSteps(StepDay(daysAgo: 0)!)), "Read steps: Today")
        XCTAssertNil(PermissionAsk.reason(.undoLast))
    }

    func testEveryAnswerSaysNothingWasReadOrChanged() {
        for connection in VoiceConnection.allCases {
            for reply in [PermissionAsk.declined(connection), PermissionAsk.blocked(connection), PermissionAsk.declinedEarlier(connection)] {
                XCTAssertTrue(reply.hasPrefix("not allowed: "), reply)
                XCTAssertTrue(reply.contains("nothing was read or changed"), reply)
                XCTAssertTrue(reply.contains(connection.title), reply)
            }
        }
    }

    func testEveryConnectionHasATitle() {
        XCTAssertEqual(VoiceConnection.presentations.title, "Presentations")
        XCTAssertEqual(VoiceConnection.steps.title, "Steps")
        XCTAssertEqual(Set(VoiceConnection.allCases.map(\.preferenceKey)).count, VoiceConnection.allCases.count)
    }
}
