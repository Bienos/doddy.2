# S2 status — phone calls with Doddy (Twilio + ElevenLabs)

> **Merged 2026-10-10:** this work now sits on the combined branch line. The server lives in
> `server/messaging/` (it was `server/`), its ADRs are 139–168 (were 036–065), the
> `/v1/voice/token` route is gone (the app uses the Vercel `server/voice-token`), and this line's
> M4 Reminders was replaced by the main line's. See `docs/implementation/MERGE_PLAN.md`.
>
> **Security fixes (ADR-175):** PINs are now 6–8 digits; lockouts escalate (15 min → 24 h) with a push to the owner; see `SECURITY_REVIEW_MESSAGING.md`.

Date: 2026-10-10. Owner decisions on that date:
- Calls in **both directions**.
- **Opt-in memory copy on the server**, so calls can answer from memories.

## How a call works
1. **Inbound:** the user calls Doddy's Twilio number, which is imported into ElevenLabs and assigned to the "Doddy (phone)" agent.
2. **Call start:** while the phone rings, ElevenLabs calls `POST /webhooks/elevenlabs/call-start` with the caller ID.
   - The server answers with dynamic variables.
   - Only a verified number whose owner turned calls on gets a session. Unknown numbers and numbers with calls off get none.
3. **Session:** the session key is a `secret__` variable. ElevenLabs only puts it in tool request headers (`X-Doddy-Session`), never in the model's context. Every tool request also carries `X-Doddy-Tool-Secret`.
4. **PIN:** the agent asks for the PIN (`verify_pin`). Only after that can it `search_memories` or `save_note`.
   - The PIN is an scrypt hash.
   - 5 wrong tries lock it for 15 minutes.
5. **Answers:** answers come only from the user's opt-in memory copy. It holds the corrected text and is encrypted at rest (AES-256-GCM, bound to account and row). It is **not end-to-end encrypted**: the server decrypts it to answer.
6. **Notes:** notes said on a call go to an inbox. The app shows them under Settings → Phone calls, and they become memories only when the user taps **Save to memories**. The push notification doesn't contain the note.
7. **Outbound ("Call me now"):** goes only to the verified number, after consent `calls-v1`.
   - Limits are 3 per hour and 10 per day.
   - The server passes the same session variables to ElevenLabs' Twilio outbound-call API.
   - A timeout is recorded as `unknown` and never redialled.

## Built
- **Server:** migration `002_calls.sql`, `calls.ts`, `crypto.ts`, `memorySearch.ts`, routes `calls.ts` (app) and `elevenlabs.ts` (webhook and tools), `ElevenLabsOutboundCaller`.
- **`server/messaging/scripts/setup-phone-agent.mjs`:** creates the workspace secret, the 3 webhook tools (with secret and session headers) and the agent.
- **Since 2026-10-10 (ADR-172):** the prompt, tools and settings live in `voice-agent/phone/` and are checked in CI (`voice_agent_spec.py check --agent phone`); the script reads them. Its tool requests now also carry `pre_tool_speech` / `force_pre_tool_speech`, the same fields the app agent's live tools use. The dry-run output was compared by eye with the earlier one; it was **not** re-validated against the ElevenLabs OpenAPI schema.
  - The agent has the prompt, an AI disclosure in its first sentence, no audio recording, and 30-day transcript retention.
  - The workspace-wide call-start webhook is changed only with `--set-workspace-webhook`.
- **DoddyCore:** `CallsClient.swift` (settings, PIN, consent `calls-v1`, call me now, call list, notes inbox, memory copy on/off and snapshot), `CallPIN` rules shared with the server, `.weakPIN` error, capability `.phoneCalls`. The catalog never reports it as "available"; it is "needs setup" until the screen confirms.
- **App:**
  - **Settings → Phone calls:** Doddy's number with a Call button, PIN set/change/remove, "Answer calls from my number", "Let Doddy use my memories on calls" (with the not-end-to-end wording), "Doddy may call me" (with the consent text), Call me now, recent calls, and the call notes inbox.
  - **Memory sync:** `MemoryCopySync` re-uploads the full current memory list after every change while the copy is on, so deletions and corrections carry over.
  - **Private notes (ADR-310) are never in the copy.** Since 2026-10-18 `MemoryCopyItem.from` requires the set of private notes and leaves them out, and `MemoryCopySync` reads that set just before every upload. Before this, the first upload after switching "Memory on calls" on sent every note, private ones included, until the next note change replaced it with a filtered copy. To clear such copies, Doddy replaces the server copy once after the update, at launch or when it comes to the front, while the copy is on and only after the notes were read successfully (`MemoryCopyResend`). It counts as done only once the server confirmed an upload; until then it is tried again. Linux tests: `CallsClientTests`. `MemoryCopySync.swift` was type-checked on Linux against DoddyCore with stand-ins for `ServerConfig` and `UpdatesModel`; it and the `RootView` triggers have NOT been built in Xcode or run on a device.
  - **Saving call notes:** a saved note gets source "Your voice note" and the time it was said.
  - **Deleting server data** now also clears the call settings and the memory copy.
  - **Privacy manifest:** other user content is now marked linked.

## Executed (Linux, Node 22.22.0, PostgreSQL 16.15, Swift 6.2.3)
| Check | Result |
|---|---|
| Server `npm test` | **22 tests, 0 failures**, 11 new for S2: secret check, unknown/calls-off callers, PIN gate + lockout, encryption at rest, notes + content-free push, snapshot replace/delete, outbound consent + session + unknown outcome, settings, account deletion cascade, not-configured 503s |
| Mutation check | Removing the PIN check from `search-memories` makes the PIN test fail |
| `swift test` (DoddyCore) | **46 tests, 0 failures**, 5 new |
| End-to-end: Swift client + simulated ElevenLabs → real server + Postgres | **15/15 PASS** after fixing one real bug it found (below) |
| `setup-phone-agent.mjs --dry-run` | All 6 requests validate against ElevenLabs' published OpenAPI schema, with no unknown fields |
| App Swift files | parse; guard PASS |

**Bug found by the end-to-end run, fixed:** iOS sends memory IDs in uppercase and Postgres returns them in lowercase. The encryption binding used the ID as sent, so every copied memory failed to decrypt on a call. The server now lowercases IDs, and the server test sends uppercase IDs like iOS does.

## Not run / owner actions
- **Nothing has run against the real services:** no real phone call, Twilio number, ElevenLabs agent or tool request has been tried. Apple and Twilio were stand-ins; ElevenLabs requests were simulated.
- **App target not compiled in Xcode.**
- **Before calls work:**
  1. Deploy the server.
  2. Set `MEMORY_ENCRYPTION_KEY` and `ELEVENLABS_TOOL_SECRET` (`openssl rand -base64 32` each).
  3. Run `setup-phone-agent.mjs`.
  4. Import the Twilio number into ElevenLabs and assign it to the agent.
  5. Set the call-start webhook.
  6. Set `ELEVENLABS_PHONE_AGENT_ID`, `ELEVENLABS_PHONE_NUMBER_ID` and `DODDY_PHONE_NUMBER`.
- **Back up `MEMORY_ENCRYPTION_KEY`:** losing it makes memory copies, call notes and queued messages unreadable (queued ones then fail as `body_unreadable` and are never sent). Users can re-upload copies by switching memory off and on again; pending notes would be lost.
- **Legal/privacy before other users:**
  - privacy policy text for the memory copy, call transcripts at ElevenLabs (30 days) and Twilio call records;
  - EU AI Act disclosure (done in the first message);
  - consent rules for outbound calls in each country used.

## Known limits
- Scheduled check-in calls (Doddy calling at a set time) are not built; only "Call me now".
- Search on calls is lexical (same rules as the app), not semantic.
- The memory copy is re-uploaded in full after each change. That's fine for hundreds of memories; at much larger sizes it would need incremental sync.
- One shared PIN lockout per account (not per call), so someone guessing can lock out the real user for 15 minutes.

## Recaps (ADR-684, 2 Nov 2026, branch `claude/call-recap`, not merged)

Owner: "czy daje mi recap rozmowy co było ogarnięte", then "i robimy ten recap też". **State: built and tested with fakes. No real call has produced a recap. The two SwiftUI files are not compiled.**

**State of the line on 2 Nov 2026** (read only): Doddy's number +372 636 0658 is imported into ElevenLabs and assigned to "Doddy (phone)"; the live `doddy-messaging` start-up log says `calls`, `outboundCalls` and `taskCalls` true and `push` false; the phone agent had no conversations yet.

### What the user gets
After a call to Doddy's number or a Call me now: Settings › Phone calls › Recent calls shows "recap coming", then "recap ready". Opening it shows:
- **Summary**: one or two sentences in the caller's language, written by Claude Haiku from the transcript only; or, when there is none, why (no key on the server, the daily cap, a second failure, the summary claimed something was saved, nobody spoke).
- **Settled on the call** and **Doddy couldn't do this on a call**: each item with the words it came from (`Said: "…"`).
- **Notes Doddy took**: the notes `save_note` put in the inbox on that call, with the reminder that each becomes a memory only when saved in Notes from your calls.
- **Next step**, the **transcript** (a PIN said on the call shows as ••••), and **Delete recap**.

### How it works
1. ElevenLabs' workspace post-call webhook (`POST /webhooks/elevenlabs/post-call`, HMAC `ELEVENLABS_WEBHOOK_SECRET`) brings the transcript. Payloads of `ELEVENLABS_PHONE_AGENT_ID` go to `src/callRecaps/service.ts` (`onPhonePostCall`); the task-call agent's go to its answer card as before; others are dropped.
2. A payload is kept only if a `calls` row from the last 2 days has its conversation id (Call me now: from ElevenLabs' reply) or its Twilio call SID (calls in: from the call-start webhook). Such a row exists only for a confirmed number with calls on. Kept: the turns' text, times and tool names, encrypted (`call_recaps.input_ciphertext`).
3. The worker (`recapLoop`, every 5 s) masks the caller's PIN, asks the writer (optional), checks its answer (`src/callRecaps/recap.ts`), stores the recap encrypted with its SHA-256 digest, deletes the turns, and writes a receipt. A writer failure is tried once more after 3 minutes, then the recap is built without a summary.
4. The app (`CallRecapLoader`, DoddyCore) gets `GET /v1/calls/:id/recap`, saves it in `v21_call_recaps` (read back), then `POST /v1/calls/:id/recap/ack {digest}`: the server deletes its copy and returns receipts. A failed ack leaves the server copy; it is retried the next time the recap opens. `DELETE /v1/calls/:id/recap` deletes the server's copy first, then the iPhone's. A recap never opened is wiped after 30 days; deleting the account removes every row.

| Route | Reply |
|---|---|
| `GET /v1/calls` | each call now has `recap`: `none`, `waiting`, `ready`, `acked`, `deleted` or `expired` (older apps ignore it) |
| `GET /v1/calls/:id/recap` | `{ callId, state }`, plus `recap` and `digest` when `ready`; 404 for a call of another account |
| `POST /v1/calls/:id/recap/ack` | `{ deletions: [ { what, reason, deletedAt } ] }`; 409 `recap_mismatch` / `no_recap`; repeated acks get the same answer |
| `DELETE /v1/calls/:id/recap` | `{ deletions }` |

Limits: model-written recaps `CALL_RECAP_DAILY_PER_ACCOUNT` (default 30, ceiling 100) and `CALL_RECAP_DAILY_PER_SERVER` (default 300, ceiling 5000, in `server_daily_usage`); past them the recap has no summary.

### Checked (Linux, 2 Nov 2026)
- `server/messaging`: `npm run typecheck`; `npm test` against a throwaway Postgres 16: **609 pass, 0 fail, 0 skipped** (11 new in `test/callRecaps.test.ts`: PIN masking, save claims in English and Polish, pointer checks, the whole path from call-start to ack with receipts, Call me now, other accounts, unknown and calls-off callers, other agents, bad signatures, replays, writer retry, the daily cap, Delete, 30-day expiry, account deletion). Turning the PIN masking off made 3 of them fail.
- DoddyCore `swift test` (Swift 6.2.3, Linux): **2,244 tests, 0 failures** (13 new: `CallRecapTests`, `SQLiteCallRecapRepositoryTests`, the `callRecaps` data-flow row).
- `scripts/typecheck_app_logic.sh`: `CallRecapModel.swift` type-checks in Swift 6 against DoddyCore.
- `tools/build_strings_catalog.py --check`, `voice_agent_spec.py check --agent phone`, `setup-phone-agent.mjs --dry-run`, the secrets manifest tests.

### Not checked
- **No real call, no real post-call payload.** The payload shape follows the call cases' (`conversationSchema`) and ElevenLabs' documented `metadata.phone_call.call_sid`; neither was seen from the phone agent. Whether ElevenLabs' call-start webhook sends `call_sid` (or `conversation_id`) for calls in, as the code expects, is unverified; with neither, a call in can't be matched and gets no recap (nothing is stored for it). The first real call answers this: its `calls` row shows whether `call_sid` was filled.
- **`CallRecapView.swift` and the `CallsSettingsView.swift` change: BLOCKED / NOT RUN** (SwiftUI, no Xcode here). Nothing seen on a device.
- The real Claude Haiku call with this schema; the Polish wording in context.

### Owner steps to turn it on
1. Merge and deploy `doddy-messaging` (migration 016 runs at start-up).
2. In ElevenLabs › Agents › Settings, the workspace **post-call webhook** points at `https://doddy-messaging-zw1n.onrender.com/webhooks/elevenlabs/post-call`, transcripts on, audio off, with the secret that is in `ELEVENLABS_WEBHOOK_SECRET` (the same webhook call cases need). Nothing on the phone agent changes.
3. Check `ELEVENLABS_PHONE_AGENT_ID` is `agent_4801m5q2sq5xft6ab6k0mnyda04v` on the server; the start-up log then says `callRecaps: true` (and `callRecapWriter: true` with `ANTHROPIC_API_KEY`).
4. Build the app from the merged branch, make one call, open Recent calls.

### Privacy
- **To Anthropic:** the words of a call between the user's own confirmed number and Doddy (PIN masked), including anything Doddy read out from the memory copy on that call. Not the audio, not the phone number. `DataFlow` row `callRecaps` says so in What leaves this iPhone.
- **On the server:** the turns until the recap is built, then the recap, encrypted with `MEMORY_ENCRYPTION_KEY`, until the app acknowledges it (at most 30 days). Logs carry ids, states and counts only.
- **Caller ID can be faked:** a caller spoofing the user's number (calls on) gets a recap written into the user's account, without the PIN. It holds only what that caller said and what Doddy answered without the PIN; the daily caps bound the cost.
- A PIN said as words ("dwa pięć…") instead of digits is not masked.
