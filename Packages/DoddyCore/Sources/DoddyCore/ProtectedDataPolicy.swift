import Foundation

/// Voice tools while the iPhone is locked (ADR-723). A conversation can go on after the iPhone locks
/// (background audio, the island). With the Face ID lock on, the person asked for their things to stay
/// behind Face ID, so once iOS says protected data is unavailable (the iPhone is locked) the tools that
/// read or change them stop: notes and lists, contacts, calendar and reminders, photos, health, accounts
/// and anything else of theirs. Sums and Doddy's own timers keep working, and they can always be stopped.
/// With the lock off, or the iPhone unlocked, every tool runs exactly as before.
///
/// Fail closed: a tool not listed in `openTools` (a new one included) counts as reaching the person's things.
/// The voice controller asks `allows` before a call's own handling and, when it is false, answers `reply`.
public enum ProtectedDataPolicy {
    /// Tools that neither read nor change anything of the person's: sums, unit and currency conversion
    /// (public ECB rates, ADR-300), the lost-wallet steps (public pages, ADR-692), and Doddy's own timer,
    /// stopwatch, focus timer, wind-down and translator on this iPhone, which can always be stopped.
    public static let openTools: Set<String> = [
        VoiceToolName.calculate, VoiceToolName.convertUnits, VoiceToolName.convertCurrency, VoiceToolName.lostWallet,
        VoiceToolName.setTimer,
        VoiceToolName.startStopwatch, VoiceToolName.stopStopwatch, VoiceToolName.checkStopwatch,
        VoiceToolName.startFocus, VoiceToolName.stopFocus, VoiceToolName.checkFocus,
        VoiceToolName.startWindDown, VoiceToolName.stopWindDown,
        VoiceToolName.startTranslator, VoiceToolName.stopTranslator,
    ]

    /// True when `tool` may run now. False only with the Face ID lock on, the iPhone locked
    /// (`protectedDataAvailable` false) and a tool that isn't open.
    public static func allows(tool: String, protectedDataAvailable: Bool, appLockOn: Bool) -> Bool {
        guard appLockOn, !protectedDataAvailable else { return true }
        return openTools.contains(tool)
    }

    /// What the agent hears instead of a result. Nothing was looked up or changed.
    public static let reply = "locked: the iPhone is locked and the user has Doddy's Face ID lock on, so Doddy can't read or change their notes, lists, contacts, calendar, reminders or accounts right now. Nothing was looked up, saved or changed. Tell the user in one sentence to unlock the iPhone and ask again."
}
