import DoddyCore
import Foundation
import XCTest

/// A stand-in for a started conversation: not Sendable, like the real one.
@MainActor private final class FakeConversation {
    var ended = false
    func end() async { ended = true }
}

/// ADR-686: a start that takes too long is cancelled and reported, and a start that connects
/// after the limit anyway is ended, so nothing keeps listening.
@MainActor
final class StartLimitTests: XCTestCase {
    func testAStartInTimeIsReturned() async throws {
        let late = LateBox()
        let value = try await StartLimit.run(seconds: 5, operation: { 7 }, lateResult: { _ in late.count += 1 })
        XCTAssertEqual(value, 7)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(late.count, 0)
    }

    func testAnErrorFromTheStartPassesThrough() async {
        struct Boom: Error, Equatable {}
        do {
            _ = try await StartLimit.run(seconds: 5, operation: { () async throws -> Int in throw Boom() }, lateResult: { _ in })
            XCTFail("should have thrown")
        } catch {
            XCTAssertEqual(error as? Boom, Boom())
        }
    }

    func testASlowStartTimesOutAndIsCancelled() async {
        let sawCancel = LateBox()
        do {
            _ = try await StartLimit.run(seconds: 0.05, operation: { () async throws -> Int in
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { sawCancel.count += 1; throw error }
                return 1
            }, lateResult: { _ in })
            XCTFail("should have timed out")
        } catch {
            XCTAssertEqual(error as? StartLimit.TimedOut, StartLimit.TimedOut())
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(sawCancel.count, 1, "the start was told to stop")
    }

    func testAStartThatIgnoresTheLimitAndConnectsLateIsHandedBack() async {
        let conversation = FakeConversation()
        do {
            _ = try await StartLimit.run(seconds: 0.05, operation: { () async throws -> FakeConversation in
                // Ignores cancellation, as a start stuck inside a framework might.
                let until = Date().addingTimeInterval(0.3)
                while Date() < until { await Task.yield(); try? await Task.sleep(nanoseconds: 10_000_000) }
                return conversation
            }, lateResult: { late in await late.end() })
            XCTFail("should have timed out")
        } catch {
            XCTAssertEqual(error as? StartLimit.TimedOut, StartLimit.TimedOut())
        }
        XCTAssertFalse(conversation.ended)
        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(conversation.ended, "a conversation that connected after the limit is ended")
    }

    func testTimeoutInvalidatesCallbacksBeforeTheCallerResumes() async {
        let callbacks = LateBox()
        do {
            _ = try await StartLimit.run(seconds: 0.01, operation: { () async throws -> Int in
                try await Task.sleep(for: .seconds(5))
                return 1
            }, onTimeout: { callbacks.count += 1 }, lateResult: { _ in })
            XCTFail("expected timeout")
        } catch {
            XCTAssertEqual(error as? StartLimit.TimedOut, StartLimit.TimedOut())
            XCTAssertEqual(callbacks.count, 1, "callbacks are invalidated before the caller resumes")
        }
    }

    func testCallerCancellationFinishesBeforeUncooperativeProviderAndCleansUpLateResult() async throws {
        let provider = SuspendedStart()
        let conversation = FakeConversation()
        let task = Task {
            try await StartLimit.run(seconds: 30, operation: {
                await provider.wait()
                return conversation
            }, lateResult: { await $0.end() })
        }
        while provider.continuation == nil { await Task.yield() }
        task.cancel()
        // Release the provider only after the cancelled caller returns. A failure to resume the
        // caller hangs here until the outer test timeout instead of falsely passing after 30 s.
        do { _ = try await task.value; XCTFail("expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(conversation.ended)
        provider.continuation?.resume()
        for _ in 0..<100 where !conversation.ended { await Task.yield() }
        XCTAssertTrue(conversation.ended)
    }

    func testAlreadyCancelledCallerNeverStartsProvider() async {
        let called = LateBox()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await StartLimit.run(operation: { called.count += 1; return 1 }, lateResult: { _ in })
        }
        do { _ = try await task.value; XCTFail("expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(called.count, 0)
    }

    func testTheMessageIsNotTheOfflineOne() {
        XCTAssertFalse(StartLimit.message.lowercased().contains("offline"))
        XCTAssertEqual(StartLimit.seconds, 10)
    }
}

@MainActor private final class LateBox { var count = 0 }

@MainActor private final class SuspendedStart {
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0 } }
}
