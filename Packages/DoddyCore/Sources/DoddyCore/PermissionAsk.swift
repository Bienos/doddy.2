import Foundation

// "Let Doddy use Calendar?" (ADR-565, owner 2026-10-20: "every time you want to have access to it,
// you have to have a pop-up that asks for permission ... sliding from the bottom"). When a voice
// tool needs a connection that is switched off in Doddy, or that iOS has refused, the app holds the
// call and slides a sheet up over the conversation instead of answering "not connected" at once.
// Allow turns the switch on (iOS asks with its own prompt the first time) and the call is handled
// again from the start, so its own ask, card and checks still apply (ASK-01). Not now answers the
// agent and isn't asked again in that conversation.
//
// This file is the rule; the sheet and the hold live in the app's voice controller.

public enum PermissionAsk {
    /// What the sheet offers.
    public enum Kind: Equatable, Sendable {
        /// Off in Doddy, and iOS hasn't refused it: Allow turns the switch on, and iOS shows its own
        /// prompt if it has never been asked.
        case turnOn
        /// iOS refused it (now or earlier): only iPhone Settings can allow it again, so the sheet
        /// opens Settings instead of pretending a tap here could.
        case openSettings
    }

    /// `iosRefused` is iOS's own answer for Doddy (denied or restricted), whatever the switch says.
    public static func kind(iosRefused: Bool) -> Kind {
        iosRefused ? .openSettings : .turnOn
    }

    /// Whether the sheet may be shown for this call. One sheet at a time, and never again for a
    /// connection the user said Not now to in this conversation (no nagging).
    public static func mayAsk(_ connection: VoiceConnection, declined: Set<VoiceConnection>, sheetShowing: Bool) -> Bool {
        !sheetShowing && !declined.contains(connection)
    }

    /// What Doddy was asked to do, in the words "What Doddy did" uses, so the user sees why now.
    public static func reason(_ request: VoiceToolRequest, calendar: Calendar = .current) -> String? {
        guard let described = ActivityRequest.describe(request, calendar: calendar) else { return nil }
        guard let detail = described.detail, !detail.isEmpty else { return described.title }
        return "\(described.title): \(detail)"
    }

    // MARK: What the agent hears

    /// The user tapped Not now. Nothing was read or changed.
    public static func declined(_ connection: VoiceConnection) -> String {
        "not allowed: the user chose not to let Doddy use \(connection.title) right now, so nothing was read or changed. Say so in one short sentence and don't ask for \(connection.title) again in this conversation. They can turn it on later in Settings, Connections."
    }

    /// iOS refused it and the user was offered iPhone Settings. Doddy can't see what they do there.
    public static func blocked(_ connection: VoiceConnection) -> String {
        "not allowed: iPhone Settings has \(connection.title) turned off for Doddy, so nothing was read or changed. The app showed the user how to open iPhone Settings. Tell them in one short sentence; once they allow it there, they can ask again."
    }

    /// Asked already in this conversation and the user said Not now: the agent hears it straight away.
    public static func declinedEarlier(_ connection: VoiceConnection) -> String {
        "not allowed: earlier in this conversation the user chose not to let Doddy use \(connection.title), so nothing was read or changed. Don't ask again; they can turn it on in Settings, Connections."
    }
}
