# A spoken yes answers a card

Decision `2026-11-14-spoken-yes-and-fewer-cards`, step 2a (owner: "„Tak” głosem na wszystko").
- **What changes:** every change still shows its card with the exact payload. The person's own short yes now runs it as a tap would: "tak", "yes" or "jasne", said at least a second after the card appeared and within 120 s (`SpokenConfirmation`, `VoiceSessionController.spokenAnswer`).
- **Tap only:** money and bookings (`pay_for_page`, `book_flight`, `call_places`), any unclassified tool, a card waiting for a choice, and every change once outside text is in the conversation.
- **The rules say the same as the code:** `tools.json` says `yes_or_tap` for 64 tools and `tap` for 3. The spec script, the capability guard, `doddy_rules.yaml`, `ASK_FIRST.md` and the "only after you tap" lines on screen were updated to match.
- **Not changed:** the live agent's prompt and tool descriptions (step 3, the owner's word), and the tools that will run at once without a card (steps 2b and 2c).
