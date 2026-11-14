# A spoken yes is enough for everything but money and bookings; Doddy's own undoable things run at once

- **Date:** 2026-11-14
- **Decided by:** owner, 14 Nov 2026: "Ogólnie … co chwilę trzeba coś potwierdzać … karty potwierdzenia lepiej nie cb to mówi a nie potrzebuje kliknięcia zawsze … to psuje flow", then chose "„Tak” głosem na wszystko" (a spoken yes for everything; only payments and bookings keep a tap) and allowed building on #453
- **Status:** accepted. Step 1 (the table) in the pull request that added this file; step 2a (a spoken yes answers every card but tap-only ones) in the next; steps 2b, 2c and 3 open (below)
- **Replaces:** in part, `2026-11-11-asked-for-runs-at-once` ("changes keep their card") and the `changes: tap_on_card_with_exact_payload` line of `docs/trust/config/doddy_rules.yaml`, once step 2 lands

## Why
Read on 14 Nov 2026: 67 of the 121 voice tools need a tap on a card (`voice-agent/tools.json`), and a spoken yes is refused for every change (`AskLedger`: "a spoken yes for a change … the card stays up"; the live prompt: "A spoken yes is not enough there"). Among them are a timer, an alarm, a reminder, a note, a list and opening Maps. From the Action Button or the island each card means taking the phone out and tapping, so the conversation stops. The research packs of 12 Nov say the same: confirmation should follow risk and reversibility, not be the same for everything.

## Decision
Three tiers (`ConfirmationTiers` in DoddyCore):

| Tier | What | Tools |
|---|---|---|
| **At once** | Runs when asked; Doddy says what it did; Undo where it changed something | everything that runs at once today, plus Doddy's own undoable things on the phone: `set_timer`, `set_alarm`, `create_reminder`, `save_memory`, `remind_me_about_note`, `remind_when_to_leave`, `parking_spot` (save, find), `create_list`, `add_ingredients`, `open_map`, `open_camera`, `open_food_app`, `undo_last`, `lost_wallet`, and the drafts the person sends themselves: `draft_message`, `draft_blik_transfer`, `draft_invoice`, `make_presentation` |
| **Spoken yes** | The card shows the exact payload and Doddy reads it out; a tap or the person's own short "tak" said after the card appeared runs exactly that | every other change: calendar, reminders, alarms cancelled, list items removed, the parking spot forgotten, shortcuts, the home, plans, calls to the person's own phone, handed-over tasks and Studio jobs, and every write through an online account (sending, replying, forwarding, trashing email; events; Todoist; Notion; Drive) |
| **Tap only** | Only a tap on the card | `pay_for_page`, `book_flight`, `call_places` (it books or orders by phone) |

- **The yes is strict** (`SpokenYes`, unchanged): a short answer that is only a yes, from the person's own side of the conversation; "nie", "czekaj", "ale" anywhere undoes it. One yes covers one action, exactly the payload on the card, within the card's time; a changed payload needs a new yes (DOD-07 is kept: the approval is still bound to the exact payload, it can now be spoken after Doddy read it out).
- **After outside text, a tap again.** Once an email, a web page, a document, an online account or the shared screen has put text into the conversation (#453, `OutsideContentSession`), a spoken yes is not enough for anything on the spoken-yes tier: those words could have led to the ask.
- **A tool nobody classified is tap only**, so a new tool fails safe until it is put in a tier.

Steps:
1. **This pull request:** the table and its tests in DoddyCore. Nothing in the app reads it yet.
2. **The app follows the table**, in three parts so each stays reviewable:
   - **2a, a spoken yes answers the cards.** Every card but the tap-only ones takes the person's own yes (`SpokenConfirmation` in DoddyCore, `spokenAnswer` in the voice controller): the strict `SpokenYes`, from the user's side only, at least **one second** after the card appeared (Doddy has begun reading it out; words left over from before don't count) and within its 120 s, and never while the card waits for the person to choose something (several places Maps found for a note's reminder). A card that changes on screen counts from its change. The cards `AskFirst` makes (removing from a list, forgetting the parking spot, a task handed over, a Studio job, opening a food app) are `.yesFirst` and turn back into a tap once outside text is in the conversation; the tools' own payload cards and the server's write cards are checked against the tier as it is when the yes is heard. `doddy_rules.yaml`, `voice-agent/tools.json` (`x_doddy.ask`: `yes_or_tap` for 64 tools, `tap` for the three), `scripts/voice_agent_spec.py`, `scripts/check_forbidden_capabilities.sh`, `docs/trust/ASK_FIRST.md` and the screens' "only after you tap" lines change with it.
   - **2b, at once.** The at-once tools that change nothing or already have Undo lose their card: `save_memory`, `create_reminder`, `add_ingredients`, `undo_last`, the drafts and hand-overs (`draft_message`, `draft_blik_transfer`, `draft_invoice`, `make_presentation`, `lost_wallet`, `open_map`, `open_camera`, `open_food_app`, the last four only while Doddy is on screen, so "opened" is never said of something iOS didn't open).
   - **2c, Undo first, then at once.** `set_timer`, `set_alarm`, `create_list`, `remind_me_about_note`, `remind_when_to_leave` and saving the parking spot have no Undo in "What Doddy did" (`ActivityUndo`), and a new parking spot replaces the old one for good; each keeps its card, answered by a yes, until it has one.
3. **The live agent** (the owner's separate word, after a TestFlight build with step 2): the prompt's "A spoken yes is not enough there" and the tools' descriptions change to "read the exact payload, then a yes is enough; payments and bookings need a tap". Changing the agent first would tell people to say yes to an app that still waits for a tap.

Known gaps of 2a, said plainly:
- **The yes words** cover English, Polish, German, French, Spanish, Italian, Dutch and Portuguese (`SpokenYes`). Croatian, Japanese and Chinese have none, so there the English "yes" is the only spoken yes, and those screens show the English line about it. Adding words for them is the owner's call (the list's own comment).
- **The agent still says "tap"** until step 3: its prompt and tool descriptions are unchanged, so a person may hear "tap the card" and find that "tak" also works.

## Consequences
- Fewer stops: a timer, an alarm, a reminder or a note from the Action Button no longer needs the phone in hand; a message or a calendar change needs only "tak" after Doddy reads it.
- **Risks that stay, said plainly:** speech can be misheard, and the app can't tell the owner's voice from someone else's in the room or on a TV; the strict yes, the read-out payload and the vetoes lower this, they don't remove it. A send or a call made on a misheard yes reaches another person and can't be undone. Payments and bookings stay on a tap for that reason.
- At-once tools must keep a one-step Undo where they change something; step 2 checks each against `ActivityUndo` and keeps the card for any that has none.
- The constitution's `ask_first` section and `docs/trust/ASK_FIRST.md` change with step 2 (a sensitive path: the pull request says why).

## Evidence
- Run (Linux, Swift 6.1.3): `ConfirmationTierTests`, written first and seen red, then green; the results and the deliberate breaks are in the pull request.
- Not run: nothing in the app uses the table yet; no device.
