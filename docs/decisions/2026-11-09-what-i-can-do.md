# "What I can do" lists features in plain words, with an honest status each, and opens them

- **Date:** 2026-11-09
- **Decided by:** owner. Asked in the session of #270 for What I can do to stay on Home's menu and to describe features "carefully", following the brand guidelines. The owner approves the words before merge.
- **Status:** proposed, owner approval of the copy pending
- **Replaces:** the "What's built" list of engineering capability names (ADR-195, ADR-548's catalog list)

## Why
The screen listed the internal `Capability` enum. The names were engineering names ("Typed AI questions", "Updates as notifications"), the status words were technical ("Needs setup · check Settings → Phone calls"), and nothing on it could be tapped. Its opening paragraph showed in English for every language, and it pointed to "Settings › What leaves this iPhone", a path that doesn't exist.

## Decision
- **Rows.** The screen lists features as a person would name them: talk, notes, lists, reminders and calendar, Messages, Phone calls, Calls for you, Tasks, Cheapest this week, Translate. Each row has three lines:
  - what Doddy does;
  - what stays with the person;
  - a status in words.
- **The rules live in DoddyCore** (`WhatICanDo`), tested on Linux.
- **Statuses come from the build:**
  - The release scope hides a feature's row entirely.
  - Code missing from the catalog shows "Not in this version".
  - A feature that needs the messaging server, in a build without its address, shows "Needs setup".
  - Phone calls and Calls for you show "Not tried on a real call yet" until `WhatICanDo.realCallRecorded` is set together with a recorded real call.
  - Notes are "Ready". Everything else is "In testing".
- **Tapping a row:**
  - Phone calls and Calls for you open inside the sheet.
  - Notes, lists, Messages, Tasks and leaflets open from Home once the sheet closes.
  - Talk, reminders and Translate open nothing.
  - What leaves this iPhone is a link at the bottom, since it is no longer on Home's menu.
- **Language.** The opening paragraph and the rows follow the phone's language (English or Polish), and the paragraph names Settings › Privacy.
- **The words:** `docs/design/WHAT_I_CAN_DO_COPY.md`.

## Consequences
- **The screen's claims.** It no longer claims "Available" for anything that hasn't been shown on a phone.
- **When something changes.** A feature that goes live, or a first real call, means changing the status rule and its test. A new feature needs a row, words in both languages and a test.
- **Website words.** The website's moments (`design/website-what-can-doddy-do/COPY.md`) are Doddy's voice, scripted demonstrations. These rows are product voice, so they share facts with the site (for example "Sending stays your job", "Nothing is added unless you tap Add") but not lines.

## Evidence
See the pull request: DoddyCore tests on Linux (Swift 6.1.3), the strings check, and the hosted Mac job for the app and the UI tests.
