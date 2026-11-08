import Foundation

/// One choice per connected app instead of a switch per tool (ADR-815, ADR-816): Off, look only, or
/// look and act. The server turns the app's per-tool switches on and off to match
/// (`PUT /v1/tools/access`); this type only names the choice and reads it back from the tool list.
///
/// ASK-01 is unchanged by any choice: every look still asks first, and every change still needs a
/// tap on a card that shows exactly what will happen.
///
/// Platforms: iPhone (Settings → Online accounts). Pure, tested on Linux.
public enum AppAccess: String, Codable, CaseIterable, Sendable {
    case off
    /// Doddy may look things up in the account (the read tools). Writes stay off.
    case read
    /// Doddy may also send, add or change things, each only after a tap on its card.
    case act

    /// The choice a tool list amounts to, as the server shows it: `act` if any write tool is on,
    /// else `read` if any tool is on, else `off`. A hand-made mix reads as the nearest of the three.
    public static func of(_ tools: [ToolView]) -> AppAccess {
        if tools.contains(where: { $0.enabled && $0.risk == .write }) { return .act }
        return tools.contains(where: \.enabled) ? .read : .off
    }
}
