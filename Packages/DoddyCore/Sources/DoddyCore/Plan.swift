import Foundation

// Several changes on one card (docs/design/SETTINGS_AND_CONNECTIONS.md §4, ADR-204). The agent
// calls `propose_plan` with the steps; the app checks every step exactly as if it had been asked
// on its own, shows them together with a tick box each, and runs only the ticked ones, in order,
// after one tap. Look-ups are not steps: the agent runs them first with the usual tools.

/// The tools a plan may contain: changes that finish without leaving Doddy. Opening Maps,
/// Shortcuts or a Messages draft would leave the app half-way through, so those stay one card
/// each. A Gmail draft or Todoist task (ADR-209) gets its own approval from Doddy's server for its
/// exact arguments when the card is shown, as a single card would.
public enum PlanTool {
    public static let maxSteps = 5
    public static let allowed: [String] = [
        VoiceToolName.saveMemory, VoiceToolName.createCalendarEvent, VoiceToolName.createReminder, VoiceToolName.setTimer,
        CloudToolName.draftEmail, CloudToolName.addTodoistTask,
        // Adding to one of the user's lists (ADR-216): matched and read back when the step runs.
        VoiceToolName.addToList,
    ]
}

public struct PlanStep: Equatable, Sendable, Identifiable {
    /// 1-based, in the order the steps run.
    public let number: Int
    public let toolName: String
    public let request: VoiceToolRequest

    public var id: Int { number }

    /// Nil for notes, which are always on.
    public var connection: VoiceConnection? { VoiceConnection.serving(toolName) }

    public func activity(calendar: Calendar) -> ActivityRequest? {
        ActivityRequest.describe(request, calendar: calendar)
    }

    /// A Gmail draft or Todoist task, run through Doddy's server (ADR-209).
    public var cloudCall: CloudToolCall? {
        if case .cloudTool(let call) = request { return call }
        return nil
    }

    /// "Change" edits the step in the app (ADR-205). Online-account steps can't be changed there:
    /// their preview and approval come from the server for the exact arguments.
    /// A list step isn't changed on the card either: its list is matched when it runs.
    public var canChange: Bool {
        if case .addToList = request { return false }
        return cloudCall == nil
    }

    /// What the step does, for the confirm button ("Add 2 reminders").
    var kind: Kind {
        switch request {
        case .saveMemory: .note
        case .createCalendarEvent: .event
        case .setTimer: .timer
        case .cloudTool(let call): call.name == CloudToolName.draftEmail ? .email : .task
        case .addToList: .list
        default: .reminder
        }
    }

    enum Kind { case note, event, reminder, timer, email, task, list }
}

/// Why a step can't run, decided by the app when the card is shown and again at the tap.
public enum PlanBlock: Equatable, Sendable {
    /// Settings → Pause all.
    case paused
    /// Switched off in Settings → Connections, or not allowed in iOS Settings.
    case notConnected(VoiceConnection)
    /// Doddy's server didn't prepare a Gmail or Todoist step (not set up, switched off, not
    /// connected, unreachable). `screen` is for the card; `reply` is the agent's line.
    case onlineAccount(screen: String, reply: String)
    /// Tried `count` times in the last day without a confirmed result (ActionRetry, ADR-319).
    case tooManyTries(app: ActivityApp, count: Int)

    public var screenText: String {
        switch self {
        case .paused: "Skipped: connections are paused"
        case .notConnected(let connection): "\(connection.title) isn't connected"
        case .onlineAccount(let screen, _): screen
        case .tooManyTries(let app, let count): "Tried \(count) times in the last day without a confirmed result. Look in \(app.title) first."
        }
    }

    /// The step's line in the reply to the agent and in "What Doddy did".
    public var reply: String {
        switch self {
        case .paused: ConnectionPause.reply
        case .notConnected(let connection): "failed: \(connection.title) isn't connected. Nothing was done."
        case .onlineAccount(_, let reply): reply
        case .tooManyTries(let app, let count): VoiceToolReply.retryStopped(count: count, app: app)
        }
    }
}

public enum PlanParse: Equatable, Sendable {
    case plan([PlanStep])
    /// Nothing is shown. The text goes back to the agent (a question to ask, or what was wrong).
    case refused(String)
}

public enum PlanProposal {
    /// `steps` is a JSON array, sent as a string because the tool's parameters are flat
    /// (voice-agent/tools.json). A real array is accepted too.
    public static func parse(parametersJSON: Data, now: Date = Date(), calendar: Calendar = .current) -> PlanParse {
        let args = (try? JSONSerialization.jsonObject(with: parametersJSON)) as? [String: Any] ?? [:]
        let raw: Any?
        if let text = args["steps"] as? String {
            raw = try? JSONSerialization.jsonObject(with: Data(text.utf8))
        } else {
            raw = args["steps"]
        }
        guard let items = raw as? [Any] else {
            return .refused("failed: the plan was incomplete (steps must be a JSON array). Nothing was done.")
        }
        guard !items.isEmpty else { return .refused("failed: the plan has no steps. Nothing was done.") }
        guard items.count <= PlanTool.maxSteps else {
            return .refused("failed: a plan can have at most \(PlanTool.maxSteps) steps. Split it, or ask the user which to do first. Nothing was done.")
        }

        var steps: [PlanStep] = []
        for (index, item) in items.enumerated() {
            let number = index + 1
            guard var fields = item as? [String: Any], let tool = fields.removeValue(forKey: "tool") as? String else {
                return .refused("failed: step \(number) of the plan has no tool. Nothing was done.")
            }
            guard PlanTool.allowed.contains(tool) else {
                return .refused("failed: step \(number) (\(tool)) can't be part of a plan; a plan may only use \(PlanTool.allowed.joined(separator: ", ")). Call \(tool) on its own instead. Nothing was done.")
            }
            let data = (try? JSONSerialization.data(withJSONObject: fields)) ?? Data("{}".utf8)
            let request = VoiceToolRequest.parse(name: tool, parametersJSON: data, now: now, calendar: calendar)
            switch request {
            case .saveMemory, .createCalendarEvent, .createReminder, .setTimer, .addToList:
                steps.append(PlanStep(number: number, toolName: tool, request: request))
            case .cloudTool(let call) where call.isWrite:
                // The server validates the arguments when it prepares the step.
                steps.append(PlanStep(number: number, toolName: tool, request: request))
            case .needsClarification(_, let clarification):
                // The whole plan waits for the answer, so no step runs on a guessed time.
                return .refused("failed: not added yet: step \(number) (\(tool)): \(clarification.problem). Ask the user \(clarification.question), then call \(VoiceToolName.proposePlan) again with their answer. Nothing was done.")
            case .invalid(_, let reason):
                return .refused("failed: step \(number) (\(tool)) was incomplete (\(reason)). Nothing was done.")
            default:
                return .refused("failed: step \(number) (\(tool)) can't be part of a plan. Nothing was done.")
            }
        }
        return .plan(steps)
    }

    /// The confirm button counts what will happen: "Add 1 reminder", "Add 2 events", "Do 3 things".
    public static func confirmTitle(_ ticked: [PlanStep]) -> String {
        guard let first = ticked.first else { return "Nothing ticked" }
        let count = ticked.count
        guard ticked.allSatisfy({ $0.kind == first.kind }) else { return "Do \(count) things" }
        func counted(_ word: String) -> String { "\(count) \(word)\(count == 1 ? "" : "s")" }
        switch first.kind {
        case .note: return "Save \(counted("note"))"
        case .event: return "Add \(counted("event"))"
        case .reminder: return "Add \(counted("reminder"))"
        case .timer: return "Start \(counted("timer"))"
        case .email: return "Draft \(counted("email"))"
        case .task: return "Add \(counted("task"))"
        case .list: return count == 1 ? "Add to the list" : "Add to \(count) lists"
        }
    }
}

/// Text returned to the agent for a plan. Each step keeps its own result line, with the same
/// prefixes as the single-step tools, so the agent never hears "done" for a step that wasn't.
public enum PlanReply {
    public static let declined = "declined: the user chose not to do this plan. Nothing was done."
    public static let unticked = "declined: the user unticked this step. Nothing was done."

    /// `changed` are the steps the user edited on the card (ADR-205): the agent is told, so it
    /// repeats what was actually done rather than what it first proposed.
    public static func summary(_ results: [(step: PlanStep, reply: String)], changed: Set<Int> = []) -> String {
        var lines = ["plan: one result per step, in order. Tell the user each one. Only say a step was done if its line starts with \"added:\", \"saved:\" or \"drafted:\"."]
        for result in results {
            let text = result.reply.replacingOccurrences(of: "\n", with: " ")
            let note = changed.contains(result.step.number) ? " (The user changed this step on screen before it ran; use these details, not your proposal.)" : ""
            lines.append("\(result.step.number). \(text)\(note)")
        }
        return lines.joined(separator: "\n")
    }
}
