# The beta hides features with one list in code: the release scope

- **Date:** 2026-11-07
- **Decided by:** owner, 7 Nov 2026: "Zacznij od B, zrób przełącznik Hide w DoddyCore", after the review `docs/product/PRZEGLAD_FUNKCJI_2026-11-07.md` (`docs/implementation/GO_LIVE_CHECKLIST.md`, B2)
- **Status:** applied in the pull request from `claude/elegant-bell-te82es`, once merged
- **Replaces:** the numbers this decision had on its branch before it reached `main`: ADR-732, then ADR-813. Both are taken on `main` by other decisions, so cite this file instead.

## Why
Until now a feature could only be shipped or deleted: there was no switch for "Hide" (`GO_LIVE_CHECKLIST.md` B2). The 7 Nov review proposed a beta of the conversation, memory and the iPhone's own apps, and hiding everything that needs a server the beta doesn't keep, a vendor, a permission the beta doesn't ask for, or that has never run on a phone.

## Decision
- `ReleaseScope` in DoddyCore is one list of hidden `Feature`s. `ReleaseScope.shipping` is what the app ships; `ReleaseScope.everything` hides nothing.
- **Shown in the beta:** the conversation (ElevenLabs only), notes and lists, Apple Calendar, Reminders and Contacts, timers, alarms, the stopwatch, sums, the weather and Wikipedia, photo notes and Doddy's camera, Messages behind its own consent, Polish and English. 43 of the 45 features and the eight machine-translated languages are hidden.
- **Hiding is "no way in":**
  - the voice tool is refused by `ToolGate` before anything else (`Decision.hidden`, reply `VoiceToolReply.hidden`, nothing logged);
  - the Home menu item, bottom-bar button and card, the Settings row, the Connections switch, the icon quick action, the language in the picker and the capability in "What I can do" (`CapabilityCatalog.hiding`) go with it;
  - the code and the person's data stay.
- **The build decides, never a server.** A Debug build has Settings › About › Advanced › "Developer: show every feature" (`releaseScope.previewEverything`); a Release build never reads it.
- **Every tool is placed.** Each `Feature` owns its tools, and `ReleaseScopeTests` checks that every tool in `voice-agent/tools.json` is core or belongs to exactly one feature, so a new tool must be placed on purpose. The shipping scope keeps 41 of the 107 tools and lists the 66 to take off the live agent (`docs/implementation/RELEASE_SCOPE.md`); the owner makes that change (owner queue 22).

## Consequences
- The beta can be cut down without deleting code, and the owner can still try any hidden feature on a Debug build.
- The live agent keeps offering hidden tools until the owner takes them off; until then Doddy may offer a feature and the app answers that it isn't in this version.
- **Not covered yet:** the widget bundle's parking widget and recording control, the "Record with DODDY" phrase (it answers "Recording isn't in this version of Doddy."), routines a person turned on in an older build, and the "What leaves this iPhone" text.
- **Features merged into `main` after the list was written aren't in it**, so every build shows them until they are placed. For example, the "A thought is ready for review" routine (ADR-785) is shown in Settings next to the hidden routines.

## Evidence
- **On the branch (7 Nov, Linux, Swift 6.1.3):** DoddyCore 2,422 tests passed, 0 failed (`ReleaseScopeTests` 10, `ToolGateTests` 11); `scripts/typecheck_app_logic.sh`; `voice_agent_spec.py check` (102 tools then); the string catalog check; the capability guard; the platform specs.
- **After merging `main` (7 Nov):** BLIK transfers had been removed from the app (ADR-810), so the `blik` feature and `draft_blik_transfer` left the scope. A static check in Python found every tool in `tools.json` placed once, 60 hidden and 41 kept, matching `RELEASE_SCOPE.md`. `scripts/ci.sh --only checks` was run; Swift was not compiled or run in that session (no toolchain).
- **After merging `main` again (8 Nov):** six new tools from `main` placed (`draft_invoice` with invoices, `text_me` with updates, `call_me_later` with phone calls; `make_something`, `pay_for_page` and `lost_wallet` as the new hidden features `studio`, `payments` and `lostWallet`), so 43 of 45 features and 66 of 107 tools are hidden. A static check in Python found every tool placed once. Swift not compiled or run in that session.
- **Not run:** the app's SwiftUI, App Intents and `RecordingCoordinator` edits were never compiled before the pull request's hosted Mac job. The UI tests launch with everything shown; no UI test of the shipping scope exists. Nothing seen on a device.
