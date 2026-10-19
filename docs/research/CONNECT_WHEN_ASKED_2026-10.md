# Connect when asked: research (2026-10-19)

Owner question, in their words: *"Is there any chance to have a flow where we have everything connected in the backend,
but nothing is turned on until the user asks for it? So somebody asks, hey Doddy, can you send an email to XYZ to do
XYZ? And then we have to come up with the flow of the user accepting and logging into his profile."*

The build prompt that follows from this is `prompts/CONNECT_WHEN_ASKED.md`.

## Short answer

Yes. Most of it is already built. What's missing is the step in the middle: when a tool isn't on yet, Doddy sends the
user to Settings instead of offering to connect right there in the conversation.

- **Already true:** every online account (Gmail, Calendar, Drive, Notion, Todoist, Outlook) is set up on the server
  through Composio, every tool is in the catalog and on the voice agent, and for a new user **nothing is connected and
  every switch is off** (`docs/integrations/ONLINE_ACCOUNTS.md`: "Everything starts off").
- **Already true:** sending needs a tap on a card with the exact email (ASK-01, ADR-483/485), and "sent" is said only
  when Gmail returns a message id (DOD-08).
- **Missing:** the "just in time" connect. Today `send_email` with Gmail off answers *"switched off. Tell the user they
  can switch it on in Settings, Online accounts"* (`VoiceCloudTools.cloudFailed`). The user has to leave the
  conversation, find Settings, connect, switch the right tool on, come back and ask again.

## What the code does today (this branch, `fc8a502`)

| Step | Where | Today |
|---|---|---|
| Agent asks to send | `voice-agent/tools.json` `send_email` | Called with `to`, `subject`, `body` |
| App gate | `VoiceSessionController.handle` → `handleCloud` | ASK-01 `prepare` first |
| Server check order | `backend/src/tools/service.ts` `checkUsable` | 1. server set up → 2. **switch on** → 3. connected → 4. grant covers the tool |
| What a new user gets | same | `capability_disabled` ("turned off in Settings"), because the switch is checked before the connection |
| What the app says | `Packages/DoddyCore/.../OnlineAccounts/VoiceCloudTools.swift` | "Tell the user they can switch it on in Settings, Online accounts" |
| Sign-in itself | `backend` `connect` → Composio `connectedAccounts.link` → `DoddyApp/Features/ConnectedApps/SystemWebAuthenticator.swift` | System sign-in sheet (`ASWebAuthenticationSession`), ephemeral, verified completion (ADR-076, ADR-445) |
| Gmail permissions asked | ADR-485 | `gmail.readonly`, `gmail.compose`, `gmail.send`, `gmail.modify`, all at once |
| Local permissions (Calendar, Reminders…) | `connectionNeeded` + `connectionCard` in `VoiceView.swift` | Already an in-conversation card, which opens the Connections sheet |

Two small problems found while reading:
1. `checkUsable` reports "isn't set up on this server" with the code `not_connected`. A connect card must never appear
   for an account the server can't connect, so these need different codes.
2. Because the switch is checked first, the app can't tell "never connected" from "connected but this tool is off".
   The connect flow needs to know which one it is.

## Findings

### 1. Google's rules for Gmail permissions (primary sources)

- **Only `gmail.send` is "sensitive". `gmail.readonly`, `gmail.compose`, `gmail.modify`, `gmail.metadata` and
  `https://mail.google.com/` are "restricted".** (Gmail API scopes page.)
- **Restricted scopes plus a server = a yearly security assessment.** "If you store restricted scope data on servers
  (or transmit), then you must go through a security assessment" (Gmail scopes page), "an annual security assessment
  from a Google empanelled group of security assessors" (Google Cloud help, restricted scope verification). Doddy's
  server (via Composio) handles Gmail data, so the four scopes Doddy asks for today would need this before launch.
  Third-party sources put the cost at a few hundred to a few thousand dollars a year; not verified with Google.
- **So a send-only first connection needs no yearly assessment.** Sending a new email (`send_email`) needs only
  `gmail.send`. Replying, forwarding, drafting and reading need restricted scopes.
- **Unverified apps:** Google may show an "unverified app" screen before the consent screen, and an unverified app is
  limited to 100 new users. The screen goes away after verification (Google Cloud help, unverified apps). Sensitive
  scopes still need Google's verification (brand, privacy policy, scope justification) before public launch.
- **Users can untick permissions.** When an app asks for two or more non-sign-in scopes, Google shows checkboxes, and
  "the application must check what scopes are granted by the users and can't assume users grant all requested scopes."
  Google's advice: ask for "the smallest set of scopes needed", in context, when the feature is used, explaining why
  first (Google, granular permissions). Asking for only `gmail.send` means one permission and no checkboxes.
- **Incremental authorization** (`include_granted_scopes`) lets an app add scopes later to one grant
  (IETF draft and Google's guidance). Whether Composio passes this through is **not known**; see below.

### 2. Composio

- **Composio has this exact pattern built in**, called in-chat authentication: when a tool needs an account, the agent
  gets a Connect Link, the user signs in, and the tool is retried. It works through the `COMPOSIO_MANAGE_CONNECTIONS`
  meta tool. **Doddy can't use that meta tool:** the capability guard bans meta tools and generic proxies on purpose
  (ADR-096). Doddy already has its own connect route that does the same job (`/v1/tools/{toolkit}/connect`), so the
  idea carries over without the meta tool.
- **Scopes belong to an auth config, not to a link.** Doddy calls `connectedAccounts.link(userId, authConfigId,
  {callbackUrl, allowMultiple: false})`. To ask for "send only" first and more later, Doddy needs **two Gmail auth
  configs** (send-only and full) and an upgrade step that replaces one connection with the other. Existing connections
  stay tied to the auth config they were made with. Whether Composio supports two configs for one toolkit and one user
  cleanly is **not verified**.
- **Whose name is on Google's screen.** With Composio's shared app, Google says "Composio wants to access your
  account" and there is a "Secured by Composio" badge. With Doddy's own Google OAuth client in a custom auth config,
  it says Doddy. A small 302 redirect on Doddy's domain can hide `backend.composio.dev` on the way back, and
  `long_redirect_url: true` skips Composio's short link on the way out (Composio white-labeling docs). The current auth
  config is `ac_XUGmWDS79r-R` (ADR-485); whether it is Composio's app or Doddy's is not recorded.
- **Granted scopes must be readable.** The server refuses a connection whose grant it can't check (ADR-075, ADR-100).
  Whether Composio reports the granted scopes is still unverified live; the `grant_checked` log line (ADR-485) is
  there to find out. This decides whether "the user unticked Send" can be detected at all.

### 3. The sign-in sheet on iPhone

- Doddy already uses Apple's system sign-in sheet (`ASWebAuthenticationSession`), the approach Google accepts for
  native apps (RFC 8252). No password or token ever reaches the app.
- It runs **ephemeral** (`prefersEphemeralWebBrowserSession = true`): nothing is shared with Safari, so the user types
  their Google email and password every time. Non-ephemeral would reuse a Safari Google sign-in (often just "choose
  account"), but iOS then shows "Doddy wants to use … to sign in" and the sign-in cookie is shared with Safari. This is
  a product choice for the owner (decision D3 in the prompt). Not re-checked against Apple's docs in this research.

### 4. The voice conversation during sign-in

- The sign-in can take a minute or more (password, two-step code). Doddy's tools allow 60–90 s for an answer
  (`timeout_secs` in `tools.json`). **So the tool call should be answered at once ("needs connecting"), not held open
  during sign-in.**
- ElevenLabs lets the app send **contextual updates** ("useful for activity in a UI not accessible to the voice
  agent") and a `user_activity` message that resets the turn timeout, suggested every ~30 s during long silences
  (ElevenLabs client-to-server events). Whether a contextual update makes the agent speak by itself is not documented
  in what was found; it may wait for the user's next turn.
- No documented client-tool timeout was found.
- The app has no contextual-update path yet (no call in `DoddyApp/Features/Voice/`). It uses the ElevenLabs Swift SDK
  (`project.yml`) and OpenAI Realtime; both need checking.
- Doddy must never make it look as if the user spoke (no fake user message). If the app can't make the agent take a
  turn honestly, the card asks the user to say "go ahead".

## Options for Gmail permissions (owner decision D1)

| | A. Send only first (recommended) | B. Everything at first connect (today) |
|---|---|---|
| Google's screen | One permission: send email on your behalf | Read, compose, send, change; with checkboxes |
| Yearly security assessment | Not needed for this tier | Needed before public launch |
| Second sign-in later | Yes, the first time the user asks Doddy to read or reply | No |
| Matches "nothing on until asked" | Fully | Connected wider than asked; only the switches hold it back |
| Work | Two Composio auth configs + an upgrade step | Least |

## To verify live (needs the owner's test account)

1. `GMAIL_SEND_EMAIL` works with **only** `gmail.send` granted (Composio's action may call other Gmail endpoints).
2. Composio reports the granted scopes on the connected account (`grant_checked` log line).
3. Two Gmail auth configs for one user, and replacing a send-only connection with a full one.
4. A contextual update (ElevenLabs) or system item (OpenAI Realtime) reaches the agent mid-conversation, and whether it
   starts a reply.
5. The voice session survives a 2–3 minute sign-in with the microphone muted.

## Sources

- Google, Gmail API scopes: https://developers.google.com/workspace/gmail/api/auth/scopes
- Google, granular OAuth permissions: https://developers.google.com/identity/protocols/oauth2/resources/granular-permissions
- Google Cloud help, restricted scope verification: https://support.google.com/cloud/answer/13464321
- Google Cloud help, unverified apps: https://support.google.com/cloud/answer/7454865
- IETF draft, OAuth incremental authorization: https://datatracker.ietf.org/doc/html/draft-ietf-oauth-incremental-authz-03
- Composio, in-chat authentication: https://docs.composio.dev/tool-router/using-in-chat-authentication
- Composio, custom auth configs: https://docs.composio.dev/docs/auth-configuration/custom-auth-configs
- Composio, white-labeling: https://docs.composio.dev/docs/auth-configuration/white-labeling
- ElevenLabs, client-to-server events: https://elevenlabs.io/docs/eleven-agents/customization/events/client-to-server-events
- Third-party, Gmail scope and CASA summaries (cost figures only, not authoritative):
  https://developer.nylas.com/docs/cookbook/use-cases/build/google-oauth-scopes.md,
  https://www.unipile.com/integrating-google-oauth-2-0-user-authentication-into-your-app/,
  https://deepstrike.io/blog/google-casa-security-assessment-2025
