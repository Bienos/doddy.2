# Doddy's asks pop up as a card, and what he finishes arrives in Messages

- **Date:** 2026-11-10
- **Decided by:** owner: "czy to może po prostu się pojawiać z góry lub z dołu, na przykład jakiś taki pop-up"; "ma być ze wszystkim prawie jak coś chce się zapytać"; "on powinien takie rzeczy potem wysłać do wiadomości a nie zadania … i mieć miejsce z plikami"; "dobra, daj mi chwilę, coś poszukam i ci dam znać i on potem to wysyła w wiadomościach swoich na apce z opisem"; "zrób wszystko"; and on the transcript footnote: "usuń to".
- **Status:** applied in the pull request from `claude/determined-cray-wqlagk`
- **Replaces:** the transcript as the only place a card or result is shown (ADR-595 kept: the conversation stays on Home)

## Why
Read from the ElevenLabs log on 10 Nov 2026:
- `conv_3301m724…` (directions to Park Żerański): every `open_map` was refused with "Another item is waiting for the user's answer". The owner said "nie widzę tego": a card he couldn't see blocked every later card. `open_map` could only search one place, so "z Kocimskiej 4 do parku" went into the Maps search box, not into directions.
- `conv_1501m701…` (a report on Warsaw cafés): it went to `hand_over_errand`. Doddy said the result would be "w Zadaniach". The owner expected it in Messages.
- `conv_9201m70j…` (a deck about Warsaw): `make_document` showed only an Open button in the transcript, with no way to save the file or send it on.

## Decision
1. **The card pops up from the bottom.** A card that waits for a tap, or something Doddy just made or found (a file, a contact, the parking spot, a presentation, photos, the lost-wallet steps), opens the conversation's sheet as a card at half height. The sheet shows only those cards, and "Show the conversation" opens the whole transcript. Home stays usable behind it. The card closes by itself once nothing on it is left.
2. **The newest ask wins.** A new card replaces one still waiting. Nothing on the replaced card runs, and its tool call is answered `declined: a newer request replaced this card…` (`VoiceToolReply.replacedByNewerAsk`).
3. **Directions.** `open_map` takes an optional `from` and `mode` (driving, walking, transit). With either one it opens Apple Maps directions (`daddr`/`saddr`/`dirflg`). The reply says Doddy can't see the route Maps chose.
4. **The transcript footnote is gone.** "He keeps listening if you leave the app…" is shown once, at the top of the first transcript, with OK and "What leaves this iPhone". Home still says "Doddy is an AI, not a person"; Settings keeps "What leaves this iPhone".
5. **Results arrive in Messages as Doddy's message.**
   - A finished task (done or failed, as the server reported it) is saved in the thread under the task's own id (`ThreadDelivery.errand`), so it is saved once. The message has the server's short answer and "See everything Doddy found".
   - A file a voice conversation started is saved with a line from Doddy and the file card (`ThreadDelivery.document`). It is called ready only when the server says so. Not in a private conversation.
   - Files have **Share**, which downloads the file and opens iOS's share sheet (Files, Messages, Mail…). The person sends it; Doddy sends nothing.
6. **Notifications open Messages.** The messaging server's pushes for a finished task and a ready file carry `{"doddy":{"kind":"errand-result"}}` / `"file-ready"`, a kind only, never words or ids. Their text now says the result waits in Messages.
7. **Doddy's words** (repo only; the live agent changes only on the owner's separate instruction): after `hand_over_errand` starts, "Dobra, daj mi chwilę, poszukam i dam ci znać w Wiadomościach"; `make_document` says the file lands in Messages.

## Consequences
- Tasks and Files keep everything as before. Messages is now where results are announced.
- A task's result text becomes an earlier turn for questions in Messages, so the person can ask follow-ups. It was made on Doddy's server already, so nothing new leaves the iPhone.
- A file bubble is added only after a voice conversation starts a file. A file made in Messages already had one.
- The hand-over card's own lines still say the result waits in Tasks. That is still true. Pull request #303 rewrites that card, so it is left for it.
- Server pieces need a deploy, which is not done here: `doddy-messaging` (the push kinds and texts) and `doddy` (the `make_document` reply text). The voice agent needs a sync of `open_map`, `hand_over_errand`, `make_document` and the prompt.

## Evidence
See the pull request: the Linux groups that ran, the Swift tests written but not run here (no toolchain), and nothing seen on a device.
