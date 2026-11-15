# A voice conversation ends when the iPhone locks, if Doddy's Face ID lock is on

- **Date:** 2026-11-14
- **Decided by:** the owner approved this work and its edit to the voice controller and `VoiceView.swift` (agent brief, 14 Nov 2026). The points under "Owner decisions" are proposals until the owner says otherwise.
- **Status:** applied in the pull request from `claude/protected-data-mute`
- **Replaces:** the "Not changed (report only): a conversation keeps running if the phone locks" note in ADR-723. `ProtectedDataPolicy` (ADR-723 follow-up) stays and is now used.

## Why
What the code did before, read on 14 Nov 2026:
- Nothing in `DoddyApp` listened for the iPhone's lock. The only use of `isProtectedDataAvailable` was the island's Unmute check (`ProtectedData` in `Shared/VoiceActivity/VoiceActivityIntents.swift`).
- `Config/Doddy-Info.plist` has the `audio` background mode, so a conversation goes on when the iPhone locks: the microphone stays open and audio keeps going to the voice service. Mute on the island is open on a locked iPhone; Unmute needs the iPhone unlocked (`IslandMute`). Neither ends anything.
- The saved notes, lists, profile, learned facts and recent conversations are handed to the agent once, at the start, as dynamic variables (`VoiceSessionController.start`). They cannot be taken back, so a conversation that goes on after the lock can still answer from them, whatever the tools do.
- `handle` had no check on the lock. `ProtectedDataPolicy` (DoddyCore, tested in `AppLockReachTests`) was never called by the controller; `STATUS.md` and `docs/platforms/iphone.md` said so ("not wired").
- The stores are created with `completeUntilFirstUserAuthentication` (`AppEnvironment`, `ConversationLogStore`, `ActivityLogStore` and others), so they stay readable after the first unlock. A tool read on a locked iPhone therefore did not fail and did not come back empty: it returned the data. Only the lock rule can stop it, and it has to be the app's. The one read that depends on the lock itself, Apple Health, already reports it apart from an empty week (`HealthReader`, `Failure.locked`).
- A card waiting when the iPhone locked stayed on the conversation until a tap or a spoken yes; the microphone that hears a yes was still open.
- `AppLock.isLocked` is the Face ID lock's own clock (it comes back after a minute away). A running conversation never asked it.

With "Lock Doddy with Face ID" on, the person asked for their things to stay behind Face ID. A conversation that listens and answers from notes on a locked iPhone does not keep that.

## Options
1. **End the conversation when the iPhone locks, only with the Face ID lock on.** Chosen.
2. **Mute instead of ending.** Rejected: what the agent was given stays in its context and cannot be taken back; the island's Unmute would pick the same conversation up again, which is a resume; and Mute is a toggle that the island can flip either way.
3. **End every conversation when the iPhone locks, lock on or off.** Rejected: a conversation started from the island or the Action Button and carried on in a pocket is a feature (ADR-577, background audio). Only a person who switched the lock on asked for more.
4. **Only refuse the tools (`ProtectedDataPolicy` alone).** Rejected alone: it leaves the microphone open and the agent talking from what it holds. Kept as well, for the moment between iOS's notice and the end finishing.
5. **End as a drop, the way a phone call does (`fail`).** Rejected: a lock is not an error. A drop shows a red warning, keeps what the person said last as a draft, and does not bump the start number, so a start still connecting could carry on.

## Decision
One small pure type in DoddyCore, `ProtectedDataGuard` (`ProtectedDataGuard.swift`), decides; the voice controller does what it says.

| Notice | Conversation | Face ID lock | Result |
| --- | --- | --- | --- |
| iPhone locking | connecting, or listening / thinking / speaking (muted, in a long turn, with a card waiting or not) | on | end with `VoiceSessionEnd.iPhoneLocked` |
| iPhone locking | any | off | nothing: a conversation in a pocket goes on |
| iPhone locking | none (idle, ended, failed) | on | nothing, but the guard remembers the lock |
| the same notice again | any | any | nothing: one lock ends a conversation once |
| iPhone unlocked | any | any | nothing: it never resumes or starts anything |
| start of a conversation | connecting | on, and iOS says the data is unavailable | end at once (iOS says nothing about a lock that was already there, so the start reads its answer once, `sync`) |

1. **Stopping.** `stop(.iPhoneLocked)` is the one way out: it closes the microphone and the agent's connection, drops every card and every yes, and keeps no draft. A card still waiting is cleared at once, before `stop` has had its turn, so a tap in that moment finds nothing to run.
2. **Tools.** Until the end has finished, a call that reaches the person's things (anything not in `ProtectedDataPolicy.openTools`) is refused at the top of `handle`, before anything is looked up or logged, with `ProtectedDataPolicy.reply` and `isError: true`: it starts with "locked:" and says nothing was looked up, saved or changed. Never an empty list, an empty search or a success (DOD-08).
3. **Not resumed.** The unlock changes nothing. A new conversation starts by the person's own request through the existing rules (`AppLockPolicy.startConversation`: held until the Face ID lock is open).
4. **Wording.** The end is `VoiceSessionEnd.iPhoneLocked`, code `locked`; it is not a drop, no recovery draft is made for it, and its status reads "Stopped listening". The voice screen (`VoiceView`, ended state) adds one line: "Doddy stopped listening because the iPhone locked. Unlock it and start a new conversation when you're ready." (Polish in `l10n/pl.json`). The line makes no claim about anything being or not being done; it says only what happened.
5. **Wiring.** Two observers (iOS's protected-data notices) are registered with the existing audio observers and removed with them; one call into the guard per notice; one `sync` at the start. `scripts/check_forbidden_capabilities.sh` has a check that keeps this wired.

### Unchanged on purpose
- A change the person already approved and that is running (a plan after its tap) runs to its end and is logged, as in ADR-458; its result is not sent to the agent, because the conversation is over.
- What every end does stays: the transcript is kept on this iPhone when that is on, a recap note is written on this iPhone when that is on, and Logbook counts the end like "Stop listening" (as ended by the person); the server's `endedBy` is left out for it.
- No new notification, permission or setting, and nothing is added to the island or Lock Screen (the island's "ended" card does not say why).
- An iPhone with no passcode never reports a lock (iOS), so nothing changes there.

### Owner decisions
- **Ending, not muting, and only with the Face ID lock on** (options 1 to 3). Ending for everyone would be a one-line change in the guard's call (`appLockOn`), and a different product choice.
- **A conversation started on a locked iPhone ends at once with the lock on**, even inside the minute in which the Face ID lock still counts as open (`PrivateNotes.relockAfter`). The iPhone's own lock has no such grace. After the minute, the existing rule already holds the start until the unlock.

## Consequences
- With the lock on, a person who locks the iPhone in the middle of a conversation finds it ended and starts a new one; nothing is carried over except the usual "recent conversations" when they are on.
- The line is on the voice screen only. A person who never opens Doddy again after the lock sees the island's usual "ended" card. A Live Activity text for this would be a separate change in `Shared/` and the widget.
- iOS says "will become unavailable" a little before the data goes, and a notice can be late if the app is suspended; a conversation keeps the app running through the audio background mode. Neither was seen on a device.
- Logbook counts "locked" as ended by the person.

## Evidence
- DoddyCore on Linux (Swift 6.1.3): `ProtectedDataGuardTests` (20), written first. Red twice: the build failed with the new types missing, then, with a stub that decides nothing, 15 of the 20 failed. Green with the guard. Six deliberate breaks of the guard each fail it.
- `scripts/check_forbidden_capabilities.sh` gained one check (DOD-08, DOD-11); shown failing on four planted regressions.
- `scripts/typecheck_app_logic.sh` passes for its 48 files; the controller is not among them. The new controller functions and the gate were type-checked in a stand-in harness against DoddyCore, and `VoiceSessionController.swift`, `VoiceView.swift` and `DoddyTests/VoiceSessionControllerTests.swift` were parsed. That is not a build.
- **Not compiled:** the controller, `VoiceView` and the new app-target tests (`ProtectedDataControllerTests`); no Xcode here, the hosted `ios-build` is the first compile. **Not seen on a device:** the notices, the end on a real lock, the line on the screen.
