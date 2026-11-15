# The big island is gone: Doddy's island is only ever the small one

- **Date:** 2026-11-15
- **Decided by:** owner (Pat, 15 Nov 2026): "Usuń wgl … dużą wyspę i zostaw tylko tą małą najlepiej chyba", after seeing the big island open on an Action Button press although "only the small island" was wanted since 9 Nov and "it switches from big to small" was reported on 12 Nov.
- **Status:** applied in the pull request of branch `claude/optimistic-keller-4r9elt`. Not verified on a device.
- **Replaces:** the island expansion of ADR-577, ADR-579 and ADR-616 (the request that opened the island up when Doddy spoke or a card arrived, and its Settings switch). Follows `2026-11-09-small-island-call-bars` and `2026-11-12-action-button-audio-and-island`, which had made it opt-in.

## Why
The big (expanded) island was a request the app sent to iOS: an alert update of the Live Activity (`VoiceLiveActivity.expand`), from three places, all behind Settings › Voice and personality › "Expand when Doddy speaks". It was off by default since 9 Nov, but a value stored on the owner's phone, or a press that forces it (#334, removed on 12 Nov), kept bringing it back, and the owner wants the small island only. Apple's documentation describes the expanded presentation as the result of touching and holding the island or of an alert, not of an activity starting (search, 15 Nov 2026). So the switch was the only thing the app could be doing to open it.

## Decision
- Removed: the three requests (`TalkInIsland`'s press, `VoiceSessionController.expandIslandIfDue` and `expandIslandForCard`), `VoiceLiveActivity.expand`, the alert update and its sound, `IslandExpansion` (DoddyCore) with its tests, and the Settings row "Expand when Doddy speaks". The Live Activity is updated with content only, never with an alert.
- Kept: the preference key `islandExpands` and the one-time move of Back Tap's old "Small island" into it (`LaunchPreferencesMigration`), because "Erase everything" removes a stored value and the migration is tested. Nothing reads the key any more.
- The Polish line for the removed row is gone from `l10n/pl.json`; the catalog was regenerated.

## Consequences
- The island can no longer open up into the big island on its own, with no sound. A card waiting for the user (a text, a transfer, a calendar change) is shown on the small island's sign as before; the person opens it by touching the island or Doddy.
- iOS may still show the big island if the person touches and holds the island, and iOS draws its own feedback when the Action Button runs a control (the round face, Apple's symbol); the app can't remove that.
- A person who liked the big island loses it. The owner is the only user of the app now; the feature can come back from this decision's history if wanted.

## Evidence
- `make test-core` (Linux, Swift 6.1.2) and `scripts/ci.sh --only checks`: see the pull request.
- Not run: **the app is not compiled** here (no Xcode): `VoiceSessionController`, `VoiceLiveActivity`, `TalkInIsland`, `SettingsScreens` and `IslandBaselineTests` are checked by `swiftc -parse` only; the hosted `ios-build` job is their first compile. Nothing was seen on a device.
