import XCTest
@testable import DoddyCore

final class VoiceTokenSupplyTests: XCTestCase {
    private let server = URL(string: "https://voice.example.com/api/voice-token")!

    @MainActor
    private final class Requests {
        var calls = 0
        var answers: [CheckedContinuation<Result<String, VoiceTokenError>, Never>] = []
        var waiting: [(Int, CheckedContinuation<Void, Never>)] = []

        func fetch(_ endpoint: URL) async -> Result<String, VoiceTokenError> {
            await withCheckedContinuation { answer in
                calls += 1
                answers.append(answer)
                let ready = waiting.filter { calls >= $0.0 }
                waiting.removeAll { calls >= $0.0 }
                ready.forEach { $0.1.resume() }
            }
        }

        func waitFor(_ count: Int) async {
            if calls >= count { return }
            await withCheckedContinuation { waiting.append((count, $0)) }
        }

        func finish(_ result: Result<String, VoiceTokenError>) { answers.removeFirst().resume(returning: result) }
    }

    /// Return only after the press has reached its suspension on the token request. Both run
    /// on MainActor, so resuming `entered` cannot let this helper return before token() suspends.
    @MainActor
    private func startPress(_ supply: VoiceTokenSupply, _ requests: Requests) async -> Task<VoiceTokenSupply.Token, any Error> {
        let endpoint = server
        var task: Task<VoiceTokenSupply.Token, any Error>!
        await withCheckedContinuation { (entered: CheckedContinuation<Void, Never>) in
            task = Task { @MainActor in
                entered.resume()
                return try await supply.token(endpoint: endpoint, owner: "one", fetch: requests.fetch)
            }
        }
        return task
    }

    @MainActor
    func testPressJoinsAnUnfinishedWarmupInsteadOfRequestingAnotherToken() async throws {
        let supply = VoiceTokenSupply()
        let requests = Requests()
        supply.warm(endpoint: server, owner: "one", fetch: requests.fetch)
        await requests.waitFor(1)
        let press = await startPress(supply, requests)
        requests.finish(.success("first"))
        let token = try await press.value
        XCTAssertEqual(token.value, "first")
        XCTAssertEqual(token.source, .warming)
        XCTAssertEqual(requests.calls, 1)
    }

    @MainActor
    func testTwoPressesNeverReceiveTheSameToken() async throws {
        let supply = VoiceTokenSupply()
        let requests = Requests()
        let first = Task { try await supply.token(endpoint: server, owner: "one", fetch: requests.fetch) }
        await requests.waitFor(1)
        let second = Task { try await supply.token(endpoint: server, owner: "one", fetch: requests.fetch) }
        requests.finish(.success("first"))
        await requests.waitFor(2)
        requests.finish(.success("second"))
        let values = try await [first.value.value, second.value.value]
        XCTAssertEqual(Set(values), ["first", "second"])
        XCTAssertEqual(requests.calls, 2)
    }

    @MainActor
    func testClearRejectsLateTokenAndDoesNotEraseANewerWarmup() async throws {
        let supply = VoiceTokenSupply()
        let requests = Requests()
        let old = Task { try await supply.token(endpoint: server, owner: "one", fetch: requests.fetch) }
        await requests.waitFor(1)
        supply.clear()
        // An explicit press may start despite the unused warm-up cool-down.
        let new = Task { try await supply.token(endpoint: server, owner: "two", fetch: requests.fetch) }
        await requests.waitFor(2)
        requests.finish(.success("old-account"))
        do { _ = try await old.value; XCTFail("a cleared token must not reach the provider") }
        catch { XCTAssertEqual(error as? VoiceTokenError, .cancelled) }
        requests.finish(.success("new-account"))
        let token = try await new.value
        XCTAssertEqual(token.value, "new-account")
        XCTAssertEqual(requests.calls, 2)
    }

    @MainActor
    func testAnotherServerCannotJoinAnEarlierRequest() async throws {
        let supply = VoiceTokenSupply()
        let requests = Requests()
        supply.warm(endpoint: server, owner: "one", fetch: requests.fetch)
        await requests.waitFor(1)
        let other = URL(string: "https://other.example.com/api/voice-token")!
        let press = Task { try await supply.token(endpoint: other, owner: "one", fetch: requests.fetch) }
        await requests.waitFor(2)
        requests.finish(.success("wrong-server"))
        requests.finish(.success("right-server"))
        let token = try await press.value
        XCTAssertEqual(token.value, "right-server")
    }

    @MainActor
    func testFailureIsReturnedOnceAndUnusedWarmupsKeepTheirCooldown() async {
        let supply = VoiceTokenSupply()
        let requests = Requests()
        supply.warm(endpoint: server, owner: "one", fetch: requests.fetch)
        await requests.waitFor(1)
        let press = await startPress(supply, requests)
        requests.finish(.failure(.rateLimited(retryAfterSeconds: 60)))
        do { _ = try await press.value; XCTFail("must report the server refusal") }
        catch { XCTAssertEqual(error as? VoiceTokenError, .rateLimited(retryAfterSeconds: 60)) }
        XCTAssertEqual(requests.calls, 1)
        XCTAssertFalse(supply.warm(endpoint: server, owner: "one", fetch: requests.fetch))
    }

    @MainActor
    func testAnEmptyReplyFailsWithoutRepeatedRequests() async {
        let supply = VoiceTokenSupply()
        let press = Task { try await supply.token(endpoint: server, owner: "one", fetch: { _ in .success("") }) }
        do { _ = try await press.value; XCTFail("empty credentials are unusable") }
        catch { XCTAssertEqual(error as? VoiceTokenError, .badResponse) }
    }

    @MainActor
    func testCancelledPressDoesNotConsumeOrDuplicateThePreparedToken() async throws {
        let supply = VoiceTokenSupply()
        let requests = Requests()
        supply.warm(endpoint: server, owner: "one", fetch: requests.fetch)
        await requests.waitFor(1)
        let press = await startPress(supply, requests)
        press.cancel()
        requests.finish(.success("prepared"))
        do { _ = try await press.value; XCTFail("cancelled starts cannot connect") }
        catch { XCTAssertEqual(error as? VoiceTokenError, .cancelled) }
        let next = try await supply.token(endpoint: server, owner: "one", fetch: requests.fetch)
        XCTAssertEqual(next.value, "prepared")
        XCTAssertEqual(next.source, .shelf)
        XCTAssertEqual(requests.calls, 1)
        XCTAssertTrue(supply.warm(endpoint: server, owner: "one", fetch: requests.fetch),
                      "a consumed token allows preparation for the next conversation")
        await requests.waitFor(2)
        requests.finish(.failure(.offline))
    }
}
