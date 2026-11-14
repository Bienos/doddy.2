# Doddy keeps what the person says about themselves without asking each time, and shows it all in one Memory place

- **Date:** 2026-11-14
- **Decided by:** owner, 14 Nov 2026: "Niech zapisuje ale nie mówi użytkownikowi co chwilę że zapisał nie trzeba my będziemy tego używać żeby mieć lepszy context o użytkowniku", then chose the recommended option (kept on this iPhone only, used by Doddy, visible and deletable) and added: "te przełączniki to nw ogólnie powinno być coś takie jak memories or storage w ustawieniach i tam powinien być dostęp"
- **Status:** accepted; step 1 of 3 in the pull request that adds this file
- **Replaces:** for people who turn it on, the after-conversation card that asks about a preference or personal fact (`FactProposer`, ADR-440 Phase C). Nothing else; the "Worth keeping?" card for notes stays

## Why
Read on 14 Nov 2026:
- Learning is on only when the person turns on "Learn from how I use Doddy" (`PreferenceKey.learningOn`, off by default).
- Even then, at most one preference or personal fact is offered per conversation (three cards a day) on a card after the conversation. Nothing is kept unless they tap Save (`LearningService.proposeAfterConversation`, `LearningLimits`).
- Doddy therefore knows very little about the person after weeks of talking. Every fact costs a card, which is exactly the friction the owner asked to remove.

## Decision
- **With the person's own yes**, given once, "Remember what I tell you about myself" (`LearningMoment.keepsQuietly`; off until they turn it on), and learning on: after a conversation, the preferences and personal facts they said about themselves are kept as confirmed learned facts, **without a card and without Doddy saying so** (`LearningService.keepQuietlyAfterConversation`).
- **The same sentences and checks as the card:**
  - `SaveSuggestions` picks the person's own sentences, never Doddy's, a tool's or a page's;
  - `LearningPolicy` and `SensitiveContentFilter` keep out secrets, health and medication, religion, politics, orientation, immigration, precise location, and a third person's health or money;
  - a sentence they once said "Never this" to is never kept;
  - the same words are kept once;
  - nothing is kept in a private or translator conversation, while connections are paused, or in sensitive mode.
- **A few at a time:** at most 3 from one conversation and 10 a day (`LearningLimits.quietPerConversation`, `quietPerDay`). They don't use up the day's cards for routines.
- **Marked and verified:** each fact is marked as kept quietly (`LearningProvenance.keptQuietly`, written only when true, so older rows stay byte for byte). It counts as kept only as read back from the database (`confirm` checks its own write).
- **Where it is kept and who uses it:** on this iPhone only, in the learned facts table. The voice agent gets the facts only while "Use what Doddy learned in voice conversations" is on, exactly as now (`voiceContext(shared:)`). "That's wrong" and delete work as for any learned fact.
- **With quiet memory on, no card asks about a fact.** Routine cards are unchanged.

Steps:
1. **This pull request:** the rules and the service in DoddyCore, with tests. Nothing in the app calls them yet, so nothing changes for anyone.
2. **One Memory place in Settings** (after #454, which edits `SettingsScreens.swift`):
   - the one-time yes for quiet memory;
   - the learning switches;
   - everything Doddy keeps: notes, learned facts, recaps. Each one is visible, with "kept from what you said on <date>" for a quietly kept fact, and each can be deleted.
   - The app calls `keepQuietlyAfterConversation` when a conversation ends, before the "Worth keeping?" card, and never announces it.
   - `docs/trust/config/doddy_rules.yaml` gets its `memory_policy.quiet_learning` lines in the same pull request, so the constitution names quiet memory when the app starts doing it.
3. **A changed fact replaces the old one:** "Mieszkam w Berlinie" kept quietly retires "Mieszkam w Warszawie" (the rules of decision `2026-11-14-changed-facts-update-the-note`). The old one stays visible as replaced.

## Consequences
- **Doddy gets to know the person** from what they say, without a card per fact, once they have said yes to it.
- **Privacy:** more of what the person says about themselves is kept on the iPhone. When the voice sharing switch is on, it reaches ElevenLabs in the conversation's context, as confirmed facts already do. The filter is word rules in English and Polish: a sensitive fact said in other words can slip through. The person sees it in Memory and can delete it, and nothing is kept without their one yes.
- **Before step 2 ships:** the privacy policy and the App Store answers must say that, with this on, Doddy keeps what the person says about themselves on the iPhone without asking each time (`docs/OWNER_QUEUE.md`). Never write "privacy guaranteed".
- **Known limits:** the sentences come from `SaveSuggestions`, which needs at least four words and a signal, so very short facts ("Mieszkam w Berlinie") are often not picked. Widening that is a separate change, with its own tests.

## Evidence
- Run (Linux, Swift 6.1.3): `QuietMemoryTests` (10, real SQLite) and `QuietMemoryRulesTests` (6), written first and seen red, then green; the learning suites around them still pass. The results and the deliberate breaks are in the pull request.
- Not run: nothing in the app calls this yet; no device.
