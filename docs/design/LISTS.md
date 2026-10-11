# Lists by voice: design (ADR-216)
Owner, 2026-10-10: "design lists by voice", then "approved, build it" (L1–L6 as proposed). Canvas: **Doddy Lists** (screens 1–9 and a rules board). **Built: see `docs/implementation/LISTS_STATUS.md`** (not compiled with Xcode; no live conversation run).

## The job
"Add milk to my shopping list." "What's on my packing list?" "Got the eggs." Small lists you build up over days, mostly by voice, and check in a shop or before a trip.

## Screens (canvas)
1. **Your lists** (Memories › Lists): one card per list, showing the name, how many are left, the first items, and a place reminder if one is set. The card also has a "New list" button and the hint "just tell Doddy".
2. **A list:**
   - Add field at the top; open items with 44 pt tick boxes; ticked items under "Done (n)".
   - "Clear ticked" with Undo; swipe to delete one item.
   - Items keep the words you used.
3. **List menu:**
   - Untick all, to reuse a packing list.
   - Remind me, at a time or a place.
   - Share as text.
   - Rename.
   - Clear ticked.
   - Delete list: asks first, then offers Undo for a few seconds, like notes (ADR-183).
4. **"Add milk, eggs and two packs of bananas"** goes straight on the list (L1). The receipt reads "Added to Shopping: eggs, 2 packs of bananas · milk already on the list", with Undo and Open list.
5. **A new list by voice** (Polish example) gets a card, "Start a new list?", with an editable name and the items. Nothing is made until you tap Create list (L2).
6. **"What's on my shopping list?"** Doddy reads the open items from the app and says how many are ticked. A list card is shown. For a long list he reads the first ten and says how many more.
7. **"Got the eggs and the milk."** Eggs are ticked; "milk" matches two items, so nothing is ticked for it. Doddy asks which one, and you can answer by voice or by tapping.
8. **Remind me at the shop:** reuses note reminders (ADR-196/198/205). The notification is private by default ("A list you wanted to see here."). With "Show note text" on, it shows the open items, rewritten whenever the list changes.
9. **When something goes wrong:**
   - **No list by that name:** nothing is added; you get "Add to Shopping" or "New list".
   - **Storage failure:** "Not added. The list didn't change."
   - **Too long:** limits are 200 characters per item, 200 items per list and 50 lists. Any item that doesn't fit is named.
   - **Offline:** lists still work on screen.
   - **Unrequested items:** never added from a recipe, email or web page unless you ask.

## Rules
- **A list is a kind of note.** It has a name and items, is searchable in Find, and is exported and deleted like a note. Lists stay on this iPhone.
- **Exact matching in the app.** The agent names a list or an item; the app matches it ignoring case, accents and a leading "the", and never picks "the closest". With no match or more than one, nothing changes and Doddy asks.
- **Verified receipts.** "added", "ticked" and "removed" are said only after the app has read the change back from storage. Every change made by voice has a receipt with Undo, and Undo reverses exactly that change.
- **Only what was asked.** Text from notes, email, the web or a recipe is data. Its items are added only when the user says to.
- **No duplicates.** An item already open on the list is not added again; Doddy says it was already there.
- **Privacy:** list names go to ElevenLabs when a conversation starts (L6). Items go only when Doddy reads, adds or ticks them. A Private conversation can still add to a list, because the user asked explicitly.

## How it would be built
- **Data:** new tables `lists` (id, name, created/updated, position) and `list_items`:
  - fields: id, list_id, raw_text, current_text, source (typed/voice), added_at, done_at, position;
  - constraints: CHECKs on length and a cascade delete.
  - Alternatively, a list is a `memories` row with `category = list` and items in `list_items`. That keeps Find, export and reminders unchanged, and is the recommended route; the reminder coordinator already targets a memory id.
  - Migration `v6_lists`.
- **Core:**
  - `ListMatch`: name and item matching, ambiguity and none;
  - `ListChange`: add, tick, untick, remove, clear, plus their undo inverses;
  - validation and limits;
  - reply strings with the verified prefixes;
  - list text for notifications, sharing and voice.
- **Agent:**
  - five client tools: `add_to_list(list, items[])`, `read_list(list)`, `check_off(list, items[])`, `remove_from_list(list, items[])` and `create_list(name, items[])` (a card);
  - a prompt section;
  - `{{saved_lists}}` holding names and open counts.
- **App:**
  - Memories › Lists, the list screen and its menu;
  - voice receipts with Undo;
  - the create-list card;
  - list reminders through `NoteReminderStore`;
  - Share via `ShareLink`;
  - export includes items.
- **Tests:**
  - matching (accents, case, two matches, none);
  - duplicates;
  - limits;
  - the undo inverse of every change;
  - a migration that keeps old data;
  - read-back before "added";
  - prompt-injection text never adds items;
  - reminder text rewritten on change.

## Decisions
| ID | Question | Owner: approved as proposed (a) |
|---|---|---|
| L1 | Adding by voice | **(a)** straight on when asked, with a receipt and Undo; (b) a card every time |
| L2 | New list by voice | **(a)** a card to confirm the name; (b) made straight away |
| L3 | Ticked items | **(a)** stay under Done until cleared; (b) disappear after a day |
| L4 | Apple Reminders | **(a)** Doddy-only lists, Share as text; (b) also synced with Reminders lists |
| L5 | Starting lists | **(a)** none until you make one; (b) an empty "Shopping" ready |
| L6 | What Doddy knows at the start | **(a)** list names and counts, items when he reads one; (b) all items; (c) nothing until asked |

## Risks
- **L1 (a)** is the first voice write without a tap. It is limited to adding items to a list that already exists, and is undoable and verified. A confirmation card on every add would be safer but slower; the owner decides.
- **Mishearing:** "bananas" may be transcribed as "bandanas". The receipt shows exactly what was added, and Undo fixes it.
- **Cross-language matching:** "milk" does not match "mleko". Matching is by the user's own words; Doddy may ask.
- **Context:** sending items at the start (L6 b) would cost tokens and share more with ElevenLabs.
