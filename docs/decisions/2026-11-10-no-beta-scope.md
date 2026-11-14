# Every feature is shown in every build: the beta scope is dropped

- **Date:** 2026-11-10
- **Decided by:** owner, 10 Nov 2026: "wgl to zapomnij o becie jakby nie było tego" (forget the beta, as if it didn't exist)
- **Status:** accepted; applied in the pull request `claude/no-beta-scope` (not compiled, see Evidence)
- **Replaces:** `2026-11-07-release-scope` (the hidden list), `2026-11-08-translator-in-beta` and `2026-11-08-show-everything-until-beta` (their "beta" framing; the features stay shown). `docs/product/V1_SCOPE.md` no longer applies as a scope.

## Why
The release scope hid about 40 features in the shipping build so a small beta would only meet what had been checked. The owner no longer wants a beta tier. Release and TestFlight builds already returned `.everything` from `ReleaseScopeStore` since 8 Nov; what remained was `ReleaseScope.shipping` (the beta list) behind it, the Debug switch that selected it, and tests and docs that asserted it.

## Decision
- `ReleaseScope.shipping` equals `ReleaseScope.everything`: `hidden` is empty, `hiddenTools` is empty, every voice tool in `voice-agent/tools.json` is reachable, every Settings row, Home menu row, Connections switch, quick action, "What I can do" row and language is offered. `ReleaseScopeStore.current` returns `.shipping` in Release and in Debug.
- The `ReleaseScope` type and API stay (gate, capability `hiding`, connection groups, `languages`, `previewEverythingKey`), tested with scopes that do hide something, so a later decision can hide a feature again. The Debug toggle "show every feature" is removed from Settings › Advanced because it changes nothing now; the launch argument the UI tests pass still works.
- Live agent: it keeps all its tools. `docs/OWNER_QUEUE.md` row 22 (take 66 tools off the agent) is obsolete and struck through. Nothing on ElevenLabs, Render or Vercel was touched, and `tools.json` descriptions are unchanged.
- Languages: `languages` offers all nine for any scope equal to `.everything`, so the eight machine-drafted ones are offered too (they were already in Release builds since 8 Nov). Only Polish and English have been read by a native speaker (`l10n/REVIEW_NOTES.md`).

## What is shown now that the beta hid
Plan card; meaning search, Google Keep and text import, voice memos, tidy-up, Spotlight, What Doddy knows (learning), DODDY Capture recordings, shared lists, Shopping mode on the Lock Screen, place reminders; Leave by, parking (and its quick action), birthdays, evening wrap-up, weekly look-back, weekly plan, steps; Files, Doddy on the web, cloud memory, online accounts (Gmail, Outlook, Google Calendar, Drive, Notion, Todoist), web search, errands (tasks), price watch, Following, daily news, notifications and texts (`text_me`), phone calls (`call_me_later`, `call_me_now`), calls for you (`call_places`), Studio, Payments (`pay_for_page`); Apple Health, the training plan, HomeKit, BLIK transfer drafts, presentations, inFakt invoice drafts, InPost parcels, the lost-wallet checklist; all nine languages. (Already shown before this change: Messages, translator, leaflets, Claude documents, photo notes and camera.)

## Honesty rules that still hold
- Nothing claims to work when it can't. A feature whose server flag, key, account, permission or entitlement is missing keeps its own status: "needs setup", "not available", "not tried on a real call yet" (`WhatICanDo`, `StatusCopy`, the connection rows). `WhatICanDo.realCallRecorded` stays false until a real call is recorded.
- `ToolGate`, Pause all, per-connection switches, approval cards bound to the exact payload, "unknown is never success", and the constitution (`docs/trust/`) are unchanged. Nothing here edits a gate.
- The free-team build (`project-iphone.yml`, no entitlements): Apple Health already says the build can't use it (`HealthReader.isAvailable`). **HomeKit is not checked:** without the entitlement `HomeKitClient.request()` waits up to a minute for an answer that never comes and then reports not determined; it does not say "this build can't use HomeKit". Not changed here; it needs a look on a device or a decision. The widgets, "Save to Doddy" and shared lists need the App Group and are left out of that build.

## What it costs
Every server feature is now reachable by every user of every build. Code defaults live in `server/messaging/src/config.ts`; the **live** values are on Render and were not read in this change (the figures marked "reported" come from the owner's session notes, not from Render).
- **Per use, paid to a vendor:** leaflets / "Cheapest this week" (Claude vision on leaflet pages; code default 30 a day per account, 1,000 per server; reported live: `DEALS_ENABLED=1`, 10 a day per person, 100 a day per server). Files and Claude answers (`ask_claude`, `make_document`; reported 8 a day per person through the Claude units). Errands (`ERRANDS_ENABLED`, default 0; 10 a day per account, 30 per server by code). Studio (`STUDIO_ENABLED`, default 0; dollar caps `STUDIO_JOB_LIMIT_USD`, `STUDIO_DAILY_*_CAP_USD`, `STUDIO_MONTHLY_SERVER_CAP_USD`; 3 a day per account, 10 per server). Messages / the assistant (`ASSISTANT_ENABLED`, 100 a day per account, 1,000 per server by code). Price watch (`WATCHES_ENABLED`). Radar alerts (`RADAR_ALERTS_ENABLED`; reported on). Texts (30 a day per account, 300 per server) and outbound calls (20 a day per server), phone number calls and "call me": cost per text or minute on Twilio and ElevenLabs. Calls for you / `call_places` (task calls, `TASK_CALL_LIMIT_*`).
- **Off by flag, so they say "not set up":** Studio, payments (USDC), Doddy's phone number and anything else whose flag is 0 on the live server. The app shows them and the server answers that they aren't on.
- **Other:** online accounts need the owner's OAuth apps; inFakt invoices are drafts only (nothing is sent to inFakt in any build); BLIK drafts only; Apple Health and HomeKit need entitlements the free team doesn't have.
- **The live voice agent** now offers every tool again, so conversations can start these features: more tool calls, more ElevenLabs minutes on long tasks.

## What the owner must watch
1. Render flags and caps against what you want everyone to reach: `DEALS_*`, `ERRANDS_*`, `ASSISTANT_*`, `STUDIO_*`, `WATCHES_ENABLED`, `RADAR_ALERTS_ENABLED`, `SMS_*`, `OUTBOUND_*`, `TASK_CALL_LIMIT_*`. A flag turned on later is instantly reachable by everyone.
2. Vendor spend: Anthropic, ElevenLabs, Twilio, Render. Per-person caps bound one user, the per-server caps bound the day.
3. Features that have never run for real: file making by voice, calls (`WhatICanDo.realCallRecorded`), recordings, online accounts, Studio, Takeout import. They are shown with honest status but not seen on a device.
4. The messaging database plan (owner queue 1): every feature stores more in it.
5. The eight machine-drafted languages are now offered; decide whether to hide them again.
6. HomeKit on a free-team build (above).

## Evidence
- Run on Linux (Swift 6.1.2): `swift test --package-path Packages/DoddyCore ...`, `scripts/ci.sh --only swift,checks`, `python3 -I tools/build_strings_catalog.py --check`, `swiftc -parse` on the edited app files. Results are in the pull request.
- Not compiled, not run: all SwiftUI and `DoddyTests` / `DoddyUITests` changes (no Xcode here). Nothing seen on a device.
