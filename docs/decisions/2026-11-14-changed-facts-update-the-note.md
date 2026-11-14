# A new note that changes an old one is offered as an update to that note, not saved as a second note

- **Date:** 2026-11-14
- **Decided by:** owner chose "Zmienione fakty (Recommended)" from the memory directions (14 Nov 2026), after "ta pamięć to chyba trzeba trochę lepszą zrobić"
- **Status:** proposed; step 1 of 3 is in the pull request that adds this file
- **Replaces:** nothing; builds on ADR-252 (a note keeps every wording it has had)

## Why
Today a changed fact becomes a second note next to the first, and nothing says which is current. Read in the code on 14 Nov 2026:
- Saving a new note only warns about the same words (`DuplicateNote`). "Gate code is 5555" beside a saved "Gate code 4821" is offered as new (`SaveSuggestions.isCovered` says so: a different number is new information).
- `RecallConflicts` flags notes that disagree in digits only, and never picks one. "Mieszkam w Warszawie" and "Mieszkam w Berlinie" have no digits and are not flagged.
- A correction with history already exists (ADR-252, `MemoryStore.correct`, `MemoryHistory`): every wording a note has had is kept with its date. It is reached only by editing the note by hand. No conversation, card or typed save leads to it.
- The search index holds the current wording only, which is right for "where do I live", so the earlier wordings are seen on the note, not found by recall.
- A sentence like "mieszkam teraz w Berlinie" never reaches the after-conversation suggestions (`SaveSuggestions.evaluate` scores it 0; the threshold is 3). Changed facts arrive through an explicit "remember…" or a typed save, so the offer belongs at the moment a note is saved.

So no migration and no new table are needed: the part to build is the way from a new note to the existing correction.

## Decision
1. **Step 1 (this pull request): the rules.** `NoteUpdateMatch.offer(forNewText:notes:privateIDs:)` in DoddyCore returns the one saved note the new words may replace, or nil. Rules, not a model; it only offers and saves nothing.
   - The same words with a different number: every number differs, the other words are the same (one side's a subset of the other's, at least two words).
   - A fact with one value: where a person lives and where they work (a short table, Polish and English); same slot, different first word of the value. Things that add up (likes, allergies) are never on it.
   - Exactly one saved note. Two that fit means no offer: nobody knows which one changed.
   - Never a private note (the caller passes `PrivateNotes.ids`), a list or a sample.
2. **Step 2 (next pull request): the offer on the save screens.** Where a note is about to be saved (the voice save card, a typed save in Messages, the new-note editor), when `offer` returns a note, the card shows the old words and two actions: "Update that note" and "Save as a new note". Update goes through `MemoryStore.correct` (ADR-252); the screen says "Updated" only after the store's read-back, otherwise it says what failed and the note is unchanged. A card the person ignores changes nothing. Touches `VoiceView.swift` and `VoiceSessionController.swift` (hot files; open #453 edits the controller, so that part waits for it), `l10n/` strings, and a UI test.
3. **Step 3 (only if wanted): history in recall.** A question about the past ("where did I live in March?") answered from a note's earlier wordings with their dates, with its own evaluation. Not started.
- Not decided here, for the owner: a voice tool `correct_memory` that lets the agent propose the target note. It needs a change to the live agent's tools (the owner's step) and `tools.json`.

## Consequences
- A person who says "remember that I live in Berlin" with "Mieszkam w Warszawie" saved is offered to update it, and the old wording stays in its history with its date.
- **False offers and misses, by design.** "San Francisco" and "San Jose" look like the same place (the first word of the value is compared); "Przeprowadziłem się do Warszawy" differs from "Mieszkam w Warszawie" only by the case ending and is offered; a change in words the table doesn't know (a new job without "pracuję") gets no offer and stays a second note, as today. A wrong offer costs one tap on "Save as a new note". Add a phrase with its tests when one is missed.
- Privacy: a private note's words are never read for the match and never shown on a card. No audio, no server, no new stored data.
- Constitution: DOD-06 (memory the person controls: nothing changes without their tap), DOD-08 (an update is called done only after a read-back, step 2). The rules use only the person's own words and invent nothing.
- Platforms: DoddyCore, used by the iPhone app. The paused Watch and Mac apps don't use it.

## Evidence
- Run (Linux, Swift 6.1.3): `NoteUpdateMatchTests`, 17 tests, written first and seen red (the target did not build without the types), then green. Six deliberate breaks (taking the first match when two fit, not excluding private notes, not requiring the numbers to differ, treating any two slots as the same, one shared word being enough, words not needing to be a subset) were each caught by a test.
- Not run: nothing in the app uses these rules yet (step 2), so nothing on a device or in a UI has changed.
