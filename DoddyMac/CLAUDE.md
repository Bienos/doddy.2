# DoddyMac: the Mac menu bar app
**PAUSED (ADR-572): do not build or change this folder unless the owner re-enables the Mac.** See `docs/platforms/mac.md` › Re-enabling.
Read `/STATUS.md`, then `docs/platforms/mac.md`.
- **Scope:** this folder and `DoddyMacWidgets/`. They're a separate project (`project-mac.yml`, `make project-mac`) with nothing from the iPhone app.
- **No network, microphone or sync with the iPhone** (the capability guard enforces this). Notes live in this Mac's own SQLite database.
