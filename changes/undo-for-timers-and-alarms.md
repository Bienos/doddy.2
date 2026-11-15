# Timers and alarms get Undo and run at once

Decision `2026-11-14-spoken-yes-and-fewer-cards`, step 2c, first half.
- **Undo in "What Doddy did":** a timer Doddy started can be stopped there, and an alarm Doddy set can be turned off there (`ActivityUndo.startedTimer`, `ActivityUndo.setAlarm`). Undo is kept only for one the iPhone listed afterwards.
  - **Timers:** Undo stops only a timer that is still counting down. One that is paused or ringing is left alone, and Undo is no longer offered once it has rung.
  - **Alarms:** Undo turns off only an alarm AlarmKit still has. A one-off alarm offers it until it rings; a repeating one, for the day.
  - **Checks:** the Timers switch and Pause all are checked first, and the iPhone's list is read back after.
- **At once:** `set_timer` and `set_alarm` run when asked, with no card (`AskFirst.ownChangesAtOnce`). `tools.json` says `runs_now` for both, and their descriptions and lines in `instructions.md` say so. The live agent's two descriptions change after this ships.
- **Unchanged:** "undo that" (`undo_last`) still means Calendar and Reminders only. Timers and alarms are undone in "What Doddy did".
- **Still keep their card:** new lists, note and leave-by reminders and the parking spot, until they have an Undo (the second half of 2c).
