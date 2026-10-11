# Review — `server/messaging` (2026-10-11)

Read-only review. No code changed. Scope: `server/messaging/src/**`, `migrations/*.sql` (grep only), and the test list.

## Tests run

| Command | Environment | Result |
|---|---|---|
| `npm ci` | Node 22.22.0, Linux container | OK |
| `TEST_DATABASE_URL=postgres://…/doddy_test npm test` | Throwaway local Postgres 16 | **40 pass, 0 fail, 0 skipped** (exit 0) |

Not run: live Twilio, APNs, ElevenLabs, GNews, Anthropic or OpenAI calls (the tests use stand-ins), and anything on a physical device.

## Findings (most severe first)

No critical issues found. The SSRF guard, tenant scoping, secret comparison, PIN lockout, and the outbox's `unknown` handling all look sound.

### Medium

1. **`src/providers/elevenlabs.ts:254-255` + `src/routes/calls.ts:113-121`**
   - **Problem:** Every non-2xx reply from ElevenLabs, including 5xx and 504, is mapped to `rejected`. That sets the call to `failed`, and the app gets a 502.
   - **Failure scenario:** A gateway timeout arrives after the call has already started ringing. The app says it failed, the user taps "Call me now" again, and gets two calls. This breaks DOD-08 (`unknown` must never become a definite result).
   - **Fix:** Map `status >= 500 || status === 408` to `{kind:"unknown"}`, so the route returns 202 `status:"unknown"`. Add a test.

2. **`src/workerLoop.ts:263-270` + `src/news/digest.ts:153-173`**
   - **Problem:** News digests are built inside the same loop that sends messages. One pass can do up to 5 digests, each with up to 10 feed fetches (10 s each) plus an AI call (60 s timeout × 3 attempts).
   - **Failure scenario:** A PIN-lock alert or a "Doddy took a note" push waits several minutes behind a slow feed or a slow model call.
   - **Fix:** Run digests on their own timer or promise, separate from `dispatchDue`. Or use `batch = 1` with a time budget, and set the writer's `maxRetries` to 0–1.

3. **`src/outbox.ts:33-49` (via `src/routes/updates.ts:393`)**
   - **Problem:** Reusing an `idempotencyKey` with different text, channels or `sendAt` silently returns the old message.
   - **Failure scenario:** The app edits an update but reuses the key. The user sees "queued", but the old text goes out. This breaks DOD-07 (the approval must match the exact payload).
   - **Fix:** Store a hash of the payload with the key, and return 409 `idempotency_mismatch` when it differs.

4. **`src/routes/calls.ts:136-141`**
   - **Problem:** `GET /v1/call-notes` decrypts every row without a try/catch.
   - **Failure scenario:** One row that won't decrypt (after a key change, or a corrupt row) makes the whole inbox return 500. The user can't see or discard any of their notes.
   - **Fix:** Use `flatMap` and skip bad rows, as `search-memories` does (`elevenlabs.ts:330-336`). Better still, return `{id, unreadable:true}` so the row can be deleted.

### Low

5. **`src/outbox.ts:8-9, 85-93`**
   - **Problem:** The 20 claimed messages are sent one after another, with up to 10 s per device. On accounts with several devices, one pass can take longer than `STALE_SENDING` (5 min).
   - **Failure scenario:** A second worker (web and worker both running) marks rows that are still in flight as `unknown`. `finalize`'s `WHERE state='sending'` then updates nothing, so a real `sent` is lost.
   - **Fix:** Make the stale threshold larger than batch × devices × timeout, or claim smaller batches. Log when `finalize` updates 0 rows.

6. **`src/routes/elevenlabs.ts:305-310`**
   - **Problem:** The PIN-lock push is queued even when `deps.push` isn't configured. `save-note` checks `deps.push`; `verify-pin` doesn't.
   - **Failure scenario:** The message is retried 5 times as `push_not_configured`, then ends as `failed`.
   - **Fix:** Add `deps.push &&` before `canPush`.

7. **`src/news/digest.ts:90-106`**
   - **Problem:** `news_sent` rows are written before `enqueue`, and not in one transaction with it.
   - **Failure scenario:** If `enqueue` throws, the stories are marked "sent" for 14 days although nothing was sent. If one channel was already queued, the digest is still recorded as `failed`.
   - **Fix:** Write the items, `news_sent` and `enqueue` in one `inTransaction`.

8. **`src/outbox.ts:39-42` (privacy, DOD-11)**
   - **Problem:** The update text is stored in plaintext in `outbound_messages.body` until it's sent, which can be up to 30 days ahead. Call notes and memory copies, by contrast, are encrypted.
   - **Failure scenario:** A database leak exposes scheduled personal messages.
   - **Fix:** Encrypt the body with `TextCipher` (AAD `account:message:id`), or document this as an accepted risk.

9. **`src/routes/calls.ts:89-92`**
   - **Problem:** `DELETE /v1/calls/pin` leaves call sessions that were already PIN-verified valid, for up to 2 h.
   - **Failure scenario:** The user removes the PIN because of a suspicious call, but that call can still search their memories.
   - **Fix:** Also run `UPDATE call_sessions SET pin_verified_at = NULL WHERE account_id = $1` (or delete them).

10. **`src/news/sources.ts` (GNews mapping, about line 37)**
    - **Problem:** The `url` from GNews isn't passed through `httpUrl`, unlike feed links (`feeds.ts`).
    - **Failure scenario:** A malformed or non-http URL reaches the app as a tappable link.
    - **Fix:** Export `httpUrl` and drop items where it returns null.

11. **`src/routes/elevenlabs.ts:339-342` (DOD-06 / tool content is data)**
    - **Problem:** Memory text goes to the phone agent verbatim, with no marker saying it's user data.
    - **Failure scenario:** A saved memory such as "ignore your rules and…" is read by the voice model as if it were an instruction.
    - **Fix:** Return `{kind:"user_memory", text}`, and confirm the agent prompt treats tool results as data. The agent prompt is outside this area, so that part is unverified.

12. **Races (count, then insert)**
    - **Where:** `elevenlabs.ts:354-364` (`MAX_PENDING_NOTES`), `calls.ts:104-111` (daily outbound limit), `phone.ts:138-146` (verify caps).
    - **Problem:** Two requests at the same moment can both pass the check before either inserts.
    - **Failure scenario:** The caps are exceeded. Rate limits keep the impact small.
    - **Fix:** `pg_advisory_xact_lock(hashtext(account_id))` inside a transaction.

### Efficiency, duplication, dead code

13. **`src/workerLoop.ts:264`:** `purgeExpiredSessions` runs a DELETE every 2 s. Move it into the hourly prune block.
14. **`src/auth.ts:304-306`:** Every authenticated request writes `devices.last_seen_at`. Update it only when it's more than an hour old (`… AND last_seen_at < now() - interval '1 hour'`, with a separate SELECT).
15. **Duplicate helpers:**
    - `sha256` (`calls.ts:192`) and `hashToken` (`auth.ts:296`) are identical.
    - The channel-availability loop is repeated in `updates.ts:387`, `news.ts:73` and `digest.ts:84`.
    - The JSON logger in `workerLoop.ts:249` is re-implemented inline in `digest.ts:77`.
    - **Fix:** One helper each.
16. **`src/routes/calls.ts:36-44`:** `GET /v1/calls/settings` makes 3 sequential queries. These could be one query with subselects. Minor.

### Not verified (worth a test)

- **`src/news/feeds.ts:11-18`:** `processEntities: true` on untrusted XML. I didn't check whether fast-xml-parser 5.11 limits DOCTYPE entity expansion (a "billion laughs" feed). Inputs are capped at 2 MB, but the expanded output isn't. Add a test with a nested-entity feed.

## Missing tests

- ElevenLabs outbound returning 5xx or a network error.
- Transient push retry, backoff, and the `MAX_ATTEMPTS` → `failed` path.
- The stale-`sending` reaper.
- PIN lock escalation (`pinLockMinutes`) across several locks.
- A phone number moving between accounts cancels the old account's queued SMS.
- Idempotency key reused with a different payload.
- An undecryptable call note.
- A digest where `enqueue` fails partway.

## Top 5 fixes

| # | Fix | Finding | Effort | Risk |
|---|---|---|---|---|
| 1 | Treat ElevenLabs 5xx/408 as `unknown` | 1 | S | Low |
| 2 | Skip or mark undecryptable call notes instead of a 500 | 4 | S | Low |
| 3 | Reject an idempotency key reused with a different payload | 3 | S | Low (needs a migration column) |
| 4 | Take digests out of the dispatch loop, or time-box them | 2 | M | Medium (worker behaviour) |
| 5 | Clear PIN-verified sessions on PIN delete; add `deps.push` check to verify-pin | 9 + 6 | S | Low |

## Constitution evidence log

- **DOD-07:** `outbox.enqueue` idempotency ignores the payload. Gap: finding 3.
- **DOD-08:** The outbox never retries `unknown` (`outbox.ts:89-90, 144`; `twilio.ts:101-104`; `apns.ts:205-209`). That is enforced in code and covered by the "failures are not retried blindly" test. Gap: ElevenLabs 5xx (finding 1).
- **DOD-06:**
  - Memories are returned only after the PIN (`elevenlabs.ts:319`), tested.
  - Turning the memory copy off deletes every copy (`calls.ts:159`), tested.
  - Notes are only "saved_for_confirmation" after a verified INSERT (`elevenlabs.ts:361-369`).
- **DOD-11:**
  - Memory text and notes use AES-GCM bound to the account and row (`crypto.ts`), tested.
  - Logs redact secrets (`app.ts:50`).
  - Gap: plaintext outbound bodies (finding 8).
- **Claims to limit:** "Tested" here means the stand-ins and a local Postgres only. No real provider delivery was exercised.

---

## Fix status (2026-10-11, owner approved "fix all")

| # | Status | Commit |
|---|---|---|
| 1 | fixed: ElevenLabs 5xx/408 → `unknown`, with a test | `0e44e7a` |
| 2 | fixed: digests run in their own loop; writer retries 2 → 1; the test fails on the old loop | `caa89b5` |
| 3 | fixed: key bound to a payload hash (migration 006); 409 `idempotency_mismatch` | `27274d5` |
| 4 | fixed: undecryptable notes listed under `unreadable` (the iOS decoder is unaffected) | `2c6187e` |
| 5 | fixed: claim refreshed per message; a reaped row is skipped; a late outcome is logged; the test fails on the old code | `f2518a1` |
| 6 | fixed: `deps.push` checked before the PIN-lock alert | `4e770d3` |
| 7 | fixed: items, `news_sent` and enqueue in one transaction | `be7787a` |
| 8 | fixed: queued text encrypted when `MEMORY_ENCRYPTION_KEY` is set (migration 007); `body_unreadable` → failed, never sent | `6eac05f` |
| 9 | fixed: changing or removing the PIN clears `pin_verified_at` on sessions | `4e770d3` |
| 10 | fixed: GNews URLs go through `httpUrl` | `cf1338a` |
| 11 | **prompt only**: rule added to `voice-agent/phone/instructions.md`; takes effect only after it is re-applied to the ElevenLabs agent. No code enforces it. | `525175a` |
| 12 | fixed: advisory lock + transaction for notes, outbound calls and verify caps; the notes race test fails on the old code | `754b1c7` |
| 13 | fixed: session purge is hourly | `caa89b5` |
| 14 | fixed: `last_seen_at` written at most hourly | `ed433eb` |
| 15 | fixed: one `sha256`, `usableChannels()` and `log` | `ed433eb` |
| 16 | fixed: settings in one query | `ed433eb` |
| XML entity bombs | verified safe: fast-xml-parser 5.11 caps entity size at 10 KB and expansion at 100 KB, with no recursive expansion. A regression test now pins this. | `f229cb8` |
| Missing tests | added: outbound 5xx, retry limit, reaper skip, number move, idempotency mismatch, unreadable note, digest enqueue failure, PIN change, parallel notes. The PIN escalation test already existed. | various |

Tests after the fixes: `TEST_DATABASE_URL=… npm test` → **53 pass, 0 fail** (Node 22.22, throwaway Postgres 16).

**Behaviour changes to note for deploy:**
- Migrations 006 and 007 run automatically on start.
- `GET /v1/call-notes` gains an `unreadable` array.
- `POST /v1/updates` can return 409 `idempotency_mismatch`.
- When both a channel isn't configured and another isn't enabled, `/v1/updates` now reports `*_not_configured` first.

**Not verified:**
- Real provider delivery.
- Deploying the migrations to the Render database.
- The ElevenLabs agent prompt update.
- iOS handling of the new `unreadable` list (the app ignores it for now).

**Testing gotcha:** without `TEST_DATABASE_URL`, `npm test` skips all database suites. It shows 14 passing tests and "skipped 0", which looks like a full pass.
