import Foundation

/// A time limit on starting a voice conversation (ADR-670).
///
/// A start that never gets going leaves a silent session that ends only when iOS or the provider
/// gives up (STATUS "Known problems", docs/implementation/VOICE_SESSION_STARTS.md: "Bound the
/// start"). `run` gives the start `seconds`; past that it cancels it and says so, so the person
/// sees a clear message instead of a conversation that can't hear them.
///
/// If the start ignores the cancellation and connects after the limit, `lateResult` gets what it
/// made, so the caller can end it and nothing keeps the microphone open.
public enum StartLimit {
    /// How long a start may take. The voice token request has its own 15 s limit before this.
    public static let seconds: TimeInterval = 10

    public struct TimedOut: Error, Equatable, Sendable {
        public init() {}
    }

    public static let message = "Doddy's voice didn't connect in time. Check your internet connection and try again in a moment."

    @MainActor
    public static func run<T>(
        seconds: TimeInterval = StartLimit.seconds,
        operation: @escaping @MainActor () async throws -> T,
        lateResult: @escaping @MainActor (T) async -> Void
    ) async throws -> T {
        let race = Race()
        var worker: Task<Void, Never>?
        var timer: Task<Void, Never>?
        defer { timer?.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
                worker = Task { @MainActor in
                    do {
                        let value = try await operation()
                        if race.claim() { continuation.resume(returning: value) } else { await lateResult(value) }
                    } catch {
                        if race.claim() { continuation.resume(throwing: error) }
                    }
                }
                timer = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                    if race.claim() {
                        worker?.cancel()
                        continuation.resume(throwing: TimedOut())
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in worker?.cancel() }
        }
    }

    /// The first of the start finishing and the limit passing wins; the other does nothing.
    private final class Race: @unchecked Sendable {
        private let lock = NSLock()
        private var decided = false
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if decided { return false }
            decided = true
            return true
        }
    }
}
