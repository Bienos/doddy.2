# Doddy's own changes with Undo run at once

Decision `2026-11-14-spoken-yes-and-fewer-cards`, step 2b.
- **What runs at once:** a note, a reminder and a dish's ingredients are saved when asked, with no card, and can be undone in "What Doddy did". The drafts and hand-overs that change nothing (a message, a BLIK transfer, an invoice draft, a presentation, the lost-wallet checklist, Maps, the camera, a food app) also run when asked.
- **The on-screen rule:** Maps, the camera, a message draft and a food app open at once only while Doddy is on screen; otherwise their card stays.
- **What keeps its card:** "undo that", because nothing undoes an undo. Timers, alarms, new lists, note and leave-by reminders and the parking spot keep theirs until they have an Undo (step 2c).
- **The rules say the same as the code:** `tools.json` says `runs_now` for the eleven, and the spec script and the rules match. The listening notice and the Reminders line in first-run access say so too.
