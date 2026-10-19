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
