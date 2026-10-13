# DoddyWatch: the Apple Watch app
Read `/STATUS.md`, then `docs/platforms/watch.md`.
- **Scope:** this folder, `DoddyWatchWidgets/`, and `DoddyApp/Features/Watch/` (the iPhone side).
- **No database or network here.** The Watch only shows what the iPhone sends, and asks the iPhone to act (the capability guard enforces this).
- **Build:** `make project`, scheme `DoddyWatch`. To run it, it needs a paired iPhone simulator with the app.
