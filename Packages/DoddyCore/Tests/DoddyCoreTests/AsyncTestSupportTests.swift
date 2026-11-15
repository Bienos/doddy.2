import XCTest

/// The test helpers themselves (`AsyncTestSupport.swift`): a hung test costs a whole hosted macOS job (100 minutes), so the
/// pause and the wait the other tests rely on are checked on their own. Each wait here has a time limit, so a lost
/// wake-up fails the test in seconds. The class is not `@MainActor` on purpose: in this package's Swift 6 mode,
/// `fulfillment(of:)` called from a main-actor test class is rejected as sending `self`.
final class AsyncTestSupportTests: XCTestCase {
    func testAGateOpenedBeforeAnyoneWaitsLetsTheNextWaiterThrough() async {
        let gate = TestGate()
        gate.close()
        gate.open()
        let passed = expectation(description: "the waiter went through")
        Task.detached { await gate.wait(); passed.fulfill() }
        await fulfillment(of: [passed], timeout: 5)
    }

    func testAGateThatWasNeverClosedDoesNotWait() async {
        let gate = TestGate()
        let passed = expectation(description: "the waiter went through")
        Task.detached { await gate.wait(); passed.fulfill() }
        await fulfillment(of: [passed], timeout: 5)
    }

    func testAWaiterRegisteredBeforeOpenIsWoken() async {
        let gate = TestGate()
        gate.close()
        let passed = expectation(description: "the waiter was woken")
        Task.detached { await gate.wait(); passed.fulfill() }
        // Give the waiter time to register first: the case the old version handled.
        try? await Task.sleep(for: .milliseconds(50))
        gate.open()
        await fulfillment(of: [passed], timeout: 5)
    }

    func testAClosedGateHoldsUntilItIsOpened() async {
        let gate = TestGate()
        gate.close()
        let early = expectation(description: "went through while still closed")
        early.isInverted = true
        Task.detached { await gate.wait(); early.fulfill() }
        await fulfillment(of: [early], timeout: 0.2)
        gate.open()
    }

    /// The race behind the 100-minute hang: `open()` lands while a call is on its way to `wait()`. With a flag read and a
    /// continuation stored in two separate steps, some rounds lose the wake-up and the call waits for ever.
    func testOpeningWhileAWaiterIsStillRegisteringNeverLosesTheWakeUp() async {
        for round in 0..<3_000 {
            let gate = TestGate()
            gate.close()
            let passed = expectation(description: "round \(round)")
            Task.detached { await gate.wait(); passed.fulfill() }
            gate.open()
            await fulfillment(of: [passed], timeout: 10)
        }
    }

    @MainActor
    func testWaitUntilReturnsAsSoonAsTheConditionHolds() async {
        var calls = 0
        let reached = await waitUntil(timeout: 5) { calls += 1; return calls >= 3 }
        XCTAssertTrue(reached)
        XCTAssertEqual(calls, 3)
    }

    @MainActor
    func testWaitUntilGivesUpInsteadOfSpinningForEver() async {
        let started = ContinuousClock.now
        let reached = await waitUntil(timeout: 0.1) { false }
        XCTAssertFalse(reached)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5), "it must stop at its limit, not keep spinning")
    }
}
