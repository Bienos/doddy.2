# One control talks to Doddy: the duplicate control and the "Talk in the Island" shortcut are gone

- **Date:** 2026-11-15
- **Decided by:** owner (Pat, 15 Nov 2026): "Masz w kodzie … kilka buildów do włączania, a Action Button powinien być jeden, ten co ci wysłałem" (the code has several variants to switch on; there should be one Action Button, the one whose island they sent: the small island with his face and the fine lines). Earlier the same day: "Ma zostać tylko Doddy z liniami a nie kilka buildów bez sensu … są 4 opcje do Dynamic Island".
- **Status:** applied in the pull request of branch `claude/optimistic-keller-4r9elt`. Not verified on a device.
- **Replaces:** the "kept so a button that has it keeps working" part of ADR-632 and `docs/implementation/ACTION_BUTTON_ISLAND.md` (the second control); ADR-577's "Talk in the Island" Shortcuts action.

## Why
Four entries about talking to Doddy showed up where the owner picks what the Action Button does: two Controls called "Talk to Doddy" with the same symbol and the same action (`TalkToDoddyControl`, kind `com.bienos.doddy2.talk`, and `TalkInIslandControl`, kind `com.bienos.doddy2.talk-island`, the ADR-577 control kept after ADR-632), the Shortcuts action "Talk in the Island" (`TalkInIslandIntent`, listed in Shortcuts only, and run by no control since ADR-632), and the App Shortcut "Talk to Doddy" (`TalkToDoddyIntent`, which opens the app). Nothing told them apart, and a wrong pick gave a different result (the app opening instead of the island).

## Decision
- **One control** talks in the island: `TalkToDoddyControl` ("Talk to Doddy", kind `com.bienos.doddy2.talk`, `TalkButtonIntent`). The second control `TalkInIslandControl` and the intent `TalkInIslandIntent` ("Talk in the Island") are deleted, with `TalkInIsland.start()` (its only caller) and their translation lines.
- **Kept:** the App Shortcut "Talk to Doddy" (`TalkToDoddyIntent`), which is how Siri and Back Tap start a conversation ("Talk to Doddy", "Hey Doddy"). It also appears in Action Button › Shortcut; iOS lists every App Shortcut there and the app can't hide one from that list without removing it from Siri.
- **Settings already offers no Action Button choice** (ADR-593); the Siri and Back Tap choice (start a conversation, or only open Doddy) is a different setting and stays.

## Consequences
- The picker shows one Doddy control that talks. **An Action Button, Control Center or Lock Screen control that was set to the removed one (kind `com.bienos.doddy2.talk-island`) is empty after the update** and has to be set to "Talk to Doddy" once; iOS remembers a control by its kind. Nothing else is lost.
- A Shortcuts-app shortcut that used "Talk in the Island" stops working. The owner is the only user.
- The App Shortcut "Talk to Doddy" opens the app, so Action Button › Shortcut gives a different result from Action Button › Controls. That stays, for Siri.

## Evidence
- `make test-core` and `scripts/ci.sh --only checks` (the strings check found the two stale Polish lines and passes after they were removed): see the pull request.
- Not run: **the app and the widget extension are not compiled** here (no Xcode): the widget bundle, `TalkInIsland`, `StartRecordingIntent` and `StartRecordingControl` are checked by `swiftc -parse` only; the hosted `ios-build` job is their first compile. Nothing was seen on a device.
