# Quiet memory, step 1: the rules

Decision `2026-11-14-quiet-memory`.
- **What it adds:** `LearningService.keepQuietlyAfterConversation`. With learning on and the person's own yes to quiet memory, it keeps preferences and personal facts they said about themselves as confirmed learned facts. It shows no card and says nothing.
- **The checks:**
  - the same checks as the card (never sensitive, never once refused, kept once);
  - not in private conversations;
  - at most 3 per conversation and 10 per day;
  - each fact is read back and marked `keptQuietly`.
- **The card:** with quiet memory on, the after-conversation card no longer asks about a fact.
- **Not yet:** nothing in the app calls it. The Memory place in Settings and the one-time yes are step 2.
