# Texts are budgeted in SMS segments, not only in messages

- **Date:** 2026-11-09
- **Decided by:** proposal, owner approval pending (research item #4 and the SMS half of #2, `Doddy-optimization-research-2026-11-09`)
- **Status:** proposed; applied on branch `sms-segment-budget`
- **Replaces:** nothing. Extends ADR-704 (daily caps on texts).

## Why
Twilio bills a text per segment. A Polish letter makes the whole text UCS-2, 67 characters a segment once split, so the old 600-character reply cap (`smsChat.ts`) could cost 9 segments, and the outbound caps (`outbox.ts`, ADR-704) counted every text as one slot whatever it cost. A synthetic 600-character Polish reply is 9 segments; a 134-character one is 2. The old reply tail "… (dalej w aplikacji Doddy)" also contained U+2026, which is not GSM-7, so even an English reply without a single Polish letter went out as UCS-2 (a 597-character English reply after the old cut: 9 segments, where plain GSM-7 is 4).

## Decision
1. `src/smsSegments.ts` estimates segments: GSM-7 (160 / 153, extension characters 2 septets, an escape pair never split) or UCS-2 (70 / 67, an emoji is 2 UTF-16 units, a surrogate pair never split). One character outside GSM-7 makes the whole text UCS-2. Smart Encoding is not assumed. It is an estimate; Twilio's `num_segments` is the truth.
2. Every queued SMS reserves its estimated segments, next to the existing one slot per text: `daily_counters` scope `sms_segments_account` and `server_daily_usage` feature `sms_segments` (migration 023), taken atomically with the same single-statement upserts as before and all given back when a later cap or the insert refuses. The per-text caps (30 / 300) stay. New defaults: 120 segments an account and 1,200 for the server a UTC day (`SMS_SEGMENTS_DAILY_PER_ACCOUNT`, `SMS_SEGMENTS_DAILY_PER_SERVER`): 4 segments for each text the per-text caps allow. **Owner decision needed:** these two numbers.
3. A reply to Text with Doddy is cut to 3 segments (`SMS_REPLY_MAX_SEGMENTS`; about 200 Polish characters or about 450 plain GSM-7 ones), at a sentence end, else a word end, never changing a letter. There is no in-app copy of a text answer (the question and the reply are not stored), so the tail does not say the answer is in the app; it says "zapytaj dalej w aplikacji Doddy" (ask further in the app), in plain ASCII so a GSM-7 reply stays GSM-7. **Owner decision needed:** 3 segments as the budget, and whether the app should ever keep the full answer (that would need a new stored surface and its privacy review).
4. The estimate is stored per text (`outbound_messages.est_segments`) and Twilio's count in `reported_segments`, taken from the status callback only if it sends `NumSegments` and the status is final, and from the message lookup (`num_segments`) when an unknown outcome is settled.

## Consequences
Long Polish texts (news digests up to 640 characters, approved texts) now use up to 10 segments of the day's budget, so a few of them can reach the segment cap before the text cap. A single text larger than the whole cap is refused. The shared Messages prompt already says "keep answers short"; it was not changed, so the model may still write more than fits and the cut is what enforces the budget. Voice is untouched.

## Evidence
Twilio, `what-sms-character-limit` (9 Nov 2026): 160 / 153 and 70 / 67; one UCS-2 character switches the whole message; billed per segment. The page does not list the GSM-7 extension table or the surrogate rule (taken from 3GPP TS 23.038 and UTF-16), and its sentence "a message of 140 characters that includes one non-GSM character gets split into two segments" does not agree with its own limits (140 UCS-2 characters are 3 segments at 67); the estimator follows the limits. The status-callback page (`track-outbound-message-status`) does not list `NumSegments`. Tests: `test/smsSegments.test.ts`, `test/smsSegmentsDb.test.ts`, `test/smsChat.test.ts`.
