# Every voice conversation is scored, so failures are found without the owner reporting them

- **Date:** 2026-11-14
- **Decided by:** owner ("8 okej", 14 Nov 2026, to "automatic evaluation of each conversation in ElevenLabs: it would mark conversations with 'I can't', a tool error or frustration, and from the worst I'd make new tests"; then "Do now everything")
- **Status:** applied to the live main agent on 14 Nov 2026 (`voice-agent/README.md`, "Every conversation is scored"); recorded in the pull request that adds this file
- **Replaces:** nothing

## Why
Until 14 Nov 2026 Doddy's failures were found only when the owner noticed them in a conversation: a wrong "I can't", a question before a look-up, a tool abandoned when the user spoke, an answer the server couldn't give (decision `2026-11-14-voice-agent-does-the-work-live`, "Why"). The main agent had no evaluation criteria and no data collection fields (read 14 Nov 2026: `platform_settings.evaluation.criteria` empty, `analysis_items` empty).

## Decision
The live main agent scores every conversation when it ends, with ElevenLabs' analysis model (`gemini-2.5-flash`, the default) on the transcript ElevenLabs already keeps:
- four yes/no criteria: did what was asked; no wrong "I can't" and no question before a look-up already asked for; tools worked; said only what tool results show (no price, date, hour or "done" without a result, the prompt-side form of DOD-08 and DOD-09);
- ElevenLabs' built-in frustration check;
- two fields: `failure_kind` (one of nine values) and `failed_request` (at most 12 English words, no personal details).

The exact texts and ids are in `voice-agent/evaluation.json`. Conversations that fail a criterion, or whose `failure_kind` isn't `none`, are where new agent tests come from.

## Consequences
- No change to what Doddy says or does: the prompt, tools, voice and turn settings are untouched.
- Privacy: no new data leaves the phone and no new company sees the conversation; ElevenLabs already stores the transcript and already writes a summary of it with the same analysis model. The two fields are written by that model from the transcript; `failed_request` is told to leave out personal details, which a model can't guarantee.
- The criteria are judged by a model: a fail is a lead to read, not proof. Whether they judge fairly is read from the first scored conversations.
- Cost: the read-back shows `llm_billed: false` on each item; what ElevenLabs charges for post-call analysis was not checked on the account's usage page.

## Evidence
- Applied with `agents_update_analysis`: `agtvrsn_1201m7dyz6xdeharp66kmmazayce` (criteria and fields), then `agtvrsn_2201m7dyzktqfcc9k4djgfjgf5mc` (frustration check). Read back with the config summary: prompt 31,434 characters, 119 tools, as before (`agtvrsn_3801m7dy4mebeeys840egzdqvb0w`).
- Rollback: `agents_update_analysis` with empty `analysis_items`.
- Not run: no conversation had been scored when this was written.
