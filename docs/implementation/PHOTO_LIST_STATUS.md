# A list from a photo: status (ADR-270)
Date: 2026-10-11. Owner: "do all of them" (round 3, item 7).

## What ships
- **New list** has **Read a list from a photo**:
  - Apple's photo picker, which needs no photo library permission;
  - the text is read on this iPhone with Vision, the same reader as photo notes (ADR-218), with language correction off;
  - the photo isn't kept or sent anywhere.
- **Turning text into items** (`PhotoList.proposal`):
  - one item per line, in the words as read;
  - bullets, numbers and checkboxes at the start of a line are dropped (`-`, `•`, `*`, `1.`, `2)`, `[ ]`, `☐`, `✓` and similar);
  - repeats are dropped, like typed items;
  - a first line ending in ":" ("Shopping:") becomes the suggested name, only if the name is still empty.
- **Review:** the items go into the New list editor, under any already typed, with "Read 8 lines from the photo. Check them before Create." Every line can be edited or deleted. Nothing is saved until Create.
- **Limits:** lines over 200 characters, or past 200 items, are left out and counted on screen. A photo with no list lines says so and adds nothing.

## Files
- **Core:** `PhotoNotes.swift` (`PhotoList`).
- **App:** `Features/Photos/PhotoViews.swift` (`ListPhotoPicker`; Vision and the picker stay in `Features/Photos`, as the guard requires); `Features/Lists/ListViews.swift` (`NewListSheet`).
- **Tests:** `PhotoListTests` (2).

## Verified (Linux)
- `PhotoListTests` pass.

## NOT RUN
- No Xcode build, and never tried with a real photo.
- Not known: how well Vision reads handwriting in Polish without language correction. The review step exists because of this.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-07 scoped_action_approval | Read lines only fill the editor; Create saves | — | UI not compiled |
| DOD-06 user_controlled_relevant_memory | Words kept as read, never corrected; every line editable first | `testBulletsAndNumbersGoAndAHeadingBecomesTheName` | Handwriting accuracy unknown |
| DOD-11 observable_privacy | On-device Vision; photo not kept; picker needs no library access | — | — |
