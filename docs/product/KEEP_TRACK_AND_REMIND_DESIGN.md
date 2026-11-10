# Doddy keeps track and reminds: the design (proposal)

Date: 2026-11-05. Owner (in Polish): think wider. The point is that Doddy helps the user remember and reminds them of important things; how could this be designed? The narrower prompt for "Doddy writes first" is `PROACTIVE_COMPANION_PROMPT.md`; it becomes one piece of this design.

**A proposal. Nothing below is built, except where a row says "exists".** It was written from the repo's docs (`docs/platforms/iphone.md`, `NOTE_REMINDERS.md`, `NOTIFICATION_IDEAS.md`, `MESSAGES_STATUS.md`, `SHOPPING_WATCH.md`), not from running anything. Where it touches an existing rule, the conflict is listed in section 12.

## 1. The one job

> The user tells Doddy something once. Doddy keeps it, and brings it back **when the user can act on it**, in the quietest way that still works, until the user says it is done.

Three promises that make it trustworthy, and a design that breaks one of them is wrong:
1. **Nothing is lost.** What the user handed over is stored, and the user can see all of it in one place.
2. **Nothing is invented.** Doddy never "remembers" something that wasn't said or saved, and never says it did something without a confirmation (DOD-06, DOD-08).
3. **Nothing nags.** One tap on the shoulder, at a useful moment, with a way to say "not now" and "stop this". No guilt, no streaks (DOD-03, DOD-10).

## 2. What exists today, and the gap

Everything below stores or surfaces a kind of "thing to remember", but each lives in its own place and nothing answers the question "what is open for me right now?".

| Source | Holds | Surfaces as | State |
|---|---|---|---|
| Notes with a reminder (time, place, repeat, "ring like an alarm") | A saved note, brought back | Local notification, opens the note | exists (ADR-190, 196, 211, 651) |
| Apple Reminders through Doddy | A to-do | Reminders' own banner | exists (M4) |
| Calendar events | Meetings | Today card, a nudge 10 / 30 / 60 min before, set by the user per event | exists (ADR-095) |
| Birthdays from Contacts | Dates | Notification | exists (ADR-288) |
| Lists, shopping list | Items | A place reminder says how many things are left | exists (ADR-652) |
| Timers, alarms, stopwatch | Time | AlarmKit, Lock Screen, island | exists (ADR-260, 650, 652) |
| Errands (tasks handed over) | A job running in the background | Home "Done" card, the Tasks list, a push | exists; push untested on a device |
| Price watch | A price the user wants | One push when confirmed | exists; off on the server |
| Parcels (InPost) | A tracking number | A list, refreshed on a tap | exists, off by default |
| Routines: morning, evening, weekly look-back, weekly plan, tidy-up | Doddy's own rhythm | Notifications, at most one a day, quiet 22:00 to 07:00 | exists |
| Recordings "Remember this", learned facts, "What Doddy knows" | Things said | Search and the memory screens | exists |

**The gaps:**
1. No single list of "things Doddy is holding for me", so nobody can check that nothing fell through.
2. A thing the user said in a conversation ("muszę jeszcze kupić buty") becomes memory only if they save a note. Nothing is proposed.
3. No sense of **importance**: a bin day and a visa deadline ring the same way.
4. Triggers are only time and place. Not "before I meet Marek", "when the price drops", "when I open the shop's list", "when it has been open for a week".
5. Doddy never writes first inside Messages, and there is no "follow-up" idea at all ("what happened with those shoes?").
6. No shared **attention budget**: each kind has its own switch and cap, but nothing decides which of five ready things is worth the one tap today.

## 3. The core idea: open loops

An **open loop** is anything that is started and not yet finished, in the user's life, that Doddy was told about or was given: "buy the shoes", "call the dentist", "waiting for the parcel", "the price drops below 300", "Ania's birthday gift", "send Marek the file", "renew the passport by 12 Dec".

Doddy's job is to hold open loops safely and close them honestly. This turns the existing pieces (reminders, watches, errands, lists, parcels, events) into **sources**, and adds one thing on top: **the loop**, a small record that links to its source and says what is still pending.

### The record (all stored on the iPhone, exact provenance, GRDB/SQLite, read back before "saved")

| Field | Meaning |
|---|---|
| `id`, `created_at`, `updated_at` | |
| `title` | The user's own words, or a fixed label for a source ("Cena: Nike Pegasus 41"). Never a model's rewording without the user's tap |
| `kind` | `todo`, `waiting_for` (a parcel, an answer, a task), `watch` (a price), `date` (deadline, birthday, event), `follow_up` (revisit after a time), `intent` (wants to buy or do, no date) |
| `source` | Link to where it came from: note id, recording id and time range, message id, errand id, watch id, calendar event id, list item id |
| `state` | `open`, `waiting` (nothing for the user to do yet), `snoozed_until`, `done`, `dropped` |
| `importance` | `low`, `normal`, `important`. Set by the **user**. Doddy may propose "ważne?" (deadline, money, a person) but a proposal changes nothing until accepted |
| `loudness` | `quiet` (appears inside the app only), `nudge` (a notification), `ring` (an alarm). Defaults from importance, editable per loop |
| `triggers[]` | `at_time`, `at_place`, `before_event(match)`, `when_watch_confirms`, `when_task_done`, `after_open_days(n)`, `when_person(name)` |
| `last_surfaced_at`, `surfaced_count`, `outcomes[]` | What happened each time it was shown: `opened`, `done`, `snoozed`, `ignored`, `stopped` |
| `person` (optional) | A Contacts reference the user chose, for "before I meet Marek" |

Not stored: anything inferred about the user's habits, mood or location history. Triggers are what the user asked for.

## 4. Capture: how loops come in

Rule: **a loop exists only after the user says yes to it**, except sources the user already created themselves (a reminder, a watch, an errand), which become loops automatically because they are already the user's own request.

| Entry | What happens | Confirmation |
|---|---|---|
| Voice: "Doddy, pamiętaj, że w czwartek muszę oddać książkę" | The agent proposes a card: **Zapisać jako sprawę?** with the title, the date and the loudness. Reuses the existing card-and-tap flow | A tap on the card (a spoken yes is not enough, as for any change) |
| Messages: the user types "muszę kupić buty do 20 listopada" | Doddy answers, and offers one chip: **Dodaj do spraw** | A tap |
| End of a conversation | Doddy may say once: "Mam zapisać coś z tego, co mówiłeś? Padło: oddać książkę w czwartek, kupić buty." The list comes from what the user said in that conversation, shown on a card, never silently saved | A tap on each |
| A note, list item, recording "Remember this", photo note | "Remind me" already exists; it now also creates the loop | The existing sheet |
| Share Sheet | "Save to Doddy" gains "…and remember it" | The sheet |
| Calendar, Reminders, parcels, price watches, errands | Read in as sources; they appear in the same list | Already the user's |

Extraction is a **proposal from a model, validated by code**: the title must be a quote or a close span of what the user said, dates are parsed by code and shown resolved with weekday and time zone ("czw. 12 listopada, 09:00, czas warszawski", acceptance A-20), and nothing is written before the tap.

## 5. Importance and loudness

Three loudness steps, in order of how much they intrude. Doddy uses the **lowest one that is still safe** for the loop's importance.

| Loudness | What it is | Used for | Sound / Focus |
|---|---|---|---|
| **quiet** | Appears on Home in "Teraz" and in the loop list. No notification | normal and low things, "intent" loops, stale items | none |
| **nudge** | A local or push notification; title names only the kind, body names the thing only if the Lock Screen text setting is on | important things, due soon; watches and finished tasks | iOS default; Time Sensitive only for what the user set for a moment |
| **ring** | An AlarmKit alarm, through Silent mode and Focus | what must not be missed (medicine, collecting a child, a deadline), only when the user chose "ring" | system alarm sound |

How importance is set, simply: when a loop is created the card has one line, **Jak ważne?** with three choices (Zwykłe, Ważne, Nie przegap). "Nie przegap" means `ring`. Default is Zwykłe, so the user never gets loud things they did not choose. Doddy can suggest "Ważne?" when a date is close or the words say "muszę", "termin", "nie zapomnij", but the suggestion is a chip, not an action.

## 6. When: the trigger engine (all deterministic, in code)

The model never decides **when**. Code evaluates triggers, and each trigger has a verified source of truth.

| Trigger | Example | Source of truth |
|---|---|---|
| `at_time` | "w czwartek o 9" | A scheduled notification read back from iOS's pending list |
| `at_place` | "jak będę w sklepie" | Existing place reminders (ADR-196) |
| `before_event(match)` | 10 min before a meeting whose title contains "Marek": "Masz o nim 2 notatki i 1 otwartą sprawę (plik do wysłania)" | Calendar on the phone + the person link; names shown only when the Lock Screen setting is on |
| `when_watch_confirms` | The shoes reach 300 zł | The server's confirmed read (ADR-614). Never a model's claim |
| `when_task_done` | The errand finished or failed | The server's task state |
| `after_open_days(n)` | A "buy shoes" intent open 10 days with no watch | The loop's own `updated_at`. Surfaces **once**, as a question: "Dalej chcesz kupić buty? Mogę pilnować ceny." |
| `when_person` | When the user opens a chat with Ania in Messages or says "Ania" to Doddy | Only inside Doddy, never reading other apps |

Not triggers, ever: what the user browsed, bought, who they met, where they went (beyond a place they set), or anything read from other apps.

## 7. Where: the surfaces

One loop can be shown in different places depending on loudness and what the user is doing. Each place has one job.

| Surface | Job | State |
|---|---|---|
| **Home › "Teraz"** | A calm card: the one to three things that matter now ("Dziś: oddać książkę. Czeka: paczka InPost. Cena spadła: buty"). It replaces nothing; it sits with the existing Today card | idea |
| **Today card** | Calendar and Reminders of today, as now | exists |
| **Notification** | The tap on the shoulder: the kind in the title, one line, one to three actions (Otwórz, Zrobione, Za godzinę, Jutro 9:00, Przestań o tym) | exists for several kinds; the unified one is an idea |
| **Messages thread** | After the user opens a notification, or by opening Messages, a **Doddy card** with the same content and the action buttons. The card is *created by code*, shown when the user arrives, and stored in the thread only after they act on it. Not a bubble that appears while the app is closed | idea (needs the owner's decision, section 12) |
| **Voice greeting** | When the user starts a conversation, Doddy can mention one open loop in one sentence ("Przy okazji, paczka jest od wczoraj w paczkomacie"). Only if "Pilnowanie" is on, and once per loop per day | idea |
| **Morning check-in and weekly plan** | The existing routines gain a line from the loops. They do not become longer or more frequent | exists as routines |
| **Lock Screen / widget** | The widget's snapshot lists the top three open loops | the snapshot exists (ADR-219) |
| **Live Activity** | For a thing that is running now (a task, a timer, a parcel out for delivery) | partly exists |

## 8. The attention budget

One place, in code, decides what may reach the user. All routines, watches, errands and loops go through it.

1. **Hard rules (never relaxed by a model):** quiet hours 22:00 to 07:00 for anything Doddy decided; the only exceptions are what the user set for a time (timers, reminders, alarms, event nudges). At most **one** self-initiated notification a day, as now (`NOTIFICATION_IDEAS.md` rule 3). Action items and what the user set always show.
2. **Ranking when several are ready:** (a) set for this time by the user, (b) due within 24 h and important, (c) a confirmed watch or a finished task, (d) due soon and normal, (e) stale intents. The top one is sent; the others wait for the next day, or go into the "Teraz" card instead of a notification.
3. **Merging:** several loops about one person, shop or trip become one message ("3 sprawy związane z podróżą do Lizbony").
4. **Backoff from the user's behaviour:** each loop kind keeps its recent `outcomes[]`. Two ignored messages of a kind in a row mean no more of that kind for 7 days, and the user is told once and given the switch. A "Przestań o tym" on a message closes that loop and writes nothing else.
5. **The user is always in charge:** a global switch "Doddy może przypominać o moich sprawach" (default off), per kind switches (today's list in Settings › Notifications), and a place that shows what he is holding and why.

## 9. Closing loops honestly

- "Zrobione" is the user's word. Doddy marks a loop `done` when the user says so, or when a trusted source confirms it: the calendar event ended, the reminder was completed in Apple Reminders, the parcel is delivered (InPost's status), the watch triggered, the task finished with a confirmed result. The state text names the source ("Zrobione: paczka odebrana, potwierdził InPost").
- **Unknown stays unknown.** An unreadable parcel status, a task that failed and a price that couldn't be read say that. They never become "done" and are never retried blindly (a rule that already holds for external writes).
- A `done` or `dropped` loop disappears from "Teraz" and stays in a history that the user can delete, with the deletion read back before "deleted".
- **Review:** the weekly routine offers one screen, "Co jeszcze jest otwarte", with three buttons per row (Zrobione, Przypomnij później, Zapomnij o tym). Nothing happens by itself.

## 10. The screens (working wireframes, not final design)

Colours and type: `DoddyDesignTokens` and `Theme`. Doddy's art only from the owner's numbered pack (`UploadedDoddy_*`, `WholeDoddy_*`); no new art is drawn.

**Home, "Teraz" card**
```
┌───────────────────────────────────────┐
│  Teraz                                │
│  ● Dziś 9:00  Oddać książkę   [Zrobione]│
│  ○ Cena spadła  Buty Nike     [Otwórz] │
│  ○ Czeka       Paczka InPost           │
│                       Wszystkie sprawy ›│
└───────────────────────────────────────┘
```

**"Na oku" page (working name; the one place for everything held)**
```
Na oku                         [+]
 Dziś (1)
  Oddać książkę · czw. 9:00 · ważne
 Czeka (2)
  Paczka InPost · potwierdza InPost
  Zadanie: loty do Lizbony · 3 opcje
 Pilnuję (1)
  Buty Nike do 300 zł · sprawdzam 4×/dzień
 Później (3)
  Prezent dla Ani · z notatki 12 paź.
```
Each row: tap opens the source; swipe: Zrobione, Za godzinę, Jutro, Zapomnij. A row's "i" shows **why it is here**: "Dodane przez Ciebie 3 listopada, z rozmowy o 14:02", with a link to the exact words (provenance).

**Capture card (after a conversation or in Messages)**
```
Zapisać to jako sprawę?
 „oddać książkę do czwartku"
 czw. 12 listopada · czas warszawski
 Jak ważne?  ( Zwykłe | Ważne | Nie przegap )
          [Zapisz]   [Nie]
```

**Notification and its card in Messages**
```
Lock Screen:   Cena spadła · Coś, czego pilnujesz, jest w lepszej cenie.   [Otwórz] [Pilnuj dalej]
In Messages:   ┌ Doddy ────────────────────────────┐
               │ Nike Pegasus 41: 289 zł w Zalando  │  (price and shop from the server, shown as data)
               │ poniżej Twojej kwoty 300 zł.       │
               │ [Zobacz w sklepie] [Sprawdź inne]  │
               └────────────────────────────────────┘
```

## 11. The roles: code, the model, the user

| Does | Who | Why |
|---|---|---|
| Stores loops, checks triggers, applies quiet hours and caps, schedules, reads back | **Code** | Rules are enforced in code, never in a prompt |
| Notices a candidate loop in what the user said | **Model proposes**, code validates the quote and parses the date | Model output is a proposal |
| Writes the words of a nudge | **Fixed templates first**; a model only to merge several signals, and only inside the validator described in `PROACTIVE_COMPANION_PROMPT.md` | Grounded, short, no invented facts |
| Decides to create, close or delete a loop | **The user**, by a tap | No silent memory |
| Facts about the world (a price, a parcel, a delivery) | **A trusted provider's confirmed answer** | `unknown` is never success |

## 12. Conflicts with what the repo already decided (need the owner)

| Existing rule | Where | Conflict | Suggested resolution |
|---|---|---|---|
| "Doddy never decides on its own to notify" and "Unprompted resurfacing ('a year ago you saved…'): **Never without a new decision**" | `NOTE_REMINDERS.md` principle 1 and catalogue | Stale-intent questions and "before I meet Marek" are self-initiated | A **new decision**: allowed only for loops the user accepted into "Na oku", only for the kinds they switched on, still inside the one-a-day cap. Never a "year ago" feature |
| Messages is started by the user | `MESSAGES_STATUS.md` | A Doddy card in the thread | The card appears when the user arrives (from a notification or by opening Messages) and is stored only after a tap. No bubble while the app is closed |
| Notifications never carry names by default | ADR-190 | "Marek", a product | Keep: names only with the existing text setting |
| Re-engagement is forbidden | persona rules | A "what about those shoes?" can feel like it | It is a question about a loop the user opened, offered once, closeable with "Przestań o tym", never worded as missing the user |
| The live agent changes only on the owner's separate instruction | CLAUDE.md | Capture cards in a conversation need prompt and tool changes | Written here, not applied. Each live change needs a yes on the exact text |
| No cloud accounts or new infrastructure unless a milestone says so | CLAUDE.md | The design is mostly on-device | Stays on-device except what already exists (watches and errands on the messaging server, push) |

## 13. Build order (each step stands alone and can be stopped)

| Step | What the user gets | What it needs | Acceptance (examples, to be written into `ACCEPTANCE_TESTS.md`) |
|---|---|---|---|
| **L0** | **"Na oku": one read-only page** that lists what already exists (reminders on notes, Apple Reminders due, events with nudges, errands, watches, parcels, birthdays) with its source and a link. No new notifications, no new storage | Read-only aggregation in DoddyCore; a Settings row | Every row opens its source; a deleted source disappears; nothing leaves the phone |
| **L1** | Loops are a real record: create from a note, from a voice card, or in Messages by a chip; importance and loudness; done, snooze, drop. "Teraz" on Home | GRDB table, read-back on write, an ADR | A saved loop survives a restart and a failed write says so; delete is read back; no loop exists without a tap |
| **L2** | The attention budget and the unified triggers (event with person, stale intent as one question, watch and task as loops) | One scheduler in code, a rank function with tests, backoff from outcomes | The cap and quiet hours hold across all kinds; two ignores stop a kind for 7 days |
| **L3** | A Doddy card in Messages and a mention in the voice greeting | The owner's decisions in section 12, the live-agent yes | A card never appears while the app is closed; "Przestań o tym" closes the loop |
| **L4** | The composer model merges several signals into one line | `PROACTIVE_COMPANION_PROMPT.md` and its validator | A message with a number not in a signal is dropped; sensitive topics send nothing |

L0 is a good first milestone: it shows the value (everything in one place) with the least risk, and it settles what the unified model has to hold.

## 14. Privacy and failure

- **On the iPhone by default.** Loops, triggers and outcomes are stored locally and can be exported and deleted. The server sees only what already goes there: a watch's draft, an errand, a push token. A loop's words reach a model only if the user turned on a model feature, and private notes never (ADR-310).
- **Failures:** if iOS notifications are off, the loop stays in the app and says so; if the store is down, the page says so and nothing is claimed saved; if a source can't be read (a calendar permission was revoked), the row says "nie mogę tego teraz sprawdzić" and keeps the loop.
- **"What leaves this iPhone"** gains a row for this feature before it ships.

## 15. Constitution evidence log (for when it is built)

| Rule | Enforced by (to build) | Gap |
|---|---|---|
| ASK-01 always ask first | The switch is off by default; every create, change or close is a tap on a card | Not built |
| DOD-06 memory is explicit, with provenance | Loops store a source link; no loop without a tap | Not built |
| DOD-08 verified status | Saved / done / deleted only after read-back or a trusted confirmation | Not built |
| DOD-03 / DOD-10 no guilt, no dependency, no pressure | Attention budget, backoff, template check for banned phrases | The phrase list isn't written |
| DOD-07 content is data | Parcel, shop and email text is shown as data and never copied into a trigger or a link | Not built |
| DOD-11 observable privacy | "Na oku" shows what is held and why; "What leaves this iPhone" row | Not written |
| ADR-190 | Lock Screen text is the kind only, unless the setting is on | Exists for notes |

## 16. Decisions for the owner

1. **Direction:** do you want L0 ("Na oku", read-only, everything in one place) as the first milestone, or go straight to L1?
2. **The name:** "Na oku", "Pilnuję", or "Sprawy" (the last collides with errands, which the voice prompt already calls sprawy).
3. **Messages:** is a Doddy card that appears when the user arrives acceptable (section 7), or only notifications?
4. **The new rule** from section 12: self-initiated, only for loops the user accepted, one a day.
5. **Importance:** is the three-step "Zwykłe, Ważne, Nie przegap" the right shape, with "Nie przegap" meaning an alarm that rings through Silent mode?
6. **The model:** fixed templates first and a model later (my recommendation), or a model from the start?
7. A new ADR and, for L3, a yes on the exact live-agent change.
