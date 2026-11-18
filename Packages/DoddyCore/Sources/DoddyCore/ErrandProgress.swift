import Foundation

/// Content-free server events, persisted with the existing errand. Counts are observations, not percentages.
public struct ErrandProgress: Codable, Equatable, Sendable {
    public struct Event: Codable, Equatable, Sendable {
        public let stage: String
        public let requests: Int
        public let searches: Int
        public let fetches: Int
        public let at: String
    }
    public let stage: String
    public let requests: Int
    public let searches: Int
    public let fetches: Int
    public let updatedAt: String
    public let events: [Event]

    public func message(for state: ErrandState, polish: Bool) -> String {
        // A terminal task never keeps displaying an older active stage.
        guard state == .running else {
            switch state {
            case .done: return Self.message(stage: "completed", polish: polish)
            case .failed: return Self.message(stage: "failed", polish: polish)
            case .cancelled: return Self.message(stage: "cancelled", polish: polish)
            case .queued: return polish ? "Sprawa czeka na rozpoczęcie." : "The task is waiting to start."
            case .draft: return polish ? "Sprawa nie została wysłana." : "The task has not been submitted."
            case .unknown: return polish ? "Nie udało się potwierdzić stanu sprawy." : "The task's status couldn't be confirmed."
            case .running: break
            }
            return ""
        }
        return Self.message(stage: stage, polish: polish)
    }

    public static func message(stage: String, polish: Bool) -> String {
        switch stage {
        case "waiting_for_service": polish ? "Czekam na odpowiedź." : "Waiting for a response."
        case "researching": polish ? "Sprawdzam źródła." : "Checking sources."
        case "writing_report": polish ? "Przygotowuję raport." : "Preparing the report."
        case "completed": polish ? "Wynik jest gotowy." : "The result is ready."
        case "failed": polish ? "Nie udało się dokończyć." : "The task couldn't be finished."
        case "cancelled": polish ? "Sprawa anulowana." : "Task cancelled."
        default: polish ? "Doddy pracuje nad sprawą." : "Doddy is working on the task."
        }
    }
}
