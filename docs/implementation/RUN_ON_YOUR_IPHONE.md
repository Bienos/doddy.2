# Run Doddy on your iPhone from Xcode (2026-10-12)

Owner: "I want it built in Xcode first, not the App Store … start properly testing". This is the path for
a development build straight from your Mac to your own iPhone. It is not TestFlight and not the App Store.

## What the branch holds
Branch `claude/zealous-albattani-7ay32v` (13 October, evening) = the default branch at `e2734941` (everything
merged up to #79: the first-use screens, action status and recovery, the Watch, iPad and Mac work, the audit
fixes), plus four merges that were still on their own branches:
- the app icon from your pack (ADR-460) and this guide (from `claude/friendly-bohr-gy15jv`);
- the island's pre-cut round faces for its compact and minimal views;
- the "Big brain. Small body." share card in Settings (PR #78, ADR-462 here);
- the voice screen that leads with Doddy and a sound wave, the transcript one tap away (ADR-463, ADR-464 here).

What is known about it, honestly:
- The default branch at `e2734941` compiles on Xcode 26.6 in GitHub CI (iOS Simulator), and the unit tests and
  the UI tests pass there (run 38426020997, PR #79's head, which has the same tree).
- `claude/friendly-bohr-gy15jv` (the icon on top of the default branch) also built and passed every test in CI
  (run 38322023821 on 13 October).
- This branch: every Linux check passes (`scripts/ci.sh --core-only` with Swift 6.1), and its hosted CI run
  38457949789 passed on 13 October at 20:45 UTC (Xcode 26.6: every target compiles; unit tests and 29 UI tests
  pass on the simulator, 1 skipped). That run was the first compile of the wave and the faces.
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
   git checkout claude/zealous-albattani-7ay32v
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
| Voice | Token server | `https://doddy-voice-token.onrender.com/api/voice-token` (Render, since 13 Oct) |
| Voice | Access code | one of the codes in that service's `DODDY_ACCESS_CODES` (Render dashboard → doddy-voice-token → Environment) |
| Ask Doddy (typed questions) | Gateway address | `https://doddy-gateway.onrender.com` (Render, since 13 Oct) |
| Ask Doddy (typed questions) | Invite code | one of the codes in that service's `GATEWAY_INVITE_CODES` (Render dashboard → doddy-gateway → Environment) |
| Connected Apps server (development) | Server address | `https://doddy-yaci.onrender.com` |
| Connected Apps server (development) | Session token | mint one: `docs/integrations/DEPLOY_RENDER.md`, step 4 |
| Messages from Doddy → Notifications and texts | Server (development) | `https://doddy-messaging-zw1n.onrender.com` |

The two Render servers are on the free plan: the first request after a quiet spell can take about a minute
while they wake up.

**Vercel is no longer used for these.** The Vercel account `doddyyyy` is blocked (since 12 October), so the voice
pass server and the Ask Doddy gateway now run on Render, next to the other two servers (owner, 13 October: "go
with render"). Checked at 18:45 UTC on 13 October: both answer, and the voice pass server is configured (a wrong
code gets `401 invalid_access_code`).
- All four Render servers are on the **free plan**: after about 15 idle minutes one sleeps, and the first request
  can take 30 to 60 seconds. The app waits only 15 seconds for a voice pass, so the first voice start after a quiet
  spell can fail; try again a minute later. The Starter plan keeps a service awake.
- Without a token server, leave the field empty: the app then uses ElevenLabs' development agent directly. That
  works for you alone; it's the open agent the P0 card is about.

## Before you start testing
- The voice agent is public with its login off (build board P0 "Switch on login for the voice agent"). Fine
  while you're the only tester. Switch it on before anyone else gets the app.
- Known open defect: Doddy stops talking when Instagram opens (ADR-207).

## Then test
Work through `MAC_VERIFICATION_CHECKLIST_2026-10-10.md` (sections 1–17, then 4f–4n), and write each result in
its **Result log**: the Xcode version, the iPhone and iOS version, and what happened. A feature counts as
"seen working" only from that log. Move its card on the build board to Done only then.
