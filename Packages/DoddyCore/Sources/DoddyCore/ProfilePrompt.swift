import Foundation

/// Text for the voice agent's `{{user_profile}}` placeholder: the fields the user reviewed and
/// saved in the introduction. Sent only when the user switched "Use in voice conversations" on
/// (DECISIONS.md ADR-092); otherwise the agent gets `notShared` and knows nothing about them.
public enum ProfilePrompt {
    public static let variableName = "user_profile"

    /// Also the agent's placeholder default, so a build that sends nothing reads the same.
    public static let notShared = "(The user has not shared their introduction answers with voice conversations.)"
    public static let empty = "(The user has not saved any introduction answers.)"

    /// Fixed labels, in a fixed order. Values are the user's own words, already length-limited
    /// by `ProfileKey.maxLength` when they were saved.
    public static func render(_ profile: ApprovedProfile, shared: Bool) -> String {
        guard shared else { return notShared }
        let lines = ProfileKey.allCases.compactMap { key -> String? in
            guard let value = profile.value(key) else { return nil }
            return "- \(label(key)): \(oneLine(value))"
        }
        guard !lines.isEmpty else { return empty }
        return (["The user told you this in the app's introduction and approved it:"] + lines).joined(separator: "\n")
    }

    static func label(_ key: ProfileKey) -> String {
        switch key {
        case .name: "Call them"
        case .help: "What would make you useful"
        case .style: "How they like answers"
        case .language: "Language that feels natural"
        case .humor: "Humour"
        case .context: "What they'd like a hand with these days"
        }
    }

    /// Line breaks would let a value pose as a new prompt line; keep each value on its line.
    static func oneLine(_ value: String) -> String {
        value.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}
