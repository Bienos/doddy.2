import XCTest
@testable import DoddyCore

/// Finished tasks and files arrive in Messages as Doddy's own messages (owner, 10 Nov 2026).
final class ThreadDeliveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_300_000)
    private let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!

    private func errand(_ state: ErrandState, answer: String? = "Trzy kawiarnie: Relaks, Kafka i Charlotte.",
                        language: String = "pl", failure: ErrandFailureCode? = nil) -> StoredErrand {
        StoredErrand(
            id: id, createdAt: now, state: state,
            draft: ErrandDraft(words: "raport o kawiarniach", brief: "Kawiarnie", title: "Kawiarnie w Warszawie", language: language),
            result: answer.map { ErrandResult(answer: $0, checkedAt: "2026-11-10") }, failure: failure)
    }

    func testADoneTaskSaysDoneWithTheServersAnswerUnderTheTasksOwnID() throws {
        let message = try XCTUnwrap(ThreadDelivery.errand(errand(.done), now: now))
        XCTAssertEqual(message.id, id)
        XCTAssertEqual(message.sender, .doddy)
        XCTAssertEqual(message.delivery, .sent)
        XCTAssertEqual(message.basis, .general)
        XCTAssertTrue(message.text.hasPrefix("Gotowe: „Kawiarnie w Warszawie”."))
        XCTAssertTrue(message.text.contains("Trzy kawiarnie: Relaks, Kafka i Charlotte."))
    }

    func testOnlyAFinishedTaskBecomesAMessage() {
        for state in [ErrandState.draft, .queued, .running, .cancelled, .unknown] {
            XCTAssertNil(ThreadDelivery.errand(errand(state), now: now), "\(state)")
        }
        // "Done" with no result kept is never called done.
        XCTAssertNil(ThreadDelivery.errand(errand(.done, answer: nil), now: now))
    }

    func testAFailedTaskSaysWhyInTheTasksLanguage() throws {
        let polish = try XCTUnwrap(ThreadDelivery.errand(errand(.failed, answer: nil, failure: .timeLimit), now: now))
        XCTAssertTrue(polish.text.contains("Nie udało mi się dokończyć"))
        XCTAssertTrue(polish.text.contains("limit czasu"))
        let english = try XCTUnwrap(ThreadDelivery.errand(errand(.failed, answer: nil, language: "en", failure: nil), now: now))
        XCTAssertTrue(english.text.contains("reason unknown"))
    }

    func testALongAnswerIsClippedAtAWord() {
        let long = String(repeating: "słowo ", count: 300)
        let text = ThreadDelivery.errand(errand(.done, answer: long), now: now)!.text
        XCTAssertTrue(text.contains("…"))
        XCTAssertLessThan(text.count, ThreadDelivery.answerLimit + 200)
    }

    private let link = URL(string: "https://doddy.example/v1/documents/abcdefghijklmnopqrstuvwx?exp=1&sig=x")!

    func testAFileBeingMadeIsNotCalledReady() throws {
        let doc = RunDocument(url: link, name: "Warszawa.pptx", kind: "deck", status: .working)
        let message = try XCTUnwrap(ThreadDelivery.document(doc, polish: true, now: now))
        XCTAssertEqual(message.document?.url, link)
        XCTAssertTrue(message.text.contains("Robię to dla ciebie"))
        XCTAssertFalse(message.text.contains("gotowe"))
        XCTAssertEqual(ThreadDelivery.caption(of: message), message.text)
        XCTAssertNil(ThreadDelivery.document(RunDocument(url: link, name: "x", kind: "deck", status: .failed), polish: true, now: now))
    }

    func testAFileMadeByVoiceSaysWhatItIsAbout() throws {
        let doc = RunDocument(url: link, name: "Kraków.pptx", kind: "deck", status: .working)
        let call = CloudToolCall(name: CloudToolName.makeDocument, arguments: [
            "kind": .string("deck"), "title": .string("Kraków"),
            "request": .string("  Prezentacja o weekendzie w Krakowie\n dla rodziców, 8 slajdów  "),
        ])
        let brief = try XCTUnwrap(ThreadDelivery.madeFileBrief(of: call))
        XCTAssertEqual(brief, "Prezentacja o weekendzie w Krakowie dla rodziców, 8 slajdów")
        let message = try XCTUnwrap(ThreadDelivery.document(doc, about: brief, polish: true, now: now))
        XCTAssertTrue(message.text.hasPrefix("Robię to dla ciebie"))
        XCTAssertTrue(message.text.hasSuffix("\n\n" + brief))
        XCTAssertEqual(message.document?.url, link)
    }

    func testOnlyMakeDocumentHasABrief() {
        XCTAssertNil(ThreadDelivery.madeFileBrief(of: CloudToolCall(name: CloudToolName.webSearch, arguments: ["request": .string("x")])))
        XCTAssertNil(ThreadDelivery.madeFileBrief(of: CloudToolCall(name: CloudToolName.makeDocument, arguments: ["request": .string("   ")])))
        XCTAssertNil(ThreadDelivery.madeFileBrief(of: CloudToolCall(name: CloudToolName.makeDocument, arguments: [:])))
        let doc = RunDocument(url: link, name: "Kraków.pptx", kind: "deck", status: .ready)
        XCTAssertEqual(ThreadDelivery.document(doc, about: nil, polish: false, now: now)?.text, "Here it is: “Kraków.pptx”.")
    }

    func testALongBriefIsClippedAtAWord() throws {
        let call = CloudToolCall(name: CloudToolName.makeDocument, arguments: ["request": .string(String(repeating: "slajd ", count: 400))])
        let brief = try XCTUnwrap(ThreadDelivery.madeFileBrief(of: call))
        XCTAssertTrue(brief.hasSuffix("…"))
        XCTAssertLessThanOrEqual(brief.count, ThreadMessage.fileAboutLimit + 1)
    }

    func testTheSameFileIsNotAddedTwice() {
        let doc = RunDocument(url: link, name: "Warszawa.pptx", kind: "deck", status: .working)
        let message = ThreadDelivery.document(doc, polish: false, now: now)!
        let laterLink = URL(string: "https://doddy.example/v1/documents/abcdefghijklmnopqrstuvwx?exp=2&sig=y")!
        XCTAssertTrue(ThreadDelivery.hasDocument(RunDocument(url: laterLink, name: "Warszawa.pptx", kind: "deck", status: .ready), in: [message]))
        XCTAssertFalse(ThreadDelivery.hasDocument(doc, in: []))
    }

    func testAPlainFileBubbleHasNoCaption() {
        let file = ThreadDocument(url: link, name: "Warszawa.pptx", kind: "deck")
        XCTAssertNil(ThreadDelivery.caption(of: .file(file, now: now)))
    }

    func testATaskResultIsDoddysOwnTurnForFollowUpQuestions() {
        let message = ThreadDelivery.errand(errand(.done), now: now)!
        let turns = ThreadRules.history(from: [message], before: now.addingTimeInterval(60))
        XCTAssertEqual(turns.map(\.role), [.assistant])
    }
}

extension ThreadDeliveryTests {
    func testADeliveredTaskHasNoSecondCardUnderTheThread() {
        let done = errand(.done)
        let message = ThreadDelivery.errand(done, now: now)!
        XCTAssertEqual(ThreadTaskResults.shown([done], now: now).map(\.id), [done.id])
        XCTAssertTrue(ThreadTaskResults.shown([done], now: now, thread: [message]).isEmpty)
    }
}
