# Run Doddy on your iPhone from Xcode (2026-10-12)

Owner: "I want it built in Xcode first, not the App Store … start properly testing". This is the path for
a development build straight from your Mac to your own iPhone. It is not TestFlight and not the App Store.

## What the branch holds
Branch `claude/friendly-bohr-gy15jv` = the default branch, plus:
- the iOS compile fixes from #69 and the UI test fixes from #70 (branch `claude/jolly-bell-mlwnqb-uitests`);
- the new app icon from your pack (ADR-460).

What is known about it, honestly:
- #69's head compiles on Xcode 26.6 in GitHub CI (iOS Simulator). On #70, CI run 181 had 23 of 26 UI tests
  passing, and run 182 was still going on 12 October at 22:40 UTC.
- This exact branch (with the icon) has not been built anywhere yet. Nothing has been installed on a real iPhone.
- Signing has never been done. Expect Xcode to ask for things the first time.

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
| Voice | Token server | `https://doddy-voice-token.vercel.app/api/voice-token` |
| Voice | Access code | the owner code you were given as a file (`VOICE_TOKEN_SERVER_STATUS.md`) |
| Ask Doddy (typed questions) | Gateway address | `https://doddy-gateway.vercel.app` |
| Ask Doddy (typed questions) | Invite code | the invite code you were given privately (`M2_STATUS.md`) |
| Connected Apps server (development) | Server address | `https://doddy-yaci.onrender.com` |
| Connected Apps server (development) | Session token | mint one: `docs/integrations/DEPLOY_RENDER.md`, step 4 |
| Messages from Doddy → Notifications and texts | Server (development) | `https://doddy-messaging-zw1n.onrender.com` |

The two Render servers are on the free plan: the first request after a quiet spell can take about a minute
while they wake up.

## Before you start testing
- The voice agent is public with its login off (build board P0 "Switch on login for the voice agent"). Fine
  while you're the only tester. Switch it on before anyone else gets the app.
- Known open defect: Doddy stops talking when Instagram opens (ADR-207).

## Then test
Work through `MAC_VERIFICATION_CHECKLIST_2026-10-10.md` (sections 1–17, then 4f–4n), and write each result in
its **Result log**: the Xcode version, the iPhone and iOS version, and what happened. A feature counts as
"seen working" only from that log. Move its card on the build board to Done only then.
