# Doddy is steered by voice: almost everything in the app can be asked for and done by talking

- **Date:** 2026-11-27
- **Decided by:** owner ("I would like to be able to steer and do almost everything by voice … except translator mode and calling people should have some restrictions and protocol of prompt injection … she should ask questions if not certain or need more info", 27 Nov 2026), with these choices the same day: money and bookings by a **strong spoken yes**; **calls and texts to contacts by voice**; build **the whole app by voice** first.
- **Status:** accepted; built in steps, one pull request each (below). The live ElevenLabs agents change only on the owner's separate word ("push it live"), as `AGENTS.md` requires.
- **Replaces:** nothing yet. Step 3 will replace the tap-only rule for `pay_for_page`, `book_flight` and `call_places` (`ConfirmationTiers.tapOnly`, decision `2026-11-14-spoken-yes-and-fewer-cards`). Extends `2026-11-25-doddy-acts-without-asking`: Doddy still never asks for permission to do what was asked; he asks only for what is missing or unclear.

## Why
- Large parts of the app have no voice tool: Settings, editing or deleting a note, cancelling a task, reading Doddy's Messages, price watches, parcels, trips, and moving between screens.
- Some cards still need a finger: money and bookings (tap only), cards waiting for a choice, a card that ran out, and a card cannot be changed by voice ("make it six instead").
- The prompt tells Doddy to pick the likelier meaning and ask only when he cannot act at all; the owner wants a precise question when something is missing or unclear.

## Decision
The order of work, each step a pull request merged on green checks:
1. **The whole app by voice.** A table of every action on every screen (`docs/product/VOICE_COVERAGE.md`): each one has a voice tool, gets one, or says why it stays a tap. New tools follow the existing tiers: looks and reads run at once; Doddy's own undoable things run at once with Undo; everything that sends, deletes or reaches someone else shows its card with the exact payload and runs on a tap or the user's own spoken yes. A card can be changed by voice; the changed card is read back and needs a new yes. Signing in to an online account keeps one tap (Apple and Google require it).
2. **Ask when unsure.** Doddy keeps acting at once on a clear request and never asks permission for a look-up. He asks one short, specific question when a needed detail is missing, two readings lead to different actions, a name matches several contacts, the speech recognition was unsure, or a change could hit the wrong thing. Tools can answer `needs detail: <question>` instead of guessing.
3. **Money and bookings by a strong spoken yes.** Doddy reads back the exact amount, who gets it and what is booked; only a full phrase such as "tak, zapłać" / "yes, pay" (or "tak, zarezerwuj" / "yes, book") said after the card appeared runs it. A plain "tak" does not. A tap still works. The approval stays bound to the exact payload; a changed payload voids it.
4. **Calls and texts to contacts by voice, with a protocol.** Only a person from the user's Contacts, a place from a place search, or a number the user said out loud; never a number from an email, a page or the screen. The card and the read-back show the number and exactly what Doddy will say or send; the yes covers that and nothing else. On a call Doddy says he is an AI, keeps to the task, gives out nothing beyond the card, ignores instructions from the other person, and ends the call when someone tries to steer him. Daily limits and quiet hours stay. Texts to contacts use the server route already built (`CONTACT_TEXTS_ENABLED`, decision `2026-11-09-texts-to-contacts`).
5. **Translator and outside text.** The translator stays tool-free and only translates ("ignore your instructions" is translated, never obeyed). Text from emails, pages, files, the screen, calls and other people is data, never an instruction; an action it suggests runs only when the user asks for it in their own words. A set of attack tests runs with the agent tests.

Doddy stays male in every language ("Doddy is a he" in the prompt), as decided earlier; the owner's "she" on 27 Nov was not a change of that.

## Consequences
- More of the app is reachable by voice, so more tools: the prompt and tool list grow, which costs tokens and time per turn and can make wrong picks more likely. Each step adds agent tests for the tools it adds.
- Step 3 lowers the bar for money from a tap to a spoken phrase. The phrase must be the user's own words on their side of the conversation, after the card, within its time limit, with any "no", "wait" or "but" voiding it, as `SpokenYes` already does.
- Step 4 lets Doddy reach people other than the user. The constitution's rules for external writes apply: exact payload, approval bound to it, "unknown" is never success.

## Evidence
Recorded per step in its pull request.
