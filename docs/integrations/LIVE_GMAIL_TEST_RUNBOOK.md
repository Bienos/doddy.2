# Live Gmail test with ASK-01 (prompt step 3): runbook for the owner

Prepared 2026-10-18. **Nothing here has been run.** Each numbered step needs you; the agent changes no Render setting,
no live agent and sends no email without your yes on the exact change.

State checked read-only on 2026-10-18: Render service `srv-db5kvu142hec739b9tu0` (https://doddy-yaci.onrender.com) is
live on `754e5d6`, deployed from `claude/loving-dirac-uuxoux`, auto-deploy off. Branch `claude/trusting-sagan-7lky84`
fast-forwards onto it.

## 1. Merge and deploy (you)
1. Merge `claude/trusting-sagan-7lky84` into `claude/loving-dirac-uuxoux` (a fast-forward; a PR is fine).
2. In Render, deploy the new head (auto-deploy is off). The free plan forgets its database when it sleeps: do steps
   2–5 in one sitting.

## 2. Composio Gmail auth config (you, in Composio)
Set auth config `ac_XUGmWDS79r-R` (or a new one) to exactly these Google scopes, plus the identity ones (`openid`,
`email`, `profile`, `userinfo.email`, `userinfo.profile`):
`gmail.readonly`, `gmail.compose`, `gmail.send`, `gmail.modify`.
`https://mail.google.com/` is refused as too broad. After you connect, Render's log has one line
`"event":"grant_checked"` listing the granted scope **names** (never tokens) and any `notAllowed`. If Composio's
managed Google app can't be narrowed, that line shows it; then it needs Doddy's own Google OAuth client.

## 3. A new session key and token (you)
1. Render → the service → Environment → `DODDY_SESSION_SIGNING_KEY` → **Generate**. (The old value appeared in an
   earlier transcript; don't reuse it.) Save, then redeploy.
2. On your Mac, with that value in your clipboard (never paste it into a chat):
   ```text
   cd backend && npm ci && npm run build && DODDY_SESSION_SIGNING_KEY=… npm run session:mint
   ```
3. Keep the printed token for the curl steps below (`export T=…`), and/or put it in the app (Settings → Connected Apps
   server). The iPhone app needs a new build from this branch for the ask cards; an older build's reads are refused by
   the new server (that's intended).

## 4. The test, with curl (you run each command; each one is a yes)
```text
B=https://doddy-yaci.onrender.com
# Connect Gmail: open the printed authorizationUrl in a browser and approve Google.
curl -s -X POST $B/v1/tools/gmail/connect -H "authorization: Bearer $T" -H 'content-type: application/json' -d '{}'
# DODDY_APP_RETURN_URL is still the temporary /v1/health page: copy attempt, status and connected_account_id from the
# address bar into:
curl -s -X POST $B/v1/tools/gmail/complete -H "authorization: Bearer $T" -H 'content-type: application/json' \
  -d '{"attemptId":"…","nonce":"…","result":{"kind":"callback","status":"success","connectedAccountId":"ca_…"}}'
# Switch on check_email and draft_email (and send_email only if you want the send test).
for t in check_email draft_email send_email; do curl -s -X PUT $B/v1/tools/switch -H "authorization: Bearer $T" \
  -H 'content-type: application/json' -d "{\"tool\":\"$t\",\"enabled\":true}"; echo; done
```
**ASK-01 check:** this must be refused (403, `ask_first_required`), and nothing read:
```text
curl -s -X POST $B/v1/tools/run -H "authorization: Bearer $T" -H 'content-type: application/json' \
  -d '{"tool":"check_email","arguments":{"max":5},"timeZone":"Europe/Warsaw"}'
```
Then ask, read the card, and say yes by sending its approvalId:
```text
curl -s -X POST $B/v1/tools/prepare -H "authorization: Bearer $T" -H 'content-type: application/json' \
  -d '{"tool":"check_email","arguments":{"max":5},"timeZone":"Europe/Warsaw"}'
curl -s -X POST $B/v1/tools/run -H "authorization: Bearer $T" -H 'content-type: application/json' \
  -d '{"tool":"check_email","arguments":{"max":5},"timeZone":"Europe/Warsaw","approvalId":"…"}' | jq '.count, [.items[].when]'
```
Report the count and dates only, not senders or subjects. A draft and one test send to your own address work the
same way (`draft_email`, then `send_email` with `{"to":"<your address>","subject":"Doddy test","body":"…"}`): read
the card's lines, and only then run with its approvalId. Check Gmail: the draft in Drafts, the test email in Sent and
Inbox.

## 5. Put things back (you)
- `DODDY_APP_RETURN_URL` back to `doddy-dev://connected-apps/return`.
- Disconnect Gmail if you don't want it connected: `POST $B/v1/tools/gmail/disconnect` with `{}`.

## 6. Live voice agent (separate yes)
The ElevenLabs agent still has the old prompt and tools. Syncing it (`voice-agent/README.md`) changes a live service:
the agent will show you the exact diff and wait for your yes.
