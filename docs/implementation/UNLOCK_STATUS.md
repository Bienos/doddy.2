# Unlock as you go — status (ADR-324)
Date: 2026-10-11. Owner: "go build it, one card with two taps". Decision and rules: `docs/product/UNLOCK_AS_YOU_GO.md`.

**Overall: built on Linux and the live ElevenLabs agent prompt is updated; the iOS app is NOT compiled and NOT run on an iPhone.** The DoddyCore package part is tested here; the SwiftUI and controller part is syntax-parsed only.

## What was built

| Piece | File | What it does |
|---|---|---|
| Unlock model | `Packages/DoddyCore/Sources/DoddyCore/Unlock.swift` | `UnlockNeed` (an iPhone connection, or one online tool), `UnlockStep` (allow connection · connect account · switch on the one tool), `UnlockPlan` (steps, one tap at a time). `UnlockNeed.from(error, tool:)` turns the server's typed refusals (`capability_disabled`, `not_connected`, `connection_expired`, `permission_insufficient`) into a need and nothing else; an expired approval is not one. `UnlockPlan.onlineSteps(for:catalog:accountNotConnected:)` builds the steps from the server's catalog: connect if the account isn't connected, then the switch if the tool is off; web search never connects; nothing to unlock means no card. Replies for declined, iOS-blocked and failed steps never claim access was given. |
| Card state and flow | `DoddyApp/Features/Voice/VoiceSessionController.swift` | `UnlockCard` (stages asking · working · blocked · failed) and `unlock`. The tool call being handled is kept (`currentCall`). A device connection that is off, or an online tool the server refused as off or not connected, now calls `askToUnlock` instead of answering "go to Settings": the agent's call waits like any card. `allowUnlockStep` runs the current step and checks it (iOS permission granted; toolkit status `connected`; tool `enabled`) before the next step shows; after the last step the **same call with the same arguments** runs again through `handle`, so a write still gets its approval card. `declineUnlock` replies "declined" and changes nothing. iOS already denied → stage blocked, agent told, card shows Open iPhone Settings. Connect and switch go through `OnlineAccountsModel`, the same code as Settings, Online accounts (demo servers get their demo tap). |
| Card | `DoddyApp/Features/Voice/VoiceView.swift` | "Let Doddy use Gmail?" with the server's own blurb (never the agent's words), the steps with ticks when there are two, one primary button per step, **Not now**, and "Only this, only because you asked. You can take it back any time in Settings." Blocked and failed states with OK / Open iPhone Settings. The island shows "needs confirmation" while the card waits. |
| Agent prompt (spec) | `voice-agent/instructions.md` | The two Settings lines replaced: say one short line while the card waits, never claim access, never send the user to Settings for this; "declined" is accepted without asking again. |
| Tests | `Packages/DoddyCore/Tests/DoddyCoreTests/UnlockTests.swift` | 11 tests, below. |

Kept: the old in-call "X is off" card (`connectionNeeded`) for the places a permission turns out missing after a tap (iOS took it back mid-way); those have no request to run again. Settings, Connections and Settings, Online accounts unchanged: they are the inventory and the way to take access back (ADR-063, ADR-097). Connecting still never switches a tool on; the switch is its own step and its own tap.

## Verified (Linux, Swift 6.1.2, this session)
```text
$ swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined
Executed 781 tests, with 0 failures (0 unexpected)      # 770 before + 11 UnlockTests
$ swift test ... --filter UnlockTests
Executed 11 tests, with 0 failures
$ swiftc -parse DoddyApp/Features/Voice/VoiceView.swift DoddyApp/Features/Voice/VoiceSessionController.swift   # syntax only
(no output)
$ scripts/check_forbidden_capabilities.sh   → PASS (web auth still only in Connected Apps; the controller uses the existing SystemWebAuthenticator type)
$ scripts/verify_imported_pack.py           → PASS: 259 files
```
UnlockTests cover: only the four server codes raise a card, an expired confirmation and non-server errors never do, web search never asks to connect; disconnected Gmail → connect then the one switch; connected Gmail with `read_email` off → that switch only (no other tool unlocked); already allowed → no steps; unknown tool → no steps; no catalog → the error code decides; guessed toolkit ids match the server's fixtures; the plan advances one tap at a time and stops at the end; replies never say access was given.

## NOT verified (needs the Mac and an iPhone)
- The app does not compile here. `scripts/ci.sh` on the Mac: SwiftUI, `@Observable` observation of `unlockAccounts` (an `OnlineAccountsModel` the controller owns), Swift 6 concurrency diagnostics.
- A real conversation: the ElevenLabs tool-call wait while the user is in the system browser for an account connect (the same risk the write-approval card already has); the request running again after the last tap; a write showing its approval card after the consent card.
- Demo mode end to end (mock server): "Connect demo Gmail" on the card, then the switch, then the request.
- iOS denial: the blocked card and Open iPhone Settings.
- Dynamic Type, VoiceOver order of the step list, dark mode.
- A real conversation against the updated live agent: that Doddy says one short line and waits while the card is up, and accepts "declined" without asking again.

## Live agent (owner: "yes update the live agent too", 2026-10-11)
Agent `agent_0501m4et27vyeawrwqfdxxfszfa6` was re-read first (version `agtvrsn_7001m4nt39q1fhwrhtsyqdegf35g`); both old sentences were present verbatim. Only those two were replaced, with the exact text now in `voice-agent/instructions.md`; the prompt is otherwise unchanged and the 51 tools were not sent. New version `agtvrsn_2901m4ny3aecery96s4qqx3z5zeh`. Not run in a conversation yet.

## Constitution evidence (DOD rules)
- `disallow_model_only_approval`, DOD-07: the card is raised from `UnlockNeed.from(error)` and `DeviceConnections.access`, never from the agent's text; every step is verified against the server's answer or iOS before the next (tests: `testOnlyUnlockableServerCodesRaiseACard`, `testConnectedAccountWithToolOffNeedsOnlyThatSwitch`).
- `minimum_needed_permissions`: one connection, one account, one tool per request (`onlineSteps` never adds a second tool).
- "Done only on trusted confirmation": the request's own reply still comes from the server or iOS after the re-run; the consent flow itself replies only declined / blocked / failed.
- No memory of a decline; nothing stored beyond the same switch Settings would set.
- Claims to limit: nothing here is "implemented and tested" on an iPhone; the Linux tests prove the pure logic and the reply wording only.
