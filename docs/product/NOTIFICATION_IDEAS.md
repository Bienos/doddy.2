# Notification ideas: what Doddy could send, and what it says (proposal)

Date: 2026-10-24. Owner (24 Oct, in Polish): think up other notifications, for example a reminder once a week; how they would look and what they would say, with examples. **A proposal: nothing below is built**, except where a row says "exists". The sound and Lock Screen fixes that come first are ADR-650 (`docs/implementation/NOTIFICATIONS_AND_TIMERS.md`). Polish is the default; English follows each line.

## The rules every Doddy notification follows

1. **Useful first.** One line that says what to do now; a tap opens exactly that thing, never Home.
2. **What you set rings; Doddy's own routines whisper.** Time Sensitive (through a Focus) only for what the user set for a moment: timers, reminders, time to leave. Routines never push through a Focus (DOD-10, `DoddyNotificationKind`).
3. **At most one routine a day** from Doddy (morning, evening, weekly, tidy-up and the new ones together), none in quiet hours (proposed 22:00 to 7:00). What the user set doesn't count.
4. **Nothing private on the Lock Screen by default.** The title names the kind ("Przypomnienie", "Urodziny"); a note's words or a name only with "Show note text in notifications" on (ADR-190, as today).
5. **Grounded.** "Doddy remembers…" only from something saved on this iPhone (a note, a list, an event, a birthday), and it says which (DOD-06, DOD-08). Never invented.
6. **Doddy's voice, short.** No guilt, no streaks, no "I miss you", no fake urgency, no emojis or exclamation marks. Health, money and anything sensitive: plain, no jokes (DOD-03, DOD-10).
7. **Every kind has its own switch** (Settings › Notifications); anything new is off until the user turns it on or says yes to it in a conversation. A long-press action turns that kind off.
8. **Actions where they save a step:** Zrobione, Za godzinę, Jutro 9:00, Otwórz.

## A. What you set: it rings

| # | When | Lock Screen (Polish) | English | State |
|---|---|---|---|---|
| A1 | Timer ends | Ringing screen **Makaron** · Zatrzymaj · Powtórz. While it runs: **MINUTNIK** · Makaron · 7:42 · Pauza · Zatrzymaj | **Pasta** · Stop · Repeat; **TIMER** · Pasta · 7:42 · Pause · Stop | ADR-650 (iOS 26) |
| A2 | Alarm | **Siłownia** · Zatrzymaj · Drzemka | **Gym** · Stop · Snooze | exists (ADR-260, 283) |
| A3 | Apple Reminders reminder | **Zadzwonić do mamy** (Reminders' own banner, 15:30) | **Call Mum** | alerts again since ADR-650 |
| A4 | Doddy's reminder on a note | **Przypomnienie** · Kod do paczkomatu: 4471 / with text hidden: **Przypomnienie** · Notatka, którą chciałeś zobaczyć. Actions: Otwórz notatkę · Za godzinę · Jutro 9:00 · Zrobione | **Reminder** · Parcel locker code: 4471 / A note you asked to see again | exists (ADR-190), Time Sensitive since ADR-650 |
| A5 | **New: "Important: ring like an alarm".** For what mustn't be missed (medicine, picking up a child, a deadline) | Ringing screen **Leki** · Zrobione · Za 10 min | **Medicine** · Done · In 10 min | idea |

A5 by voice: "Przypomnij mi codziennie o 8 o lekach, i niech zadzwoni" → the card says "Zadzwoni jak budzik, także w trybie cichym". Needs an option on Doddy's reminders (an AlarmKit alarm with the note's label), a `ring` choice on `remind_me_about_note`, and the owner's yes on the live agent.

## B. The rhythm of the week (opt-in, at most one a day)

| # | When | Lock Screen (Polish) | English | State |
|---|---|---|---|---|
| B1 | **New: Monday plan,** Mon 8:00 | **Nowy tydzień** · 3 spotkania, 2 przypomnienia, w czwartek urodziny. Zerknąć? | **New week** · 3 meetings, 2 reminders, a birthday on Thursday. Take a look? | idea |
| B2 | **Weekly chores you set by voice** | **Przypomnienie · w każdy czwartek** · Wystaw śmieci. Actions: Zrobione · Za godzinę | **Reminder · every Thursday** · Put the bins out | exists (repeating reminders, ADR-211); make it known on "What I can do" |
| B3 | **New: monthly bills,** a preset of B2 | **Przypomnienie · co miesiąc, 10. dnia** · Czynsz: termin płatności dziś | **Reminder · monthly, on the 10th** · Rent is due today | idea (the repeat exists) |
| B4 | Sunday look-back, 19:00 | **Twój tydzień z Doddym** · Krótkie podsumowanie, gdy zechcesz. Proposed: · 12 notatek i 3 listy w tym tygodniu. Zerknąć? | **Your week with Doddy** · 12 notes and 3 lists this week | exists (ADR-306); the counts are the idea |
| B5 | Weekly tidy-up | **Porządki w Doddym** · Kilka minut na porządki? | **Tidy up Doddy** · A few minutes to tidy up? | exists (ADR-228) |
| B6 | **New: a stopwatch** that counts up ("włącz stoper") | No notification: the Lock Screen and island count up · **STOPER** · 12:07 · Stop | **STOPWATCH** · 12:07 · Stop | idea; a new voice tool |

B1's counts are read on the iPhone. iOS doesn't promise the app time on Sunday night, so the words are fixed when the notification is scheduled; unless Doddy refreshed them in the last 12 hours, it says only "Nowy tydzień · Zerknąć, co Cię czeka?" and the screen does the counting.

## C. Doddy remembers (only from what you saved)

| # | When | Lock Screen (Polish) | English | State |
|---|---|---|---|---|
| C1 | **New: a birthday with a gift idea,** 3 days before | **Urodziny Ani w piątek** · Masz zapisany pomysł na prezent (notatka z 12 października). Names hidden: **Czyjeś urodziny w piątek** · Masz zapisany pomysł na prezent | **Ania's birthday on Friday** · You saved a gift idea (note from 12 October) | idea (birthdays exist, ADR-288) |
| C2 | **New: at the shop with a list** (arriving at a place you picked) | **Jesteś przy sklepie** · Zakupy: 4 rzeczy na liście. Action: Otwórz listę | **You're at the shop** · Groceries: 4 things on the list | idea (place reminders exist for notes, ADR-196) |
| C3 | **New: before a meeting,** 10 min before an event whose title names someone you have notes about | **Za 10 min: spotkanie z Markiem** · Masz o nim 2 notatki | **In 10 min: meeting with Marek** · You have 2 notes about him | idea (event nudges exist) |
| C4 | **New: "for later",** Saturday 10:00, at most once a week, only for notes the user marked "na później" | **Odłożone na później** · Książka od Tomka. Zerknąć teraz? Actions: Otwórz · Za tydzień · Już nie | **Saved for later** · The book from Tomek | idea |
| C5 | **New: parking,** when Doddy saves where you parked | Doddy asks in the conversation: "Przypomnieć za 2 godziny, zanim skończy się postój?" → a timer (A1) **Parkowanie** · Zatrzymaj | **Parking** · Stop | idea (parking and timers exist) |

## D. Doddy finished (what you asked for)

| # | When | Lock Screen (Polish) | English | State |
|---|---|---|---|---|
| D1 | An errand is done | **Gotowe** · Loty do Lizbony: 3 opcje od 420 zł. Zobacz | **Done** · Flights to Lisbon: 3 options from 420 zł | exists (ADR-570); whether the title shows is an open owner decision |
| D2 | **New: a file Doddy made in Messages** | **Prezentacja gotowa** · Plan wyjazdu, 8 slajdów | **Presentation ready** · Trip plan, 8 slides | idea (ADR-606) |

## What Doddy never sends

| Never | Why |
|---|---|
| "Tęsknię za Tobą" / "Dawno nie gadaliśmy" | Claims a feeling and builds guilt (DOD-03, DOD-10) |
| "Nie przerywaj serii: 5 dni z rzędu!" | Streaks are pressure, not help |
| "Masz 3 nowe funkcje!!!" | Marketing in a personal assistant's channel |
| "Ostatnia szansa…" | Fake urgency |
| A note's words or a name with the setting off | Privacy on the Lock Screen (ADR-190) |
| Anything in quiet hours the user didn't set | Doddy's routines whisper |

## Order I'd build them in

1. ADR-650 on a device first (its checklist), so what exists rings.
2. **A5** "ring like an alarm" for important reminders: the most direct answer to "no sound"; small (AlarmKit is in place).
3. **B1** the Monday plan: the weekly reminder the owner asked for, made useful.
4. **C2** the shop list: the place trigger exists for notes.
5. **C1** birthday with a gift idea: shows what a memory companion is for.
6. B6 and the rest when asked.

## Owner's answers (24 Oct 2026)

- **Build A5, then B1:** both are in code on `claude/notifications-sound-timers` (ADR-651, `docs/implementation/RINGING_REMINDERS_AND_WEEKLY_PLAN.md`); not compiled or seen on a device yet.
- **Quiet hours:** yes, 22:00 to 07:00, for Doddy's routines.
- **One a day:** for notifications "out of nowhere" only. Timers and anything that is an action item always show. Built as: Doddy's own tip never comes on a day a routine already did.
- **"1 i 3" (next):** a list's place reminder says how many things are left, and a real count-up stopwatch; both are in code on `claude/stopwatch-and-shop-list` (ADR-652, `docs/implementation/STOPWATCH_AND_SHOP_LIST.md`), not compiled or seen on a device.
- **Sound (5), owner: "systemowy":** the system's own sounds. Notifications keep iOS's default sound, and timers and ringing reminders ring with the system alarm sound through AlarmKit. No custom sound is made or bundled.
- **An errand's title on the Lock Screen (4), owner: "zrób jak trzeba" (left to me):** it stays out. The done push carries no words from the errand ("Gotowe. Wynik sprawy czeka w aplikacji."). Showing the title would mean putting it in the push payload, which the server and Apple's push service would then read, or building a notification service extension that fills it in on the phone; neither fits a change that can't be compiled or tried on a device here, and the current text already says where the result is. Open it again if the title becomes worth that cost.
- **Live agent (24 Oct, owner: "2 tak"):** A5's `ring` and the three stopwatch tools are on the live agent (`voice-agent/README.md`). Not tried in a real conversation yet.

## Decisions for the owner (as asked on 24 Oct)

1. Which of A5, B1, C1 to C5, D2 and B6 to build, and in what order (the list above is the recommendation).
2. Quiet hours: 22:00 to 7:00 by default?
3. At most one routine notification a day?
4. D1: the task's title on the Lock Screen, or only with "Show note text"? (Answered 24 Oct: left to the builder; it stays out, see above.)
5. Sound: iOS's default notification sound (as today), or a short Doddy sound (a sound file of up to 30 seconds, made for Doddy and licensed; needs sound design)? (Answered 24 Oct: the system's.)
6. A5, B6 and C5 add or change voice tools: each needs a yes on the exact live-agent change.
