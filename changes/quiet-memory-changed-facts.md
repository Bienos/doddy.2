# Quiet memory, step 3: a changed fact replaces the old one

Decision `2026-11-14-quiet-memory`.
- **What it does:** a fact kept quietly that changes one already in use takes the old one out of use. Examples: a new place the person lives or works, or the same words with a different number ("My shoe size is 43" after "42").
- **How:** this uses the rules of decision `2026-11-14-changed-facts-update-the-note`. The old fact is retired, not deleted, so it stays visible on the Memory screen; only the new one reaches a conversation.
- **When nothing changes:** if two old facts fit, or none does, both stay as they are.
- **Not yet:** nothing in the app calls quiet memory until step 2.
