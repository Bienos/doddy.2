# What the app can do by voice

The table for step 1 of decision `docs/decisions/2026-11-27-voice-first-doddy.md`: every action a person can tap in the
iPhone app, and whether a voice tool covers it. Built on 27 Nov 2026 from `DoddyApp/Features/` and
`voice-agent/tools.json`. Watch and Mac are paused (ADR-572) and left out. Update a row when a tool lands.

**Status:**
- **voice**: a tool does it.
- **new**: added by the pull request that adds this file.
- **next**: planned for a later step.
- **tap**: stays a tap, for the reason given.

| Screen | Action | Status | Tool or reason |
|---|---|---|---|
| Memories | save, find a note | voice | `save_memory`, `search_memories` |
| Memories | change a note's text | new | `change_note` |
| Memories | delete a note | new | `delete_note` (Undo in Memories) |
| Memories | undo a delete, pin, make private, change type, read aloud | next | |
| Memories | delete all notes | tap | wipes everything; Settings only |
| Note reminders | set one | voice | `remind_me_about_note` |
| Note reminders | turn one off | new | `cancel_note_reminder` |
| Note reminders | done or snooze a due reminder | next | |
| Lists | create, add, tick, remove, read | voice | `create_list`, `add_to_list`, `check_off`, `remove_from_list`, `read_list` |
| Lists | rename, delete, clear ticked | new | `rename_list`, `delete_list`, `clear_ticked` |
| Lists | untick all, templates, shopping mode, undo a change | next | |
| Sharing | share a list, stop, join, leave | tap | iCloud's own sharing sheet |
| Today | reminders: add, finish, change, delete | voice | `create_reminder`, `change_reminder`, `delete_reminder` |
| Alarms, timers | set, list, turn off an alarm | voice | `set_alarm`, `set_timer`, `list_alarms`, `cancel_alarm` |
| Alarms, timers | stop or pause a timer | next | needs AlarmKit's timers listed (draft #497) |
| Focus, stopwatch | start, stop, check | voice | `start_focus`, `stop_focus`, `check_focus`, `start_stopwatch`, `stop_stopwatch`, `check_stopwatch` |
| Focus, stopwatch | pause and resume | next | |
| Tasks | hand over, read results | voice | `hand_over_errand`, `check_errands` |
| Tasks | stop a task | new | `cancel_task` |
| Tasks | delete a task | next | |
| Studio | make a brief | voice | `make_something` |
| Studio | stop or delete one | next | |
| Calls | call me now, later, every morning; stop morning calls | voice | `call_me_now`, `call_me_later`, `call_me_every_morning`, `stop_morning_calls` |
| Calls | cancel a booked call, the call switches, keep a call note | next | the switches with `change_setting` |
| Calls | set the call PIN | tap | a secret is typed, never said aloud |
| Call cases | ask places, book, order | voice | `call_places` |
| Call cases | call now, cancel, end or take over a live call | next | step 4 (calls protocol) |
| On my radar | follow | voice | `follow_news` |
| On my radar | stop following | new | `unfollow_news` |
| On my radar | reorder, add a feed, summarize or save a story | next | |
| Shopping | find deals | voice | `find_deals` |
| Shopping | price watches and price alerts | next | |
| Trips, flights | plan, find flights | voice | `plan_trip`, `find_flights` |
| Trips, flights | find trips in email, forget them | next | |
| Parcels | add, refresh, remove | next | |
| Messages, files | ask Claude, make a file | voice | `ask_claude`, `make_document` |
| Messages, files | read Doddy's messages, open a file, delete a conversation | next | |
| Recordings | start, stop, recap | next | |
| Sport, Health | training plan, steps, health week | voice | `open_training_plan`, `read_steps`, `read_health_week` |
| Sport, Health | training log | next | |
| Sport, Health | turn Apple Health on | tap | Apple's own consent sheet |
| Settings | Doddy's style, switches, routines, connections | next | `change_setting` with a fixed list; each switch's side effect is run too |
| Settings | open any screen | next | `open_screen`; needs a choice of what happens to the conversation |
| Online accounts | connect, disconnect | tap | Apple and Google require a tap to sign in |
| Online accounts | disconnect | next | |
| Privacy, account | Face ID lock, erase everything, sign out, delete the account | tap | protects everything else; asks Face ID or confirms on screen |
| Payments, invoices | pay for a page | voice | `pay_for_page`; a tap now, a strong spoken yes in step 3 |
| Payments, invoices | the inFakt key | tap | a secret is typed, never said aloud |
| Backup | make, restore | tap | needs Files and a password |
