import Foundation

/// A pause a test controls, for faking a slow answer from the network.
///
/// Why it exists (15 Nov 2026): the first version of `MessagingTokenRenewalTests.Wire` looked at a "held" flag and only then
/// registered the waiting call, as two separate locked steps. A `release()` landing between them found nobody waiting, resumed
/// nothing, and the call then waited for ever. One hosted macOS run hung that way until the job's 100-minute timeout.
/// Here "is it still closed?" and "register my wait" are one locked step, under the same lock `open()` takes, so an
/// `open()` can never fall between them: it either runs first (the call goes straight through) or finds the waiter.
final class TestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// From now on a call to `wait()` waits until `open()`.
    func close() {
        lock.withLock { closed = true }
    }

    /// Returns at once while the gate is open, otherwise when `open()` is called.
    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let mustWait = lock.withLock { () -> Bool in
                guard closed else { return false }
                waiters.append(continuation)
                return true
            }
            if !mustWait { continuation.resume() }
        }
    }

    /// Lets every waiting call through, and any call after it, until the next `close()`.
    func open() {
        let released = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            closed = false
            let list = waiters
            waiters = []
            return list
        }
        for continuation in released { continuation.resume() }
    }
}

/// Waits until `condition` holds, for at most `timeout` seconds. False when it gave up, so a test fails with a message
/// instead of spinning until the job's timeout (a `while … { await Task.yield() }` has no way out).
@MainActor
func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(timeout)
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}
