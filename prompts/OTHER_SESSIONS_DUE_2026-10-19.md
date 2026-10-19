# Finish what my other Doddy sessions left open (19 Oct)

Repo `Bienos/doddy.2`, default branch `claude/loving-dirac-uuxoux`. Read `STATUS.md` and `CLAUDE.md` first.

**Start only after the merge session is done.** The merge session is `session_01RGYbtpY4KDQunpJzkXaWhh` ("Voice back and merge #84, #88, #90"). It merges #84, #88 and #90 and updates `STATUS.md`. Check it with `get_session` and read its last message. If it's still working, wait for it, using `send_later` every 30 minutes. Don't redo its work.

## Rules
- **Your own branch:** push only to this session's branch, or to new branches you create.
- **Other sessions' branches:** to change one, first ask its session with `send_message`. If it says no, or doesn't reply within 60 minutes, tell me rather than push.
- **Secrets and live services:** never handle secret values. Never change Vercel, Render, Twilio, ElevenLabs, Composio, Upstash, Supabase or Apple settings without my yes in this chat. Read-only checks are fine.
- **Merging:** merge only with green `core` and `ci`, no conflict, and `expectedHeadSha` set. Use merge commits only, never rebase or force-push. Never skip or loosen a test.
- **Done means done:** don't say anything works on a device. Mark it not run.

## My decisions (19 Oct) — record and build these
- **Translator mode asks first,** like every other tool (ASK-01). No code change; the tests already expect it. Record it as a new ADR row in `DECISIONS.md`. Search for the highest number first, and don't reuse 483, 490–495 or 530. Mark #84's open question answered in `STATUS.md`.
- **BLIK ceiling is 1,000 zł per transfer** (was 10,000 zł).
  - Change `BlikTransferLimits.maxGrosze` in `Packages/DoddyCore/Sources/DoddyCore/BlikTransfer.swift` to 100,000 grosze, and its doc comment.
  - Update `BlikTransferTests.swift`: 1000 is allowed, 1000.01 is refused.
  - Update `docs/implementation/BLIK_TRANSFER_STATUS.md`, any user-facing string or agent text that names the limit (grep `10,000`, `10 000` and `10000` in `l10n/`, `voice-agent/` and `DoddyApp/`), and an ADR row.
  - Do it in one PR from main. Merge it when `core` and `ci` are green.

- **The repository stays public.**
  - Record it as an ADR row.
  - Correct ADR-497's text, which says the repo is private and that Actions time is paid for; that's not true for a public repo on standard runners.
  - Because it's public, grep the repo for anything that looks like a secret (keys, tokens, `sk-`, `GOCSPX`, `ac_`, `ca_` IDs, private URLs) with `scripts/check_forbidden_capabilities.sh` and a plain `git grep`, and list any hits to me, names and paths only.

## Work for you, in this order
0. **Privacy fix first.** The fix that stops private notes reaching the calls server when "Memory on calls" is on was never merged; it's stranded on `claude/sweet-albattani-shbi30`.
   - Port it onto a new branch from main and open a PR with tests.
   - Merge it when CI is green and you've shown me the diff.
   - Then tell me how to check whether a copy of my notes already sits on the calls server, read-only.
1. **Live voice agent safety check.** The live ElevenLabs agent (`agent_0501m4et27vyeawrwqfdxxfszfa6`) has five tools that aren't in main's spec:
   - `text_me` and `call_me_later` (from `claude/awesome-cray-2lb9ia`);
   - `add_to_diary`, `pay_for_page` and `upcoming_renewals` (from a stale 12 Oct branch).

   Some don't ask first (no `x_doddy.ask`).
   - Read the live agent with `agents_get` (read-only).
   - For each tool, propose in one line: detach it, or keep it and add `x_doddy.ask='tap'` with `confirm_on_screen`.
   - Don't change the agent until I say yes, then sync once and record the new version in `voice-agent/README.md`.
2. **Phone number branch** (`claude/awesome-cray-2lb9ia`, session `session_01TWmNMWhbDNzDVVkN5AfFhs`). Ask that session to do these, or do them yourself if it agrees to stand down:
   - merge main in, with a merge commit;
   - add the ASK-01 fields to `text_me` and `call_me_later`;
   - renumber its ADR-493, 494 and 495 from 531 up;
   - drop the duplicate guard fix in `6abc1546` through the merge resolution, not a rebase;
   - get CI green on its draft PR. Don't merge it.
3. **PR #86** (connect an account in the conversation; Cowork session `session_01ArZvvveZvmZojLVjeTYk9q`, idle). Same pattern:
   - merge main in;
   - renumber its ADR-483;
   - keep both the BLIK line and the card line in `voice-agent/instructions.md`;
   - get CI green. Keep it a draft.
4. **PR #89** (payments; Cowork session `session_01F7jUa7kUbN3RRMPdCoRzW6`).
   - Its iPhone CI failed twice on `MemoryJourneyTests`, which reads a note back with a trailing space. The same test passes on #84, #88 and #90.
   - Find out whether #89 causes it, and ask its session to fix it (or fix it yourself if that session agrees to stand down).
   - Don't merge it.
   - Also check: the messaging database migration number `008` is claimed three times across branches. Propose new numbers.
5. **Motion work** (`claude/motion-mv1`, session `session_016KREaFAvF9A2hS5Pa8c72B`). That session wrote a revised MV2–MV6 prompt. Find it, tell me what it would do and whether its base is green, and don't run it.
6. **Hey Doddy on Apple speech** (dashboard session `session_018r8gGKVoMPdiACDQb5AgkW`; source branch `claude/great-shannon-i93mh3`, ADR-472).
   - Check what's already on main. A sweep found both parts may already be there.
   - Port only what's missing to a new branch from main, as a draft PR with CI green. Don't merge it.
   - Then answer the dashboard session's open question for me.
6b. **Render drift.**
   - The live `doddy` backend on Render runs the ASK-01 server, but the app on my phone is older and doesn't ask first, so cloud reads are refused until I install a new build. Fix `STATUS.md` and `DEPLOY_RENDER.md`, which say Render still runs the old server.
   - Vercel `doddy-gateway` has no environment variables at all, which doesn't match the secrets manifest. Report what it needs, names only.
7. **Same-commit Redeploy fix.** If the merge session recommended porting PR #71's `4abd32ff`, port it to `site/`, `gateway/` and `server/voice-token/vercel.json` in a small PR. Don't merge it without my yes, because each merge uses Vercel builds.
8. **Old blocked sessions from 13–16 Oct** (Atlas storage, App deployment readiness, OpenAI token access, App deployment and testing setup, Dashboard quick-win). For each, read the last message and say still due or stale, in one line each.
9. **Report.** Give a table of every item: done, waiting on a session, or waiting on me. Include links, CI runs and what was not run.

## For me (list these at the top of your report, don't do them)
- **Apple:** confirm the paid Apple Developer account, turn on Sign in with Apple for `com.bienos.doddy2.dev`, build main on my phone, and talk to Doddy.
- **Render:** move to paid plans before **10 Nov**, when the free database is deleted.
- **Twilio:** upgrade, allow Poland and submit the ID bundle (2–3 business days), then send the VA and MG service IDs to the phone session.
- **Composio:**
  - finish connecting Gmail (approve the link, paste the callback URL into the Composio session);
  - delete the old full-mailbox connection `ca_Zo3YFgH…`;
  - decide whether Gmail should have send and modify scopes.
- **Security clean-up:**
  - rotate the Anthropic key pasted in a chat on 17 Oct;
  - delete the two old Supabase edge functions (still open);
  - decide on the Render copies of the voice-token server and the gateway.
- **Calls (#90):** the legal basis for the recording notice, a Twilio subaccount limited to Poland, and a Polish calling agent.
- **Decisions:**
  - the #90 secrets split.
- **Native review** of the translations.
- **Device log** of the double voice session bug.
