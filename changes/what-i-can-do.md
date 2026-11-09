What I can do (Home › ••• › What I can do) was rebuilt (decision `2026-11-09-what-i-can-do`, words in `docs/design/WHAT_I_CAN_DO_COPY.md`).

- **Rows.** It lists features in plain words, with what Doddy does, what stays with the person, and a status worked out from the build: Ready, In testing, Needs setup, Not tried on a real call yet, or Not in this version. Calls never claim to work.
- **Opening a feature:**
  - Phone calls and Calls for you open inside the sheet.
  - Notes, lists, Messages, Tasks and leaflets open from Home.
  - What leaves this iPhone is a link at the bottom.
- **Polish.** The opening paragraph and the rows are in Polish on a Polish phone, and the paragraph now names Settings › Privacy.
- **Code.** The rules are `WhatICanDo` and `CapabilityIntroduction` in DoddyCore, tested on Linux (`WhatICanDoTests`, `CapabilityIntroductionTests`).
- **UI test.** `LaunchSmokeTests.testWhatICanDoOpensPhoneCalls` (new).
