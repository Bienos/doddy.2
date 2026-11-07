import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// "Turn off the living room lights" / "Run Good night" (HomeKit, owner 28 Oct 2026).
// A model only proposes a `HomeCommand`. This file decides whether it is allowed, which exact
// accessory or scene it means, what the approval card says, and what Doddy may claim afterwards.
// The HomeKit calls themselves (HMHomeManager) live in the app and are NOT BUILT yet.
// Rules: a change to the home needs the person's tap bound to the exact payload (ASK-01);
// "done" only when HomeKit confirmed it; `unknown` is never success and is never retried.

public enum HomeAccessoryKind: String, Equatable, Sendable {
    case light, outlet, fan, thermostat
    /// Never controlled by Doddy: a wrong or injected command could let someone in or turn off safety.
    case lock, garageDoor, securitySystem, camera, doorbell, other

    public var isControllable: Bool {
        switch self {
        case .light, .outlet, .fan: true
        default: false
        }
    }
}

public struct HomeAccessory: Equatable, Sendable {
    public let id: String
    public let name: String
    public let room: String?
    public let kind: HomeAccessoryKind
    public let reachable: Bool

    public init(id: String, name: String, room: String?, kind: HomeAccessoryKind, reachable: Bool) {
        self.id = id; self.name = name; self.room = room; self.kind = kind; self.reachable = reachable
    }
}

public struct HomeScene: Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// What the app read from HomeKit on this iPhone. Never leaves the phone as a whole.
public struct HomeSnapshot: Equatable, Sendable {
    public let accessories: [HomeAccessory]
    public let scenes: [HomeScene]

    public init(accessories: [HomeAccessory], scenes: [HomeScene]) {
        self.accessories = accessories; self.scenes = scenes
    }
}

/// What the model asked for, in the person's words.
public enum HomeProposal: Equatable, Sendable {
    case power(on: Bool, name: String, room: String?)
    case scene(name: String)
}

/// A request resolved to exact HomeKit ids. This is what the card shows and what the tap approves.
public enum HomeCommand: Equatable, Sendable {
    case power(on: Bool, accessoryID: String, accessoryName: String, room: String?)
    case runScene(sceneID: String, sceneName: String)

    /// The card's sentence. Built from HomeKit's own names, never from the model's words.
    public var cardText: String {
        switch self {
        case let .power(on, _, name, room):
            "Turn \(on ? "on" : "off") \(name)\(room.map { " in \($0)" } ?? "")?"
        case let .runScene(_, name):
            "Run the scene \u{201C}\(name)\u{201D}?"
        }
    }

    /// Identifies this exact payload, so an approval cannot be reused for another command.
    public var digest: String {
        let payload: String
        switch self {
        case let .power(on, id, _, _): payload = "power|\(on)|\(id)"
        case let .runScene(id, _): payload = "scene|\(id)"
        }
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum HomeResolution: Equatable, Sendable {
    case ready(HomeCommand)
    /// Several matches: ask the person which one. Never pick for them.
    case ambiguous([String])
    case notFound
    case refused(reason: String)
    case unreachable(name: String)
}

extension VoiceToolName {
    public static let controlHome = "control_home"
}

extension HomeProposal {
    /// The model's words, for the activity line only. The card shows HomeKit's names instead.
    public var summary: String {
        switch self {
        case let .power(on, name, room): "Turn \(on ? "on" : "off") \(name)\(room.map { " in \($0)" } ?? "")"
        case let .scene(name): "Run \u{201C}\(name)\u{201D}"
        }
    }
}

extension VoiceToolRequest {
    /// `action`: "on", "off" or "scene". `name` is the accessory or scene; `room` only narrows an accessory.
    static func parseControlHome(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let action = args.text("action")?.trimmingCharacters(in: .whitespaces).lowercased() else {
            return .invalid(name: name, reason: "action must be on, off or scene")
        }
        guard let target = args.text("name")?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .invalid(name: name, reason: "name is required: the light, outlet, fan or scene the user named; ask them which")
        }
        switch action {
        case "on", "off":
            return .controlHome(.power(on: action == "on", name: target, room: args.text("room")?.trimmingCharacters(in: .whitespacesAndNewlines)))
        case "scene":
            return .controlHome(.scene(name: target))
        default:
            return .invalid(name: name, reason: "action must be on, off or scene")
        }
    }
}

public enum HomeCommandRules {
    public static func resolve(_ proposal: HomeProposal, in home: HomeSnapshot) -> HomeResolution {
        switch proposal {
        case let .scene(name):
            let matches = home.scenes.filter { fold($0.name) == fold(name) }
            switch matches.count {
            case 0: return .notFound
            case 1: return .ready(.runScene(sceneID: matches[0].id, sceneName: matches[0].name))
            default: return .ambiguous(matches.map(\.name))
            }
        case let .power(on, name, room):
            var matches = home.accessories.filter { fold($0.name) == fold(name) }
            if let room, !room.isEmpty {
                matches = matches.filter { $0.room.map { fold($0) == fold(room) } ?? false }
            }
            guard !matches.isEmpty else { return .notFound }
            if let blocked = matches.first(where: { !$0.kind.isControllable }) {
                return .refused(reason: "Doddy doesn't control \(blocked.kind.rawValue) accessories; use the Home app.")
            }
            guard matches.count == 1 else {
                return .ambiguous(matches.map { [$0.room, $0.name].compactMap { $0 }.joined(separator: " ") })
            }
            let accessory = matches[0]
            guard accessory.reachable else { return .unreachable(name: accessory.name) }
            return .ready(.power(on: on, accessoryID: accessory.id, accessoryName: accessory.name, room: accessory.room))
        }
    }

    /// The tap approves exactly one command. Anything else is refused.
    public static func isApproved(_ command: HomeCommand, approvedDigest: String?) -> Bool {
        approvedDigest == command.digest
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// What HomeKit said after the call. Only `.confirmed` may be reported as done.
public enum HomeOutcome: Equatable, Sendable {
    case confirmed
    case failed(String)
    /// Timed out or no answer: the home may or may not have changed. Never retried by itself.
    case unknown
}

extension VoiceToolReply {
    public static func home(_ command: HomeCommand, outcome: HomeOutcome) -> String {
        switch outcome {
        case .confirmed:
            "changed: HomeKit confirmed it. \(command.cardText.replacingOccurrences(of: "?", with: "")). Say it in one short sentence."
        case let .failed(reason):
            "failed: HomeKit didn't do it (\(reason)). Nothing changed that you know of; don't say it worked."
        case .unknown:
            "unknown: HomeKit gave no answer, so the home may or may not have changed. Don't say it worked and don't try again; tell the user to look at the Home app."
        }
    }

    public static let homeDeclined = "declined: the user said no. Nothing was changed. Say so in one short sentence."
    public static let homeNotAllowed = "not allowed: the user hasn't let Doddy use Home. Say so and don't ask again."
    public static let homeNotFound = "not found: no accessory or scene has that name. Don't guess one; ask the user for the name."
    public static func homeAmbiguous(_ names: [String]) -> String {
        "not changed: more than one matches (\(names.joined(separator: ", "))). Ask the user which one."
    }
    public static func homeRefused(_ reason: String) -> String { "not changed: \(reason) Say so in one short sentence." }
    public static func homeUnreachable(_ name: String) -> String {
        "not changed: \(name) isn't responding in HomeKit. Nothing was changed; don't say it worked."
    }
}
