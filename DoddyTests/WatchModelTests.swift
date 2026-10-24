import DoddyCore
import Foundation
import XCTest
#if canImport(Doddy)
@testable import Doddy
#endif

// Price watch, the app's side (docs/implementation/SHOPPING_WATCH.md, ADR-614): the card sends nothing while
// Connections are paused or with no server, shows only the server's draft of exactly the words the user was
// shown and approves it with the draft's own digest; an approval with no trustworthy answer is looked up on
// the server, never guessed and never sent again; the list is what the server last listed, a failed read
// never shows as "no watches", and nothing is stopped or deleted on the app's own say-so. A fake server stands
// in for Doddy's; the sentences themselves are held by DoddyCore's WatchTests. Also run on Linux by
// scripts/test_watch_model.sh.

final class WatchModelTests: XCTestCase {
    private let id = UUID(uuidString: "7D6C1F0E-2B8A-4C55-9A0E-3F4D5B6A7C81")!
    private let draft = PriceWatchDraft(title: "Zmywarka", shop: "Media Expert", url: "https://www.mediaexpert.pl/p/1", thresholdMinor: 180_000)
    private var language: NotificationLanguage { NotificationLanguage.current }

    /// The server's draft of `draft`, unless a field is changed.
    private func preview(title: String? = nil, thresholdMinor: Int? = nil, digest: String? = nil) -> WatchPreview {
        WatchPreview(id: id, digest: digest ?? draft.digest, title: title ?? draft.title, shop: draft.shop, url: draft.url,
                     thresholdMinor: thresholdMinor ?? draft.thresholdMinor, currency: draft.currency, language: draft.language,
                     currentMinor: 189_900, checkedAt: Date(), expiresAt: Date().addingTimeInterval(600))
    }

    private func summary(_ state: WatchState, id other: UUID? = nil) -> WatchSummary {
        WatchSummary(id: other ?? id, state: state, title: "Zmywarka", shop: "Media Expert", url: "https://www.mediaexpert.pl/p/1",
                     thresholdMinor: 180_000, createdAt: Date(), lastPriceMinor: 189_900)
    }

    @MainActor
    private func makeModel(_ backend: FakeWatchBackend?, paused: Bool = false, push: PushCount = PushCount()) -> WatchModel {
        WatchModel(backend: { backend }, isPaused: { paused }, registerForPush: { push.times += 1 })
    }

    /// The draft and the server's preview on the card, when it is showing one.
    @MainActor
    private func shownPreview(_ model: WatchModel) -> (PriceWatchDraft, WatchPreview)? {
        if case .preview(let shown, let held) = model.phase { return (shown, held) }
        return nil
    }

    @MainActor
    private func waitFor(_ what: String, file: StaticString = #filePath, line: UInt = #line, _ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("never became true: \(what)", file: file, line: line)
    }

    // MARK: Step one: the draft

    @MainActor
    func testTheCardShowsTheServersDraftOfTheSameWordsAndApprovesNothing() async {
        let backend = FakeWatchBackend { $0.create = .success(self.preview()) }
        let model = makeModel(backend)
        await model.start(draft)
        let shown = shownPreview(model)
        XCTAssertEqual(shown?.0, draft, "the card keeps the words the user was shown")
        XCTAssertEqual(shown?.1.id, id)
        XCTAssertNil(model.problem)
        XCTAssertEqual(backend.calls, ["create"], "a draft is made and nothing is approved")
        await model.start(draft)
        XCTAssertEqual(backend.count("create"), 1, "a second tap while the draft is up sends nothing")
    }

    @MainActor
    func testNothingIsSentWhileConnectionsArePausedOrWithNoServer() async {
        let paused = FakeWatchBackend { $0.create = .success(self.preview()) }
        let pausedModel = makeModel(paused, paused: true)
        await pausedModel.start(draft)
        XCTAssertEqual(pausedModel.phase, .idle)
        XCTAssertEqual(pausedModel.problem, WatchWords.paused(language), "said in words")
        XCTAssertEqual(paused.calls, [], "paused: not even a draft is asked for")

        let running = FakeWatchBackend { $0.create = .success(self.preview()) }
        let runningModel = makeModel(running)
        await runningModel.start(draft)
        XCTAssertNotNil(shownPreview(runningModel), "the same request goes when Connections are on")

        let noServer = WatchModel(backend: { nil }, isPaused: { false }, registerForPush: {})
        await noServer.start(draft)
        XCTAssertEqual(noServer.phase, .idle)
        XCTAssertEqual(noServer.problem, WatchWords.noServer(language))
        XCTAssertFalse(noServer.isServerConfigured)
    }

    @MainActor
    func testARefusedDraftIsSaidInWordsAndShowsNoPreview() async {
        let backend = FakeWatchBackend { $0.create = .failure(WatchError.priceNotReadable(.blocked)) }
        let model = makeModel(backend)
        await model.start(draft)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.problem, WatchWords.problem(WatchError.priceNotReadable(.blocked), language))
        backend.configure { $0.create = .failure(WatchError.alreadyBelow(currentMinor: 179_900)) }
        await model.start(draft)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.problem?.contains(Money(minor: 179_900).text(language)) ?? false, "the price the server read is named: \(model.problem ?? "nil")")
        backend.configure { $0.create = .success(self.preview()) }
        await model.start(draft)
        XCTAssertNotNil(shownPreview(model), "the user can try again")
        XCTAssertNil(model.problem, "an old refusal is cleared when the user tries again")
    }

    // MARK: Step two: the yes

    @MainActor
    func testTheYesApprovesTheDraftsOwnDigestAndTheListIsTheServers() async {
        let push = PushCount()
        let backend = FakeWatchBackend {
            $0.create = .success(self.preview())
            $0.approve = .success(WatchApproval(id: self.id, state: .active, endsAt: Date()))
            $0.list = .success([self.summary(.active)])
        }
        let model = makeModel(backend, push: push)
        await model.start(draft)
        await model.approve()
        XCTAssertEqual(model.phase, .started(draft), "started only when the server confirmed active")
        XCTAssertEqual(backend.calls, ["create", "approve", "hasAccount", "list"], "then the list is read from the server")
        XCTAssertEqual(backend.approvedDigests, [draft.digest], "the yes is bound to the digest of the words the card showed")
        XCTAssertEqual(model.watches.map(\.state), [.active])
        XCTAssertEqual(push.times, 1, "the push token is asked for once the watch is on")
    }

    @MainActor
    func testARefusedYesStartsNothingAndAsksForNoPushToken() async {
        let push = PushCount()
        let backend = FakeWatchBackend {
            $0.create = .success(self.preview())
            $0.approve = .failure(WatchError.tooManyOpenWatches)
        }
        let model = makeModel(backend, push: push)
        await model.start(draft)
        await model.approve()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.problem, WatchWords.problem(WatchError.tooManyOpenWatches, language))
        XCTAssertEqual(push.times, 0)
        XCTAssertEqual(backend.count("list"), 0)
        XCTAssertTrue(model.watches.isEmpty, "nothing is listed that the server didn't list")
    }

    @MainActor
    func testADraftThatIsntForTheShownWordsIsNeverApprovedByTheModel() async {
        let others: [(String, WatchPreview)] = [
            ("another digest", preview(digest: String(repeating: "0", count: 64))),
            ("another title", preview(title: "Inna zmywarka")),
            ("another price", preview(thresholdMinor: 170_000)),
        ]
        for (name, held) in others {
            // The real client refuses these already; the model checks again before it sends a yes.
            let backend = FakeWatchBackend { $0.create = .success(held) }
            let model = makeModel(backend)
            await model.start(draft)
            await model.approve()
            XCTAssertEqual(backend.calls, ["create"], "\(name): nothing is approved")
            XCTAssertEqual(model.phase, .idle, name)
            XCTAssertEqual(model.problem, WatchWords.problem(WatchError.previewMismatch, language), name)
        }
    }

    @MainActor
    func testAnApprovalWithNoTrustworthyAnswerIsLookedUpNeverGuessedNeverSentAgain() async {
        enum Expect { case started, previewAgain, unsure }
        let cases: [(String, WatchApproval, Result<WatchSummary, any Error>, Expect)] = [
            ("held active", .unknown, .success(summary(.active)), .started),
            ("held draft", .unknown, .success(summary(.draft)), .previewAgain),
            ("held stopped", .unknown, .success(summary(.stopped)), .unsure),
            ("lookup failed", .unknown, .failure(WatchError.server(.offline)), .unsure),
            // A 202 that names a state other than active is no confirmation either.
            ("202 says triggered, held stopped", WatchApproval(id: id, state: .triggered), .success(summary(.stopped)), .unsure),
            ("202 says triggered, held active", WatchApproval(id: id, state: .triggered), .success(summary(.active)), .started),
        ]
        for (name, approval, held, expect) in cases {
            let push = PushCount()
            let backend = FakeWatchBackend {
                $0.create = .success(self.preview())
                $0.approve = .success(approval)
                $0.get = held
                $0.list = .success([self.summary(.active)])
            }
            let model = makeModel(backend, push: push)
            await model.start(draft)
            await model.approve()
            XCTAssertEqual(backend.count("approve"), 1, "\(name): the yes is sent once, never again by itself")
            XCTAssertEqual(backend.count("get"), 1, "\(name): the server is asked about that one watch")
            switch expect {
            case .started:
                XCTAssertEqual(model.phase, .started(draft), "\(name): the server holds it active")
                XCTAssertEqual(push.times, 1, name)
            case .previewAgain:
                XCTAssertNotNil(shownPreview(model), "\(name): the yes never arrived, so it can be said again")
                XCTAssertEqual(model.problem, WatchWords.notStartedYet(language), name)
                XCTAssertEqual(push.times, 0, name)
            case .unsure:
                XCTAssertEqual(model.phase, .unsure, "\(name): not sure, and not claimed")
                XCTAssertNil(model.problem, name)
                XCTAssertEqual(push.times, 0, name)
                XCTAssertEqual(backend.count("list"), 1, "\(name): the list shows the server's word")
            }
        }
    }

    // MARK: Saying no, and closing the card

    @MainActor
    func testNoAndClosingRemoveTheDraftThatWasNeverApproved() async {
        let backend = FakeWatchBackend { $0.create = .success(self.preview()) }
        let model = makeModel(backend)
        await model.start(draft)
        await model.decline()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(backend.calls, ["create", "delete"], "the unapproved draft is removed from the server")
        XCTAssertEqual(backend.deletedIDs, [id])
        await model.cardClosed()
        XCTAssertEqual(backend.count("delete"), 1, "closing after no deletes nothing more")

        // A draft that can't be deleted just lapses on the server; the card still closes.
        let failing = FakeWatchBackend {
            $0.create = .success(self.preview())
            $0.delete = .failure(WatchError.server(.offline))
        }
        let other = makeModel(failing)
        await other.start(draft)
        await other.cardClosed()
        XCTAssertEqual(other.phase, .idle)
        XCTAssertEqual(failing.count("delete"), 1)
    }

    @MainActor
    func testAWatchThatWasApprovedIsNotDeletedWhenTheCardCloses() async {
        let backend = FakeWatchBackend {
            $0.create = .success(self.preview())
            $0.approve = .success(WatchApproval(id: self.id, state: .active))
        }
        let model = makeModel(backend)
        await model.start(draft)
        await model.approve()
        await model.cardClosed()
        XCTAssertEqual(backend.count("delete"), 0, "closing the card after a yes leaves the watch alone")
        XCTAssertEqual(model.phase, .started(draft))
        model.beginCard()
        XCTAssertEqual(model.phase, .idle, "an old card's result doesn't show on the next")
        XCTAssertNil(model.problem)
    }

    @MainActor
    func testACardOpeningMidRequestDoesNotClearItAndASecondTapSendsNothing() async {
        let gate = Gate()
        let backend = FakeWatchBackend {
            $0.create = .success(self.preview())
            $0.createGate = gate
        }
        let model = makeModel(backend)
        let words = draft
        let first = Task { await model.start(words) }
        await waitFor("reading") { model.phase == .reading }
        model.beginCard()
        XCTAssertEqual(model.phase, .reading, "a request on its way isn't cleared by the next card")
        // A second tap while the first request is on its way. It runs beside it, so a broken guard shows up as a
        // second request below instead of as a test that never ends.
        let second = Task { await model.start(words) }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(backend.count("create"), 1, "a second tap sends nothing")
        gate.open()
        await first.value
        await second.value
        XCTAssertEqual(backend.count("create"), 1)
        XCTAssertNotNil(shownPreview(model))
    }

    // MARK: The list

    @MainActor
    func testOpeningTheListMakesNoServerAccountJustToLook() async {
        let backend = FakeWatchBackend {
            $0.account = false
            $0.list = .success([self.summary(.active)])
        }
        let model = makeModel(backend)
        await model.refresh()
        XCTAssertTrue(model.watches.isEmpty)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNil(model.loadProblem)
        XCTAssertEqual(backend.calls, ["hasAccount"], "no account: no request, so none is made")
    }

    @MainActor
    func testTheListIsTheServersAndAFailedReadNeverShowsAsNoWatches() async {
        let backend = FakeWatchBackend { $0.list = .success([self.summary(.active), self.summary(.triggered, id: UUID())]) }
        let model = makeModel(backend)
        await model.refresh()
        XCTAssertEqual(model.watches.map(\.state), [.active, .triggered], "as the server listed them")
        XCTAssertNil(model.loadProblem)
        XCTAssertTrue(model.hasLoaded)

        backend.configure { $0.list = .failure(WatchError.server(.offline)) }
        await model.refresh()
        XCTAssertEqual(model.watches.count, 2, "a failed read keeps what was listed")
        XCTAssertEqual(model.loadProblem, WatchWords.problem(WatchError.server(.offline), language), "and says it couldn't be read")

        backend.configure { $0.list = .success([]) }
        await model.refresh()
        XCTAssertTrue(model.watches.isEmpty, "only the server's own empty list is empty")
        XCTAssertNil(model.loadProblem)
    }

    // MARK: Stop and delete

    @MainActor
    func testStopShowsStoppedOnlyAfterTheServersAnswerEvenIfTheListCantBeReRead() async {
        let backend = FakeWatchBackend { $0.list = .success([self.summary(.active)]) }
        let model = makeModel(backend)
        await model.refresh()
        backend.configure { $0.list = .failure(WatchError.server(.offline)) }
        await model.stop(id)
        XCTAssertEqual(model.watches.first?.state, .stopped, "the server's 204 is what says it is stopped")
        XCTAssertNil(model.message)
        XCTAssertEqual(backend.count("stop"), 1)
    }

    @MainActor
    func testARefusedStopIsSaidAndTheListShowsWhatTheServerHolds() async {
        let backend = FakeWatchBackend { $0.list = .success([self.summary(.active)]) }
        let model = makeModel(backend)
        await model.refresh()
        backend.configure {
            $0.stop = .failure(WatchError.notStoppable(state: .triggered))
            $0.list = .success([self.summary(.triggered)])
        }
        await model.stop(id)
        XCTAssertEqual(model.watches.first?.state, .triggered, "not stopped on the app's own say-so")
        XCTAssertEqual(model.message, WatchWords.problem(WatchError.notStoppable(state: .triggered), language))
        XCTAssertTrue(model.busy.isEmpty, "the row is free again")
    }

    @MainActor
    func testASecondStopWhileOneIsOnItsWaySendsNothing() async {
        let gate = Gate()
        let backend = FakeWatchBackend {
            $0.list = .success([self.summary(.active)])
            $0.stopGate = gate
        }
        let model = makeModel(backend)
        await model.refresh()
        let watchID = id
        let first = Task { await model.stop(watchID) }
        await waitFor("busy") { model.busy.contains(id) }
        let second = Task { await model.stop(watchID) }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(backend.count("stop"), 1, "a second tap sends nothing")
        gate.open()
        await first.value
        await second.value
        XCTAssertEqual(backend.count("stop"), 1)
        XCTAssertTrue(model.busy.isEmpty)
    }

    @MainActor
    func testADeletedWatchLeavesTheListOnlyAfterTheServersAnswer() async {
        let backend = FakeWatchBackend { $0.list = .success([self.summary(.active)]) }
        let model = makeModel(backend)
        await model.refresh()
        backend.configure { $0.delete = .failure(WatchError.server(.offline)) }
        await model.delete(id)
        XCTAssertEqual(model.watches.count, 1, "a failure removes nothing")
        XCTAssertEqual(model.message, WatchWords.problem(WatchError.server(.offline), language))
        XCTAssertTrue(model.busy.isEmpty)
        backend.configure { $0.delete = .success(()) }
        await model.delete(id)
        XCTAssertTrue(model.watches.isEmpty, "the server's 204 removes it")
        XCTAssertNil(model.message)
    }

    @MainActor
    func testStopAndDeleteWithNoServerSayWhyAndChangeNothing() async {
        let model = WatchModel(backend: { nil }, isPaused: { false }, registerForPush: {})
        await model.stop(id)
        XCTAssertEqual(model.message, WatchWords.noServer(language))
        await model.delete(id)
        XCTAssertEqual(model.message, WatchWords.noServer(language))
        XCTAssertTrue(model.watches.isEmpty)
    }
}

/// How many times the push token was asked for.
@MainActor
private final class PushCount {
    var times = 0
}

/// Holds every call that waits on it until `open()`; a call that comes after it is open goes straight through.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let passes = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiting.append(continuation)
                return false
            }
            if passes { continuation.resume() }
        }
    }

    func open() {
        let released = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            let all = waiting
            waiting = []
            return all
        }
        for continuation in released { continuation.resume() }
    }
}

/// Doddy's server, scripted: what each call answers, and what was asked, in order. A gate holds a call until
/// the test lets it go.
private final class FakeWatchBackend: WatchesBackend, @unchecked Sendable {
    struct Script {
        var account = true
        var create: Result<WatchPreview, any Error> = .failure(WatchError.server(.offline))
        var approve: Result<WatchApproval, any Error> = .success(.unknown)
        var get: Result<WatchSummary, any Error> = .failure(WatchError.server(.offline))
        var list: Result<[WatchSummary], any Error> = .success([])
        var stop: Result<Void, any Error> = .success(())
        var delete: Result<Void, any Error> = .success(())
        var createGate: Gate?
        var stopGate: Gate?
    }

    private let lock = NSLock()
    private var script = Script()
    private var log: [String] = []
    private var digests: [String] = []
    private var deleted: [UUID] = []

    init(_ configure: (inout Script) -> Void = { _ in }) {
        configure(&script)
    }

    func configure(_ edit: (inout Script) -> Void) { lock.withLock { edit(&script) } }

    /// The calls that were made, by name, in order.
    var calls: [String] { lock.withLock { log } }
    var approvedDigests: [String] { lock.withLock { digests } }
    var deletedIDs: [UUID] { lock.withLock { deleted } }
    func count(_ name: String) -> Int { calls.filter { $0 == name }.count }

    private func record(_ name: String) { lock.withLock { log.append(name) } }
    private func scripted<T>(_ pick: (Script) -> T) -> T { lock.withLock { pick(script) } }
    private func hold(_ gate: Gate?) async {
        await gate?.wait()
    }

    func hasAccount() async -> Bool {
        record("hasAccount")
        return scripted { $0.account }
    }

    func createWatch(_ draft: PriceWatchDraft) async throws -> WatchPreview {
        record("create")
        await hold(scripted { $0.createGate })
        return try scripted { $0.create }.get()
    }

    func approveWatch(_ id: UUID, digest: String) async throws -> WatchApproval {
        record("approve")
        lock.withLock { digests.append(digest) }
        return try scripted { $0.approve }.get()
    }

    func watches() async throws -> [WatchSummary] {
        record("list")
        return try scripted { $0.list }.get()
    }

    func watch(_ id: UUID) async throws -> WatchSummary {
        record("get")
        return try scripted { $0.get }.get()
    }

    func stopWatch(_ id: UUID) async throws {
        record("stop")
        await hold(scripted { $0.stopGate })
        try scripted { $0.stop }.get()
    }

    func deleteWatch(_ id: UUID) async throws {
        record("delete")
        lock.withLock { deleted.append(id) }
        try scripted { $0.delete }.get()
    }
}
