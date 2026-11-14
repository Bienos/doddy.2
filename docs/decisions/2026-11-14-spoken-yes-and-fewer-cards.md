# A spoken yes is enough for everything but money and bookings; Doddy's own undoable things run at once

- **Date:** 2026-11-14
- **Decided by:** owner, 14 Nov 2026: "Ogólnie … co chwilę trzeba coś potwierdzać … karty potwierdzenia lepiej nie cb to mówi a nie potrzebuje kliknięcia zawsze … to psuje flow", then chose "„Tak” głosem na wszystko" (a spoken yes for everything; only payments and bookings keep a tap) and allowed building on #453
- **Status:** accepted; step 1 of 3 in the pull request that adds this file
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
2. **The app follows the table** (after #453 is merged): the voice controller runs the at-once tools without their card and says what it did, keeps Undo, lets the own-payload cards take a spoken yes, and keeps tap only for the third tier. `doddy_rules.yaml`, `voice-agent/tools.json`, `scripts/voice_agent_spec.py` and `docs/trust/ASK_FIRST.md` change in the same pull request, so the rules never say something the code doesn't do.
3. **The live agent** (the owner's separate word, after a TestFlight build with step 2): the prompt's "A spoken yes is not enough there" and the tools' descriptions change to "read the exact payload, then a yes is enough; payments and bookings need a tap". Changing the agent first would tell people to say yes to an app that still waits for a tap.

## Consequences
- Fewer stops: a timer, an alarm, a reminder or a note from the Action Button no longer needs the phone in hand; a message or a calendar change needs only "tak" after Doddy reads it.
- **Risks that stay, said plainly:** speech can be misheard, and the app can't tell the owner's voice from someone else's in the room or on a TV; the strict yes, the read-out payload and the vetoes lower this, they don't remove it. A send or a call made on a misheard yes reaches another person and can't be undone. Payments and bookings stay on a tap for that reason.
- At-once tools must keep a one-step Undo where they change something; step 2 checks each against `ActivityUndo` and keeps the card for any that has none.
- The constitution's `ask_first` section and `docs/trust/ASK_FIRST.md` change with step 2 (a sensitive path: the pull request says why).

## Evidence
- Run (Linux, Swift 6.1.3): `ConfirmationTierTests`, written first and seen red, then green; the results and the deliberate breaks are in the pull request.
- Not run: nothing in the app uses the table yet; no device.
