# Lists by voice status (ADR-223)
Date: 2026-10-10. Owner: "design lists by voice", then "approved, build it" (L1–L6 as proposed). Design: `docs/design/LISTS.md`, canvas "Doddy Lists".

## What ships
**On screen**
- **Memories:** a Notes | Lists switch. Lists shows one card per list (name, how many left, first items, a reminder if set) and a New list button. The new-list sheet takes a name and, optionally, first items, one per line.
- **A list:**
  - an add field; open items with 44 pt tick boxes; ticked items under "Done (n)";
  - Clear ticked;
  - swipe to delete an item;
  - the note reminder section;
  - an Undo bar for 8 seconds after every change.
- **Menu:**
  - Untick all.
  - Remind me: the note reminder sheet, time or place, once or repeating.
  - Share as text: the name plus the open items.
  - Rename.
  - Clear ticked.
  - Delete list: asks first; the list and its items come back with the note Undo bar ("List deleted. Undo").
- **Opening a list:** a reminder tap or a link opens the list screen (`MemoryOrListView`).

**By voice (all five tools are live on the agent)**
- **`add_to_list` (L1):** items go straight on with no card, are read back, and show a receipt on the conversation screen: "Added to Shopping", already-there items, items that are too long, the list being full, and Undo.
- **`read_list`:** the open items in order (Doddy reads at most 10 and says how many more), the ticked count, and a receipt with the open items.
- **`check_off` / `remove_from_list`:** only clear matches change. An item that matches several is not changed; the receipt offers those items to tap, and Doddy asks. Items not on the list are named.
- **`create_list` (L2):** a "Start a new list?" card with an editable name; nothing is made until you tap Create list. An existing name gets "not created", and Doddy offers to add to it instead.
- **No list by that name:** nothing changes; Doddy hears the user's list names and asks.
- **Translator mode** refuses list tools, like every other tool.
- **"Pause all connections"** doesn't stop lists, because they never leave the iPhone.

**Rules in code**
- **Matching:** lists and items are matched by `ListMatch`, ignoring case, accents, punctuation and a leading article, plus "list" in a list's name. Items match on the same words, or on one item containing all the words. "milk" never matches "mleko".
- **Recall:** search never returns lists (`RepositoryRecallService`), so Find, Ask and `search_memories` don't show them.
- **Note types:** a note can't become a list, and a list can't become a note type (`ListError.notANote`). Type pickers use `MemoryCategory.noteCategories`.
- **Duplicates:** an item already open isn't added again. Limits are 200 characters per item, 200 items per list and 50 lists, all enforced in code; a CHECK on item length also enforces the 200-character limit.
- **Agent context (L6):** `{{saved_lists}}` holds names with open and ticked counts only. The Home › Translate start sends the not-shared line instead.
- **Reminders:** a list's reminder text is "Shopping: milk, eggs" (or "nothing left"). Doddy rewrites the waiting notification after every change. It is private by default, like notes.
- **Export:**
  - JSON export includes `listItems` (omitted when there are none).
  - The plain-text export in Settings adds a Lists section, with `[ ]` for open items and `[x]` for ticked ones.
- **Privacy text:** Settings › Privacy, "What leaves this iPhone" and the conversation screen footnote now mention list names, and items only when Doddy reads or changes a list.

## Files
- **Core:**
  - `Lists.swift`: model, limits, matching, voice parsing, replies, `ListsPrompt`, `ListRepository`;
  - `MemoryTypes.swift`: `.list` and `noteCategories`;
  - `VoiceTools.swift`: five cases and `Arguments.texts`;
  - `ActivityLog.swift`, `ConnectionPause.swift`, `Search.swift` (recall filter, export), `DataFlow.swift`;
  - `schemas/memory.schema.json`: category `list`.
- **Persistence:**
  - `DoddyDatabase.swift`: `v6_list_items`;
  - `SQLiteListRepository.swift`;
  - `SQLiteMemoryRepository.swift`: export, type guard;
  - `SQLiteNoteReminderRepository.swift`: list reminder text.
- **App:**
  - `Features/Lists/ListViews.swift`: overview, list screen, menu, Undo bar, new-list sheet, `MemoryOrListView`;
  - `MemoryStore.swift` and `MemoryStore+Lists.swift`: lists apart from notes, changes, `ListUndo`, delete with items;
  - `AppEnvironment.swift`;
  - `MemoriesView.swift`, `HomeView.swift`, `RootView.swift`, `MemoryDetailView.swift`, `CaptureView.swift`, `Components.swift`, `SettingsView.swift`;
  - `VoiceSessionController.swift`: tools, `ListReceipt`, card;
  - `VoiceView.swift`: card, receipt.
- **Agent:**
  - `voice-agent/tools.json`: five tools;
  - `instructions.md`, `session.json`, `README.md`;
  - `scripts/voice_agent_spec.py`: array parameters.
- **Tests:**
  - `ListsTests` (9);
  - `SQLiteListRepositoryTests` (6);
  - `DataFlowTests` updated.

## Verified (Linux, Swift 6.2.1)
- **Package tests:** 397 pass (382 before, 15 new). The new tests cover:
  - matching of names and items, including two matches, no match and other languages;
  - duplicates and limits;
  - parsing of all five tools and invalid calls;
  - reply prefixes;
  - the prompt variable holding names only;
  - the text export;
  - on real SQLite: create, add, reopen the file, unique names, notes and lists kept apart, recall never returning a list, rename keeping the original name;
  - tick, clear, Undo and untick;
  - cascade delete;
  - JSON export of items;
  - the item limit;
  - list reminder text.
- **Agent spec check:** passes (29 tools in the spec; the live agent has 30, including `propose_plan`).
- **`scripts/ci.sh --core-only`:** PASS, including the imported-pack check after the schema hash update.
- **`swiftc -parse`:** passes on every changed app file.

## NOT RUN / UNVERIFIED
- **App:** not compiled or run (no Xcode here), and no screen has been seen. Untested on a device: the swipe actions in a `List` inside the Memories `NavigationStack`, the Undo timing, and the menu inside the toolbar.
- **Live conversation:** none run. Unchecked: whether the agent uses list names from `{{saved_lists}}`, sends items as an array, skips the confirm-on-screen line for adds, and asks on "not found".
- **Find and restore (ADR-224):** Find now shows lists that match by name or item, and restoring a JSON export puts list items back. The Markdown export lists them as task lists.
- **Notification wording:** the private body is the general "A note you asked to see again.", the title is "Reminder" and the button is "Open note". The canvas was updated to match. A list-specific wording is not built.
- **Server copy for phone calls** (opt-in): sends notes only, not lists.

## Constitution evidence log (docs/trust/config/doddy_rules.yaml)
| Rule | What enforces it here | Tests run | Gaps / claims to limit |
|---|---|---|---|
| DOD-06 user_controlled_relevant_memory | Items only on the user's request. The prompt says notes, email, web and recipes are not requests. Exact matching in the app, never "closest". Duplicates not added | `testItemsMatchExactlyThenByAllWordsAndNeverGuess`, `testCreateAddDuplicatesAndReopen` | The "only what was asked" rule for adds is enforced by the prompt; the app can't tell why the agent called the tool |
| DOD-07 scoped_action_approval | L1: adds, ticks and removes to an existing local list run on the spoken request without a card (owner-approved), with Undo. A new list needs a tap on a card | `testParsesTheListTools` | First voice write without a tap; limited to local lists, undoable |
| DOD-08 verified_status_and_receipts | Every change is one transaction, read back before success. Replies say "added", "ticked" or "removed" only for what changed, and "not found" or "not changed" otherwise | `testRepliesUseTheVerifiedPrefixes`, `testTickUntickClearRemoveAndUndo` | Controller path not compiled |
| DOD-09 correction_and_recovery | Undo for every change, and for deleting a list (including its items) | `testTickUntickClearRemoveAndUndo`, `testDeletingTheListDeletesItsItemsAndExportCarriesThem` | Undo of an add skips items ticked since |
| DOD-11 observable_privacy | Lists stay on the iPhone. List names (not items) go to ElevenLabs at the start; items only when read or changed. Privacy screens say so. Translator Home start sends none | `testListsPromptHasNamesAndCountsOnly`, `DataFlowTests` | ElevenLabs keeps the conversation, including any items read aloud |

Don't claim: "synced", "shared lists", "works with Apple Reminders", "Doddy understands any wording", or that the app was tested on a device.
