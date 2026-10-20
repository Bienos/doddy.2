import XCTest
@testable import DoddyCore

/// The action status model (ADR-319 to ADR-322) and voice session recovery (ADR-360) in Polish:
/// every fixed text Doddy writes for them has Polish, and the user's own words stay as kept.
final class ActionStatusTextTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_630_000)

    func testEveryStatusHasPolishAndEnglishIsUnchanged() {
        for status in ActionStatus.allCases {
            XCTAssertEqual(status.text(.english), status.text)
            XCTAssertNotEqual(status.text(.polish), status.text, "\(status)")
        }
        XCTAssertEqual(ActionStatus.unknown.text(.polish), "Nie wiadomo, czy się udało")
    }

    func testEveryNoteTheSettlingWritesHasPolish() throws {
        // Notes and lists settled from Doddy's own database (ADR-321), as LocalCheck writes them.
        let checks: [ActivityCheck] = [
            .note(key: "n1-x"), .listAdd(list: "Zakupy", items: ["mleko"]), .listTick(list: "Zakupy", items: ["mleko"]),
            .listRemove(list: "Zakupy", items: ["mleko"]), .listCreate(name: "Wyjazd"),
        ]
        for check in checks {
            for found in [true, false] {
                let english = found ? "Found in \(check.place) when Doddy checked." : "Not in \(check.place) when Doddy checked, so it didn't happen. You can ask again."
                let polish = ActivityText.note(english, .polish)
                XCTAssertNotEqual(polish, english, english)
                XCTAssertEqual(ActivityText.note(english, .english), english)
            }
        }
        XCTAssertEqual(ActivityText.note("Found in the list “Zakupy” when Doddy checked.", .polish), "Znalezione na liście „Zakupy” przy sprawdzaniu.", "the list name stays as written")
    }

    func testTheThreeTryStopNoteHasPolishForEveryApp() {
        for app in ActivityApp.allCases {
            let reply = VoiceToolReply.retryStopped(count: 3, app: app)
            let note = try? XCTUnwrap(ActivityEntry.outcome(of: reply, isLookup: false).1)
            let polish = ActivityText.note(note ?? "", .polish)
            XCTAssertTrue(polish.hasPrefix("Doddy próbował tego 3 razy"), "\(app): \(polish)")
            XCTAssertTrue(polish.contains(app.title(.polish)))
        }
    }

    func testReceiptsTranslateDoddysLabelsAndKeepWhatWasReadBack() {
        let list = ActivityReceipt(list: "Zakupy", listID: UUID(), lines: ["Added: mleko", "Already on the list: jajka"], readAt: t0)
        XCTAssertEqual(list.lines(.polish), ["Lista: Zakupy", "Dodano: mleko", "Już na liście: jajka"])
        XCTAssertEqual(list.lines(.english), list.lines)
        XCTAssertEqual(list.heading(.polish, time: "10:02"), "Odczytane z: Notatki, 10:02")
        XCTAssertEqual(list.heading(.english, time: "10:02"), "Read back from Notes at 10:02")

        let cloud = ActivityReceipt(app: .todoist, externalID: "t1", lines: ["Todoist task added. Answer from the first try; nothing ran again."], readAt: t0)
        XCTAssertEqual(cloud.lines(.polish), ["Dodano zadanie w Todoist. Odpowiedź z pierwszej próby; nic nie uruchomiono ponownie."])
        // A title that happens to start like a label is the user's, but only the label is changed.
        let note = ActivityReceipt(app: .memories, externalID: nil, lines: ["“Removed: the old shelf”"], readAt: t0)
        XCTAssertEqual(note.lines(.polish), ["“Removed: the old shelf”"], "quoted words are never relabelled")
    }

    func testHistoryReadsInPolish() {
        let request = ActivityRequest.describe(.saveMemory(text: "Kod do bramy 4821"), calendar: .current)!
        let entry = ActivityLog.recoverInterrupted([ActivityEntry.started(request, at: t0)], at: t0 + 60)[0]
        let time: (Date) -> String = { $0 == self.t0 ? "10:00" : "10:01" }
        XCTAssertEqual(entry.historyText(.polish, time: time), "W toku 10:00 → Nie wiadomo, czy się udało 10:01")
        XCTAssertEqual(entry.historyText(.english, time: time), "In progress 10:00 → Not sure it happened 10:01")
    }

    func testPlanBlocksHavePolish() {
        XCTAssertEqual(PlanBlock.tooManyTries(app: .reminders, count: 3).screenText(.polish),
                       "Próbowano 3 razy w ciągu doby bez potwierdzenia. Najpierw sprawdź: Przypomnienia.")
        XCTAssertEqual(PlanBlock.paused.screenText(.polish), "Pominięto: połączenia są wstrzymane")
        XCTAssertEqual(PlanBlock.notConnected(.calendar).screenText(.polish), "Brak połączenia: Kalendarz")
        XCTAssertEqual(PlanBlock.onlineAccount(screen: "Gmail isn't connected", reply: "x").screenText(.polish), "Gmail isn't connected", "the server's words are kept")
        for block in [PlanBlock.paused, .notConnected(.timers), .tooManyTries(app: .calendar, count: 4)] {
            XCTAssertEqual(block.screenText(.english), block.screenText)
        }
    }

    func testEveryWayAConversationEndsHasPolish() {
        let ends: [VoiceSessionEnd] = [.userEnded, .doddyEnded, .stoppedListening, .dropped(.offline), .dropped(.connectionLost), .dropped(.error(""))]
        for end in ends {
            for connected in [true, false] {
                let english = SessionRecovery.status(end, connected: connected)
                XCTAssertEqual(SessionRecovery.status(end, connected: connected, language: .english).title, english.title)
                let polish = SessionRecovery.status(end, connected: connected, language: .polish)
                XCTAssertNotEqual(polish.title, english.title, "\(end)")
                XCTAssertEqual(polish.detail == nil, english.detail == nil)
            }
        }
        XCTAssertEqual(SessionRecovery.status(.dropped(.connectionLost), connected: true, language: .polish).title, "Rozmowa została przerwana")
        XCTAssertEqual(SessionRecovery.status(.dropped(.error("Token server down.")), connected: false, language: .polish).detail, "Token server down.", "a service's reason is kept as it was")
    }
}
