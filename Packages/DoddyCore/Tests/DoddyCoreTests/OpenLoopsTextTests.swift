import DoddyCore
import XCTest

final class OpenLoopsTextTests: XCTestCase {
    private let languages: [NotificationLanguage] = [.polish, .english]

    private var everyStatus: [OpenLoopStatus] {
        let price = Money(minor: 28_900)
        let target = Money(minor: 30_000)
        var all: [OpenLoopStatus] = [
            .overdue, .dueToday(hasTime: true), .dueToday(hasTime: false), .scheduled, .noDate,
            .atPlace("Post office"), .nudgeSet(leadMinutes: 30), .nudgeAtOldTime, .queued, .running, .finished, .failed,
            .watching(lastPrice: price, threshold: target), .watching(lastPrice: nil, threshold: target),
            .priceReached(price), .priceReached(nil), .cannotConfirm,
        ]
        all += ReminderRepeat.allCases.map { .repeating($0) }
        all += [ParcelStatusKind.preparing, .inTransit, .readyForPickup, .delivered, .problem, .returned, .unknown].map { .parcel($0) }
        return all
    }

    func testEveryStatusHasAPlainSentenceInBothLanguages() {
        for status in everyStatus {
            for language in languages {
                let text = OpenLoopsText.status(status, language)
                XCTAssertFalse(text.isEmpty, "\(status) \(language)")
                XCTAssertFalse(text.contains("!"), "no exclamation marks: \(text)")
                XCTAssertFalse(text.contains("…"), "no trailing promise: \(text)")
            }
            XCTAssertNotEqual(OpenLoopsText.status(status, .polish), OpenLoopsText.status(status, .english), "\(status)")
        }
    }

    func testWatchingNamesThePersonsOwnPriceAndTheLastPriceTheServerConfirmed() {
        let line = OpenLoopsText.status(.watching(lastPrice: Money(minor: 34_900), threshold: Money(minor: 30_000)), .english)
        XCTAssertEqual(line, "Last seen: PLN 349.00. Your price: PLN 300.00")
        let waiting = OpenLoopsText.status(.watching(lastPrice: nil, threshold: Money(minor: 30_000)), .english)
        XCTAssertFalse(waiting.contains("Last seen"), "no price is claimed before one was confirmed")
    }

    func testUnknownIsNeverWordedAsSuccessOrActive() {
        for language in languages {
            let text = OpenLoopsText.status(.cannotConfirm, language).lowercased()
            for word in ["done", "gotowe", "active", "aktywn", "delivered", "dostarczon"] {
                XCTAssertFalse(text.contains(word), "\(word) in \(text)")
            }
        }
    }

    func testAHiddenTitleFallsBackToTheSourcesGenericName() {
        let item = OpenLoopItem(source: .noteReminder, sourceID: "x", title: .hidden, section: .today, status: .overdue, when: nil)
        XCTAssertEqual(OpenLoopsText.title(item, .polish), "Przypomnienie o notatce")
        XCTAssertEqual(OpenLoopsText.title(item, .english), "Note reminder")
        let named = OpenLoopItem(source: .errand, sourceID: "y", title: .text("Flights to Lisbon"), section: .today, status: .finished, when: nil)
        XCTAssertEqual(OpenLoopsText.title(named, .polish), "Flights to Lisbon", "the person's own words are kept exactly")
    }

    func testEverySectionAndSourceHasWordsAndAnUnreadableSourceIsNeverSaidToBeEmpty() {
        for language in languages {
            for section in OpenLoopSection.allCases { XCTAssertFalse(OpenLoopsText.sectionTitle(section, language).isEmpty) }
            for source in OpenLoopSource.allCases {
                XCTAssertFalse(OpenLoopsText.sourceName(source, language).isEmpty)
                let line = OpenLoopsText.unavailableLine(source, language).lowercased()
                XCTAssertTrue(line.contains("odczytać") || line.contains("can't read"), line)
                XCTAssertFalse(line.contains("nic") || line.contains("nothing"), line)
            }
            XCTAssertFalse(OpenLoopsText.screenTitle(language).isEmpty)
            XCTAssertFalse(OpenLoopsText.emptyLine(language).isEmpty)
            XCTAssertTrue(OpenLoopsText.moreLine(3, language).contains("3"))
        }
    }
}
