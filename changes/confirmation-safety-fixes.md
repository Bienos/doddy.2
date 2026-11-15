# Confirmation safety fixes (review of steps 2a and 2b)

Decision `2026-11-14-spoken-yes-and-fewer-cards`.
- **A lone "ja" is no longer a spoken yes.** It is Polish for "I"; "ja bitte", "klar" and the rest still count.
- **Camera:** a yes said with Doddy in the background says the camera couldn't open, never "opened".
- **At once:** a change that runs with no card writes its row before it starts, so End can't leave a note with no row or Undo.
- **Ingredients:** the reply says why each one was left out (on the list, or At home), never "the user unticked".
- **Screens:** Settings › Connections, Online accounts and the private conversation line say "say yes or tap", or "when you ask", where the tap is gone. In the eight other languages two of those lines show in English until they are translated.
- **Ran:** DoddyCore tests and `scripts/ci.sh --only checks,swift`. **Not run:** the app build (CI `ios-build`), a device.
