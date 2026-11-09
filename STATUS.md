# Doddy: current status (read this first)

Doddy is a voice-first companion for iPhone and iPad. The Apple Watch app and the Mac menu bar prototype are **paused** (ADR-572). This page says what is true now, in one page. **Replace facts when they change; don't add dated log paragraphs.** What a pull request changed goes in `changes/` (see `changes/README.md`); the full log up to 7 Nov 2026 is in `docs/archive/STATUS-log-2026-10-08-to-2026-11-07.md`.

Last checked: **9 Nov 2026** against `main` at `d1eec13` (#284). The code facts below were read from the repository and from the change notes of every pull request merged since 7 Nov (folded in and deleted on 9 Nov). **Live services were not re-read on 9 Nov** except where a row says so: their rows come from `docs/OWNER_QUEUE.md` and the notes, and may be older than this date.

## Code
- **Default branch:** `main`. It is the only permanent branch; every change arrives by pull request. Agents squash-merge their own pull requests once `core`, `ios-build` and `sensitive-paths` are green (`AGENTS.md`, "Merging").
- **CI:** `.github/workflows/ios.yml`. Pushes to `main` run every job (ADR-765, ADR-811); pull requests run path-selected jobs and the UI smoke classes. The Mac job (`ios-build`) may run 100 minutes and caches the app's Swift packages; `Config/Package.resolved` pins the seven remote packages; package resolution is retried when GitHub's downloads answer 504 (this blocked every Mac build on 8 to 9 Nov).
- **Open pull requests:** [GitHub list](https://github.com/Bienos/doddy.2/pulls). #172 (the Mac UI tests split over four jobs) has been held since 7 Nov because it conflicts with the CI design of #209 and #211. Merged but **off until the owner turns them on:** #196 (Doddy's own phone number), #193 (Studio research jobs), #192 (USDC pay-for-pages, test network only).
- **Decisions:** ADR-001 to ADR-828 in `DECISIONS.md` (look them up by number, never read the file whole); new ones are files in `docs/decisions/` (26 so far).
- **Migrations are frozen by tests.** Phone: `DoddyDatabaseFrozenMigrationsTests`. Messaging server: `test/migrationsFrozen.test.ts`; its files run 001 to 024 (017 exists twice, both merged; the next new one is 025).

## What changed in the product since 7 Nov (from `main`, not on a device)
- **Doddy account required** (decision `2026-11-08-required-account`). The welcome signs in with **Apple or Google** and has no way past it; email codes are hidden for now (`2026-11-09-email-sign-in-off-for-now`). `Config/Doddy-Info.plist` names the Supabase project, so accounts are **on** in every build. Servers: backend `link-device` and token check, messaging `POST /v1/accounts/sign-in`, voice token server accepts the account's token. Voice prefers the account's token. Deleting an Apple account also asks Apple to revoke (code ready; needs the Apple key, owner queue 24). Doddy Web: Apple or Google opens the same account as the iPhone.
- **Every build shows every feature until the beta** (`2026-11-08-show-everything-until-beta`; Debug: `2026-11-08-debug-shows-every-feature`). `ReleaseScope.shipping` (the beta list: 66 of 109 voice tools hidden) is kept for later, with the translator inside it. Messages (Ask Doddy) is on by default. Voice-data consent moved into first-run setup.
- **Redesign on one direction** (Brand V2.2; `2026-11-09-remove-old-design-leftovers`): new colours, Home, memory journey and Settings; the basketball opening, breathing/"Hey Doddy" islands and old art are gone; the site has no film or games. The **small island**: Action Button, Back Tap and Siri start the conversation on Home under the island, seven call-style bars (`2026-11-09-small-island-call-bars`). "What I can do" and Phone calls are on Home's ••• menu.
- **Calls and texts:** restaurant calls (one tap, up to three places, `call_places`), call-backs to Doddy's number reach the user, `call_me_later`, `text_me` goes at once to your own number (`2026-11-09-restaurant-calls-one-tap`, `2026-11-09-call-backs-and-contact-calls`). **No real call or text has been seen end to end.**
- **Files by voice:** files Doddy makes show in Messages (cards while they are being made) and one push when ready (`docs/implementation/FILE_READY_PUSH.md`).
- **Logbook and admin:** the iPhone counts usage (never words) and sends a daily summary, on by default; the owner sees every account in `/admin` once switched on (`2026-11-09-usage-counts-on-by-default`).
- **Conversation recaps:** only step 1 of 5 (the rules in DoddyCore); no screen yet (`2026-11-09-conversation-recaps`).
- **Other:** BLIK transfer drafts are back (ADR-810 superseded); every build says its commit in Settings › About; Polish covers 3,215 of 3,241 UI strings (format strings included).

## On a phone
- **Last build recorded as working on a device:** `ce02763` (PR #60, 11 Oct). TestFlight builds have since been installed (build 20 on 9 Nov showed the sign-in bug fixed by #260), but no merged change since 20 Oct has a recorded device check. To try the current code, build `main` (`make project`, scheme `Doddy`) and record the commit here.
- **TestFlight:** Xcode Cloud is the one path (ADR-697), into the App Store Connect record for `com.bienos.doddy2.dev`, which is **Doddy Beta** (ADR-812). Builds 25 and 26 stopped before building because GitHub answered 504 for LiveKit's binary packages; `ci_post_clone.sh` now retries up to six times (#267). Not yet seen to pass after that change. Build 8's export failed until every bundle ID was registered (done 8 Nov).

## Live services
| Service | Runs | Notes |
|---|---|---|
| `doddy` (Render, https://doddy-yaci.onrender.com): phone backend and Doddy Web | `8658d38` (9 Nov, owner queue 29) | Branch `main`, auto-deploy off. **Behind `main`:** only the note-source fix (#291) changed `backend/` and `web/` after it (git, 9 Nov). The admin dashboard (#266), web same-account sign-in (#280) and the account link are already in `8658d38`; the admin page still needs `DODDY_OWNER_ACCOUNTS` (owner queue 27) and Apple on the web needs owner queue 28. Free plan: sleeps after about 15 minutes. |
| `doddy`'s database (Supabase) | Free plan | Pauses after 7 days without use. Also the Doddy accounts project `doddy-gateway` (Pro plan wanted, owner queue 23). Its database password is to be rotated (owner queue 6). |
| `doddy-messaging` (Render): Messages, errands, leaflets, texts and calls, push | `8658d38` (9 Nov, owner queue 29) | Branch `main`, auto-deploy off. **Behind `main`:** call-backs (#285, migration 024), the note-source fix (#291) and the Twilio refusal log (#293). Migrations 021 to 023 are in `8658d38`. The Twilio number's "A call comes in" must point at the server before call-backs work (owner step, `2026-11-09-call-backs-and-contact-calls`). Free plan, with the worker inside the web process. |
| `doddy-messaging-db` (Render Postgres) | Free plan | **Expires 10 Nov 2026, 10:11 UTC** (read 7 Nov). Not upgraded as far as this page knows. Everything the messaging server keeps is in it (owner queue 1). |
| Vercel `doddy-voice-token`, `doddy` (www.doddy.lol), `doddy-gateway` | Production builds of `main` | #278 makes Vercel build when its last deployment is older than its shallow clone (the site's changes from #271 had not been built). **Vercel is not blocked** (`AGENTS.md`): the red statuses on pull requests come from an old Vercel account (owner queue 14) and a workflow marks them Skipped. The gateway is unused by the app (ADR-587). |
| ElevenLabs agent (main) | One agent for Debug, TestFlight and future App Store builds | **Working** (nine conversations connected on 9 Nov; read from its log). Authentication **on**, 1,000 a day (owner queue 4). Live on it: `draft_invoice`, `lost_wallet`, `call_me_later` and the `make_document` sentences (all on 9 Nov). **Not on it:** `make_something`, `text_me`, `pay_for_page`, `call_places`; the agent is changed only on the owner's instruction. |
| Old Render copies `doddy-gateway`, `doddy-voice-token` | Old branch, free plan | Not used. Delete them. |

## Platforms
| Platform | Code | Project | State | Page |
|---|---|---|---|---|
| iPhone and iPad | `DoddyApp/`, `Shared/`, `DoddyWidgets/`, `DoddyShare/`, `DoddyNotificationContent/` | `project.yml`; `project-iphone.yml` (free team, no entitlements) | Built and tested by the hosted Mac job on every push to `main` (all UI tests) and on pull requests that can reach the app (smoke UI tests) | `docs/platforms/iphone.md` |
| Web | `web/`, `backend/src/web/` | Vite, served by `doddy` | Live (behind `main`, see above) | `docs/platforms/web.md` |
| Shared core | `Packages/DoddyCore/` | Swift package | Tests on Linux and macOS in CI | `docs/platforms/README.md` |
| Apple Watch | `DoddyWatch/`, `DoddyWatchWidgets/` | `project-watch.yml` | **Paused** (ADR-572) | `docs/platforms/watch.md` |
| Mac | `DoddyMac/`, `DoddyMacWidgets/` | `project-mac.yml` | **Paused**, never compiled | `docs/platforms/mac.md` |

## Known problems
- **The messaging database is deleted on 10 Nov at 10:11 UTC unless it is upgraded** (owner queue 1).
- **Google sign-in fails** with `redirect_uri_mismatch` until Supabase's callback is registered on the Google OAuth client (owner queue 25). Apple is the only way in; Apple on the website needs owner queue 28.
- **No dollar spend limits** on Anthropic, OpenAI or Monid (owner queue 2, 13).
- **No staging environment:** Debug, TestFlight and production builds all use the production servers and voice agent. The plan is Doddy Beta on staging (ADR-812).
- **The privacy policy is out of date:** it says the app has no analytics, and does not mention Logbook, Messages on by default, or Apple's sealed refresh token (owner queue 7, 24, 26).
- **The hosted Mac's simulator sometimes freezes** during the native island UI test. That test runs alone and last, under a watchdog (ADR-764). One motion check failed once on a hitch and was loosened (#240).
- **Silent voice sessions** were seen in October (`docs/implementation/VOICE_SESSION_STARTS.md`). Confirming the cause still needs a device log.
- **Notes stay on the iPhone after a sign-out**, so the next person to sign in there sees them (owner decision).
- **Engineering audit, 7 Nov 2026:** most items are done; the plan and checklist are in `docs/engineering/AUDIT_2026-11-07.md`.
- **Not run in this review (9 Nov):** Swift tests and the app build (no Swift or Xcode in the session), the messaging database tests unless noted in the pull request, and anything on a device.

## Waiting on the owner
`docs/OWNER_QUEUE.md`: one list, soonest deadline first.

## How to update this page
Change the facts above, keeping them to what's true now, with the date at the top. Fold the notes in `changes/` into it and delete them in the same pull request. Never paste a log entry here.
