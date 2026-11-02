# Pictures of every screen (ADR-693)

Owner, 2 Nov 2026, after a capability map drawn as HTML mockups from the code: "Make sure these mock ups are real", then "Do" to a UI test that photographs every screen in the hosted Mac build.

**Status: written on Linux; NOT COMPILED, NOT RUN here (no Xcode).** The pull request's full run is the first compile (the tests skip there). The first `only: screens` run is the first time a picture is taken.

## How to run it

- **On GitHub:** Actions › iOS build and tests › Run workflow › branch › `only: screens`. About 40 to 60 minutes. The pictures are in the run's `screen-atlas` artifact (kept 30 days): `build/screen-atlas/*.png`, `index.tsv`, and a second copy exported from the `.xcresult` in `screen-atlas-attachments/`.
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
| 4 Settings | `test4Settings` | Settings, Voice, Voice and personality, the voice list, Siri and Back Tap, Ways to open Doddy and the Back Tap steps, Doddy's memory, My profile, What Doddy knows, What I've learned, Remembered conversations, Export backup and delete, the backup and import sheets, Language, Appearance, Privacy, What leaves this iPhone, Advanced, Try a plan card |
| 5 Connections and notifications | `test5ConnectionsAndNotifications` | Connections (and paused), Calendar reminders contacts, Online accounts, Parcels, Invoices, Doddy on the web, Ask Doddy, Apple Health, Training plan and its safety questions, Training log; Notifications, Notifications and texts, Check-ins and reminders, Alarms, Birthdays, Daily news, Phone calls, and the morning check-in, evening wrap-up, weekly plan, weekly look-back and tidy-up screens |
| 6 Looks | `test6Looks` | Home and Settings in dark, in Polish, and Home at the largest text size |

Example text typed by the test (the notes, the list) is made up. Starting Focus can bring iOS's notification question on screen; the picture keeps whatever iOS shows.

## Files

- `DoddyUITests/ScreenAtlasTests.swift`: the visits.
- `scripts/ci_screens.sh`: the run.
- `.github/workflows/ios.yml`: the `screens` choice and job.
