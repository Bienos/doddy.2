# Deleting a Doddy account also deletes its voice conversations at ElevenLabs

- **Date:** 2026-11-12
- **Decided by:** owner, 13 Nov 2026 (retention and consent, in the owner's words below), and the rest as the assistant recommended, which the owner asked for ("zrób jak mówisz")
- **Status:** decided; the code is in pull requests of their own. This file changes nothing in code, in the voice agents or on Vercel. The live ElevenLabs settings named at the end change only when the owner says so for each.
- **Replaces:** nothing. Adds to `2026-11-08-required-account` (deleting the account) and follows what the messaging server already does for phone-agent conversations.

## Why
- **Account deletion should also remove the person's voice conversations at ElevenLabs.** Settings › Delete my Doddy account (`DoddyAccountServers.deleteAccount`, `DoddyApp/Features/Account/DoddyAccountApp.swift`) runs one confirmed step per server: the messaging server, Sign in with Apple through the voice server, the backend, an older voice account, then sign-out. This proposal adds a step for the conversations with the main agent and the translator agent.
- **To delete them, Doddy has to know which conversations belong to which account.** Tokens are issued by the voice server (`server/voice-token/src/handler.js`, `GET /v1/convai/conversation/token` at ElevenLabs), so that is the place to record it. The app starts each conversation with a `userId` (`VoiceSessionController.userID()`, `DoddyApp/Features/Voice/VoiceSessionController.swift`), which can carry an id derived from the account.
- **A retention limit is the backstop.** ElevenLabs keeps each agent's conversations for the retention set on that agent (`voice-agent/*/session.json`, `privacy`). The phone agent's spec says 30 days without audio (`voice-agent/phone/session.json`).
- **The pattern already exists for phone calls.** The messaging server stores each phone-agent conversation id on its call, queues them for deletion when the account is deleted (`queuePhoneAgentDeletions`, `server/messaging/src/calls.ts`), deletes them with `DELETE /v1/convai/conversations/{id}` and counts one gone only after a read answers 404 (`server/messaging/src/providers/taskCalls.ts`; retention table in `server/messaging/README.md`).
- **ElevenLabs names the conversation when it issues a token.** Its changelog of 27 July 2026 says the token endpoint's answer carries a `conversation_id` next to `token`; its list endpoint (`GET /v1/convai/conversations`) filters by `user_id`. Neither has been tried from this repository.

## Decision (proposed)
1. **Record the id when the token is issued.**
   - After ElevenLabs answers, the voice server keeps the answer's `conversation_id` under the account, in the Upstash Redis store it already uses for sessions and limits (`STORE_PREFIX` in `server/voice-token/src/voice-auth.js`).
   - The key is a keyed hash of the account (as Apple subjects already are), the value a set of ids, and it expires a day after the ElevenLabs retention below.
   - The app never sends an id: the list is only what the server itself was given, so a deletion can only touch that account's conversations.
   - Both agents (main and translator) are covered, and so are the older Apple voice accounts (ADR-522).
2. **Also tag the conversation with an account-derived id.** The token answer adds a `userId`: a keyed hash of the account made by the voice server. The app passes it when the conversation starts. If an id was ever missed in step 1, the deletion can still find the account's conversations through the list endpoint's `user_id` filter, limited to Doddy's agent ids.
3. **Delete with the account.** A new `POST /api/voice-auth` action, `delete-conversations`, takes the Doddy account's access token, as `apple-revoke` does. The app calls it in `deleteAccount` next to `revokeApple`, before the backend removes the sign-in. The server deletes each id, then reads it back; an id counts as deleted only on a 404. It answers counts (`deleted`, `pending`), never ids.
4. **Fail safe.**
   - If the id can't be recorded, the token is not handed out (`503`, like other store failures), so no conversation starts that the server can't delete later.
   - If ElevenLabs answers without a `conversation_id`, the token is handed out, the log line says `conversation_id: missing`, and step 2 plus the retention cover that conversation.
   - Ids that weren't confirmed gone stay recorded as owed and are tried again (owner picks how, below). The app's final message names voice conversations as deleted only when the server confirmed all of them (DOD-08); otherwise it says some are still being deleted and will be gone within the retention period at most.
   - Signing out deletes nothing.
5. ~~A retention limit at ElevenLabs as the backstop: 30 days for the main and translator agents.~~ **Dropped by the owner's answer above.** Retention stays without a limit; the deletion steps above and the install-id deletion for older conversations are what remove a person's conversations.

## Owner's answers (13 Nov 2026)
- **Retention at ElevenLabs: no time limit.** The owner wants voice conversations kept ("te zmiany w Eleven Labs powinny być trzymane forever"), and wants the person to agree to that in advance ("użytkownik powinien zrzekać się, no zawsze"). Step 5 below, the 30-day backstop, is therefore **dropped**.
- **Audio:** the assistant's recommendation, which the owner asked to follow: transcripts only, no audio recording.
- **Deletion on request stays.** Agreeing in advance doesn't replace it. Settings › Delete my Doddy account removes the person's conversations at ElevenLabs (steps 1 to 4), because Apple requires an account deletion to remove the account's data, and because a consent to data processing has to be one the person can withdraw (GDPR Art. 7(3) and 17). The wording of the agreement and the legal basis are for a lawyer (`docs/legal/PRIVACY_POLICY_DRAFT.md`, `[CONFIRM]`).
- **Answers to the numbered questions below:** 1: yes, steps 1 to 4 with the account-derived `userId`. 2: no time limit; no audio (see the live settings below). 3: refuse the token when the id can't be recorded. 4: a daily Vercel cron on the voice server (no handoff between servers). 5: conversations from before this ships are covered by the app sending its own install id once at deletion, and the server deleting Doddy's agents' conversations with that `user_id`, since with no retention limit they would not age out. 6: the privacy page's lines wait for the owner's wording (owner queue 7 and 26).
- **Consent text at the first voice conversation:** one short screen saying that voice conversations are kept until the person deletes them, and that deleting the account deletes them. Words: owner and lawyer.

## The questions (answered above)
1. Yes or no to steps 1 to 4, or only step 1 (record ids) without the account-derived `userId`.
2. **Retention at ElevenLabs:** 30 days for the main and translator agents (proposed), another number, or none. And whether ElevenLabs keeps audio recordings (`record_voice`).
3. When the id can't be recorded: refuse the token (proposed) or hand it out and rely on the retention.
4. How owed deletions are retried: a daily Vercel cron on the voice server, or handing the ids to the messaging server's deletion queue, which already has a worker and the ElevenLabs key.
5. Conversations from before this ships aren't in the record. Either they age out with the retention (proposed), or the app sends its own install id once at deletion and the server deletes Doddy's agents' conversations with that `user_id`.
6. The privacy page's lines on ElevenLabs (owner queue 7 and 26).

## Consequences
- One more Redis write per token and one more call at deletion. Redis keeps conversation ids and timestamps, not words.
- The account-derived `userId` links one person's conversations together at ElevenLabs across their iPhones.
- With no retention limit, ElevenLabs' dashboard keeps showing older conversations for investigating a voice problem (`voice-agent/README.md` reads conversation logs that way). Every conversation kept is one more the deletion has to find, so the install-id deletion for conversations from before this ships matters.
- Doddy keeps no copy of the words. A retention limit isn't what deletes them any more: only the deletion steps do, so a deletion that isn't confirmed stays owed and is retried until it is.

## Evidence
- Read: `server/voice-token/src/handler.js`, `server/voice-token/src/voice-auth.js`, `server/voice-token/src/doddy-account.js`, `server/voice-token/README.md`, `DoddyApp/Features/Account/DoddyAccountApp.swift`, `DoddyApp/Features/Voice/VoiceSessionController.swift`, `DoddyApp/Features/Voice/VoiceTokenClient.swift`, `server/messaging/src/calls.ts`, `server/messaging/src/providers/taskCalls.ts`, `server/messaging/README.md`, `voice-agent/translator/session.json`, `voice-agent/phone/session.json`, `site/privacy/index.html`.
- Read on the web (12 Nov 2026): ElevenLabs' changelog of 27 July 2026 and its "List conversations" and "Users" reference pages.
- Read on 13 Nov 2026 (read-only, ElevenLabs connector): the main agent's `privacy` has `record_voice: true`, `retention_days: -1` (no limit), `delete_audio: false`, `zero_retention_mode: false`. So **no time limit already holds, and audio is recorded**. The translator agent's file says the same (`voice-agent/translator/session.json`).
- **Live settings to change, only when the owner says so for each** (`AGENTS.md`): `record_voice` → `false` on the main agent and, if the owner agrees, the translator. This is the "no audio" answer above; today it is not in effect.
- **Done 14 Nov 2026 (owner: "Main and translator"):** `record_voice` → `false` on the main agent and the translator, read back; the versions and the rollback are in `voice-agent/README.md`. Audio recorded before that is still held; transcripts stay, with no time limit.
- Not run: any call to ElevenLabs that changes anything, a token request against the live server.
