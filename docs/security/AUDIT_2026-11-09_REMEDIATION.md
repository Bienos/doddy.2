# Security audit of 9 Nov 2026: what was checked, fixed and left

The audit itself is kept as it was delivered: [`AUDIT_2026-11-09.md`](AUDIT_2026-11-09.md) (revision `54e1e63`, offline source review, three findings). This page records what was done about it. It does not replace it.

**Status of this page: written 9 Nov 2026 on branch `claude/compassionate-darwin-rh03mv`, from `adb8f64`. Nothing here has been deployed, and nothing was run against a live service, a real account or a phone.** Where a line says "tested", the test is named and was run; where it says "not compiled" or "not run", it was not.

## Summary

| # | Finding (audit severity, confidence) | Verdict | Fixed? |
|---|---|---|---|
| 1 | Sign-out leaves messaging credentials and private push delivery active (medium, high) | **Confirmed** | Yes: the server can end one iPhone (`DELETE /v1/device`); sign-out now asks it to, and keeps asking until it answers. App side not compiled. |
| 2 | A late token refresh can restore the account after sign-out (medium, medium) | **Confirmed** (reproduced by test: 8 of 9 new tests fail on the old code) | Yes |
| 3 | Generated provider files survive local cleanup and account erasure (low, high) | **Confirmed** | Yes |
| – | Account B adopted while account A's messaging credential remains (audit: needs follow-up) | **Not confirmed as reachable from the screens.** A related, real hole was found next to it | Hardened; see below |

None of the three was already resolved at `adb8f64`: `git diff 54e1e63..HEAD` touched none of the files the audit names (the later commits are site, CI and Home design work).

## Finding 1: sign-out and the messaging server

**Cause.** `DoddyAccountServers.forgetAccountTokens` deleted the iPhone's copy of its messaging token. On the server, the token is a row of `devices` (stored as a hash) with the iPhone's APNs address in the same row. Nothing ended it: `requireDevice` accepted the token forever, and `sendPush` addressed every device of the account, signed out or not. Account deletion removed devices; ordinary sign-out did not. The existing `DELETE /v1/device/push-token` was never called by sign-out.

**Fix.**
- **Server** (`server/messaging/src/routes/account.ts`): `DELETE /v1/device`, authenticated by the iPhone's own token, deletes that device row. Token and push binding are columns of it, so both end in one statement. Other iPhones of the account are untouched. It refuses (409) for an iPhone of an anonymous account that no Doddy account owns, because that row is the only way back into that account. No migration.
- **Client rules** (`DoddyCore/Account/MessagingDeviceRevocation.swift`, tested on Linux): the request, and a list of tokens whose revocation is *owed*. A token is written to a separate Keychain slot first, then removed from the slot the app uses, so signing out is immediate; the request is tried at once and again at each launch and each sign-in, until the server answers. `204` and `401` (already gone) end the obligation; `409` ends it too (a retry would say the same); a timeout, `429`, `5xx` or `404` (a server that doesn't have the route yet) leave it owed. At most 5 are kept, oldest first. The owed list never restores a session: its tokens are used for this one request and nothing else.
- **App** (`DoddyApp/Features/Account/DoddyAccountApp.swift`, and `ServerPendingRevocationStore` in `Infrastructure/Server/ServerKeychainStore.swift` (a Keychain file already on the guard's list)): wires the above to the Keychain and to sign-out. A sign-out because the account stopped working goes the same way.

**Local sign-out is not confirmed revocation, and the code keeps them apart.** After a sign-out that couldn't reach the server, the iPhone is signed out and the server still knows the token until the retry succeeds. There is no screen that says so; `PendingDeviceRevocations.count` is the only trace. Until it is answered, a copied token still works. That window is as long as the iPhone stays offline or unlaunched.

**Tests run.**
- `server/messaging/test/deviceRevocation.test.ts`, 7 tests, real Postgres: the token is refused afterwards and a repeat is safe; a push sent after revocation reaches only the other iPhone (checked through the real outbox with a fake APNs sender); the other iPhone keeps working and can still register for push; signing in again gives a new token and the old one stays dead; the anonymous-account guard; a missing, malformed or unknown token deletes nothing; `DELETE /v1/device/push-token` still behaves as before.
- `MessagingDeviceRevocationTests`, 12 tests: each answer's meaning, durability across a restart, a token added during a retry is not lost, a failed write never drops what is owed.
- Not run: the app glue (`DoddyAccountApp.swift`, `ServerKeychainStore.swift`). It was only syntax-checked (`swiftc -parse`); no Xcode here.

**Deploy order matters.** Deploy the messaging server first. An app that signs out against a server without the route gets `404` and keeps the token owed (harmless, but nothing is revoked until the server has it). The messaging service is behind `main` and auto-deploy is off (`STATUS.md`), so this is an owner step.

**Not done, and why.**
- *Bounded token lifetime / rotation.* A device token never expires. Idle expiry for account-linked devices is a small server change, but it would also have to decide what happens to pushes for an iPhone nobody opens for 90 days, and the app's recovery from a `401` (it signs in again through the account) can't be exercised here. Recommended as a follow-up, not a launch blocker now that sign-out revokes.
- *A device list with remote revocation.* New UI; not part of fixing the finding.
- *Neutral notification previews.* Checked what the server actually pushes: calls, errands, watches, Studio and call notes are already fixed neutral sentences ("Doddy finished the call. The answer is waiting in the app."). Only the user's own scheduled updates, text replies and news digests carry content. iOS's own "Show Previews" setting already hides content on the lock screen. A per-app choice is a product decision; recommended as a follow-up.

## Finding 2: a late refresh restoring a signed-out account

**Cause.** `DoddyAccountModel.refreshed` awaited the network, then unconditionally saved and installed the result. `@MainActor` serialises the code but not the suspension points, so a sign-out, or another account signing in, during the wait was overwritten by the old account's answer (a success), or signed out by it (a failure). Callers that joined the same refresh got its result with no check either.

**Fix** (`DoddyAccountModel.swift`). An `identityEpoch` that every sign-out, sign-in and change of account starts. A refresh is applied, once and inside the shared task, only if the epoch and the user are still the ones it started with; every caller that waited on it checks the epoch again before being handed anything. A stale success writes nothing to the Keychain; a stale failure signs nobody out. Cancellation is a courtesy; the check is what makes it correct. Also:
- `signOut()` now forgets locally *first*, then tells Supabase. Before, a pending refresh had the whole network round trip to bring the session back.
- A different account signing in over a kept session now runs the sign-out hook for the old one, so its server credentials are dropped (this is the model-level answer to the follow-up below).

**Tests run.** `DoddyAccountRaceTests`, 9 tests, with a transport the test holds open: late success after sign-out; late success after A→B; a late failure of A's refresh not signing B out; a late failure after sign-out; two callers sharing one refresh both refused; sign-out not waiting for the server; epochs; and two controls (an ordinary refresh, the same person signing in again). Run against the original model, 8 fail (the control passes). The 13 `DoddyAccountModelTests` and the 17 `DoddyAccountTests` pass unchanged.

**Remaining.** The same person signing in again while a refresh is on its way also starts a new epoch, so that refresh is dropped and its caller gets a one-off `.signedOut` error although the person is still signed in. It is safe (the dropped refresh used a refresh token the new sign-in replaced) and the next call refreshes normally; callers read the error as "no token now". Not worth a more complicated rule.

## Finding 3: copies at Anthropic

**Cause.** `AnthropicClaudeProvider.makeDocument` kept the file ids in memory, deleted them fire-and-forget only after a successful download, and never looked at the response (`fetch` doesn't throw on `429` or `500`). A failed download, a timeout, a restart or a refused delete left the copy at Anthropic with no record anyone could retry, and erasing the account couldn't know it existed.

**Provider contract checked** (Anthropic's Files API reference, 9 Nov 2026): `DELETE /v1/files/{id}` returns `200` with `type: "file_deleted"`. The page doesn't list a not-found answer; the messaging server's Studio already treats Anthropic's NotFound as "gone", and so does this. Retention of files that are never deleted is not documented there either, so none is assumed.

**Fix.**
- The provider writes each file id into a ledger the moment it sees it (before the download), deletes in `finally` whatever else fails, and counts a copy as gone only on `200` or `404`; `429`, `5xx`, a refused key or no answer leave it owed.
- Owed copies reuse the backend's existing `cleanups` table (provider `anthropic_file`, `connection_id` = the file id; nothing else about the file is stored, no migration). That table is already kept through account erasure (`KEPT_ON_ERASE`).
- The hourly sweep retries them (not within a document job's 8 minutes, so a running job is never raced; 24 tries, like connections; a row past that stays visible as `failed`, never dropped). It logs counts only (`document_files_swept`).
- Erasing an account removes owed copies in the same request through a new remover; one that fails makes the answer `complete: false` and stays queued, like any other provider.

**Tests run.** `backend/test/document-file-cleanup.test.ts`, 14 tests: copies deleted after a success, a failed download, a job that never finishes and a job whose signal fired; `429`/`5xx`/network answers stay owed and `404` counts as gone; a broken ledger doesn't lose the document; sweep retry, not racing a young row, giving up visibly after 24 tries, a crash leaving ids owed and the next process deleting them, a connection id never sent to Anthropic; erasure keeping the obligation and finishing it. They don't compile against the old code (the API didn't exist), so "fails before the fix" is by construction, not by a red run.

**Remaining.** If the very first `messages` call times out after Anthropic made files, their ids were never seen and can't be tracked; whether Anthropic expires them is unverified. Studio in the messaging server already tracks and re-reads its copies (ADR-740) and was not changed. The backend service must be deployed for any of this to take effect (owner step; auto-deploy is off).

## The account-switch follow-up

The audit asked for a reproduction of "A signed in, B adopted, A's messaging credential still used" before calling it a finding.
- **Not reachable from the screens, as far as the source shows.** When a session exists the welcome sheet offers only "Continue" (`SignInSheet.accountContent`); no sign-in button is shown. The model API, however, allowed it, and in that case A's token stayed in the Keychain. Now the model runs the sign-out hook when the user changes (above).
- **A real adjacent hole, confirmed by reading the code (timing-dependent, not reproduced on a device).** `bringEarlierData`, `signInMessaging`, `linkBackend` and `messagingTokenOnMain` wait on a server (about 20 seconds when Render's free instance is asleep), then wrote the messaging device token and the backend token with no check that the person was still signed in. Sign out during that wait and the signed-out account's credentials were written back. Each now remembers `identityEpoch` before the wait and drops the answer if it changed; a messaging token the server made for an account that signed out is revoked at once. Not compiled.

## Also reviewed

| Area | Result |
|---|---|
| Local notes after sign-out | Unchanged, as the product decision says; the sign-out dialog discloses it. An "erase on sign-out" choice and per-account local stores are new UI and an owner decision (`docs/platforms/iphone.md`, Known gaps). Recommended. |
| Messaging database TLS | `db.ts` passes `DATABASE_URL` to `pg` as given: TLS happens only if the URL asks for it, and the deployment uses Render's Internal URL. **Not changed**: forcing TLS blind can stop the service. Owner step: check the URL, add `?sslmode=require` if the provider allows it, or add a guard like the backend's once confirmed. |
| Voice provider keys, webhooks, SSRF, Supabase verification | The audit found no issue; nothing here contradicts it, and nothing was changed. |
| Spend limits, backups, provider retention, log redaction, operator access, key rotation | Dashboard and production settings; not checkable from the repository. Already in `docs/OWNER_QUEUE.md` where known. |
| inFakt credential scope | The audit rejected it (the adapter throws today). Unchanged; scope and clear it before a working adapter ships. |

## Follow-up

**Before real users, with this change:** deploy the messaging server, then the backend (owner); build and run the app on a device and check the three sign-out cases below.
**Soon:** idle expiry for account-linked device tokens; an owed-revocation notice or a device list in Settings; a per-app notification-preview choice; erase-on-sign-out; TLS on the messaging database; an alert on `document_files_swept` with `failed > 0`.
**Device checks nobody has done:** sign in and out online (the iPhone gets no push afterwards, its old token is refused); sign out in airplane mode, then go online and relaunch (the revocation is paid); sign out while the first sign-in's link request is still pending (nothing is written back).

**Separate, already known, and dated:** the messaging database on Render's free plan **expires 10 Nov 2026, 10:11 UTC** (`STATUS.md`, OWNER_QUEUE 1). Everything above, and every account's server data, is in it.
