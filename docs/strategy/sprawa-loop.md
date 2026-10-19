# The sprawa loop: the first session

**Status:** the flow is the owner's (19 Oct 2026, ADR-540). **It isn't built as one loop, and none of it has run on a device.** This page says what the first session should do, which parts already exist in the code (checked 19 Oct on main at `01e7b345`), what's missing, and how each step fails and recovers. It's the north star for the beta (M5). The strategy around it is in `STRATEGY.md`; the metrics are in `docs/product/VALIDATION.md`.

**The loop:** hand it over → Doddy keeps your words → one question → it comes back at that moment with the next step ready → you tap → done, with undo.

Polish lines on this page are the owner's where marked **[OWNER]**. The rest are drafts for the native review in Phase 5.

---

## The first session, step by step

### 1. One question, nothing else
On first launch Doddy asks one question **[OWNER]**:

> **Co ci wisi nad głową?**

- **No tour.** No feature list, no "here's what I can do".
- **Two ways to answer.**
  - A **text field**, ready to type. Typing needs no sign-in, no network and no permission.
  - A **microphone button**. The microphone permission is asked **only now, when the user taps it** **[OWNER]**, never at install.
- **One line under the question says Doddy is an AI,** with a link to the privacy policy. EU AI Act Art. 50 transparency duties apply from 2 Aug 2026. The wording comes in Phase 3.
- **If the user dismisses it,** Home shows the same question and text field until a first sprawa is saved.

### 2. The user hands over a sprawa
Example **[OWNER]**:

> "Muszę oddać buty na Zalando do piątku."

### 3. Doddy repeats the exact words and asks one thing
Doddy repeats what the user said, word for word, then asks one question, about **when** **[OWNER]**:

> "Muszę oddać buty na Zalando do piątku." **Mam ci przypomnieć w czwartek wieczorem?**

- **Online (sharp):** the agent reads the deadline in the user's words and proposes a moment. The rule [ASSUMPTION: generalised from the owner's example]: with a deadline, the evening before at 19:00; with no deadline, it asks when. It says the proposed time out loud and checks it against the user's own words (`said_time`, below).
- **Offline or typed without AI (clumsy, still honest):** no guessing. Doddy asks "Kiedy ci przypomnieć?" with a few buttons: *Dziś wieczorem* · *Jutro rano* · *Wybierz dzień i godzinę*.
- **At most this one question.** Never ask something Doddy already has (the words, the deadline the user just gave).

### 4. Tap yes → the sprawa card
The user taps **Tak**. Under ASK-01 that's a change, so it takes a tap on the card, not a spoken yes. The card shows exactly what will be kept:
- **the user's words, in quotes, unchanged;**
- **when Doddy will bring it back:** "czwartek, 19:00";
- **the next step,** if there is one, labelled as Doddy's suggestion and never mixed with the user's words. For example: "Wydrukuj etykietę zwrotu i zanieś paczkę do paczkomatu.";
- **the state:** open;
- **Zmień czas** and **Usuń**.

**Notifications are asked for here, the first time,** because this is the moment the user wants the bring-back. If they refuse, the card says so plainly:

> "Powiadomienia są wyłączone, więc Doddy nie przypomni o tej sprawie. Czeka na ekranie głównym."

### 5. The bring-back
At the agreed time a local notification arrives. It carries the **next step** and a **"Gotowe?"** button **[OWNER]**.
- **Tapping the notification** opens the sprawa card with the next step and a large **Gotowe?**.
- **Long-pressing it** shows the actions: **Gotowe?** · *Za godzinę* · *Jutro rano* · *Otwórz*.
- **iOS detail:** notification actions only appear on a long press or swipe, not on the banner itself. Tapping the banner, which opens the card, is the path most people will take.

### 6. Tap → logged done, with undo
Tapping **Gotowe?** marks the sprawa done and logs it in **What Doddy did**, for example "Zamknięte: oddać buty na Zalando", with **Undo** for 24 hours **[OWNER: logged done, with undo]**.
- **Undo** reopens the sprawa. If its time has passed, Doddy asks for a new one.
- **"Done" here means the user's own tap.** When a later skill does the step itself (sends a message, books a time), "done" waits for the provider's confirmation (ASK-01, DOD-08).

---

## What exists and what's missing

Checked in the code on 19 Oct. Nothing in this table has been seen on a device.

| Step | Exists today | Missing for the loop |
|---|---|---|
| **1. One question** | First launch shows an optional intro once per install (`OpeningPreferences.firstLaunchIntroSeen`, `DoddyApp/App/RootView.swift`), then Home: a dashboard with Save, Find, tools and cards, a "get to know each other" card (`IntroductionView`), and the hint "Try saying: Remember the gate code is 4821" (`HomeView.swift:150`). The microphone is asked when a conversation starts (`VoiceSessionController.microphoneAllowed`, `AVAudioApplication.requestRecordPermission`), after Sign in with Apple (`VoiceAccessGate.swift`) and the voice-provider consent. Typing a note: `CaptureView`. The spoken greeting is sent by the app as `opening_line` ("Hej, tu Doddy. Co słychać?", `WakeGreeting.openingLine` in `DoddyCore/WakeWord.swift`, ADR-254). | A first screen with the question and a text field. The voice path puts three steps before the first word: sign-in, consent and the mic prompt (see "Changes", item 1). |
| **First-conversation tour** | `voice-agent/instructions.md`, "First conversation": a two-to-three-sentence tour, then "one thing to try". The flag comes from `DoddyCore/FirstConversation.swift`; the app sends it when a conversation starts. | The owner doesn't want a tour. The tour becomes the one question, or goes. |
| **2–3. Exact words, repeat, one question** | `MemoryRecord.rawText` is kept unchanged after edits (`DoddyCore/MemoryTypes.swift`). A voice save goes through `save_memory` and a card (`VoiceSessionController`, `.saveMemory`), stored as `.explicitVoice`. `said_time` checks the agent's date against the user's own words for it, and asks if they don't match (`DoddyCore/SaidTime.swift`). | **The words aren't the user's.** By voice, `rawText` is whatever text the agent passes, and the prompt tells it to rewrite numbers as digits. Nothing keeps the transcript of what the user said. No rule says "repeat their words". Doddy doesn't propose a moment; `said_time` only checks a time the user already gave. |
| **4. One tap → sprawa card** | Separate cards for the note (`save_memory`) and its reminder (`remind_me_about_note`). The reminder's receipt shows only once iOS lists it as pending. Notification permission is asked when the first note reminder is set (`VoiceSessionController.swift:1374`). | **Two tools and two cards**, so two taps. `propose_plan` can't carry a note reminder. No card shows the words, the time and the state together. A note has no due time of its own; the time lives in a separate `MemoryReminder` row. |
| **5. Bring-back with the next step** | Note reminders are **local notifications** (`UNUserNotificationCenter`; `NoteReminderCoordinator` in `DoddyCore/NoteReminders.swift`; `NoteReminderNotifications.swift`). The one-off category has the long-press actions Open note, In 1 hour, Tomorrow 09:00 and **Done ("Gotowe")**. iOS's 64-pending limit is shared with birthdays (ADR-523). | The body is private by default: "Notatka, którą chcesz zobaczyć ponownie." The note's text shows only if a Settings switch is on (off by default). Nothing prepares or stores a next step. |
| **6. Done, logged, undo** | Done goes through `NoteReminderStore.done`, then `NoteReminderCoordinator.markDone`. "What Doddy did" has Undo for 24 h for Calendar and Reminders changes, list changes and saved notes (`DoddyCore/ActivityUndo.swift`). `undo_last` by voice. | **Done on a one-off note reminder deletes the reminder** (`markDone` → `remove`). It isn't logged and can't be undone. A note has no open/done state; `MemoryCategory` has `commitment` and `intention`, but nothing marks them finished. |
| **Metrics** | Proposed only: `schemas/telemetry.schema.json`, `docs/quality/VALIDATION_AND_METRICS.md`. Settings says "Analytics and telemetry: Off (not built)". On the iPhone only: the learning loop's outcome events, including `capability_gap` (`DoddyCore/Learning/`). | Nothing measures a sprawa saved, brought back or closed. `docs/product/VALIDATION.md` defines them; Phase 5 checks they're logged. |

---

## Changes the loop needs

**The feature freeze and the loop overlap here** (strategy, open decision 2). None of these adds a tool, an integration or a platform. Several change existing screens or data. The owner decides which go into the beta and in which phase. Nothing below is scheduled yet.

| # | Change | Kind | Notes |
|---|---|---|---|
| 1 | **First screen:** the question, a text field, a mic button and the AI line, in place of the intro and Home's first visit for new installs. | Changes existing screens | Shares the screen with Phase 3's AI disclosure. Tapping the mic still brings sign-in, consent and the mic prompt together. Lighter option: let the first sprawa be typed or dictated with the keyboard, and start voice from the second. The keyboard's dictation is Apple's and needs no Doddy sign-in; its privacy line goes in the policy. |
| 2 | **No tour:** the "First conversation" section of the prompt becomes the one question, and the first conversation's `opening_line` asks "Co ci wisi nad głową?" instead of "Co słychać?". | Prompt, plus the existing flag and greeting | Phase 4 rewrites the prompt anyway. |
| 3 | **Exact words:** keep the user's own transcript of the sprawa as its text, and label anything the agent rewrote. | Changes the save path | The text path is already exact. By voice, it needs the provider's user transcript for that turn. Code must choose the words, not the prompt ("prompts describe rules; code enforces them"). |
| 4 | **One tap for the sprawa and its time.** | Changes an existing card | Either let `propose_plan` carry a note reminder, or one sprawa card that saves both. ASK-01 level: change (tap on a card that shows the exact words and time). |
| 5 | **Propose the moment:** with a deadline, the evening before at 19:00; ask once; `said_time` checks it. Offline: the three buttons. | Prompt rule, plus buttons on an existing card | 19:00 is a guess; the beta measures snoozes. |
| 6 | **Lock Screen text:** the sprawa's words, a short title, or today's private line. | Setting default | Owner decision 3 in the strategy. |
| 7 | **Next step:** stored with the sprawa as Doddy's labelled suggestion; shown in the notification body and on the card. | Data and card change | Never presented as the user's words. Phase 4's skills (Message, Email, Kalendarz) can later make the step a ready draft. |
| 8 | **Done is logged and undoable:** a sprawa keeps an open/done/dropped state; a one-off reminder's Done no longer deletes silently. | Data change (migration) | Needs a new `ActivityUndo` case and a DoddyCore migration, with tests on Linux. |
| 9 | **The loop's metrics,** with no content in them. | New events | Phase 5 (`docs/product/VALIDATION.md`). |

---

## When it goes wrong

Every step has a failure path (CLAUDE.md rule 9). Copy in Polish is draft.

| What fails | What the user sees | What's kept |
|---|---|---|
| Microphone refused | The text field stays focused: "Napisz, co ci wisi nad głową." | Nothing lost; voice can be allowed later in Settings |
| No network, or the voice server is down | Typing works. Doddy asks "Kiedy ci przypomnieć?" with the three buttons, and says voice needs the internet (ADR-289 already does this on the voice screen). | The sprawa and its local reminder, on the iPhone |
| Sign in with Apple fails or is cancelled | The text path, with one line saying voice needs sign-in | Nothing lost |
| Voice mishears | The card shows the words before anything is saved; the user corrects them or types | Only what the user approved on the card |
| Saving fails (storage) | "Nie zapisano tej sprawy." The draft stays on screen. Never "saved" without a read-back from the store. | The draft |
| Notifications refused | The line in step 4; the sprawa on Home with its time | The sprawa, with no bring-back |
| Over iOS's 64 pending notifications | Saved, with a line saying Doddy can't set a reminder for it until one clears | The sprawa (ADR-523 shares the limit) |
| The notification is missed (phone off, Focus) | The sprawa shows as overdue on Home | The open sprawa |
| Gotowe tapped by mistake | Undo in What Doddy did, for 24 h | The sprawa reopens |
| The user deletes the sprawa | It's gone from Home, search and the agent's context, and its reminder is removed | Nothing; deletion is checked by reading the store again |

---

## Privacy
- **Spoken sprawy go to the voice provider** (ElevenLabs or OpenAI) as audio and text. Saved notes that aren't marked private are sent at the start of each conversation, up to 6,000 characters (`docs/product/V1_SCOPE.md`). The policy (Phase 3) lists this, with retention.
- **Typed sprawy stay on the iPhone** unless a conversation starts.
- **The Lock Screen** can show the sprawa's words, depending on owner decision 3.
- **Metrics never carry the words,** names or times (`docs/product/VALIDATION.md`).

## Character and tone (constitution)
- Doddy doesn't guilt or nag. A reminder never says "znowu zapomniałeś?". (DOD-10)
- No jokes on sensitive sprawy: health, money trouble, family. (DOD-03)
- No claimed feelings. "Gotowe?" is a question about the task, not about Doddy. (DOD-03)

## What the device run must show (acceptance, NOT RUN)
These become part of `docs/testing/device-checklist.md` once the owner decides which changes go in. Today the app can't pass them, because the loop isn't joined up.
1. On a fresh install, the first screen asks "Co ci wisi nad głową?". No tour, and no microphone prompt before the mic is tapped.
2. In flight mode, a typed sprawa is saved and its reminder set from the buttons.
3. A spoken sprawa's card shows the words the user said. Compare with the provider's transcript in the device log.
4. The sprawa and its time take one tap.
5. The notification arrives at the set time and shows the next step, with the Lock Screen text as decided.
6. Gotowe logs the sprawa in What Doddy did; Undo reopens it.
7. Refusing notifications leaves the sprawa on Home with its time and the honest line.

## Constitution evidence log
This is a design page. It enforces nothing on its own.

| Rule | Code that enforces it today | Gap for the loop |
|---|---|---|
| DOD-02 honesty | Offline is never called a server refusal (`Offline.swift`, ADR-289) | The words aren't the user's by voice (change 3) |
| DOD-06 user-controlled memory | `rawText` is immutable; delete is verified | No open/done state on a note (change 8) |
| DOD-07 scoped approval | ASK-01: the server gate and app ask cards (PR #87) | Two cards for one sprawa (change 4). ASK-01 has never run on a device. |
| DOD-08 verified status | Note reminders report "set" only when iOS lists them as pending | Done isn't logged (change 8) |
| DOD-09 correction and recovery | Undo for 24 h in What Doddy did | Not for a note reminder's Done (change 8) |
| DOD-11 observable privacy | Notification text private by default | Lock Screen default to decide (change 6) |

**Claims to avoid until a device run says otherwise:** "Doddy keeps your exact words" (not true by voice today), "it reminds you" (built, never seen on a device), "one tap" (two today).
