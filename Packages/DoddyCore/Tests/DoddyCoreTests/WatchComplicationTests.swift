import DoddyCore
import XCTest

/// Watch complications and the Smart Stack (ADR-262): only times, counts and list names.
final class WatchComplicationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(isOn: Bool = true, reminderIn: [TimeInterval] = [1800, 7200]) -> WidgetSnapshot {
        WidgetSnapshot(
            writtenAt: now, isOn: isOn,
            pinned: [.init(id: UUID(), text: "Locker code 4512")],
            reminders: reminderIn.map { .init(memoryID: UUID(), fireAt: now.addingTimeInterval($0), timeZoneID: "Europe/Warsaw", text: "Call the dentist") },
            lists: [
                .init(id: UUID(), name: "Hardware", openCount: 1, doneCount: 0, items: []),
                .init(id: UUID(), name: "Shopping", openCount: 4, doneCount: 2, items: []),
            ])
    }

    func testOnlyTimesCountsAndListNamesAreShown() {
        let content = ComplicationContent.make(snapshot(), at: now)
        XCTAssertEqual(content.state, .ready)
        XCTAssertEqual(content.nextReminder, now.addingTimeInterval(1800))
        XCTAssertEqual(content.openItems, 5)
        XCTAssertEqual(content.topList, .init(name: "Shopping", openCount: 4))
        // The content type has no field that could carry a note's or reminder's words.
        XCTAssertFalse(String(describing: content).contains("dentist"))
        XCTAssertFalse(String(describing: content).contains("4512"))
    }

    func testNothingIsShownWhenOffOrNotReady() {
        XCTAssertEqual(ComplicationContent.make(nil, at: now).state, .notReady)
        let off = ComplicationContent.make(snapshot(isOn: false), at: now)
        XCTAssertEqual(off.state, .off)
        XCTAssertNil(off.topList)
        XCTAssertEqual(off.relevance(at: now), 0)
    }

    func testTheSmartStackWantsItInTheHourBeforeAReminder() {
        let content = ComplicationContent.make(snapshot(reminderIn: [1800]), at: now)
        XCTAssertEqual(content.relevance(at: now), 0.75, accuracy: 0.001)
        let later = ComplicationContent.make(snapshot(reminderIn: [10_800]), at: now)
        XCTAssertEqual(later.relevance(at: now), 0.1, accuracy: 0.001)
    }

    func testTimelineHasEntriesBeforeAndAfterEachReminder() {
        let dates = ComplicationContent.timelineDates(snapshot(reminderIn: [1800, 7200]), from: now)
        XCTAssertEqual(dates, [now, now.addingTimeInterval(1801), now.addingTimeInterval(3600), now.addingTimeInterval(7201)])
    }
}

/// Adding to a list from the watch (ADR-287).
final class WatchListAddTests: XCTestCase {
    func testTheRequestRoundTripsAndTheItemIsCheckedOnTheWatch() throws {
        let list = UUID()
        let request = WatchRequest.addToList(listID: list, text: "oat milk")
        XCTAssertEqual(WatchRequest.decoded(try request.encoded()), request)
        XCTAssertNil(WatchNote.itemProblem("oat milk"))
        XCTAssertNotNil(WatchNote.itemProblem("   "))
        XCTAssertNotNil(WatchNote.itemProblem(String(repeating: "x", count: 201)))
        XCTAssertEqual(WatchReply.decoded(try WatchReply.addedToList("oat milk").encoded()), .addedToList("oat milk"))
        XCTAssertEqual(WatchReply.alreadyOnList("milk").message, "“milk” is already on the list. Nothing added.")
    }
}

final class WatchCaptureLinkTests: XCTestCase {
    func testOnlyTheNewNoteLinkOpensTheNoteScreen() throws {
        XCTAssertTrue(WatchCaptureLink.isNewNote(WatchCaptureLink.url))
        for other in ["doddy://home", "doddy://watch", "doddy://watch/new-note/extra", "doddy://open/new-note", "https://watch/new-note"] {
            XCTAssertFalse(WatchCaptureLink.isNewNote(try XCTUnwrap(URL(string: other))), other)
        }
    }
}
