import Foundation

/// Bounds provider startup, including providers that ignore cancellation (ADR-686).
/// Late conversations are returned only to `lateResult` so the caller can end them.
public enum StartLimit {
    public static let seconds: TimeInterval = 10
    public struct TimedOut: Error, Equatable, Sendable { public init() {} }
    public static let message = "Doddy's voice didn't connect in time. Check your internet connection and try again in a moment."

    @MainActor
    public static func run<T>(
        seconds: TimeInterval = StartLimit.seconds,
        operation: @escaping @MainActor () async throws -> T,
        lateResult: @escaping @MainActor (T) async -> Void
    ) async throws -> T {
        try Task.checkCancellation()
        let race = Race<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.continuation = continuation
                race.worker = Task { @MainActor in
                    do {
                        let value = try await operation()
                        if let continuation = race.claim() { continuation.resume(returning: value) }
                        else { await lateResult(value) }
                    } catch {
                        race.claim()?.resume(throwing: error)
                    }
                }
                race.timer = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(max(0, seconds))) }
                    catch { return }
                    if let continuation = race.claim() {
                        race.worker?.cancel()
                        continuation.resume(throwing: TimedOut())
                    }
                }
            }
        } onCancel: {
            // Cancelling the caller must finish immediately even if the provider ignores it.
            Task { @MainActor in
                if let continuation = race.claim() {
                    race.worker?.cancel()
                    continuation.resume(throwing: CancellationError())
                }
            }
        }
    }

    @MainActor
    private final class Race<T> {
        var continuation: CheckedContinuation<T, any Error>?
        var worker: Task<Void, Never>?
        var timer: Task<Void, Never>?
        func claim() -> CheckedContinuation<T, any Error>? {
            guard let continuation else { return nil }
            self.continuation = nil
            timer?.cancel()
            return continuation
        }
    }
}
