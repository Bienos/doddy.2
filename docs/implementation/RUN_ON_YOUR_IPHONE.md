# Run Doddy on your iPhone from Xcode (2026-10-12)

Owner: "I want it built in Xcode first, not the App Store … start properly testing". This is the path for
a development build straight from your Mac to your own iPhone. It is not TestFlight and not the App Store.

## What the branch holds
Branch `claude/friendly-bohr-gy15jv` = the default branch, plus the new app icon from your pack (ADR-460)
and this guide. Since 13 October the default branch holds the iOS compile fixes (#69) and the UI test fixes
(#70).

What is known about it, honestly:
- The default branch compiles on Xcode 26.6 in GitHub CI (iOS Simulator), and the unit tests and all 26 UI
  tests pass there (run 38325945549, #69's head before it merged).
- This branch with the icon also builds and passes every test in CI (run 38322023821, 13 October).
- Nothing has been installed on a real iPhone. Signing has never been done. Expect Xcode to ask for things the
  first time.

## You need
- A Mac with **Xcode 26** (CI uses 26.6; alarms use AlarmKit, which needs it) and Homebrew.
- Your iPhone on iOS 17 or later (alarms need iOS 26), and its cable.
- Your paid Apple Developer account, signed in under Xcode → Settings → Accounts.

## Steps
1. Get the branch:
   ```sh
   git clone https://github.com/Bienos/doddy.2 && cd doddy.2      # or: git fetch origin in your copy
   git checkout claude/friendly-bohr-gy15jv
   brew install xcodegen
   make project                    # writes Doddy.xcodeproj
   open Doddy.xcodeproj
   ```
2. **Signing.** In Xcode, click the blue Doddy project at the top left, then for each target —
   **Doddy, DoddyWidgets, DoddyShare, DoddyWatch, DoddyWatchWidgets** — open *Signing & Capabilities* and choose
   your team. Leave "Automatically manage signing" on; it registers the app IDs and the App Group
   `group.com.bienos.doddy2.dev`. `make project` rebuilds the project file, so the team has to be chosen again
   after running it.
3. **iPhone.** Plug it in and tap *Trust*. Turn on Settings → Privacy & Security → **Developer Mode** (the
   iPhone restarts).
4. Choose your iPhone at the top of the Xcode window, then **Product → Run** (⌘R). The first build takes several
   minutes.
5. **If it doesn't build:** copy the first few red errors (not the whole log) into a message to Claude.

The bundle ID stays the development placeholder `com.bienos.doddy2.dev`. That's fine for testing. When you
choose the real one (build board card "Choose the Apple developer team and the real bundle ID"), it installs as
a separate app and the notes in this one don't move across.

## Point the app at its servers
The app ships with no server addresses (build board card "Point the app at its servers"). Type them in Settings:

| Settings section | Field | Value |
| --- | --- | --- |
| Voice | Token server | `https://sliondswemhneuzehpoq.supabase.co/functions/v1/voice-token` (Supabase, since 13 Oct) |
| Voice | Access code | a code you put in that function's `DODDY_ACCESS_CODES` secret in the Supabase dashboard |
| Ask Doddy (typed questions) | Gateway address | `https://doddy-gateway.vercel.app` |
| Ask Doddy (typed questions) | Invite code | the invite code you were given privately (`M2_STATUS.md`) |
| Connected Apps server (development) | Server address | `https://doddy-yaci.onrender.com` |
| Connected Apps server (development) | Session token | mint one: `docs/integrations/DEPLOY_RENDER.md`, step 4 |
| Messages from Doddy → Notifications and texts | Server (development) | `https://doddy-messaging-zw1n.onrender.com` |

The two Render servers are on the free plan: the first request after a quiet spell can take about a minute
while they wake up.

**The Vercel account `doddyyyy` is blocked** (since 12 October; still `402 DEPLOYMENT_DISABLED` on 13 October),
so the old voice pass address `doddy-voice-token.vercel.app` and the Ask Doddy gateway don't answer.
- **Voice pass:** moved to the Supabase Edge Function in the table above (13 October). It answers only once
  its two secrets are set in the Supabase dashboard: `DODDY_ACCESS_CODES` and `OPENAI_API_KEY`. Until then it
  says `server_not_configured` (checked 18:15 UTC on 13 October). With it set, Home's voice picker can use
  OpenAI (ADR-442). Without a token server, leave the field empty: the app then uses ElevenLabs' development
  agent directly. That works for you alone; it's the open agent the P0 card is about.
- **Ask Doddy (typed questions)** won't answer until the gateway is back or moved too.
- The two Render servers (accounts and search, messages) answered normally.

## Before you start testing
- The voice agent is public with its login off (build board P0 "Switch on login for the voice agent"). Fine
  while you're the only tester. Switch it on before anyone else gets the app.
- Known open defect: Doddy stops talking when Instagram opens (ADR-207).

## Then test
Work through `MAC_VERIFICATION_CHECKLIST_2026-10-10.md` (sections 1–17, then 4f–4n), and write each result in
its **Result log**: the Xcode version, the iPhone and iOS version, and what happened. A feature counts as
"seen working" only from that log. Move its card on the build board to Done only then.
