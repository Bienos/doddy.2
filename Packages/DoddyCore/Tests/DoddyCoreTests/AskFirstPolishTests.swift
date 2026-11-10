import Foundation
import XCTest
@testable import DoddyCore

/// The ask cards are drawn as they are, so with the app in Polish their words must be Polish
/// (owner, 9 Nov 2026: "ta aplikacja dalej pokazuje angielskie jakieś wyrazy"). The rule itself
/// (who asks, tap or yes) must not change with the language.
final class AskFirstPolishTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }

    private func card(_ need: AskFirst.Need) -> AskCard? {
        switch need {
        case .yesFirst(let card), .tapFirst(let card): card
        default: nil
        }
    }

    /// Requests whose card text is chosen in AskFirst (and its helpers), one per kind of card.
    private func requests() -> [VoiceToolRequest] {
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))!
        let list = ListVoiceRequest(list: "Zakupy", items: ["mleko"])
        return [
            .searchMemories(query: "klucze"),
            .readCalendar(VoiceTimeRange(start: day, end: day.addingTimeInterval(3600))),
            .lookupContact(name: "Ania"),
            .upcomingBirthdays(days: 7),
            .findPhotos(PhotoSearchRequest(firstDay: day, days: 3)!),
            .readSteps(StepDay(daysAgo: 1)!),
            .readHealthWeek,
            .listAlarms,
            .startStopwatch(label: nil),
            .stopStopwatch,
            .checkStopwatch,
            .startFocus(minutes: 25, label: nil),
            .stopFocus,
            .checkFocus,
            .startWindDown(minutes: 10),
            .stopWindDown,
            .readList(name: "Zakupy"),
            .parkingSpot(.find),
            .parkingSpot(.clear),
            .addToList(list),
            .checkOff(list),
            .removeFromList(list),
            .noteCapabilityGap(.sendMessage),
            .handOverErrand(ErrandDraft(words: "znajdź lot", brief: "Lot do Rzymu", title: "Rzym")),
            .checkErrands(about: nil),
        ]
    }

    func testTheNoteItCardIsPolish() {
        guard case .tapFirst(let card) = AskFirst.need(for: .noteCapabilityGap(.sendMessage), polish: true) else {
            return XCTFail("the capability-gap card still needs a tap")
        }
        XCTAssertEqual(card.title, "Zanotować, czego Doddy nie umie?")
        XCTAssertEqual(card.lines, ["Na tym iPhonie zostaje tylko temat: wysyłanie wiadomości"])
        XCTAssertEqual(card.confirmLabel, "Zanotuj")
    }

    func testEnglishStaysAsItWas() {
        guard case .tapFirst(let card) = AskFirst.need(for: .noteCapabilityGap(.sendMessage)) else { return XCTFail() }
        XCTAssertEqual(card.title, "Note that Doddy couldn't do this?")
        XCTAssertEqual(card.lines, ["Kept on this iPhone as a category only: send message"])
        XCTAssertEqual(card.confirmLabel, "Note it")
    }

    func testEveryCardChangesLanguageButNotHowItAsks() {
        for request in requests() {
            let english = AskFirst.need(for: request, calendar: calendar)
            let polish = AskFirst.need(for: request, calendar: calendar, polish: true)
            XCTAssertEqual(AskFirst.needsTap(english), AskFirst.needsTap(polish), "\(request)")
            guard let en = card(english), let pl = card(polish) else { return XCTFail("no card for \(request)") }
            XCTAssertNotEqual(en.title, pl.title, "\(request) has an English title in Polish")
            XCTAssertNotEqual(en.confirmLabel, pl.confirmLabel, "\(request) has an English button in Polish")
            XCTAssertEqual(en.lines.count, pl.lines.count, "\(request)")
        }
    }

    func testPolishCardsHaveNoEnglishWords() {
        let english = ["Yes", "Search", "Read", "Check", "Look", "Note", "Add", "Remove", "Tick", "Forget", "From ",
                       "Today", "Yesterday", "Kept on", "Your words", "Name:", "List:", "For:"]
        for request in requests() {
            guard let pl = card(AskFirst.need(for: request, calendar: calendar, polish: true)) else { return XCTFail() }
            let text = ([pl.title, pl.confirmLabel] + pl.lines).joined(separator: "\n")
            for word in english {
                XCTAssertFalse(text.contains(word), "“\(word)” in the Polish card for \(request): \(text)")
            }
        }
    }

    func testTheLeaveByAndPlanCardsArePolish() {
        let arrive = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 18))!
        let leave = LeaveByAsk.card(LeaveByRequest(place: "Dworzec", arriveBy: arrive, mode: .walking, bufferMinutes: 10), calendar: calendar, polish: true)
        XCTAssertEqual(leave.title, "Obliczyć, kiedy wyjść?")
        XCTAssertEqual(leave.lines[0], "Dokąd: Dworzec")
        XCTAssertEqual(leave.lines[2], "Pieszo, z zapasem 10 min")
        XCTAssertEqual(leave.confirmLabel, "Oblicz")

        let plan = PlanAsk(goal: .firstFiveK, daysPerWeek: 3, minutesPerSession: 30)
        XCTAssertEqual(plan.cardLines(polish: true), ["Cel: Pierwsze 5 km", "Dni w tygodniu: 3, 30 min na trening", "Na pytania o bezpieczeństwo odpowiesz na ekranie."])
        XCTAssertEqual(plan.cardLines, ["Goal: First 5 km", "3 days a week, 30 min a session", "You answer the safety questions yourself, on screen."])
    }
}
