# DODDY voice service

**Live** on Vercel as the project `doddy-voice-token`; the app's voice screen uses it. An old copy on Render is unused (`STATUS.md`).

This service verifies Sign in with Apple once, keeps a revocable DODDY voice session, and exchanges
that session for a provider-scoped credential. Apple and provider credentials stay on the server;
the app never asks for a provider API key, tester code, or server URL. Voice transcripts, audio,
notes, profile data, and conversation prompts are not sent to this service for credential requests.

The app calls two routes:

- `POST /api/voice-auth`: Apple identity-token verification, refresh-token rotation, sign-out, and
  DODDY voice-session deletion. ElevenLabs must be configured before a voice account
  session can be created. `account-session` trades a Doddy account's token for this server's own session
  ("One token per server", below). `delete-conversations` deletes an account's voice conversations (below).
- `POST /api/voice-token`: validates an active DODDY session, or, during the move to one token per server, a Doddy
  account's own token, and returns an ElevenLabs conversation
  token and the account's keyed `userId` (below). ElevenLabs is the only voice (9 Nov 2026); a request that
  names OpenAI gets `400 unknown_provider`.

One more route is for Vercel, not the app: `GET /api/voice-cron`, called once a day (`vercel.json` crons) to
retry voice conversation deletions that are still owed. It needs `CRON_SECRET` and does nothing without it.

Access tokens last 10 minutes and stay in app memory. Opaque refresh tokens rotate on use and last
30 days; the app stores the current refresh token and Apple user identifier in the iOS Keychain with
device-only accessibility. A revoked Apple credential, DODDY sign-out, or invalid refresh token
requires a new Apple sign-in. The server stores only a keyed pseudonymous Apple subject, session
records, refresh-token hashes (the current one and the one it replaced), and replay/rate-limit
counters (the sign-in ones are keyed by a hash of the caller's address, never the address), the UTC day of each account's first voice token (a day number and nothing else, "How the limits fit together" below), plus, when the Apple key below is set,
Apple's refresh token for the person, sealed (AES-256-GCM) with a key of its own derived from the signing key (see "Keys" below).
Request logs contain action/provider, outcome, status, and duration only (and, for account deletion,
whether Apple revoked the link, and, at `/api/voice-token`, which kind of token the request came with, as a fixed word).

## Owner configuration required before deployment

Set these as server environment variables in the owner-controlled host. Do not put values in this
repository, app configuration, or build settings. The secret ones live in 1Password and reach the
Vercel project `doddy-voice-token` through `tools/secrets/sync.mjs` (ADR-493,
`docs/security/SECRETS_1PASSWORD.md`). The signing key is recorded there but never written by the tool.

| Name | Purpose |
|---|---|
| `APPLE_BUNDLE_ID` | Exact bundle identifier for the app build signing in (for example, the development bundle identifier). |
| `SUPABASE_URL` | Optional. The Doddy accounts project (`https://<ref>.supabase.co`, decision `2026-11-08-required-account`). With it, `/api/voice-token` also accepts a Doddy account's access token (Apple, Google or a code by email), checked against the project's published keys (`src/doddy-account.js`): no secret is needed. `account-session` takes the same token once and answers with this server's own session for the account ("One token per server" below). Its limits count per account (`account:<id>`), apart from the Apple voice accounts, whichever of the two kinds of token the request comes with. Unreadable keys answer 503 `account_check_unavailable`, never 401. Without it, only this server's own Apple sign-in works, as before. |
| `DODDY_SESSION_SIGNING_KEY` | Stable random secret, at least 32 bytes. The master key: a key of its own for each job (the access tokens, the sealed Apple tokens) is derived from it, and the Apple pseudonyms and the other keyed hashes are made with it unless `DODDY_IDENTIFIER_KEY` is set (see "Keys" below). Replace it only by the steps under "Rotating the signing key". |
| `DODDY_SESSION_SIGNING_KEY_PREVIOUS` | Optional, for a rotation only. The key that was `DODDY_SESSION_SIGNING_KEY` before: access tokens and sealed Apple tokens made with it are still accepted. It is only ever used to check and to open, never to sign or seal. Needs `DODDY_IDENTIFIER_KEY`: with a previous key and no identifier key the server answers `503 server_not_configured` rather than move anyone's identifiers. Nothing has to be set for this at deploy. |
| `DODDY_IDENTIFIER_KEY` | Optional, for a rotation only. At least 32 bytes. The key of the keyed hashes that must never change for a person: the Apple pseudonyms, the keys under which an account's voice conversations are recorded, the user id given to ElevenLabs and the rate-limit buckets. Not set means they use `DODDY_SESSION_SIGNING_KEY` exactly as they always have. Before the signing key is replaced it is set to the signing key's current value, and then it is left alone. |
| `UPSTASH_REDIS_REST_URL` | HTTPS URL for the durable shared session/rate-limit store. |
| `UPSTASH_REDIS_REST_TOKEN` | Secret for that store. Never log or expose it to the app. |
| `ELEVENLABS_API_KEY` | Owner-held ElevenLabs API credential. |
| `ELEVENLABS_AGENT_ID` | The DODDY agent ID configured by the owner. |
| `ELEVENLABS_TRANSLATOR_AGENT_ID` | Optional. The translator-only agent (no tools; `voice-agent/translator/`). A request with the body `{"agent":"translator"}` gets a token for it. When unset, the id in `src/conversations.js` (`DEFAULT_TRANSLATOR_AGENT_ID`, public) is used, so nothing has to be set. Any other `agent` value is a 400 `unknown_agent`; no body is the main agent, as before. |
| `CRON_SECRET` | Secret, at least 16 characters, in 1Password (item `voice-token-cron-secret`). Vercel sends it as `Authorization: Bearer …` to the daily retry of voice conversation deletions (`/api/voice-cron`). Without it that route answers 503 and does nothing; an owed deletion then waits until it is set. Nothing else reads it. |
| `DODDY_TOKENS_PER_HOUR` | Optional shared per-account issuance limit; defaults to `30`. |
| `DODDY_TOKENS_PER_DAY` | Optional per-account issuance limit per UTC day, on top of the hourly one; defaults to `150` (ADR-712). |
| `DODDY_GLOBAL_TOKENS_PER_HOUR` | Optional shared global issuance limit; defaults to `100`. This is the ceiling for everyone in an hour; the fair share below is counted inside it. |
| `DODDY_GLOBAL_TOKENS_PER_DAY` | Optional ceiling for the whole service per UTC day; defaults to `600`. |
| `DODDY_NEW_ACCOUNT_DAYS` | Optional: how many days an account counts as new (the day of its first token and the days after it); defaults to `7`. It is also how long, from the day the rules first run, every account first seen counts as established ("How the limits fit together" below). |
| `DODDY_NEW_ACCOUNT_POOL_PER_DAY` | Optional: tokens per UTC day shared by all new accounts together; defaults to `100`. |
| `DODDY_NEW_ACCOUNT_TOKENS_PER_DAY` | Optional: tokens per UTC day for each new account on its own; defaults to `10`. |
| `DODDY_FAIR_SHARE_BUDGET_PERCENT` | Optional: the share of the hour's budget for everyone (`DODDY_GLOBAL_TOKENS_PER_HOUR`), from 1 to 100, after which the fair share applies; defaults to `50`. At `100` the hour's budget alone decides. |
| `DODDY_FAIR_SHARE_TOKENS_PER_HOUR` | Optional: once that share is used, an account that has already had this many tokens in the hour is refused; defaults to `10`. |
| `DODDY_SIGNINS_PER_CLIENT_HOUR` | Optional: sign-ins one caller address may complete per hour; defaults to `10` (ADR-712). |
| `DODDY_SIGNINS_PER_CLIENT_DAY` | Optional: the same per UTC day; defaults to `30`. |
| `APPLE_TEAM_ID` | Optional, with the next two: the Apple Developer team ID. Lets "Delete voice account" also revoke Sign in with Apple (ADR-524). |
| `APPLE_SIGN_IN_KEY_ID` | The key ID of a Sign in with Apple key (Apple Developer › Certificates, Identifiers & Profiles › Keys). |
| `APPLE_SIGN_IN_PRIVATE_KEY` | That key's `.p8` file contents (PEM; literal `\n` line breaks work). Secret: 1Password only. |

### How the limits fit together (decision `2026-11-12-voice-token-fair-share`)

Code: `hitLimits` in `src/voice-auth.js` (one Redis script, one request to the store) and the settings in `src/handler.js`.
A token is issued only when none of these says no. They are checked in this order, the first one that says no is the
`limit` in the log, and all of them are checked before anything is counted, so a refused request uses no budget and
writes nothing about the account (ADR-671, ADR-712); the only write a refused request can make is the start day below,
and only once, for the very first request the script ever sees.

| # | `limit` in the log | Refuses when | Retry-After is |
|---|---|---|---|
| 1 | `user_hour` | the account already had `DODDY_TOKENS_PER_HOUR` tokens this hour | the end of the hour |
| 2 | `user_day` | the account already had `DODDY_TOKENS_PER_DAY` tokens today (UTC) | the next UTC midnight |
| 3 | `new_account_day` | a new account already had `DODDY_NEW_ACCOUNT_TOKENS_PER_DAY` tokens today | the next UTC midnight |
| 4 | `new_pool` | new accounts together already had `DODDY_NEW_ACCOUNT_POOL_PER_DAY` tokens today | the next UTC midnight |
| 5 | `global` | everyone together already had `DODDY_GLOBAL_TOKENS_PER_HOUR` tokens this hour | the end of the hour |
| 6 | `global_day` | everyone together already had `DODDY_GLOBAL_TOKENS_PER_DAY` tokens today | the next UTC midnight |
| 7 | `fair_share` | `DODDY_FAIR_SHARE_BUDGET_PERCENT` percent of the hour's budget for everyone (5) is used, and the account already had `DODDY_FAIR_SHARE_TOKENS_PER_HOUR` tokens this hour | the end of the hour |

- **What the app sees.** The same `429` with `{"error":"rate_limited"}` and `Retry-After` for all seven, and so the same
  text as before ("You've started a lot of conversations. Try again in N minutes, in N hours or tomorrow; your notes still
  work.", `Packages/DoddyCore/Sources/DoddyCore/VoiceToken.swift`). Nothing changes in the app. `Retry-After` says when
  the limit that refused ends; a later one can still say no.
- **New accounts.** An account is new for the UTC day of its first token and the days after it, `DODDY_NEW_ACCOUNT_DAYS` days
  in all (7 by default). While it is new it has `DODDY_NEW_ACCOUNT_TOKENS_PER_DAY` tokens a day of its own (10) and also
  draws from a pool that all new accounts share (`DODDY_NEW_ACCOUNT_POOL_PER_DAY`, 100 a day). After that only the normal
  limits apply. A new account's tokens count against the hour's and the day's budgets for everyone like any other. An
  established account is never counted against the pool, and a full pool never refuses it. Every account the server
  limits is treated the same way: a Doddy account and an older Apple voice session alike.
- **Today's testers stay where they are.** An account is new only when the day of its first token is later than the day the
  rules first ran plus `DODDY_NEW_ACCOUNT_DAYS` days. Everyone whose first token falls on that day or in the 7 days after
  it (always at least 7 x 24 hours) counts as established, for good. Tokens issued before this change left no
  first-seen day, so "first token" means the first one issued by this code: someone who used voice before it shipped, and
  who first asks for a token only after that first week, counts as new for one week.
- **What is stored.** One key per account, `doddy:voice:v1:first-seen:<account>`, holding only the UTC day number of the
  account's first token: no content, nothing else. It is written only when a token is issued (a refused request writes
  nothing), and it expires 180 days after the account's latest token, so an account in use keeps it and one that has not asked
  for a token for six months starts as new if it comes back. One key for the service, `doddy:voice:v1:fair-share-started`,
  holding the UTC day the rules first ran: set once, by the first request that reaches the script (`SET ... NX`, inside
  it), never changed afterwards, never expiring, and read at every decision. The daily counters for the whole service
  and for the new-account pool (`limit-global-day:<day>`, `limit-new-pool:<day>`) expire after a day and an hour, like the
  others. Nothing is logged about any of it beyond the fixed `limit` word.
- **If the store is reset.** Both kinds of key are then gone, and the next request sets the start day again. For the 7 days
  after that everyone who asks for a token counts as established: nobody is treated as new, which is the safer of the two
  ways a reset can go (the other would give every account a smaller allowance for a week). The cost is that for those days
  a genuinely new account has the normal limits, and that accounts which don't ask for a token in those days count as
  new when they come back. The hour's and the day's counters also start from zero, as a reset does to every limit here.
  If only the per-account keys are lost, those accounts count as new for up to a week: a smaller allowance, never a
  larger one. An unreachable store is, as always, `503` and no token.
- **The fair share.** The hourly budget for everyone is the ceiling (5). Once `DODDY_FAIR_SHARE_BUDGET_PERCENT` percent of
  it is used (50 of 100 by default), an account that already had `DODDY_FAIR_SHARE_TOKENS_PER_HOUR` tokens that hour (10)
  waits for the next hour; an account that had fewer is served as usual, up to the ceiling. In a quiet hour an account can
  still have up to `DODDY_TOKENS_PER_HOUR` (30).
- **Settings.** All six are whole numbers from 1 to 10 000 (the percentage from 1 to 100). Not set means the default, and
  nothing has to be set on the host. Anything else answers `500 server_not_configured` before anything is counted or sent,
  like the other limits. To switch a rule off, set it high (`10000`, and `100` for the percentage).
  `DODDY_NEW_ACCOUNT_DAYS` is read at every decision: changing it moves the end of every account's new window and the end of
  the first-week grace together.
- **Rolling back.** Revert the change and redeploy: the earlier code reads the three limits it always read and ignores
  the keys above, which stay in Redis (the per-account ones for up to 180 days, the counters for a day). When the change is
  deployed again later, `fair-share-started` still holds the first day, so the first-week grace does not start again;
  to start it again the owner deletes that one key in the Upstash console before redeploying.

### Keys: one per job, with a key id and a previous key (decision `2026-11-12-account-and-device-tokens`, part b)

`DODDY_SESSION_SIGNING_KEY` is the master key. Code: `src/keys.js`; used in `src/voice-auth.js` and
`src/conversations.js`. Everything the server signs, seals or derives from it:

| Job | Made with | Carries | Lives |
|---|---|---|---|
| Access token (HS256 JWT) | HMAC-SHA-256 with the key derived for `doddy/voice/access-token/v1` | `kid`, the key id, in the token header | 10 minutes |
| Apple's refresh token, sealed (AES-256-GCM) | the key derived for `doddy/voice/apple-token-seal/v1` | `v2.<key id>.<iv, ciphertext, tag>` | 400 days for a Doddy account's link; 30 days, kept alive while refreshed, for an older voice session's |
| Apple pseudonym, conversation `recordKey` and `userId`, rate-limit buckets (the caller address, the account) | HMAC-SHA-256 of a fixed prefix and the value with the identifier key | nothing: they are identifiers | as long as the person (the buckets: an hour or a day) |

- **A key per job.** Each key is HKDF-SHA256 (RFC 5869, no salt) over the master with the fixed label as `info`, 32 bytes.
  A token made for one job is refused for another, because the keys differ. The labels are never changed (a test holds
  known answers); a new job gets a new label.
- **A key id in everything signed or sealed.** It is eight characters of HKDF output over the master with its own label,
  so it needs no setting and tells nothing about the key. A value naming an id this server doesn't have is refused.
- **The previous key** (`DODDY_SESSION_SIGNING_KEY_PREVIOUS`) is accepted for checking and opening. It is never used to
  sign or seal: a new value always names the current key.
- **Identifiers are not rotated with the signing key.** They are what the person *is* here: a new Apple pseudonym is a
  new account, and conversations recorded under the old `recordKey` could not be found to delete. They use the identifier
  key, which is `DODDY_IDENTIFIER_KEY` when set and otherwise the signing key itself, which is what they have always
  used, so they are byte for byte the same as before (a test holds recorded values from the code before this change).
  The rate-limit buckets use it too, so a rotation doesn't give anyone a fresh allowance.
- **Everything made before this change still works, with no setting changed.** An access token with no `kid` is checked
  with the signing key itself (and the previous one), until it expires. A sealed value with no `v2.` prefix is opened with
  the key it was sealed with before. Refresh tokens are random and kept as hashes: no key ever touched them, so
  nobody is signed out, at the deploy or at a rotation.
- **Fails closed.** A key that is too short, or a previous key with no identifier key, makes sign-in and tokens answer
  `503 server_not_configured` (as a missing signing key always did). Nothing logs a key, a key id or a token.

**Rotating the signing key** (the owner, on the Vercel project `doddy-voice-token`; each step is a redeploy; never as part
of a `tools/secrets/sync.mjs` run, which doesn't write this key):

1. Make the new value (`openssl rand -base64 48`). Keep the current value in 1Password.
2. **Pin the identifiers, once.** Set `DODDY_IDENTIFIER_KEY` to the current value of `DODDY_SESSION_SIGNING_KEY`, exactly,
   and redeploy. Nothing changes for anyone: it is the value the identifiers already use. It is never changed afterwards.
3. **Rotate.** In one redeploy, set `DODDY_SESSION_SIGNING_KEY_PREVIOUS` to the old value and `DODDY_SESSION_SIGNING_KEY`
   to the new one. From then on tokens are signed and sealed with the new key, and everything made with the old one is
   still accepted. Check by talking to Doddy once, and the `voice_auth` and `voice_token` log lines for `status: 200`.
4. **Remove `DODDY_SESSION_SIGNING_KEY_PREVIOUS`** when nothing still needs it. Access tokens made under the old key are
   gone 10 minutes after step 3, and no refresh token ever depended on it. What does need it is Apple's refresh token
   sealed under the old key, so that deleting such an account can still revoke Sign in with Apple: a Doddy account's link
   is kept for up to 400 days (each new sign-in with Apple seals a fresh one under the current key). Removed earlier,
   nobody is signed out, but deleting an account whose link was sealed under the old key still deletes it and reports
   `apple: "no_token"` instead of revoking at Apple, until that person signs in with Apple again.

**Rolling back.** Reverting this change (redeploying the earlier code, or Vercel's rollback) leaves everything made before
it valid: the earlier code reads exactly the formats it always did. It knows one key only: it ignores
`DODDY_SESSION_SIGNING_KEY_PREVIOUS` and `DODDY_IDENTIFIER_KEY`, and makes the identifiers from `DODDY_SESSION_SIGNING_KEY`
itself. So if the signing key was rotated, put the old value back in `DODDY_SESSION_SIGNING_KEY` as well (it is the value
`DODDY_IDENTIFIER_KEY` holds), or the identifiers move; tokens made under the new key stop working then, too.
What the new code made while it was live is not read by the earlier code:
- **Access tokens** (a `kid` in the header): refused for the rest of their 10 minutes. The iPhone then asks for a new one
  with its refresh token (`VoiceAuthSession.serverRejectedSession`, read in the code, not seen on a device), which needs no
  key, so a rollback signs a voice session out only if that refresh fails too. The 30-day refresh tokens are not affected at all.
- **Sealed Apple tokens** (`v2.` values, made when someone signed in with Apple, or linked, while the new code was live):
  not opened by the earlier code for as long as they live (up to 400 days) or until that person signs in with Apple again,
  so deleting such an account would not revoke Sign in with Apple. Redeploying the new code makes them readable again; nothing
  stored is changed by either version.

### Voice conversations deleted with the account (decision `2026-11-12-voice-conversations-per-account`)

Deleting a Doddy account also deletes its voice conversations at ElevenLabs. The retention at ElevenLabs has
no time limit (owner, 13 Nov 2026), so nothing ages out: only these steps remove a conversation. Code:
`src/conversations.js`, the token in `src/handler.js`, the action in `src/voice-auth.js`, the retry in `src/cron.js`.

- **Recording.** `GET /v1/convai/conversation/token` at ElevenLabs answers `{ token, conversation_id }` (ElevenLabs'
  public API reference, read 13 Nov 2026; not yet seen against the live service). When the server issues a token it
  keeps that id under the account, in the same Redis store, as a sorted set at
  `doddy:voice:v1:conversations:<recordKey>`. `recordKey` is a keyed hash (HMAC-SHA-256 with
  the identifier key, which is `DODDY_SESSION_SIGNING_KEY` unless `DODDY_IDENTIFIER_KEY` is set, as for the Apple
  subjects) of the account: a Doddy account (`account:<id>`) or an
  older Apple voice account. The app never sends an id, so a deletion only reaches what the server itself recorded.
  The set **never expires** and holds at most 5 000 ids per account; past that the oldest are let go of (they are
  still found by `userId`, below). Redis holds ids and the times they were issued, never words.
- **`userId`.** The token answer is `{ token, userId }`. `userId` is another keyed hash of the account (32 hex
  characters) that the app passes to ElevenLabs when the conversation starts, so conversations can also be found by
  listing, `GET /v1/convai/conversations?agent_id=…&user_id=…`, if an id was ever missed. An app from before this
  doesn't pass it and still works.
- **If it can't be recorded:** the id can't be written to Redis → `503 server_not_configured` and **no token** (the log
  says `conversation_id: not_recorded`). ElevenLabs answers without a usable `conversation_id` → the token is
  handed out with `userId` and the log says `conversation_id: missing`. A missing signing key or a store without
  recording is `500 server_not_configured` before anything is sent to ElevenLabs.
- **`POST /api/voice-auth` `{ "action": "delete-conversations", "installUserId"?: "<uuid>" }`** takes a **Doddy
  account's access token** as the Bearer, like `apple-revoke` (a voice session's token is refused with 401). The
  server (1) lists the account's `userId`, and `installUserId` if the app sent one, in Doddy's agents (the main agent
  and the translator agent: no other agent is ever listed or deleted in, and a listed conversation must name one
  of them itself), adds what it finds to the record, (2) deletes each recorded id with
  `DELETE /v1/convai/conversations/{id}` and reads it back with `GET`: **an id counts as deleted only when that read
  answers 404**, and only then leaves the record. `installUserId` is the iPhone's old per-install id, for
  conversations from before `userId` existed; it is accepted only in the shape the app makes it (a UUID), so it can't
  name other people's conversations, and it is one more `user_id` to look for, nothing else. The answer is
  `{ "deleted": n, "pending": m }`, counts only. `pending` is the ids not confirmed gone, plus one when a list could
  not be read to the end or there is no ElevenLabs key, because what is there is then unknown: **it is never 0 unless
  everything is confirmed.** One request works for about 9 seconds or 300 ids; what is left stays owed. The
  action counts against the same per-caller limits as a sign-in (`DODDY_SIGNINS_PER_CLIENT_HOUR` / `_DAY`, keyed
  by account), and a refused call never reaches ElevenLabs. An unreachable store is `503`, never a count. Once the
  call is let through it also ends every voice session of the account that `account-session` made (before it
  touches ElevenLabs, so a store that is down answers `503` with nothing half done; asking again ends nothing more,
  and a refused call ends nothing). The answer is the same counts.
- **`delete-account` (an older Apple voice account)** does the same for that account's recorded conversations before
  its session is deleted and adds `conversations: { deleted, pending }` to its answer. ElevenLabs failing never keeps
  the account.
- **Owed deletions.** An account with `pending` above 0 stays in the Redis hash `doddy:voice:v1:conversations-owed`
  with the user ids to look for again (its own `userId` and any `installUserId`, which is held there only until
  nothing is owed). A daily Vercel cron (`23 3 * * *`, `GET /api/voice-cron`, `maxDuration` 60 s) tries each owed
  account again for up to 45 seconds and removes it when nothing is left. The cron checks
  `Authorization: Bearer $CRON_SECRET` against `CRON_SECRET` (compared as digests) and does nothing without it: **the
  owner must set `CRON_SECRET`** (below). Known limits: a conversation started on another device in the minutes
  after the deletion, while its short-lived account token still works, is recorded but not owed; and a change of the
  identifier key (`DODDY_IDENTIFIER_KEY`, or `DODDY_SESSION_SIGNING_KEY` while the first is not set) changes every
  `recordKey` and `userId`, so conversations recorded before are no longer found by them. Replacing the signing key by
  the steps under "Rotating the signing key" does not do that: the identifier key stays as it was.
- **Logs** carry the action, status, timing and counts (`deleted`, `pending`; for the cron `accounts`, `deleted`,
  `pending`) and a fixed word for the recording. Never an id, a `userId`, a `recordKey`, a token or a word.

To set `CRON_SECRET`: make a random value of at least 16 characters, save it in 1Password as the item
`voice-token-cron-secret` (vault `doddy-prod`), sync it to the Vercel project `doddy-voice-token` with
`tools/secrets/sync.mjs` and redeploy (`docs/security/SECRETS_1PASSWORD.md`). Until then the app's deletion still
deletes what it can at once; only the daily retry waits.

### Revoking Sign in with Apple for a Doddy account (decision `2026-11-09-apple-revoke-for-doddy-accounts`)

A Doddy account (a Supabase user, `SUPABASE_URL` set) made with Sign in with Apple needs the same
revoke, but it has no Apple voice account. Two more `POST /api/voice-auth` actions take the **Doddy account's
access token** as the Bearer, checked like `/api/voice-token` checks it (a voice session's token is
refused, and so is an access token made by `account-session`). Both need the three `APPLE_*` key settings and `APPLE_BUNDLE_ID` below; without them they
answer 200 and do nothing.

| Action | Body | When the app sends it | Answer |
|---|---|---|---|
| `apple-link` | `identityToken`, `rawNonce`, `authorizationCode` (all from the Apple sheet just used) | right after the sign-in with Apple | `{ linked: true }` once Apple's refresh token is kept, sealed, under `account:<Supabase user id>` for 400 days; `{ linked: false }` when the code wasn't the same Apple person's or Apple refused. Counted against the per-caller sign-in limits. |
| `apple-revoke` | none | first, when "Delete my Doddy account" runs | `{ appleRevoked, apple }`, `apple` being `revoked`, `failed`, `no_token` or `not_configured`. A revoked or missing token is forgotten; a failed one is kept so asking again can work. Apple failing never stops the deletion. |

`APPLE_BUNDLE_ID` is one value: it must be the bundle ID of the build that signs in (Beta:
`com.bienos.doddy2.dev`), because Apple issues the one-time code to that app.

### One token per server: this server's own session for a Doddy account (decision `2026-11-12-one-token-per-server`)

The Doddy account signs in once, at Supabase. Its token is then traded once, here, for a token that only this server
accepts, which this server can end itself. Code: the `account-session` action in `src/voice-auth.js`; the session,
refresh and sign-out code is the one an Apple voice account has always used. **This is the server's half. Nothing in the
app calls it yet**, so installed apps change in no way: they keep sending the Supabase token, which is still accepted.

- **`POST /api/voice-auth` `{ "action": "account-session" }`** takes the **Doddy account's access token** as the Bearer,
  checked exactly like `apple-link` checks it (the project's published keys; a voice session's token and an access token
  made by this action are refused, so a session can't mint another). The answer is the one `sign-in` gives,
  `{ accessToken, refreshToken, expiresIn: 600 }`: a 10-minute access token (HS256, audience `voice`, the key id and the
  access-token key of "Keys" above) and an opaque refresh token that rotates and lasts 30 days. The session is bound to the
  account, as `account:<Supabase user id>`, the bucket the account's own token already counts under. Refused with the
  answers of its neighbours: `401 session_expired` for any token that isn't a Doddy account's, `503 account_check_unavailable`
  when the project's keys can't be read, `503 server_not_configured` when the server can't issue voice tokens, the signing
  key is unusable or a limit setting is, `400` for a body over the size limit or not JSON, `405` for anything but POST.
  Nothing is made or counted for a refused call.
- **Limits.** Per account (`account-session:<account>`) and per caller address (`account-session-client:<address>`), each
  one a keyed hash, with the numbers of a sign-in (`DODDY_SIGNINS_PER_CLIENT_HOUR` / `_DAY`, 10 and 30), counted in
  the same store and failing closed, and only once the account's token has checked out. The address is believed only
  from the header Vercel sets, an unknown address shares one bucket with ten times the limit and the log says
  `noClientAddress: true`: all as for a sign-in ("Security behavior"). The two buckets are this action's own: Apple
  sign-ins from the same address are neither counted in them nor refused by them. A refused call is `429
  rate_limited` with `Retry-After`. There is no new setting.
- **Two kinds of token at `/api/voice-token` during this release.**

  | Token | Checked | Counts under | `auth` in the log |
  |---|---|---|---|
  | this server's access token, from `account-session` | HS256 signature, `kid`, expiry, and its session record in the store | `account:<id>` | `account_session` |
  | the Doddy account's Supabase token (as before) | the project's published keys | `account:<id>` | `account_token` |
  | an older Apple voice account's access token (as before) | HS256 signature, expiry, session record | the Apple pseudonym | `apple_session` |

  Both of the first two are the same account to every limit: the same `account:<id>` goes to the same Redis script, so the
  per-account hour and day, the new-account day and pool, the fair share and the daily ceiling count a person once,
  and a person can neither be counted twice nor escape counting by switching kind (tests: `test/account-session.test.js`, on
  an in-memory store and on a real Redis). They also give ElevenLabs the same keyed `userId`, so one person's conversations
  stay together, and are recorded and deleted under the same key. `auth` is a fixed word on the `voice_token` log line, so
  the share of requests still using the Supabase token can be read before it stops being accepted.
- **Ending a session.** All of it is code that already existed for Apple voice accounts:
  - `sign-out` (the session's access token) ends that session: its record and its refresh hashes. The account's other
    sessions are untouched.
  - `refresh` rotates the refresh token. A swapped-out refresh token coming back ends the whole session, and the caller
    sees the same `401 session_expired` as for any dead token (ADR-712). A refresh token that has run out (30 days) or
    been ended gives no new access token.
  - `delete-account` with the session's access token ends all of the account's sessions, revokes its Apple link, deletes
    its voice conversations and forgets the link, as it does for an Apple voice account.
  - **New:** `delete-conversations`, the call the app makes first when a Doddy account is deleted, now also ends every
    voice session of the account (`revokeUserSessions` in the store). That is the one step every deletion makes, so it is
    where this belongs; `apple-revoke` runs for accounts made with Apple only. The Apple link is left for `apple-revoke`.
  - **What "ended" means here.** Every request to this server looks the session of the access token up, so once a session
    is ended its access token is refused at once, here, even inside its 10 minutes. That is the whole of it: an ElevenLabs
    conversation token already handed out, and a conversation already running, are ElevenLabs's and live out their own
    short lives; and the Doddy account's Supabase token, which this server cannot revoke, is still accepted at
    `/api/voice-token` this release until it expires on its own.
  - **Known limits.** This server can't see that a Supabase account was deleted, so a session made on another device in the
    minutes after the deletion, or a deletion that didn't go through `delete-conversations`, leaves a session that works
    until its 30 days end (its tokens are still counted and limited under the account like any other). A session made
    while the code is live is a plain session in the store: nothing about it is read by the app yet.
- **Refreshing never shortens the Apple link.** A Doddy account's sealed Apple token (`apple-token:account:<id>`) is the
  same key an Apple voice account's refresh keeps alive. A refresh now only lengthens it, never shortens it (the 400 days
  `apple-link` gave it stay), so using the new session can't make deleting the account stop revoking Sign in with Apple.
  Apple voice accounts are extended exactly as before.
- **Moving over.** This release: `/api/voice-token` takes both kinds, `apple-link`, `apple-revoke`, `delete-conversations` and
  `account-session` take the Supabase token only (they run right after sign-in and right before deletion). A later pull
  request, once the owner confirms the installed builds are new enough (owner queue 50), stops accepting the Supabase
  token at `/api/voice-token` and leaves it only at those four. The app half is a separate pull request.
- **Rolling back.** Revert the change and redeploy. `account-session` then answers `400 unknown_action`, and the app, which
  keeps the Supabase token it still holds, uses that. Sessions made while the new code was live are plain voice sessions
  to the earlier code too: `/api/voice-token`, `refresh` and `sign-out` read them the same way and keep working until they
  end. What the earlier code does not do: end them in `delete-conversations`, and keep the Apple link's 400 days when such a
  session is refreshed (it sets 30). Nothing stored needs changing either way.

### Revoking Sign in with Apple when an account is deleted (ADR-524)

App Store guideline 5.1.1(v) expects an app with Sign in with Apple to revoke the user's tokens when
they delete their account. With the three `APPLE_*` key settings above:

1. At sign-in the app also sends Apple's one-time `authorizationCode`. The server swaps it at
   `https://appleid.apple.com/auth/token` (an ES256 client secret signed with the key, valid 5
   minutes) and keeps Apple's refresh token only if the `id_token` in Apple's reply names the same
   person whose identity token was just verified. It is stored sealed, never logged, and expires
   with the DODDY session (30 days, extended on refresh).
2. "Delete voice account" first posts that token to `https://appleid.apple.com/auth/revoke`, then
   deletes everything, the sealed token included. The reply is `{ deleted: true, appleRevoked }`.
   Apple failing or timing out (5 seconds) never keeps the account: `appleRevoked` is `false` and
   the log line says `failed`, `no_token` or `not_configured`.

Without the key, sign-in and deletion work as before and nothing is sent to Apple's token
endpoints. Accounts made before the key was set have no token to revoke until they sign in again.
To make the key: Apple Developer › Keys › +, tick Sign in with Apple, pick the app's primary App ID,
download the `.p8` once (Apple keeps no copy), note the key ID.

Apple Developer setup is also required: enable Sign in with Apple for each real app identifier and
provision the matching entitlement/profile. The app's active iOS entitlement includes the capability,
but this repository cannot enable it in the Apple Developer account. Configure the durable Redis
store before deploying; the service fails closed when it or the signing key is missing. Existing
provider credentials and live agents must be checked by the DODDY owner in the hosting/provider
dashboards. This code does not deploy or change those settings.

The former `DODDY_ACCESS_CODES` setting is retired. Remove it from the host after the new signed-in
build and server configuration are ready. Old app settings for editable server URLs and public
agent IDs are cleared on launch; the old tester code Keychain item is deleted.

## Security behavior

- Apple identity tokens are verified against Apple's published signing keys, issuer, audience,
  expiry, issue time, and the hashed nonce.
- Refresh tokens are opaque, stored server-side only as hashes, and rotated after each refresh;
  replay fails closed. The hash a refresh replaced is remembered for the life of the session, and if
  it is ever presented again the whole session ends (refresh token and access token), because the
  token was copied or two devices hold it (ADR-712). The caller gets the same `401 session_expired`
  as for any dead token; only the log line carries `reuse: true`. An app that loses the reply to a
  refresh and tries again with the old token is signed out the same way and has to sign in with Apple
  again. Only the latest replaced token is remembered, so one from two refreshes ago is just unknown.
- Every provider-token request checks the signed access token against the active durable session.
- Shared atomic per-account (hourly and daily) and global rate limits run before any paid provider
  request. Only a token that is actually issued is counted, so a refused request never uses up the
  global budget or the account's own allowance (ADR-671, ADR-712). A `429` log line says which limit
  it was (`user_hour`, `user_day`, `global`, and the four added by "How the limits fit together":
  `new_account_day`, `new_pool`, `global_day`, `fair_share`); the app sees the same `rate_limited`
  with `Retry-After` for all of them.
- Sign-in is limited per caller address (`DODDY_SIGNINS_PER_CLIENT_HOUR` / `_DAY`), in the same
  Redis store and failing closed like the rest (ADR-712). It counts sign-ins that carry a token Apple
  verified, not junk, and not refresh or sign-out. The address is only believed from the header
  Vercel sets itself (`x-vercel-forwarded-for`), and only when the host is Vercel (`VERCEL` is set);
  an IPv6 address counts as its /64. Without a usable address every caller shares one "unknown"
  bucket with ten times the limit, and the log line carries `noClientAddress: true`. This is a brake
  on making many accounts from one place, not a defence against a network of addresses: add a Vercel
  Firewall rate limit on `/api/voice-auth` for that (dashboard setting). `account-session` is limited the same way, once
  the Doddy account's token has been checked, per account and per address, in buckets of its own and with the same two
  settings ("One token per server" above).
- With the defaults an account may have 30 tokens an hour and 100 are shared by everyone, but once half
  of those 100 are used an account that already had 10 in the hour waits for the next hour
  ("How the limits fit together" above). Lower `DODDY_TOKENS_PER_HOUR` or raise
  `DODDY_GLOBAL_TOKENS_PER_HOUR` to move that; it is the owner's choice of cost against convenience.
- Request sizes, method, provider, upstream timeout, and provider response shape are checked.
- No content, credentials, Apple subject, or user/account identifier is written to application logs. Neither is a
  conversation id: deleting voice conversations logs counts only.
- The server has no in-memory session or rate-limit fallback.

## Run server tests

```sh
npm test
```

## Apple references for the iOS implementation

- [Sign in with Apple design guidance](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple)
- [Authentication Services](https://developer.apple.com/documentation/authenticationservices)
- [ASAuthorizationAppleIDProvider](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidprovider)
