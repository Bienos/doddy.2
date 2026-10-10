# Note reminders — design v0.1 (M4a)

**Status:** APPROVED by the owner 2026-10-10 with the recommended answers to D1–D5; **implemented as M4a**, device verification pending. Build evidence: `docs/implementation/M4A_NOTE_REMINDERS_STATUS.md`. ADR-176.

**How this fits next to what already exists on this line:** Apple Reminders (M4, `ReminderAction`, voice `create_reminder`) put an item in the iPhone's Reminders app; timers and event nudges (`DeviceConnections`) are local notifications; Doddy's opt-in Updates (S1, ADR-148) and daily news (N1) are server pushes. **Note reminders** are a fourth, separate thing: a local notification about one saved note that opens that note. The rules below are about note reminders only; they do not change Updates, news, timers or M4.
**Date:** 2026-10-10. **Visual study:** 9 artboards on the Pocket Notebook tokens, https://claude.ai/artifact/AVHEBdUynLJkNMwdkTJkn8 (private to the owner). This document is the source of truth for copy and behaviour; the artboards illustrate it.

## The one job

A note reminder exists for **one reason only**: the user asked Doddy to bring a saved note back at a time they chose.

> "Remind me about this tomorrow morning" → at 09:00 the iPhone shows a reminder → tap → the exact note opens.

This keeps the product promise ("Tell Doddy before you forget; find the original later") and adds the follow-through half of H4 without new permissions beyond notifications, without a server, and without EventKit.

## Principles

1. **User-asked only.** Every notification maps 1:1 to a reminder the user confirmed on screen. Doddy never decides on its own to notify.
2. **Local only.** `UserNotifications` local requests (`UNCalendarNotificationTrigger`). No APNs, no push server, no device token, no remote content.
3. **Private by default.** The Lock Screen shows that a reminder exists, not what the note says. Note text in notifications is an opt-in setting.
4. **Truthful receipts.** "Reminder set" appears only after the request is read back from `pendingNotificationRequests()`. If iOS notifications are off, Doddy says so and keeps the reminder inside the app.
5. **No guilt, no pull.** No streaks, re-engagement, "Doddy misses you", badges or teasers (persona rule `no_guilt_notifications`, `user_can_exit_without_reengagement_pressure`).
6. **Plain voice.** Notification copy is calm and literal. Character humour stays inside the app; notifications have no jokes and no emoji.
7. **Ask at the moment of need.** The permission prompt appears the first time the user sets a reminder, never at launch or in onboarding.

## Catalogue

| Notification | Status | Why |
|---|---|---|
| **Memory reminder:** a saved note, at a chosen date/time | **Proposed v1** | The only notification with a user-requested purpose today |
| Snooze of a delivered reminder | Proposed v1 (action on the notification) | Same reminder, new time, user-initiated |
| Recurring reminders ("every Monday") | Deferred | Needs evidence of demand; adds rule editing and 64-request pressure |
| Location-based ("when I get home") | Deferred | Needs location permission; separate privacy review |
| Time Sensitive interruption level | Deferred, opt-in only | Breaks through Focus; must be the user's choice per reminder |
| Voice-session Live Activity / Dynamic Island | Separate track (V3) | Not a notification; see `docs/research/VOICE_SHORTCUT_ISLAND_TOOLS_2026-10.md` |
| Voice agent proposing a reminder | Later | Agent may *propose*; the same on-screen sheet confirms (tool contract in `docs/architecture/TOOLS_AND_ACTIONS.md`) |
| Note reminders through remote push | **Never** | Note reminders are local; no note text or reminder time is sent to a server. (Updates and news are a separate opt-in server feature.) |
| Re-engagement, streaks, "you haven't saved anything", tips, marketing | **Never** | Guilt/dependency patterns; persona rules forbid them |
| Unprompted resurfacing ("a year ago you saved…") | **Never without a new decision** | Doddy would be deciding what to show the user; that breaks principle 1 |
| AI-written note-reminder text | **Never** | The body is the user's own note or fixed copy, nothing generated |
| App icon badge counts | **Off** | Badges create pressure; overdue reminders already show on Home |
| Voice | Uses Apple Reminders (M4) for now | The live agent's `create_reminder` already works; a note-linked voice path is an open decision |

## Flow and screens

### 1. Set a reminder (Memory detail → sheet)
- New row on Memory detail, below "Correct this detail": **Remind me** (`bell`).
- Sheet title: **When should I bring this back?**
- Quick picks, each showing the resolved time: *This evening · 18:00*, *Tomorrow morning · 09:00*, *Monday morning · 09:00* (next Monday), *Pick a date and time* (native `DatePicker`, minute interval 5).
  Quick picks that would fall in the past are hidden (e.g. "This evening" after 18:00).
- Under the choice, always the resolved line with weekday, date, time and time zone: **Mon 12 Oct, 09:00 · Warsaw time**. (Acceptance A-20: never schedule an ambiguous time silently.)
- Primary button **Set reminder**; secondary **Cancel**. Nothing is stored before the tap.

### 2. First time only: permission explainer (before the iOS prompt)
Shown when authorization is `.notDetermined`, after the user taps Set reminder.
- **Doddy needs permission to remind you**
- *To bring this note back at 09:00, iOS needs to let Doddy send notifications. Doddy only notifies you about reminders you set yourself. No tips, no streaks, no marketing.*
- **Continue** → system prompt (`.alert`, `.sound`; no `.badge`). **Not now** → the reminder is kept inside Doddy only (state 3b).
- No provisional authorization: a quiet delivery would defeat a reminder the user asked for.
- *As built:* the explainer is shown once. After "Not now", Settings → Reminders on notes offers **Allow notifications**.

### 3a. Receipt: scheduled and verified
Memory detail shows a chip **Reminder · Mon 12 Oct, 09:00** with **Change** and **Cancel reminder**.
Inline confirmation: **Reminder set for Mon 12 Oct, 09:00.** / *Your iPhone will show a notification. The note text stays hidden on the Lock Screen.*

### 3b. Receipt: notifications off (denied or "Not now")
**Saved in Doddy for Mon 12 Oct, 09:00.** / *Notifications are off for Doddy, so your iPhone won't alert you. When it's due, the note waits at the top of Home.* + **Open Settings** (`UIApplication.openNotificationSettingsURLString`).

### 3c. Failure
**Couldn't set the reminder. Nothing was scheduled, and your note is unchanged.** + **Try again**. Shown when the DB write fails, or `add(_:)` throws, or the read-back doesn't find the request (the DB row is then rolled back).

### 4. Delivery
| | Default (private) | With "Show note text" on |
|---|---|---|
| Title | Reminder | Reminder |
| Body | A note you asked to see again. | First 140 characters of the note's current text |
| Sound | Default | Default |
| Interruption level | `.active` | `.active` |
| Thread | `memory-reminders` | `memory-reminders` |

iOS adds the app name and icon. The user's iOS "Show Previews" setting still applies on top. In the private default the note text never enters the iOS notification store at all.

Long-press actions (category `MEMORY_REMINDER`): **Open note** (foreground), **Tomorrow 09:00** (background, reschedules), **Done** (background, marks done; never deletes the note).
Tap → the app opens straight to that memory's detail. If the memory no longer exists: the existing "This memory no longer exists." state.

### 5. Home: due now
Reminders whose time has passed and that are not Done appear at the top of Home under **Due now**: note text, "You asked to see this again · 09:00", buttons **Done** and **Tomorrow 09:00** (*as built*: the same snooze as the notification action, instead of a "Later…" sheet). This makes reminders work even with notifications off, and it is the only place overdue items appear (no badge).

### 6. Settings → Reminders on notes
- **Status:** Allowed / Off / Not asked yet (from `getNotificationSettings()`, refreshed on foreground) + Open Settings when Off.
- **Show note text in notifications:** toggle, default **off**. Footnote: *When on, the note's text is shown on your Lock Screen and stored by iOS with the notification.* Turning it on/off reschedules pending requests with the new content.
- **Reminders set:** count + list link; **Cancel all reminders** (confirmation).
- Privacy section row: **Notifications · Only reminders you set (on this iPhone)**.

### 7. Editing and deleting a note
- Editing the note's text: if text is shown in notifications, the pending request is replaced with the new text.
- Deleting a note: confirmation adds *"Its reminder for Mon 12 Oct, 09:00 will be cancelled too."*; the pending request is removed in the same operation. **Delete all** also removes all pending and delivered Doddy notifications.

## Engineering contract (for the implementing milestone)

- **Source of truth is the database**, not iOS. Table `memory_reminders` (migration `v2_memory_reminders`):
  `id TEXT PK` (also the notification request id) · `memory_id TEXT NOT NULL UNIQUE REFERENCES memories(id) ON DELETE CASCADE` · `fire_at_ms INTEGER NOT NULL` · `time_zone_id TEXT NOT NULL` · `created_at_ms INTEGER NOT NULL`. One reminder per memory. *As built:* Done and Cancel **delete** the row (no history is kept), so there is no state column.
- **Time:** store the absolute instant plus the zone it was set in. The receipt and Due card always show the zone name. Travelling keeps the absolute instant (decision D3 below).
- **Ports (as built):** `NoteNotificationScheduling` and `NoteReminderRepository` in DoddyCore; `NoteReminderCoordinator` (actor) is the only code path that schedules, moves or removes a note reminder. The iOS adapter is `DoddyApp/Infrastructure/Connections/NoteReminderNotifications.swift`, next to timers and nudges. Taps and actions arrive through the app's one delegate, `TimerBanners`, which forwards note reminders to `NoteReminderRouter`. Identifiers start with `doddy.note.`; reconcile and delete-all touch only those, never timers, nudges or pushes (tested). Table `note_reminders` (migration `v3_note_reminders`) in the shared `DoddyDatabase`.
- **Order of a schedule:** validate future time → DB insert (transaction) → `add(request)` → read back pending ids → success receipt. Any failure after the insert deletes the row and shows 3c.
- **Reconcile** on launch and on every foreground: re-add scheduled rows missing from pending (e.g. after restore), remove pending Doddy requests with no row. Background actions (Snooze/Done) update the DB in the notification response handler.
- **iOS limit:** an app may have 64 pending local notifications. Timers and event nudges share that limit, so note reminders cap at **50** and say so: *"You have 50 reminders set, the most Doddy can schedule. Finish or cancel one to add another."*
- **Guard:** extend `scripts/check_forbidden_capabilities.sh` so `UserNotifications` appears only in the reminders adapter, and `registerForRemoteNotifications` / `aps-environment` appear nowhere.
- **Privacy manifest / labels:** no new data types leave the device; no new required-reason APIs expected (re-check on implementation).

## Accessibility

- Sheet options are buttons with the full resolved time in the label ("Tomorrow morning, Sunday 11 October, 9 AM, Warsaw time").
- The receipt is announced (`AccessibilityNotification.Announcement`) only after verification.
- No colour-only state: chips carry text and the `bell` / `bell.slash` symbol. Dynamic Type wraps; nothing truncates except the 140-character notification body.
- Character art on the Due card hides under large text and when "Hide character artwork" is on.

## Acceptance tests (add to `docs/quality/ACCEPTANCE_TESTS.md` when the milestone is approved)

| ID | Scenario | Pass condition |
|---|---|---|
| N-01 | Set reminder, notifications allowed | Pending request with the row's id exists before "Reminder set" appears |
| N-02 | First reminder, not determined | Explainer then system prompt; never shown at launch/onboarding |
| N-03 | Denied / Not now | Row stored; receipt says no alert; Due card shows after time passes |
| N-04 | Delivered on locked phone, default | Notification content has no note text (inspect request content) |
| N-05 | Show note text on, then edit note | Pending content updated to new current text |
| N-06 | Delete note with reminder | Pending request gone; row gone; still gone after relaunch |
| N-07 | Delete all memories | No pending or delivered Doddy notifications remain |
| N-08 | Tap notification | Opens the exact memory; deleted memory shows "no longer exists" |
| N-09 | Tomorrow 09:00 action on Lock Screen | Row and pending request both moved; no duplicate |
| N-10 | Device time zone change | Fires at stored instant; UI shows original zone label |
| N-11 | DST change between set and fire | Fires at the shown wall time in the stored zone |
| N-12 | Past time / 51st reminder | Rejected with message; nothing stored |
| N-13 | Pending requests cleared by OS/restore | Reconcile re-adds them on next foreground |
| N-14 | Code guard | No remote notification registration; UN APIs only in adapter |
| N-15 | VoiceOver, max Dynamic Type, dark | Sheet, receipt, Due card and Settings usable |

Physical-device-only: N-04, N-09 (Lock Screen), N-10/N-11 (real clock), Focus/Summary behaviour.

## Where this fits

M4 (Apple Reminders through EventKit) is already built on this line. **M4a — note reminders** adds the local, note-linked kind next to it: no Reminders permission, opens the exact note, deleted with the note, testable on the simulator. Users who want the item in Apple Reminders keep using M4 (by voice today).

## Decisions for the owner

1. **D1 — Approve the scope:** user-asked memory reminders only; everything in "Never" stays never.
2. **D2 — M4a vs M4:** decided by the owner as "both": M4 was already built; M4a adds note reminders.
3. **D3 — Travel:** keep the absolute instant (recommended; matches what the receipt promised) or follow the wall clock in the new zone.
4. **D4 — Lock Screen privacy default:** text hidden (recommended) or shown.
5. **D5 — Quick-pick times:** 18:00 / 09:00 / next Monday 09:00, or user-configurable.
6. **D6 — Polish copy:** drafts below need a native review.

## Copy (EN → PL draft, needs native review)

| Key | English | Polski (draft) |
|---|---|---|
| detail.remind | Remind me | Przypomnij mi |
| sheet.title | When should I bring this back? | Kiedy mam ci to przypomnieć? |
| pick.evening | This evening · 18:00 | Dziś wieczorem · 18:00 |
| pick.morning | Tomorrow morning · 09:00 | Jutro rano · 9:00 |
| pick.monday | Monday morning · 09:00 | W poniedziałek rano · 9:00 |
| pick.custom | Pick a date and time | Wybierz datę i godzinę |
| sheet.confirm | Set reminder | Ustaw przypomnienie |
| receipt.ok | Reminder set for {date}. | Przypomnienie ustawione na {date}. |
| receipt.off | Saved in Doddy for {date}. | Zapisane w Doddym na {date}. |
| receipt.fail | Couldn't set the reminder. Nothing was scheduled, and your note is unchanged. | Nie udało się ustawić przypomnienia. Nic nie zostało zaplanowane, notatka jest bez zmian. |
| push.title | Reminder | Przypomnienie |
| push.private | A note you asked to see again. | Notatka do ponownego przejrzenia. |
| action.open | Open note | Otwórz notatkę |
| action.tomorrow | Tomorrow 09:00 | Jutro 9:00 |
| action.done | Done | Gotowe |
| home.due | Due now | Na teraz |
| settings.preview | Show note text in notifications | Pokazuj treść notatki w powiadomieniach |
