# Pictures of every screen (ADR-695)

Owner, 2 Nov 2026, after a capability map drawn as HTML mockups from the code: "Make sure these mock ups are real", then "Do" to a UI test that photographs every screen in the hosted Mac build.

**Status:** written on Linux (no Xcode here). PR #168's full run (41475443201) compiled it and passed, with these tests skipping. The first `only: screens` run (41475441329, 2 Nov) kept 89 screens and missed 3; Settings and Connections ran past the 10-minute limit per test, so each was split in two, and three routes were fixed (Lists, a leftover draft, iOS's notification question over Focus). Nothing here was seen on a device.

## How to run it

- **On GitHub:** Actions › iOS build and tests › Run workflow › branch › `only: screens`. About 40 to 60 minutes. The pictures are in the run's `screen-atlas` artifact (kept 30 days): `build/screen-atlas/*.png`, `index.tsv`, and a second copy exported from the `.xcresult` in `screen-atlas-attachments/`.
- **Only the sample-state pictures (ADR-696):** `only: fixtures` runs `ScreenFixtureTests` alone (about 30 minutes), for when only the fixtures changed. The script reads `SCREENS_ONLY=fixtures`.
- **On a Mac:** `scripts/ci_screens.sh`, then open `build/screen-atlas/`.
- **Anywhere else:** every `ScreenAtlasTests` test skips unless the test runner sees `DODDY_SCREEN_ATLAS=1`, so the full run (`scripts/ci.sh`) gets no slower.

## What it does, and what it doesn't

- Each visit starts the app fresh (an in-memory store, or one test store for the memory group so its notes and list survive the relaunches), walks to one screen by accessibility identifiers, waits 1.2 s and keeps a picture of the whole simulator screen: status bar and island included.
- A screen it can't reach is kept as `missed-<name>.png` with whatever was on screen and listed as `missed` in `index.tsv`. It never fails the run: the job's own result is xcodebuild's.
- It **checks nothing** about how a screen behaves. The behaviour tests are the rest of `DoddyUITests`.
- **Offline like every UI test:** no voice agent (`-voiceAgentID ""`), no server, no account. So the conversation shows the sign-in gate, and Cheapest this week, Tasks, Files, online accounts, calls, news and texts show what this build says without a server. Pictures of them working need a build with a server and an account; that is not this run.
- The iPhone simulator is the first available one (as in `ci.sh`). iPad, the Watch and the Mac aren't pictured.

## The screens

Names are `<group>-<area>-<number>-<what>.png`, so they sort in the order below.

| Group | Test | Screens |
|---|---|---|
| 1 First run | `test1FirstRun` | the five welcome chapters, the sign-in sheet and its "not connected" line, Before we start, the introduction's two questions and its review, What I can do |
| 2 Home | `test2Home` | Home on a first visit and after it, the ••• menu and its Focus and stopwatch submenu, the conversation without a voice account, Messages, Files, Today, Tasks, Cheapest this week, Translate, Focus (start and running), Stopwatch (running), What leaves this iPhone, the voice picker, Recordings and its "Before you record" notice |
| 3 Memory | `test3Memory` | the empty notes list, a new note, two save receipts, the notes list with three notes, Find with a match and with none, a note, Correct this detail, the reminder sheet, the empty lists, a new list, a list with four items, What Doddy did |
| 4 Settings | `test4aSettings`, `test4bSettings` | Settings, Voice, Voice and personality, the voice list, Siri and Back Tap, Ways to open Doddy and the Back Tap steps, Doddy's memory, My profile, What Doddy knows, What I've learned, Remembered conversations, Export backup and delete, the backup and import sheets, Language, Appearance, Privacy, What leaves this iPhone, Advanced, Try a plan card |
| 5 Connections and notifications | `test5aConnections`, `test5bNotifications` | Connections (and paused), Calendar reminders contacts, Online accounts, Parcels, Invoices, Doddy on the web, Ask Doddy, Apple Health, Training plan and its safety questions, Training log; Notifications, Notifications and texts, Check-ins and reminders, Alarms, Birthdays, Daily news, Phone calls, and the morning check-in, evening wrap-up, weekly plan, weekly look-back and tidy-up screens |
| 6 Looks | `test6Looks` | Home and Settings in dark, in Polish, and Home at the largest text size |

Example text typed by the test (the notes, the list) is made up. Starting Focus can bring iOS's notification question on screen; the picture keeps whatever iOS shows.

## Files

- `DoddyUITests/ScreenAtlasTests.swift`: the visits.
- `scripts/ci_screens.sh`: the run.
- `.github/workflows/ios.yml`: the `screens` choice and job.

## Sample states (ADR-696)

`ScreenAtlasTests` photographs what the offline simulator reaches. `ScreenFixtureTests` photographs the rest, from a Debug build launched with `-screenFixture <name>` (`DoddyApp/Features/Voice/ScreenFixtures.swift`, all `#if DEBUG`, one call in `DoddyApp.init`):

| Fixture | What it puts on screen | Test | Data |
|---|---|---|---|
| `card:<id>` | the conversation (transcript sheet) with one card waiting: memory, event, reminder, timer, alarm, message, BLIK, email, presentation, plan, ingredients, parking, changeEvent, deleteEvent, map, shortcut, camera, createList, askYes, askTap | `test7aCards`, `test7bCards` | sample arguments through DoddyCore's real tool parser, shown by the controller's `showCardForTesting`; a stand-in link drops every reply |
| `deals` | Cheapest this week with an answer, its lower parts and the basket | `test7cShopping` | `schemas/fixtures/deals_search_v1.json` (made-up shops and prices, dates of 24 Oct) |
| `dealsHome` | Home's "Leaflet offers" card | `test7cShopping` | the same |
| `errand` | Home's "Done" card, Tasks, a task's three picks | `test7cShopping` | `errand_result_shopping_v1.json` (Polish sample task) |
| `report` | the two pages of the shopping report PDF, full screen | `test7cShopping` | the same result, written by the app's own `ShoppingReport` |
| `island:<state>` | the real voice Live Activity in one real state (connecting, listening, thinking, speaking, muted, confirm, text, transfer, document, translator): iOS draws the compact island on the Home Screen, the expanded island (a long press) and the Lock Screen card; three whole-screen pictures each | `test8aNativeIsland`, `test8bNativeIsland` | none: the activity has no conversation behind it |

**What the runs showed (2 Nov, hosted Mac, nothing seen on a device):**

- The screens run on commit 26254d62 (41524238017) kept all 94 walk screens and the shopping, Tasks, picks and report pictures. All 20 cards stopped at the voice consent screen and the Deals visit showed only the form; the cards now launch with `-voice.providerConsent.elevenlabs.v1 YES` (a launch argument, held in memory, never saved) and the Deals visit scrolls to the answer.
- The `only: fixtures` run on 22d8d860 (41539601647) reached all 20 cards, the Deals answer (three pictures), the basket and all ten island states. The first island pictures (41527612593) were blank: the activity is now requested directly, iOS's answer is written on the app's screen and kept in `index.tsv`'s third column, and the test waits 30 s (first state) or 12 s for the widget's card. The Lock Screen pictures carry iOS's own first-use question, "Allow Live Activities from Doddy?"; nobody answers it in the run.
- The basket picture was marked missed only because the test waited for a button in a lower section; it now waits for the Basket screen.
- The sample sentences around the cards no longer name weekdays, because the dates in a card count from the day of the run.

Not covered yet: the translator screens, the learning cards, receipts, the leave-by card (needs a Maps lookup), a note reminder card, the Home Screen, Lock Screen and StandBy widgets, and the focus, stopwatch, shopping, call and recording Live Activities (the widget extension's own views; the voice activity above is the only one with a fixture).

`scripts/gen_screen_fixture_data.py` rebuilds `ScreenFixtureData.swift` from the contract fixtures; `ci.sh` checks it with `--check`.
