# The agent's wording for "a yes is enough" (repository only)

Decision `2026-11-14-spoken-yes-and-fewer-cards`, step 3, prepared.
- **What changed:** `voice-agent/instructions.md` (the ASK-01 section and 34 per-tool lines) and 69 tool descriptions in `voice-agent/tools.json` now say how the app confirms each tool.
  - Some tools run at once: "don't ask first".
  - A card takes the user's short yes or a tap: Doddy reads what will happen as one question and doesn't ask twice.
  - Money and bookings take a tap.
  - Every change takes a tap once outside text is in the conversation.
- **Also fixed:** stale "Confirm on screen …" lines on tools that already ran at once.
- **Not applied to the live agent:** the sync waits for a TestFlight build and the owner's word (`docs/OWNER_QUEUE.md` 114, together with 111).
