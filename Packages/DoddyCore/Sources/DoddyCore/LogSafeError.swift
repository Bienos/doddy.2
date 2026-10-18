import Foundation

/// What a log line may say about an error: its type and, for an enum, the case name. Never its
/// text or values. A network error's text can include the address it tried, and a voice
/// connection's address can carry its conversation token (constitution: no raw secrets in logs).
public enum LogSafeError {
    public static func kind(of error: any Error) -> String {
        let typeName = String(describing: type(of: error))
        let mirror = Mirror(reflecting: error)
        guard mirror.displayStyle == .enum else { return typeName }
        // A case with values: its label only.
        if let caseName = mirror.children.first?.label { return "\(typeName).\(caseName)" }
        // A case without values: its name, unless the type describes itself (that text is not safe).
        if error is CustomStringConvertible || error is CustomDebugStringConvertible { return typeName }
        return "\(typeName).\(String(describing: error))"
    }
}
